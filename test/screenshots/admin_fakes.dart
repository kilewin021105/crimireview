// Sample data for the admin screens in screenshot runs (no database).

import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/student_record.dart';
import 'package:crimireview/models/subject.dart';
import 'package:crimireview/models/tos.dart';
import 'package:crimireview/services/admin_service.dart';
import 'package:crimireview/services/document_generation_service.dart';

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
        'user_id': 'user_${email.split('@').first}',
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
  Future<StudentRecord> studentRecord(String userId) async => StudentRecord.fromJson(sampleStudentRecordJson());

  @override
  Future<List<Map<String, dynamic>>> recentAuditLog({int limit = 30}) async => [
        {'action': 'create', 'target_id': 'admin_1760000000000', 'created_at': _ago(0.2)},
        {'action': 'update', 'target_id': 'cj_rpc_art11_004', 'created_at': _ago(3)},
        {'action': 'delete', 'target_id': 'le_draft_17', 'created_at': _ago(26)},
        {'action': 'restore', 'target_id': 'cr_bjmp_009', 'created_at': _ago(50)},
      ];

  String _ago(double hours) =>
      DateTime.now().subtract(Duration(minutes: (hours * 60).round())).toIso8601String();

  /// Coverage worked out from the real TOS file: the 600 TOS drafts are all
  /// waiting, and the imported questions cover some competencies.
  @override
  Future<List<TosCoverageRow>> tosCoverage() async {
    final tos = TosCatalog.loaded ?? await TosCatalog.load();
    final rows = <TosCoverageRow>[];
    var n = 0;
    for (final s in tos.subjects) {
      for (final t in s.topics) {
        var topicActive = 0;
        for (final c in t.competencies) {
          final active = (n++ % 3 == 0) ? c.items : (n % 3 == 1 ? c.items ~/ 2 : 0);
          topicActive += active;
          rows.add(TosCoverageRow(
            code: c.code, subjectId: s.subjectId, topicCode: t.code, isTopic: false,
            tosItems: c.items, active: active, drafts: c.items,
          ));
        }
        rows.add(TosCoverageRow(
          code: t.code, subjectId: s.subjectId, topicCode: t.code, isTopic: true,
          tosItems: t.items, active: topicActive + t.items ~/ 2, drafts: t.items,
        ));
      }
    }
    return rows;
  }

  @override
  Future<int> setActiveMany(List<String> questionIds, bool active) async => questionIds.length;

  @override
  Future<List<AdminQuestionEntry>> listQuestions({
    String? subjectId,
    Difficulty? difficulty,
    bool includeInactive = true,
    bool onlyInactive = false,
    String? search,
    QuestionSource? source,
    String? templateId,
    String? tosCode,
    TosLinkFilter tosLink = TosLinkFilter.any,
    int limit = 50,
    int offset = 0,
  }) async {
    if (offset > 0) return [];
    // One TOS competency (review screen): four drafts, two approved.
    if (tosCode != null) {
      return [
        for (var i = 0; i < 6; i++)
          AdminQuestionEntry(isActive: i >= 4, question: sampleTosQuestion(i)),
      ];
    }
    // One PDF upload's batch (review screen): three waiting, one approved.
    if (templateId != null) {
      return [
        for (var i = 0; i < 4; i++)
          AdminQuestionEntry(isActive: i == 3, question: sampleGeneratedQuestion(i, templateId)),
      ];
    }
    const subjects = CriminologySubjects.all;
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
      topic: [
        'Criminal Law (Book 1)',
        'Law Enforcement Operations and Planning with Crime Mapping',
        'Personal Identification Techniques',
        'Fundamentals of Criminal Investigation and Intelligence',
        'Theories of Crime Causation',
        'Non-Institutional Correction',
      ][i % 6],
      tosCode: const ['CLJ-3.4', 'LEA-4.3', 'FS-1.2', null, 'CRIM-2', 'CA-2.2'][i % 6],
      bloomLevel: const ['Applying', 'Understanding', 'Analyzing', null, null, 'Applying'][i % 6],
      questionText: [
        'Which of the following is a justifying circumstance under Article 11 of the Revised Penal Code?',
        'What is the first step in the police planning process?',
        'Which fingerprint pattern is the most common?',
        'What should the first responder do upon arriving at a crime scene?',
        'Who proposed strain theory?',
        'Which agency supervises probationers in the Philippines?',
      ][i % 6],
      // Question 1's correct answer is much longer than the others, so the
      // "Answer stands out" warning shows in the list and the editor.
      answerOptions: i % 6 == 1
          ? const [
              AnswerOption(text: 'Being aware of the need to plan and setting objectives', isCorrect: true, rationale: 'Planning starts with recognizing the need.'),
              AnswerOption(text: 'Budgeting', isCorrect: false, rationale: 'Comes after the plan is chosen.'),
              AnswerOption(text: 'Evaluation', isCorrect: false, rationale: 'The last step.'),
              AnswerOption(text: 'Staffing', isCorrect: false, rationale: ''),
            ]
          : const [
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

List<Map<String, dynamic>> _segs(List<List<int>> answeredCorrect) => [
      for (var i = 0; i < answeredCorrect.length; i++)
        {'segmentIndex': i, 'questionsAnswered': answeredCorrect[i][0], 'correctAnswers': answeredCorrect[i][1]},
    ];

/// A student part-way through: Criminal Law on Hard, Criminology on Medium,
/// Forensic Science still on Easy, the other subjects not started.
Map<String, dynamic> sampleStudentRecordJson() {
  String ago(int hours) => DateTime.now().subtract(Duration(hours: hours)).toUtc().toIso8601String();
  return {
    'success': true,
    'profile': {
      'user_id': 'user_juan',
      'email': 'juan@example.com',
      'display_name': 'Juan Dela Cruz',
      'school': 'Buenavista Community College',
      'role': 'student',
      'rank': 'Scholar',
      'total_points': 1240,
      'current_streak': 4,
      'best_streak': 9,
      'joined_at': '2026-09-02T08:00:00Z',
    },
    'subjects': [
      {
        'subject_id': 'criminal_jurisprudence',
        'questions_answered': 100,
        'correct_answers': 81,
        'easy_correct': 34, 'easy_total': 40,
        'medium_correct': 33, 'medium_total': 40,
        'hard_correct': 14, 'hard_total': 20,
        'easy_segments': _segs([[10, 9], [10, 8], [10, 9], [10, 8]]),
        'medium_segments': _segs([[10, 8], [10, 8], [10, 9], [10, 8]]),
        'hard_segments': _segs([[10, 8], [10, 6]]),
        'last_study_date': ago(5),
      },
      {
        'subject_id': 'criminology',
        'questions_answered': 50,
        'correct_answers': 36,
        'easy_correct': 33, 'easy_total': 40,
        'medium_correct': 3, 'medium_total': 10,
        'easy_segments': _segs([[10, 8], [10, 9], [10, 8], [10, 8]]),
        'medium_segments': _segs([[10, 3]]),
        'last_study_date': ago(30),
      },
      {
        'subject_id': 'criminalistics',
        'questions_answered': 20,
        'correct_answers': 13,
        'easy_correct': 13, 'easy_total': 20,
        'easy_segments': _segs([[10, 8], [10, 5]]),
        'last_study_date': ago(72),
      },
    ],
    'mastery': [
      {'subject_id': 'criminalistics', 'topic': 'Personal Identification Techniques', 'p_known': 0.34, 'attempts': 6, 'correct': 2, 'is_mastered': false, 'last_practiced': ago(72)},
      {'subject_id': 'criminology', 'topic': 'Theories of Crime Causation', 'p_known': 0.52, 'attempts': 5, 'correct': 3, 'is_mastered': false, 'last_practiced': ago(30)},
      {'subject_id': 'criminal_jurisprudence', 'topic': 'Criminal Evidence', 'p_known': 0.71, 'attempts': 8, 'correct': 6, 'is_mastered': false, 'last_practiced': ago(5)},
      {'subject_id': 'criminal_jurisprudence', 'topic': 'Criminal Law (Book 1)', 'p_known': 0.94, 'attempts': 9, 'correct': 8, 'is_mastered': true, 'last_practiced': ago(5)},
    ],
    'quizzes': [
      {'subject_id': 'criminal_jurisprudence', 'difficulty': 'hard', 'score': 60, 'total_questions': 10, 'correct_answers': 6, 'created_at': ago(5)},
      {'subject_id': 'criminal_jurisprudence', 'difficulty': 'hard', 'score': 80, 'total_questions': 10, 'correct_answers': 8, 'created_at': ago(7)},
      {'subject_id': 'criminology', 'difficulty': 'medium', 'score': 30, 'total_questions': 10, 'correct_answers': 3, 'created_at': ago(30)},
      {'subject_id': 'criminalistics', 'difficulty': 'easy', 'score': 50, 'total_questions': 10, 'correct_answers': 5, 'created_at': ago(72)},
    ],
    'quiz_count': 17,
    'daily_challenges': 6,
    'achievements': 4,
  };
}


/// Six questions of TOS competency CLJ-3.4 (justifying, exempting, mitigating,
/// aggravating and alternative circumstances), as in content/tos/bank/clj.jsonl.
Question sampleTosQuestion(int i) {
  const stems = [
    'J was suddenly attacked with a knife by K. J grabbed a piece of wood and hit K once, disabling him. J did not provoke the attack. Which circumstance applies to J?',
    'L, who suffers from a mental illness that totally deprived him of reason at the time, killed his neighbor. Which circumstance applies?',
    'After committing homicide, M went to the police station on his own and surrendered before any warrant was issued. How does this affect his liability?',
    'N attacked a sleeping man who had no chance to defend himself, choosing that means so the victim could not resist. What circumstance attended the killing?',
    'O, a habitual drunkard, killed a man while intoxicated. How is the intoxication treated?',
    'A boat was sinking, so P threw cargo owned by Q overboard to keep the boat afloat and save the passengers. What applies to P?',
  ];
  const answers = [
    ['Self-defense, a justifying circumstance', 'Passion or obfuscation, a mitigating circumstance', 'Accident, an exempting circumstance', 'Uncontrollable fear, an exempting circumstance'],
    ['Insanity, an exempting circumstance', 'Self-defense, a justifying circumstance', 'Lack of intent, a mitigating circumstance', 'Lucid interval, an aggravating circumstance'],
    ['It is a mitigating circumstance of voluntary surrender', 'It is an exempting circumstance that frees him from liability', 'It is a justifying circumstance that makes the killing lawful', 'It has no effect because he already committed the crime'],
    ['Treachery (alevosia)', 'Evident premeditation', 'Nighttime', 'Abuse of superior strength'],
    ['As an aggravating circumstance, because the intoxication is habitual', 'As a mitigating circumstance, because drunkenness reduces control', 'As an exempting circumstance, because he was not in his right mind', 'As a justifying circumstance, because he acted without intent'],
    ['State of necessity, a justifying circumstance, though civil liability may arise', 'Accident, an exempting circumstance with no civil liability', 'Lawful exercise of a right, an exempting circumstance', 'Obedience to an order, a mitigating circumstance'],
  ];
  final correct = [0, 2, 1, 3, 0, 1][i % 6];
  final texts = List<String>.of(answers[i % 6]);
  final right = texts.removeAt(0);
  texts.insert(correct, right);
  return Question(
    id: 'tos24_CLJ-3.4_0${i + 1}',
    subject: 'criminal_jurisprudence',
    topic: 'Criminal Law (Book 1)',
    questionText: stems[i % 6],
    answerOptions: [
      for (var k = 0; k < 4; k++) AnswerOption(text: texts[k], isCorrect: k == correct, rationale: 'See the explanation.'),
    ],
    difficulty: Difficulty.medium,
    explanation: 'Revised Penal Code, Arts. 11-15.',
    legalBasis: const ['RPC Art. 11(1)', 'RPC Art. 12(1)', 'RPC Art. 13(7)', 'RPC Art. 14(16)', 'RPC Art. 15', 'RPC Arts. 11(4) and 101'][i % 6],
    source: QuestionSource.generated,
    templateId: 'tos_2024',
    tosCode: 'CLJ-3.4',
    bloomLevel: 'Applying',
  );
}

Question sampleGeneratedQuestion(int i, String uploadId) => Question(
      id: 'gen_$i',
      subject: 'criminal_jurisprudence',
      topic: 'Justifying Circumstances',
      questionText: [
        'Under Article 11 of the Revised Penal Code, which is NOT a requisite of self-defense?',
        'Defense of a relative covers which relatives of the accused?',
        'What justifying circumstance applies to a person who acts to avoid a greater evil?',
        'Who incurs no criminal liability when acting in obedience to an order?',
      ][i],
      answerOptions: const [
        AnswerOption(text: 'Unlawful aggression', isCorrect: false, rationale: 'This is the first requisite.'),
        AnswerOption(text: 'Reasonable necessity of the means', isCorrect: false, rationale: 'This is the second requisite.'),
        AnswerOption(text: 'Prior written warning', isCorrect: true, rationale: 'Article 11 does not require it.'),
        AnswerOption(text: 'Lack of sufficient provocation', isCorrect: false, rationale: 'This is the third requisite.'),
      ],
      difficulty: Difficulty.values[i % 3],
      explanation: 'Article 11(1) lists three requisites; a written warning is not one of them.',
      legalBasis: 'RPC Art. 11',
      source: QuestionSource.generated,
      templateId: uploadId,
      version: 1,
    );

/// Recent PDF uploads: one still being written, one ready, one failed.
class FakeDocumentGenerationService extends DocumentGenerationService {
  FakeDocumentGenerationService() : super.forTesting();

  static DocumentUpload sample(String status,
          {int generated = 0, String? error, int minutesAgo = 1, String? topic, String? tosCode}) =>
      DocumentUpload(
        id: 'doc_$status',
        filename: {
          'processing': 'RA_11131_Criminology_Profession_Act.pdf',
          'completed': 'Justifying_Circumstances_Reviewer.pdf',
          'failed': 'Corrections_Handout_2026.pdf',
        }[status]!,
        subjectId: {'processing': 'criminology', 'completed': 'criminal_jurisprudence', 'failed': 'corrections'}[status]!,
        topic: topic,
        tosCode: tosCode,
        requestedCount: 10,
        status: status,
        generatedCount: generated,
        errorMessage: error,
        createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      );

  @override
  Future<List<DocumentUpload>> recentUploads({int limit = 20}) async => [
        sample('processing', tosCode: 'CRIM-4.3', topic: 'Professional Conduct and Ethical Standards for Criminologists'),
        sample('completed', generated: 4, minutesAgo: 30, topic: 'Justifying Circumstances',
            error: '1 question(s) were skipped (incomplete or duplicate).'),
        sample('failed', minutesAgo: 300,
            error: "Gemini's free limit was reached. Try again later; the free quota resets every day."),
      ];
}
