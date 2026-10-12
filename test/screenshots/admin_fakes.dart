// Sample data for the admin screens in screenshot runs (no database).

import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/subject.dart';
import 'package:crimireview/services/admin_service.dart';

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
