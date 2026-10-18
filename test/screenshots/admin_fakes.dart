// Sample data for the admin screens in screenshot runs (no database).

import 'package:crimireview/models/concept.dart';
import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/subject.dart';
import 'package:crimireview/services/admin_service.dart';
import 'package:crimireview/services/concept_service.dart';
import 'package:crimireview/services/question_generation_service.dart';

class FakeAdminService extends AdminService {
  FakeAdminService() : super.forTesting();

  @override
  bool get isAdmin => true;

  @override
  Future<Map<String, dynamic>> questionStats() async => {
        'total': 812,
        'active': 759,
        'generated': 21,
        'bySubject': {
          'criminal_jurisprudence': {'total': 168, 'active': 160},
          'law_enforcement': {'total': 162, 'active': 151},
          'criminalistics': {'total': 158, 'active': 148},
          'crime_detection': {'total': 120, 'active': 110},
          'criminology': {'total': 114, 'active': 107},
          'corrections': {'total': 90, 'active': 83},
        },
      };

  @override
  Future<List<Map<String, dynamic>>> studentProgressOverview({String? search}) async => [
        _student('Juan Dela Cruz', 'juan@example.com', 1240, 0.78, 14, 2, 18, 'student', 2),
        _student('Maria Santos', 'maria@example.com', 980, 0.64, 9, 4, 16, 'student', 26),
        _student('Paolo Reyes', 'paolo@example.com', 715, 0.51, 5, 6, 12, 'student', 72),
        _student('Admin Kile', 'admin@example.com', 0, 0, 0, 0, 0, 'admin', null),
      ];

  Map<String, dynamic> _student(String name, String email, int points, double p, int mastered,
          int remediation, int tracked, String role, int? hoursAgo) =>
      {
        'display_name': name,
        'email': email,
        'total_points': points,
        'avg_p_known': p,
        'topics_mastered': mastered,
        'topics_needing_remediation': remediation,
        'topics_tracked': tracked,
        'role': role,
        'last_practiced': hoursAgo == null
            ? null
            : DateTime.now().subtract(Duration(hours: hoursAgo)).toIso8601String(),
      };

  @override
  Future<List<Map<String, dynamic>>> recentAuditLog({int limit = 30}) async => [
        {'action': 'create', 'target_id': 'admin_1760000000000', 'created_at': _ago(0.2)},
        {'action': 'update', 'target_id': 'cj_rpc_art11_004', 'created_at': _ago(3)},
        {'action': 'delete', 'target_id': 'le_draft_17', 'created_at': _ago(26)},
        {'action': 'restore', 'target_id': 'cr_bjmp_009', 'created_at': _ago(50)},
      ];

  @override
  Future<int> approveGenerated(List<String> ids) async => ids.length;

  String _ago(double hours) =>
      DateTime.now().subtract(Duration(minutes: (hours * 60).round())).toIso8601String();

  @override
  Future<List<AdminQuestionEntry>> listQuestions({
    String? subjectId,
    Difficulty? difficulty,
    bool includeInactive = true,
    String? search,
    QuestionSource? source,
    String? templateId,
    int limit = 50,
    int offset = 0,
  }) async {
    if (offset > 0) return [];
    const subjects = CriminologySubjects.all;
    // The review list: generated questions waiting for approval, and one that
    // was approved earlier.
    if (source == QuestionSource.generated) {
      return [
        for (var i = 0; i < 5; i++)
          AdminQuestionEntry(
            isActive: i == 4,
            question: sampleGeneratedQuestion(i, 'criminal_jurisprudence'),
          ),
      ];
    }
    return [
      for (var i = 0; i < 6; i++)
        AdminQuestionEntry(
          isActive: i != 3,
          question: sampleAdminQuestion(i, subjects[i % subjects.length].id),
        ),
    ];
  }
}

