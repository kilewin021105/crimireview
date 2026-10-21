import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/student_record.dart';

List<Map<String, dynamic>> segs(List<List<int>> answeredCorrect) => [
      for (var i = 0; i < answeredCorrect.length; i++)
        {'segmentIndex': i, 'questionsAnswered': answeredCorrect[i][0], 'correctAnswers': answeredCorrect[i][1]},
    ];

final passedLevel = segs([[10, 9], [10, 8], [10, 8], [10, 8]]);

Map<String, dynamic> subject({dynamic easy, dynamic medium, dynamic hard, int answered = 0}) => {
      'subject_id': 'criminal_jurisprudence',
      'questions_answered': answered,
      'correct_answers': 0,
      'easy_segments': easy,
      'medium_segments': medium,
      'hard_segments': hard,
    };

void main() {
  group('parseSegments', () {
    test('always returns 4, in order', () {
      expect(parseSegments(null), hasLength(4));
      expect(parseSegments([]), hasLength(4));
      final s = parseSegments(segs([[10, 8], [4, 3]]));
      expect(s.map((e) => e.segmentIndex), [0, 1, 2, 3]);
      expect(s[0].questionsAnswered, 10);
      expect(s[1].correctAnswers, 3);
      expect(s[2].isAttempted, isFalse);
    });

    test('reads a JSON string and ignores garbage', () {
      expect(parseSegments('[{"questionsAnswered":10,"correctAnswers":8}]')[0].isPassed, isTrue);
      expect(parseSegments('not json')[0].isAttempted, isFalse);
      expect(parseSegments(['x', 5, null, {'questionsAnswered': '10', 'correctAnswers': 9}])[3].isPassed, isTrue);
    });

    test('never lets correct exceed answered', () {
      final s = parseSegments(segs([[10, 14]]));
      expect(s[0].correctAnswers, 10);
    });
  });

  group('level reached (same gate as the difficulty sheet)', () {
    test('new student: on Easy, Medium and Hard locked', () {
      final r = SubjectRecord.fromJson(subject());
      expect(r.levelReached, Difficulty.easy);
      expect(r.isUnlocked(Difficulty.medium), isFalse);
      expect(r.isUnlocked(Difficulty.hard), isFalse);
      expect(r.started, isFalse);
    });

    test('3 of 4 Easy segments passed: still on Easy', () {
      final r = SubjectRecord.fromJson(subject(easy: segs([[10, 9], [10, 8], [10, 8], [10, 7]])));
      expect(r.easy.segmentsPassed, 3);
      expect(r.easy.passed, isFalse);
      expect(r.levelReached, Difficulty.easy);
    });

    test('a segment needs 10 answers, not just 75%', () {
      final r = SubjectRecord.fromJson(subject(easy: segs([[10, 9], [10, 8], [10, 8], [8, 8]])));
      expect(r.easy.passed, isFalse);
    });

    test('all Easy passed: Medium opens', () {
      final r = SubjectRecord.fromJson(subject(easy: passedLevel));
      expect(r.levelReached, Difficulty.medium);
      expect(r.isUnlocked(Difficulty.medium), isTrue);
      expect(r.isUnlocked(Difficulty.hard), isFalse);
    });

    test('Easy and Medium passed: Hard opens', () {
      final r = SubjectRecord.fromJson(subject(easy: passedLevel, medium: passedLevel));
      expect(r.levelReached, Difficulty.hard);
      expect(r.allPassed, isFalse);
    });

    test('everything passed', () {
      final r = SubjectRecord.fromJson(subject(easy: passedLevel, medium: passedLevel, hard: passedLevel));
      expect(r.allPassed, isTrue);
    });
  });

  group('StudentRecord', () {
    final json = {
      'success': true,
      'profile': {
        'user_id': 'u1',
        'email': 'juan@example.com',
        'display_name': 'Juan',
        'school': '  ',
        'total_points': 1770,
        'current_streak': 3,
        'best_streak': 9,
        'joined_at': '2026-09-01T00:00:00Z',
      },
      'subjects': [
        {
          'subject_id': 'criminal_jurisprudence',
          'questions_answered': 60,
          'correct_answers': 45,
          'easy_segments': passedLevel,
          'last_study_date': '2026-10-20T08:00:00Z',
        },
        {'subject_id': 'criminology', 'questions_answered': 20, 'correct_answers': 15},
      ],
      'mastery': [
        {'subject_id': 'criminology', 'topic': 'Theories', 'p_known': '0.41', 'attempts': 4, 'is_mastered': false},
        {'subject_id': 'criminology', 'topic': 'Strain', 'p_known': 0.55, 'attempts': 2, 'is_mastered': false},
        {'subject_id': 'criminal_jurisprudence', 'topic': 'Art. 11', 'p_known': 0.95, 'attempts': 6, 'is_mastered': true,
         'last_practiced': '2026-10-21T01:00:00Z'},
      ],
      'quizzes': [
        {'subject_id': 'criminology', 'difficulty': 'medium', 'score': 70, 'total_questions': 10, 'correct_answers': 7,
         'created_at': '2026-10-19T00:00:00Z'},
        {'subject_id': 'criminology', 'difficulty': 'weird', 'score': 50, 'total_questions': 10, 'correct_answers': 5},
      ],
      'quiz_count': 42,
      'daily_challenges': 5,
      'achievements': 3,
    };

    test('reads the profile, subjects and counts', () {
      final r = StudentRecord.fromJson(json);
      expect(r.displayName, 'Juan');
      expect(r.school, isNull, reason: 'a blank school is shown as none');
      expect(r.totalPoints, 1770);
      expect(r.subjects.keys, ['criminal_jurisprudence', 'criminology']);
      expect(r.subjects['criminal_jurisprudence']!.levelReached, Difficulty.medium);
      expect(r.quizCount, 42);
      expect(r.recentQuizzes, hasLength(2));
    });

    test('accuracy is total correct over total answered', () {
      final r = StudentRecord.fromJson(json);
      expect(r.questionsAnswered, 80);
      expect(r.accuracy, closeTo(60 / 80, 1e-9));
      expect(const StudentRecord(userId: 'x', email: '', displayName: 'x').accuracy, isNull);
    });

    test('mastered and needs-review use the same rules as the Students list', () {
      final r = StudentRecord.fromJson(json);
      expect(r.topicsMastered, 1);
      // Theories: 0.41 after 4 answers -> needs review. Strain: 0.55 after
      // only 2 answers -> not yet.
      expect(r.topicsNeedingReview, 1);
      expect(r.topics.first.pKnown, closeTo(0.41, 1e-9), reason: 'numeric strings are accepted');
      expect(r.topics.first.bandLabel, 'Developing');
    });

    test('an unknown difficulty is kept as null instead of failing', () {
      final r = StudentRecord.fromJson(json);
      expect(r.recentQuizzes[0].difficulty, Difficulty.medium);
      expect(r.recentQuizzes[1].difficulty, isNull);
    });

    test('last active is the latest date from any source', () {
      final r = StudentRecord.fromJson(json);
      expect(r.lastActive, DateTime.parse('2026-10-21T01:00:00Z').toLocal());
    });

    test('an empty response does not throw', () {
      final r = StudentRecord.fromJson(const {});
      expect(r.displayName, 'Student');
      expect(r.subjects, isEmpty);
      expect(r.lastActive, isNull);
    });
  });
}
