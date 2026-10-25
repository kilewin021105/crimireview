import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question.dart';
import 'supabase_service.dart';

/// One row of `public.document_uploads`: the status of one "generate
/// questions from this PDF" request.
class DocumentUpload {
  final String id;
  final String filename;
  final String storagePath;
  final String subjectId;
  final String? topic;

  /// The PRC TOS topic or competency the questions should test, e.g.
  /// `CLJ-3.4`; null for a general upload.
  final String? tosCode;
  final String? targetDifficulty;
  final int requestedCount;

  /// pending -> processing -> completed | failed, written by the Edge
  /// Function `generate-questions-from-document` (Google Gemini).
  final String status;
  final int generatedCount;
  final String? errorMessage;
  final DateTime createdAt;

  const DocumentUpload({
    required this.id,
    required this.filename,
    this.storagePath = '',
    required this.subjectId,
    this.topic,
    this.tosCode,
    this.targetDifficulty,
    required this.requestedCount,
    required this.status,
    required this.generatedCount,
    this.errorMessage,
    required this.createdAt,
  });

  bool get isWorking => status == 'pending' || status == 'processing';
  bool get isFailed => status == 'failed';
  bool get hasQuestions => status == 'completed' && generatedCount > 0;

  /// A request still "working" after this long almost certainly died with
  /// the function (it gives up well before that), so the screen says so.
  bool isStuck(DateTime now) => isWorking && now.difference(createdAt) > const Duration(minutes: 5);

  factory DocumentUpload.fromJson(Map<String, dynamic> json) => DocumentUpload(
        id: (json['id'] ?? '').toString(),
        filename: (json['filename'] ?? '').toString(),
        storagePath: (json['storage_path'] ?? '').toString(),
        subjectId: (json['subject_id'] ?? '').toString(),
        topic: json['topic'] as String?,
        tosCode: json['tos_code'] as String?,
        targetDifficulty: json['target_difficulty'] as String?,
        requestedCount: (json['requested_count'] as num?)?.toInt() ?? 0,
        status: (json['status'] ?? 'pending').toString(),
        generatedCount: (json['generated_count'] as num?)?.toInt() ?? 0,
        errorMessage: json['error_message'] as String?,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

/// Why a picked file can't be sent, or null when it can. Kept free of
/// Flutter and Supabase so it is unit-tested directly.
String? pdfProblem({required String name, required int size, Uint8List? bytes}) {
  if (!name.toLowerCase().endsWith('.pdf')) return '"$name" is not a PDF file.';
  if (size > DocumentGenerationService.maxFileBytes) {
    return 'The PDF is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB. The limit is 20 MB; split it into smaller files.';
  }
  if (bytes == null || bytes.isEmpty) return "Couldn't read that file. Choose it again, or save it again first.";
  if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
    return '"$name" does not look like a real PDF. Export or save it as PDF again.';
  }
  return null;
}

/// Uploads a faculty member's PDF and asks the Edge Function to write
/// questions from it with Google Gemini. The questions come back as
/// ordinary `questions` rows with `is_active = false`, `source =
/// 'generated'` and `template_id` = the upload id; approving one is the same
/// [AdminService.setActive] call as restoring any question.
class DocumentGenerationService {
  DocumentGenerationService._();
  static DocumentGenerationService _instance = DocumentGenerationService._();
  static DocumentGenerationService get instance => _instance;

  /// For tests only (screenshot harness): a subclass with sample data.
  @visibleForTesting
  static set debugInstance(DocumentGenerationService value) => _instance = value;
  @visibleForTesting
  DocumentGenerationService.forTesting();

  static const String _table = 'document_uploads';
  static const String _bucket = 'document-uploads';
  static const String _functionName = 'generate-questions-from-document';

  /// Same as the storage bucket's limit in `supabase_document_generation.sql`.
  static const int maxFileBytes = 20 * 1024 * 1024;
  static const int maxQuestions = 20;

  SupabaseClient get _client => SupabaseService.instance.client;

  /// The most recent uploads, newest first.
  Future<List<DocumentUpload>> recentUploads({int limit = 20}) async {
    final rows = await _client.from(_table).select().order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows).map(DocumentUpload.fromJson).toList();
  }

  /// Stores the PDF, records the request and starts the function. Returns
  /// as soon as the function has accepted the job; the result appears in
  /// [recentUploads] when Gemini is done (usually within a minute).
  Future<DocumentUpload> upload({
    required String filename,
    required Uint8List bytes,
    required String subjectId,
    String? topic,
    String? tosCode,
    Difficulty? targetDifficulty,
    int requestedCount = 10,
  }) async {
    final userId = SupabaseService.instance.userId;
    if (userId == null) throw StateError('Sign in first.');
    final problem = pdfProblem(name: filename, size: bytes.length, bytes: bytes);
    if (problem != null) throw StateError(problem);

    final uploadId = _newId();
    final storagePath = '$userId/$uploadId.pdf';
    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(contentType: 'application/pdf'),
        );

    final cleanTopic = topic?.trim();
    final row = {
      'id': uploadId,
      'filename': filename,
      'storage_path': storagePath,
      'subject_id': subjectId,
      'topic': (cleanTopic == null || cleanTopic.isEmpty) ? null : cleanTopic,
      'target_difficulty': targetDifficulty?.name,
      'requested_count': requestedCount.clamp(1, maxQuestions),
      'uploaded_by': userId,
      // Sent only when set: the column comes with supabase_tos_alignment.sql.
      if (tosCode != null) 'tos_code': tosCode,
    };
    await _client.from(_table).insert(row);

    // The function answers right away (202) and keeps working in the
    // background, so awaiting it is short. A failure to start is reported:
    // the row would otherwise sit at "pending" forever.
    try {
      await _client.functions.invoke(_functionName, body: {'upload_id': uploadId});
    } on FunctionException catch (e) {
      debugPrint('generate-questions-from-document: ${e.status} ${e.details}');
      final details = e.details;
      final message = details is Map && details['error'] is String ? details['error'] as String : null;
      throw StateError(message ??
          "The PDF was uploaded, but the question generator didn't start (error ${e.status}). "
              'Check that the Edge Function is deployed.');
    }
    return DocumentUpload.fromJson({...row, 'status': 'processing', 'created_at': DateTime.now().toIso8601String()});
  }

  /// Removes an upload record and its PDF. Questions already generated from
  /// it stay in the bank (approve or delete them like any question).
  Future<void> deleteUpload(DocumentUpload upload) async {
    try {
      if (upload.storagePath.isNotEmpty) await _client.storage.from(_bucket).remove([upload.storagePath]);
    } catch (e) {
      debugPrint('DocumentGenerationService: PDF not removed: $e');
    }
    await _client.from(_table).delete().eq('id', upload.id);
  }

  static String _newId() {
    final r = Random.secure();
    final rand = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'doc_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }
}
