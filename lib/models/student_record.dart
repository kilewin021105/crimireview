import 'dart:convert';

import 'mastery.dart';
import 'question.dart';
import 'user_progress.dart';

/// One student's full record as Faculty see it: what
/// `admin_student_record` (supabase_student_record.sql) returns.
///
/// Everything here comes from what the student's phone last synced. The
/// parsing never throws on a missing or odd field, so one bad row cannot
/// blank the whole screen.
class StudentRecord {
  final String userId;
  final String email;
  final String displayName;
  final String? school;
  final String role;
  final String rank;
  final int totalPoints;
  final int currentStreak;
  final int bestStreak;
  final DateTime? joinedAt;

  /// Keyed by subject id. Subjects the student never studied are absent.
  final Map<String, SubjectRecord> subjects;

  /// Weakest first, as the database sends them.
  final List<TopicRecord> topics;

  /// The most recent quizzes, newest first (at most 30).
  final List<QuizRecord> recentQuizzes;

  /// All quizzes ever saved, not just [recentQuizzes].
  final int quizCount;
  final int dailyChallenges;
  final int achievements;

  const StudentRecord({
    required this.userId,
    required this.email,
    required this.displayName,
    this.school,
    this.role = 'student',
    this.rank = 'Rookie',
    this.totalPoints = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.joinedAt,
    this.subjects = const {},
    this.topics = const [],
    this.recentQuizzes = const [],
    this.quizCount = 0,
    this.dailyChallenges = 0,
    this.achievements = 0,
  });

  factory StudentRecord.fromJson(Map<String, dynamic> json) {
    final profile = _map(json['profile']);
    final subjects = <String, SubjectRecord>{};
    for (final row in _list(json['subjects'])) {
      final s = SubjectRecord.fromJson(_map(row));
      if (s.subjectId.isNotEmpty) subjects[s.subjectId] = s;
    }
    final school = _str(profile['school']).trim();
    return StudentRecord(
      userId: _str(profile['user_id']),
      email: _str(profile['email']),
      displayName: _str(profile['display_name']).trim().isEmpty ? 'Student' : _str(profile['display_name']),
      school: school.isEmpty ? null : school,
      role: _str(profile['role']).isEmpty ? 'student' : _str(profile['role']),
      rank: _str(profile['rank']).isEmpty ? 'Rookie' : _str(profile['rank']),
      totalPoints: _int(profile['total_points']),
      currentStreak: _int(profile['current_streak']),
      bestStreak: _int(profile['best_streak']),
      joinedAt: _date(profile['joined_at']),
      subjects: subjects,
      topics: [for (final row in _list(json['mastery'])) TopicRecord.fromJson(_map(row))],
      recentQuizzes: [for (final row in _list(json['quizzes'])) QuizRecord.fromJson(_map(row))],
      quizCount: _int(json['quiz_count']),
      dailyChallenges: _int(json['daily_challenges']),
      achievements: _int(json['achievements']),
    );
  }

  /// Questions answered across all subjects.
  int get questionsAnswered => subjects.values.fold(0, (s, r) => s + r.questionsAnswered);

  /// Correct answers across all subjects.
  int get correctAnswers => subjects.values.fold(0, (s, r) => s + r.correctAnswers);

  /// Overall share correct, 0 to 1. Null when nothing was answered.
  double? get accuracy => questionsAnswered == 0 ? null : correctAnswers / questionsAnswered;

  /// Same rule as the Students list ("Mastered" uses the flag the phone
  /// uploads), so the two screens always show the same numbers.
  int get topicsMastered => topics.where((t) => t.isMastered).length;
  int get topicsNeedingReview => topics.where((t) => t.needsReview).length;

  /// The latest moment the student studied anything, from any source.
  DateTime? get lastActive {
    DateTime? latest;
    void consider(DateTime? d) {
      if (d != null && (latest == null || d.isAfter(latest!))) latest = d;
    }

    for (final s in subjects.values) {
      consider(s.lastStudyDate);
    }
    for (final t in topics) {
      consider(t.lastPracticed);
    }
    if (recentQuizzes.isNotEmpty) consider(recentQuizzes.first.takenAt);
    return latest;
  }
}

/// One subject's progress through Easy, Medium and Hard.
class SubjectRecord {
  final String subjectId;
  final int questionsAnswered;
  final int correctAnswers;
  final DateTime? lastStudyDate;
  final LevelRecord easy;
  final LevelRecord medium;
  final LevelRecord hard;

  const SubjectRecord({
    required this.subjectId,
    this.questionsAnswered = 0,
    this.correctAnswers = 0,
    this.lastStudyDate,
    required this.easy,
    required this.medium,
    required this.hard,
  });

  factory SubjectRecord.fromJson(Map<String, dynamic> json) => SubjectRecord(
        subjectId: _str(json['subject_id']),
        questionsAnswered: _int(json['questions_answered']),
        correctAnswers: _int(json['correct_answers']),
        lastStudyDate: _date(json['last_study_date']),
        easy: LevelRecord(
          correct: _int(json['easy_correct']),
          total: _int(json['easy_total']),
          segments: parseSegments(json['easy_segments']),
        ),
        medium: LevelRecord(
          correct: _int(json['medium_correct']),
          total: _int(json['medium_total']),
          segments: parseSegments(json['medium_segments']),
        ),
        hard: LevelRecord(
          correct: _int(json['hard_correct']),
          total: _int(json['hard_total']),
          segments: parseSegments(json['hard_segments']),
        ),
      );