Question sampleAdminQuestion(int i, String subjectId) => Question(
      id: 'q_$i',
      subject: subjectId,
      topic: ['Justifying Circumstances', 'Police Planning', 'Dactyloscopy', 'Crime Scene Management', 'Strain Theory', 'Parole and Probation'][i % 6],
      questionText: [
        'Which of the following is a justifying circumstance under Article 11 of the Revised Penal Code?',
        'What is the first step in the police planning process?',
        'Which fingerprint pattern is the most common?',
        'What should the first responder do upon arriving at a crime scene?',
        'Who proposed strain theory?',
        'Which agency supervises probationers in the Philippines?',
      ][i % 6],
      answerOptions: const [
        AnswerOption(text: 'Self-defense', isCorrect: true, rationale: 'Listed in Article 11.'),
        AnswerOption(text: 'Insanity', isCorrect: false, rationale: 'An exempting circumstance (Art. 12).'),
        AnswerOption(text: 'Minority', isCorrect: false, rationale: ''),
        AnswerOption(text: 'Uncontrollable fear', isCorrect: false, rationale: ''),
      ],
      difficulty: Difficulty.values[i % 3],
      explanation: 'Self-defense is a justifying circumstance.',
      legalBasis: 'RPC Art. 11',
      source: i == 2 ? QuestionSource.generated : QuestionSource.admin,
      version: 1 + i % 3,
    );

/// A generated question as the review list shows it: the stem the generator
/// writes for each form.
Question sampleGeneratedQuestion(int i, String subjectId) {
  const stems = [
    'Under "Justifying Circumstances", which of the following BEST describes Self-Defense?',
    'Which term under "Justifying Circumstances" matches the following description: Acting in defense of one\'s own person or rights.',
    'Under "Justifying Circumstances", which of the following is covered by RPC Art. 11(3)?',
    'Under "Justifying Circumstances", which provision is the legal basis of Defense of a Relative?',
    'Under "Exempting Circumstances", which of the following BEST describes Irresistible Force?',
  ];
  return Question(
    id: 'gen_tpl_$i',
    subject: subjectId,
    topic: i == 4 ? 'Exempting Circumstances' : 'Justifying Circumstances',
    questionText: stems[i % stems.length],
    answerOptions: const [
      AnswerOption(text: 'Defense of a Stranger', isCorrect: false, rationale: 'That statement defines another concept.'),
      AnswerOption(text: 'Self-Defense', isCorrect: true, rationale: 'Correct.'),
      AnswerOption(text: 'Defense of a Relative', isCorrect: false, rationale: 'That statement defines another concept.'),
    ],
    difficulty: Difficulty.values[i % 3],
    explanation: 'Self-Defense is a justifying circumstance.',
    legalBasis: 'RPC Art. 11(1)',
    source: QuestionSource.generated,
    version: 1,
    templateId: 'tpl_sample',
  );
}

class FakeQuestionGenerationService extends QuestionGenerationService {
  FakeQuestionGenerationService() : super.forTesting();

