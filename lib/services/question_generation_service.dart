import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// One row of `public.template_generation_status` -- a template plus how
/// many of its matching concepts have not yet produced a question.
class TemplateStatus {
  final String id;
  final String subjectId;
  final String topic;
  final String difficulty;
  final int totalConcepts;
  final int conceptsRemaining;

  const TemplateStatus({
    required this.id,
    required this.subjectId,
    required this.topic,
    required this.difficulty,
    required this.totalConcepts,
    required this.conceptsRemaining,
  });

  factory TemplateStatus.fromJson(Map<String, dynamic> json) {
    return TemplateStatus(
      id: (json['id'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? '').toString(),
      topic: (json['topic'] ?? '').toString(),
      difficulty: (json['difficulty'] ?? 'medium').toString(),
      totalConcepts: (json['total_concepts'] as num?)?.toInt() ?? 0,
      conceptsRemaining: (json['concepts_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Drives the free, no-API-key path of Automatic Item Generation (panel
/// note 1) -- the slot-filling method already scaffolded in
/// `supabase_schema_v2.sql` (`question_templates` + `concept_bank`) but
/// never previously wired to anything. See `supabase_template_generation.sql`
/// for the actual generation logic -- it lives entirely in one Postgres
/// function, `generate_questions_from_template`, so this class does almost
/// nothing beyond calling it.
///
/// There is no queue to watch: the function runs synchronously and returns
/// the result directly, because it never leaves the database (no file
/// upload, no external API call).
class QuestionGenerationService {
  QuestionGenerationService._();

  static final QuestionGenerationService _instance = QuestionGenerationService._();
  static QuestionGenerationService get instance => _instance;

  static const String _statusView = 'template_generation_status';
  static const String _function = 'generate_questions_from_template';

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Every active template, with how many concepts are left to turn into a
  /// question -- so the picker UI can show "6 available" instead of an
  /// admin discovering the ceiling by trial and error.
  Future<List<TemplateStatus>> listTemplateStatus() async {
    final rows = await _client.from(_statusView).select().order('topic');
    return List<Map<String, dynamic>>.from(rows).map(TemplateStatus.fromJson).toList();
  }

  /// Generates up to [count] questions from one template. Returns
  /// `{success, inserted, skipped, considered}` on success or
  /// `{success: false, error}` -- mirrors the shape every other RPC wrapper
  /// in this app already uses (see `AdminService.setUserRole`,
  /// `EmailVerificationService`).
  ///
  /// `inserted` can be less than requested even on success: each concept
  /// can only ever produce one question (the stem is deterministic), so
  /// once every concept for a topic has been used, further requests
  /// legitimately return `inserted: 0`.
  Future<Map<String, dynamic>> generateFromTemplate({
    required String templateId,
    int count = 5,
  }) async {
    try {
      final result = await _client.rpc(_function, params: {
        'p_template_id': templateId,
        'p_count': count,
      });
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'success': false, 'error': 'Unexpected response.'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