  LevelRecord level(Difficulty d) => switch (d) {
        Difficulty.easy => easy,
        Difficulty.medium => medium,
        Difficulty.hard => hard,
      };

  /// Whether the student can open [d] on the difficulty sheet. The same gate
  /// the app uses: Easy is always open, Medium after all 4 Easy segments are
  /// passed, Hard after all 4 Medium segments are passed.
  bool isUnlocked(Difficulty d) => switch (d) {
        Difficulty.easy => true,
        Difficulty.medium => easy.passed,
        Difficulty.hard => medium.passed,
      };

  /// The highest level the student can open.
  Difficulty get levelReached => medium.passed
      ? Difficulty.hard
      : easy.passed
          ? Difficulty.medium
          : Difficulty.easy;

  /// All three levels passed.
  bool get allPassed => easy.passed && medium.passed && hard.passed;

  bool get started =>
      questionsAnswered > 0 || easy.attempted || medium.attempted || hard.attempted;
}

/// One level of one subject: its totals and its 4 segments of 10 questions.
class LevelRecord {
  final int correct;
  final int total;

  /// Always exactly [SegmentProgress.segmentCount] entries.
  final List<SegmentProgress> segments;

  const LevelRecord({this.correct = 0, this.total = 0, required this.segments});

  int get segmentsPassed => segments.where((s) => s.isPassed).length;

  /// All 4 segments passed (10 answered, 75% or more each).
  bool get passed => segments.isNotEmpty && segments.every((s) => s.isPassed);

  bool get attempted => total > 0 || segments.any((s) => s.isAttempted);

  /// Share correct in this level, 0 to 1. Null when nothing was answered.
  double? get accuracy => total == 0 ? null : correct / total;
}

/// A topic's mastery as last synced.
class TopicRecord {
  final String subjectId;
  final String topic;

  /// Bayesian Knowledge Tracing p(known), 0 to 1.
  final double pKnown;
  final int attempts;
  final int correct;

  /// The flag the phone uploads (p(known) at least 0.90 with 4 or more
  /// answers). Used as-is so this screen matches the Students list.
  final bool isMastered;
  final DateTime? lastPracticed;

  const TopicRecord({
    required this.subjectId,
    required this.topic,
    required this.pKnown,
    this.attempts = 0,
    this.correct = 0,
    this.isMastered = false,
    this.lastPracticed,
  });

  factory TopicRecord.fromJson(Map<String, dynamic> json) => TopicRecord(
        subjectId: _str(json['subject_id']),
        topic: _str(json['topic']),
        pKnown: _double(json['p_known']).clamp(0.0, 1.0).toDouble(),
        attempts: _int(json['attempts']),
        correct: _int(json['correct']),
        isMastered: json['is_mastered'] == true,
        lastPracticed: _date(json['last_practiced']),
      );

  /// Same rule as the Students list's "Needs review": p(known) below 0.60
  /// after 3 or more answers.
  bool get needsReview =>
      pKnown < TopicMastery.remediationThreshold && attempts >= TopicMastery.remediationMinAttempts;

  /// The band name the student app uses (Struggling, Developing, ...).
  String get bandLabel => TopicMastery(
        subjectId: subjectId,
        topic: topic,
        pKnown: pKnown,
        attempts: attempts,
        correct: correct,
      ).levelLabel;
}

/// One finished quiz.
class QuizRecord {
  final String subjectId;

  /// Null when the stored value is not easy, medium or hard.
  final Difficulty? difficulty;

  /// Percent, 0 to 100.
  final int score;
  final int correct;
  final int total;
  final int? timeTakenSeconds;
  final DateTime? takenAt;

  const QuizRecord({
    required this.subjectId,
    this.difficulty,
    this.score = 0,
    this.correct = 0,
    this.total = 0,
    this.timeTakenSeconds,
    this.takenAt,
  });

  factory QuizRecord.fromJson(Map<String, dynamic> json) {
    final d = _str(json['difficulty']).toLowerCase();
    final time = json['time_taken_seconds'];
    return QuizRecord(
      subjectId: _str(json['subject_id']),
      difficulty: Difficulty.values.where((v) => v.name == d).firstOrNull,
      score: _int(json['score']),
      correct: _int(json['correct_answers']),
      total: _int(json['total_questions']),
      timeTakenSeconds: time == null ? null : _int(time),
      takenAt: _date(json['created_at']),
    );
  }
}

/// Reads a level's segments as the phone uploads them
/// (`[{segmentIndex, questionsAnswered, correctAnswers}, ...]`), always
/// returning exactly 4. Segments are matched by position, the same way the
/// app merges cloud progress; anything missing or unreadable counts as not
/// started.
List<SegmentProgress> parseSegments(dynamic raw) {
  var value = raw;
  if (value is String && value.trim().isNotEmpty) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      value = null;
    }
  }
  final list = value is List ? value : const [];
  return List.generate(SegmentProgress.segmentCount, (i) {
    final item = i < list.length && list[i] is Map ? Map<String, dynamic>.from(list[i] as Map) : null;
    if (item == null) return SegmentProgress(segmentIndex: i);
    final answered = _int(item['questionsAnswered']);
    final correct = _int(item['correctAnswers']);
    return SegmentProgress(
      segmentIndex: i,
      questionsAnswered: answered < 0 ? 0 : answered,
      correctAnswers: correct < 0 ? 0 : (correct > answered ? answered : correct),
    );
  });
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _list(dynamic v) => v is List ? v : const [];

String _str(dynamic v) => v == null ? '' : v.toString();

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0.0;
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
