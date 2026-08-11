import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question.dart';
import 'supabase_service.dart';

/// One row of `public.document_uploads` -- the admin-facing status of a
/// single "generate questions from this PDF" request.
class DocumentUpload {
  final String id;
  final String filename;
  final String subjectId;
  final String? topic;
  final String? targetDifficulty;
  final int requestedCount;

  /// pending -> processing -> completed | failed. Driven entirely by
  /// `supabase/functions/generate-questions-from-document`; the app never
  /// writes this itself once the row is created.
  final String status;
  final int generatedCount;
  final String? errorMessage;
  final DateTime createdAt;

  const DocumentUpload({
    required this.id,
    required this.filename,
    required this.subjectId,
    this.topic,
    this.targetDifficulty,
    required this.requestedCount,
    required this.status,
    required this.generatedCount,
    this.errorMessage,
    required this.createdAt,
  });

  bool get isDone => status == 'completed' || status == 'failed';
  bool get hasReviewableQuestions => status == 'completed' && generatedCount > 0;

  factory DocumentUpload.fromJson(Map<String, dynamic> json) {
    return DocumentUpload(
      id: (json['id'] ?? '').toString(),
      filename: (json['filename'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? '').toString(),
      topic: json['topic'] as String?,
      targetDifficulty: json['target_difficulty'] as String?,
      requestedCount: (json['requested_count'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'pending').toString(),
      generatedCount: (json['generated_count'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Drives the "upload a PDF, get generated questions back for review" flow
/// (Automatic Item Generation, LLM path -- see `supabase_document_generation.sql`
/// for how this differs from the slot-filling `question_templates` /
/// `concept_bank` design already scaffolded in `supabase_schema_v2.sql`).
///
/// This service owns exactly two things: getting the PDF into storage and a
/// `document_uploads` row, and kicking off the Edge Function that reads it.
/// Everything downstream -- reviewing, approving, rejecting, editing the
/// generated items -- is deliberately just [AdminService] and
/// [AdminQuestionsScreen] again: generated items are ordinary `questions`
/// rows (`source: 'generated'`, `is_active: false`) and approving one is the
/// exact same [AdminService.setActive] call as restoring any other
/// deactivated question.
class DocumentGenerationService {
  DocumentGenerationService._();

  static final DocumentGenerationService _instance =
      DocumentGenerationService._();
  static DocumentGenerationService get instance => _instance;

  static const String _table = 'document_uploads';
  static const String _bucket = 'document-uploads';
  static const String _functionName = 'generate-questions-from-document';

  /// Mirrors the Claude API's PDF input limit, checked client-side so a
  /// student -- sorry, an admin -- gets an immediate "too big" message
  /// instead of an upload that silently fails inside the Edge Function.
  static const int maxFileBytes = 32 * 1024 * 1024;

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Opens a file picker restricted to PDF, uploads it, records the request,
  /// and fires the generation function.
  ///
  /// Deliberately does NOT await the function's completion -- per the
  /// chosen "upload and check back later" flow, this returns as soon as the
  /// file is stored and the request is queued. The function keeps running
  /// server-side regardless of whether this call is awaited; [watchUploads]
  /// is how the UI learns the outcome. Returns `null` if the admin cancelled
  /// the file picker.
  Future<DocumentUpload?> pickAndGenerate({
    required String subjectId,
    String? topic,
    Difficulty? targetDifficulty,
    int requestedCount = 10,
  }) async {
    final userId = SupabaseService.instance.userId;
    if (userId == null) {
      throw StateError('Must be signed in to generate questions.');
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not read the selected file.');
    }
    if (bytes.length > maxFileBytes) {
      throw StateError(
        'File is ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB -- '
        'the limit is ${maxFileBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final uploadId = _generateId();
    final storagePath = '$userId/$uploadId.pdf';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    final cleanTopic = topic?.trim();
    final row = {
      'id': uploadId,
      'filename': file.name,
      'storage_path': storagePath,
      'subject_id': subjectId,
      'topic': (cleanTopic == null || cleanTopic.isEmpty) ? null : cleanTopic,
      'target_difficulty': targetDifficulty?.name,
      'requested_count': requestedCount.clamp(1, 30),
      'status': 'pending',
      'uploaded_by': userId,
    };
    await _client.from(_table).insert(row);

    // Fire-and-forget: the function's own lifecycle (pending -> processing
    // -> completed/failed) is what the UI actually watches, not this call.
    unawaited(_invokeGeneration(uploadId));

    return DocumentUpload.fromJson({...row, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> _invokeGeneration(String uploadId) async {
    try {
      await _client.functions.invoke(_functionName, body: {'upload_id': uploadId});
    } catch (e) {
      debugPrint('DocumentGenerationService: invoke failed: $e');
    }
  }

  /// Live view of every upload, newest first -- powers the "check back
  /// later" queue list with no manual polling.
  Stream<List<DocumentUpload>> watchUploads() {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DocumentUpload.fromJson).toList());
  }

  String _generateId() {
    final rand = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'up_${DateTime.now().microsecondsSinceEpoch}_$rand';
  }
}
