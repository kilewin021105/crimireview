import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// One row of `public.template_generation_status` -- a template plus how
/// many of its matching concepts have not yet produced a question.
class TemplateStatus {
  final String id;
  final String subjectId;
  final String topic;
  final String difficulty;

  /// Which kind of question this template makes; see [templateFormLabels].
  final String form;
  final int totalConcepts;
  final int conceptsRemaining;

  const TemplateStatus({
    required this.id,
    required this.subjectId,
    required this.topic,
    required this.difficulty,
    this.form = 'term_to_definition',
    required this.totalConcepts,
    required this.conceptsRemaining,
  });

  factory TemplateStatus.fromJson(Map<String, dynamic> json) {
    return TemplateStatus(
      id: (json['id'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? '').toString(),
      topic: (json['topic'] ?? '').toString(),
      difficulty: (json['difficulty'] ?? 'medium').toString(),
      form: (json['form'] ?? 'term_to_definition').toString(),
      totalConcepts: (json['total_concepts'] as num?)?.toInt() ?? 0,
      conceptsRemaining: (json['concepts_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The four kinds of question a concept can become, in the order they are
/// shown. The keys match `question_templates.form` in the database.
const List<String> templateFormOrder = [
  'term_to_definition',
  'definition_to_term',
  'basis_to_term',
  'term_to_basis',
];

/// Plain-words names for the forms.
const Map<String, String> templateFormLabels = {
  'term_to_definition': 'Term to definition',
  'definition_to_term': 'Definition to term',
  'basis_to_term': 'Legal basis to term',
  'term_to_basis': 'Term to legal basis',
};

/// One line saying what the student sees and picks.
const Map<String, String> templateFormHints = {
  'term_to_definition': 'Shows the term. The student picks its meaning.',
  'definition_to_term': 'Shows the meaning. The student picks the term.',
  'basis_to_term': 'Shows a legal basis. The student picks the term it covers.',
  'term_to_basis': 'Shows the term. The student picks its legal basis.',
};

/// True for the two forms that need every concept in the group to have its
/// own legal basis.
bool templateFormNeedsBasis(String form) =>
    form == 'basis_to_term' || form == 'term_to_basis';

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

  /// For tests only: lets a subclass return sample data.
  @visibleForTesting
  QuestionGenerationService.forTesting();

  static QuestionGenerationService _instance = QuestionGenerationService._();
  static QuestionGenerationService get instance => _instance;

  @visibleForTesting
  static set debugInstance(QuestionGenerationService value) => _instance = value;

  static const String _statusView = 'template_generation_status';
  static const String _function = 'generate_questions_from_template';

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Every active template, with how many concepts are left to turn into a
  /// question -- so the picker UI can show "6 available" instead of an
  /// admin discovering the ceiling by trial and error. The ordering puts a
  /// topic's four forms together, in [templateFormOrder].
  Future<List<TemplateStatus>> listTemplateStatus() async {
    final rows = await _client.from(_statusView).select().order('topic');
    final list =
        List<Map<String, dynamic>>.from(rows).map(TemplateStatus.fromJson).toList();
    int formRank(String form) {
      final i = templateFormOrder.indexOf(form);
      return i < 0 ? templateFormOrder.length : i;
    }

    list.sort((a, b) {
      final bySubject = a.subjectId.compareTo(b.subjectId);
      if (bySubject != 0) return bySubject;
      final byTopic = a.topic.compareTo(b.topic);
      if (byTopic != 0) return byTopic;
      return formRank(a.form).compareTo(formRank(b.form));
    });
    return list;
  }

  /// Generates up to [count] questions from one template. Returns
  /// `{success, inserted, skipped, considered}` on success or
  /// `{success: false, error}` -- mirrors the shape every other RPC wrapper
  /// in this app already uses (see `AdminService.setUserRole`,
  /// `EmailVerificationService`).
  ///
  /// `inserted` can be less than requested even on success: a concept makes
  /// one question per form, so once every concept has been used for a
  /// template, further requests legitimately return `inserted: 0`. Asking for
  /// exactly `conceptsRemaining` always creates that many.
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
