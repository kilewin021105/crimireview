import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/concept.dart';
import '../utils/concept_import_parser.dart';
import '../utils/error_messages.dart';
import 'supabase_service.dart';

/// What the database answered to saving or deactivating a concept.
class ConceptSaveResult {
  final bool success;
  final String? error;
  final String? id;
  final String? topic;

  const ConceptSaveResult({required this.success, this.error, this.id, this.topic});
}

/// A pasted row the database could not save, and why.
class ConceptReject {
  /// Position in the list that was sent, counting from 1.
  final int row;
  final String term;
  final String reason;

  const ConceptReject({required this.row, required this.term, required this.reason});
}

class ConceptImportResult {
  final bool success;
  final String? error;
  final int inserted;
  final List<ConceptReject> rejected;
  final String? topic;

  const ConceptImportResult({
    required this.success,
    this.error,
    this.inserted = 0,
    this.rejected = const [],
    this.topic,
  });
}

/// Faculty tools for the concept bank. Every write goes through a database
/// function that checks the caller is an admin, validates the text, and
/// writes the audit log (`supabase_concept_bank.sql`), so the rules live in
/// one place and cannot be skipped from the app.
class ConceptService {
  ConceptService._();

  /// For tests only: lets a subclass return sample data.
  @visibleForTesting
  ConceptService.forTesting();

  static ConceptService _instance = ConceptService._();
  static ConceptService get instance => _instance;

  @visibleForTesting
  static set debugInstance(ConceptService value) => _instance = value;

  static const String _table = 'concept_bank';

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Every concept, active or not (admins can read both), ordered for display.
  Future<List<Concept>> listConcepts() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('subject_id')
        .order('topic')
        .order('term');
    return List<Map<String, dynamic>>.from(rows).map(Concept.fromJson).toList();
  }

  /// Adds a concept ([id] null) or edits one. Editing changes only the term,
  /// definition and legal basis; the subject, topic and group stay.
  Future<ConceptSaveResult> saveConcept({
    String? id,
    required String subjectId,
    required String topic,
    required String term,
    required String definition,
    String? legalBasis,
    String? siblingGroup,
  }) async {
    try {
      final result = await _client.rpc('admin_save_concept', params: {
        'p_id': id,
        'p_subject_id': subjectId,
        'p_topic': topic,
        'p_term': term,
        'p_definition': definition,
        'p_legal_basis': legalBasis,
        'p_sibling_group': siblingGroup,
      });
      final map = _asMap(result);
      if (map['success'] == true) {
        return ConceptSaveResult(
          success: true,
          id: map['id']?.toString(),
          topic: map['topic']?.toString(),
        );
      }
      return ConceptSaveResult(
          success: false, error: (map['error'] ?? 'Could not save the concept.').toString());
    } catch (e) {
      return ConceptSaveResult(
          success: false, error: friendlyError(e, fallback: 'Could not save the concept.'));
    }
  }

  /// Deactivates or restores a concept. Questions already made from it stay.
  Future<ConceptSaveResult> setActive(String id, bool active) async {
    try {
      final result = await _client.rpc('admin_set_concept_active', params: {
        'p_id': id,
        'p_active': active,
      });
      final map = _asMap(result);
      if (map['success'] == true) return const ConceptSaveResult(success: true);
      return ConceptSaveResult(
          success: false, error: (map['error'] ?? 'Could not update the concept.').toString());
    } catch (e) {
      return ConceptSaveResult(
          success: false, error: friendlyError(e, fallback: 'Could not update the concept.'));
    }
  }

  /// Adds many concepts to one subject and topic. Rows that cannot be saved
  /// come back in [ConceptImportResult.rejected]; the others are saved.
  Future<ConceptImportResult> importConcepts({
    required String subjectId,
    required String topic,
    String? siblingGroup,
    required List<ConceptDraft> rows,
  }) async {
    try {
      final result = await _client.rpc('admin_import_concepts', params: {
        'p_subject_id': subjectId,
        'p_topic': topic,
        'p_sibling_group': siblingGroup,
        'p_rows': rows.map((r) => r.toJson()).toList(),
      });
      final map = _asMap(result);
      if (map['success'] != true) {
        return ConceptImportResult(
            success: false, error: (map['error'] ?? 'Could not import the concepts.').toString());
      }
      final rejected = <ConceptReject>[];
      final raw = map['rejected'];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          rejected.add(ConceptReject(
            row: (item['row'] as num?)?.toInt() ?? 0,
            term: (item['term'] ?? '').toString(),
            reason: (item['reason'] ?? '').toString(),
          ));
        }
      }
      return ConceptImportResult(
        success: true,
        inserted: (map['inserted'] as num?)?.toInt() ?? 0,
        rejected: rejected,
        topic: map['topic']?.toString(),
      );
    } catch (e) {
      return ConceptImportResult(
          success: false, error: friendlyError(e, fallback: 'Could not import the concepts.'));
    }
  }

  Map<String, dynamic> _asMap(dynamic result) {
    if (result is Map) return result.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{'success': false, 'error': 'Unexpected response.'};
  }
}