  @override
  Future<List<TemplateStatus>> listTemplateStatus() async => const [
        // Justifying Circumstances: all four forms, partly used.
        TemplateStatus(id: 'a1', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', difficulty: 'medium', form: 'term_to_definition', totalConcepts: 6, conceptsRemaining: 3),
        TemplateStatus(id: 'a2', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', difficulty: 'medium', form: 'definition_to_term', totalConcepts: 6, conceptsRemaining: 6),
        TemplateStatus(id: 'a3', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', difficulty: 'hard', form: 'basis_to_term', totalConcepts: 6, conceptsRemaining: 6),
        TemplateStatus(id: 'a4', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', difficulty: 'hard', form: 'term_to_basis', totalConcepts: 6, conceptsRemaining: 0),
        // Police Organization: two concepts share a legal basis, so the basis forms are unavailable.
        TemplateStatus(id: 'b1', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', difficulty: 'easy', form: 'term_to_definition', totalConcepts: 5, conceptsRemaining: 5),
        TemplateStatus(id: 'b2', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', difficulty: 'medium', form: 'definition_to_term', totalConcepts: 5, conceptsRemaining: 1),
        TemplateStatus(id: 'b3', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', difficulty: 'hard', form: 'basis_to_term', totalConcepts: 0, conceptsRemaining: 0),
        TemplateStatus(id: 'b4', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', difficulty: 'hard', form: 'term_to_basis', totalConcepts: 0, conceptsRemaining: 0),
      ];

  @override
  Future<Map<String, dynamic>> generateFromTemplate({required String templateId, int count = 5}) async =>
      {'success': true, 'inserted': count, 'skipped': 0, 'considered': count};
}

class FakeConceptService extends ConceptService {
  FakeConceptService() : super.forTesting();

  @override
  Future<List<Concept>> listConcepts() async => sampleConcepts;

  @override
  Future<ConceptSaveResult> saveConcept({
    String? id,
    required String subjectId,
    required String topic,
    required String term,
    required String definition,
    String? legalBasis,
    String? siblingGroup,
  }) async =>
      const ConceptSaveResult(success: true, id: 'cb_new');

  @override
  Future<ConceptSaveResult> setActive(String id, bool active) async =>
      const ConceptSaveResult(success: true);
}

const List<Concept> sampleConcepts = [
  Concept(id: 'c1', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', term: 'Self-Defense', definition: 'Acting in defense of one\'s own person or rights, provided there is unlawful aggression, reasonable necessity of the means employed to prevent or repel it, and lack of sufficient provocation.', legalBasis: 'RPC Art. 11(1)', siblingGroup: 'rpc_art11_justifying'),
  Concept(id: 'c2', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', term: 'Defense of a Relative', definition: 'Acting in defense of the person or rights of a spouse, ascendant, descendant or sibling, provided the first two requisites of self-defense are present.', legalBasis: 'RPC Art. 11(2)', siblingGroup: 'rpc_art11_justifying'),
  Concept(id: 'c3', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', term: 'Defense of a Stranger', definition: 'Acting in defense of a person who is not a relative, provided there is unlawful aggression and reasonable necessity of the means employed.', legalBasis: 'RPC Art. 11(3)', siblingGroup: 'rpc_art11_justifying'),
  Concept(id: 'c4', subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', term: 'Obedience to a Lawful Order', definition: 'Acting in obedience to an order issued by a superior for some lawful purpose.', legalBasis: 'RPC Art. 11(6)', siblingGroup: 'rpc_art11_justifying', isActive: false),
  Concept(id: 'c5', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', term: 'Philippine National Police (PNP)', definition: 'The national police force, civilian in character and national in scope, mandated to enforce the law and maintain peace and order.', legalBasis: 'RA 6975, as amended by RA 8551', siblingGroup: 'dilg_law_enforcement'),
  Concept(id: 'c6', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', term: 'National Police Commission (NAPOLCOM)', definition: 'The agency attached to the DILG that exercises administrative control and operational supervision over the PNP.', legalBasis: 'RA 6975, as amended by RA 8551', siblingGroup: 'dilg_law_enforcement'),
  Concept(id: 'c7', subjectId: 'law_enforcement', topic: 'Police Organization and Administration', term: 'Bureau of Fire Protection (BFP)', definition: 'The bureau under the DILG responsible for preventing and suppressing all destructive fires.', legalBasis: 'RA 6975, Sec. 53', siblingGroup: 'dilg_law_enforcement'),
  Concept(id: 'c8', subjectId: 'corrections', topic: 'Probation Law', term: 'Probation', definition: 'A disposition under which a convicted offender is released subject to conditions imposed by the court.', siblingGroup: 'corrections_probation_law'),
  Concept(id: 'c9', subjectId: 'corrections', topic: 'Probation Law', term: 'Parole', definition: 'The conditional release of a prisoner after serving the minimum of an indeterminate sentence.', siblingGroup: 'corrections_probation_law'),
];
