import 'dart:convert';
import 'question.dart';

class QuestionAttempt {
  final String questionId;
  final bool isCorrect;
  final DateTime timestamp;
  final int responseTimeMs;

  QuestionAttempt({
    required this.questionId,
    required this.isCorrect,
    required this.timestamp,
    required this.responseTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'isCorrect': isCorrect,
        'timestamp': timestamp.toIso8601String(),
        'responseTimeMs': responseTimeMs,
      };

  factory QuestionAttempt.fromJson(Map<String, dynamic> json) => QuestionAttempt(
        questionId: json['questionId'],
        isCorrect: json['isCorrect'],
        timestamp: DateTime.parse(json['timestamp']),
        responseTimeMs: json['responseTimeMs'],
      );
}

class TopicProgress {
  final String topicName;
  int totalAttempts;
  int correctAnswers;
  Difficulty currentDifficulty;
  List<QuestionAttempt> recentAttempts;

  TopicProgress({
    required this.topicName,
    this.totalAttempts = 0,
    this.correctAnswers = 0,
    this.currentDifficulty = Difficulty.easy,
    List<QuestionAttempt>? recentAttempts,
  }) : recentAttempts = recentAttempts ?? [];

  double get accuracy => totalAttempts > 0 ? correctAnswers / totalAttempts : 0.0;

  double get masteryLevel {
    if (totalAttempts < 5) return 0.0;
    
    double baseAccuracy = accuracy;
    double difficultyBonus = currentDifficulty.index * 0.1;
    
    return (baseAccuracy + difficultyBonus).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'topicName': topicName,
        'totalAttempts': totalAttempts,
        'correctAnswers': correctAnswers,
        'currentDifficulty': currentDifficulty.index,
        'recentAttempts': recentAttempts.map((a) => a.toJson()).toList(),
      };

  factory TopicProgress.fromJson(Map<String, dynamic> json) => TopicProgress(
        topicName: json['topicName'],
        totalAttempts: json['totalAttempts'],
        correctAnswers: json['correctAnswers'],
        currentDifficulty: Difficulty.values[json['currentDifficulty']],
        recentAttempts: (json['recentAttempts'] as List)
            .map((a) => QuestionAttempt.fromJson(a))
            .toList(),
      );
}

class SubjectProgress {
  final String subjectId;
  Map<String, TopicProgress> topicProgress;
  int totalQuizzesTaken;
  int totalQuestionsAnswered;
  int totalCorrectAnswers;
  DateTime? lastStudyDate;
  // Level progress: tracks if Easy/Medium/Hard is passed (75%+ accuracy)
  bool easyPassed;
  bool mediumPassed;
  bool hardPassed;
  // Track wrong answers for review
  Set<String> wrongQuestionIds;

  SubjectProgress({
    required this.subjectId,
    Map<String, TopicProgress>? topicProgress,
    this.totalQuizzesTaken = 0,
    this.totalQuestionsAnswered = 0,
    this.totalCorrectAnswers = 0,
    this.lastStudyDate,
    this.easyPassed = false,
    this.mediumPassed = false,
    this.hardPassed = false,
    Set<String>? wrongQuestionIds,
  }) : topicProgress = topicProgress ?? {},
       wrongQuestionIds = wrongQuestionIds ?? {};

  // Aliases for consistency
  int get correctAnswers => totalCorrectAnswers;
  int get totalAnswered => totalQuestionsAnswered;

  double get overallAccuracy =>
      totalQuestionsAnswered > 0 ? totalCorrectAnswers / totalQuestionsAnswered : 0.0;

  double get overallMastery {
    if (topicProgress.isEmpty) return 0.0;
    double totalMastery = topicProgress.values.fold(0.0, (sum, tp) => sum + tp.masteryLevel);
    return totalMastery / topicProgress.length;
  }

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'topicProgress': topicProgress.map((k, v) => MapEntry(k, v.toJson())),
        'totalQuizzesTaken': totalQuizzesTaken,
        'totalQuestionsAnswered': totalQuestionsAnswered,
        'totalCorrectAnswers': totalCorrectAnswers,
        'lastStudyDate': lastStudyDate?.toIso8601String(),
        'easyPassed': easyPassed,
        'mediumPassed': mediumPassed,
        'hardPassed': hardPassed,
        'wrongQuestionIds': wrongQuestionIds.toList(),
      };

  factory SubjectProgress.fromJson(Map<String, dynamic> json) => SubjectProgress(
        subjectId: json['subjectId'],
        topicProgress: (json['topicProgress'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, TopicProgress.fromJson(v)),
        ),
        totalQuizzesTaken: json['totalQuizzesTaken'],
        totalQuestionsAnswered: json['totalQuestionsAnswered'],
        totalCorrectAnswers: json['totalCorrectAnswers'],
        lastStudyDate: json['lastStudyDate'] != null
            ? DateTime.parse(json['lastStudyDate'])
            : null,
        easyPassed: json['easyPassed'] ?? false,
        mediumPassed: json['mediumPassed'] ?? false,
        hardPassed: json['hardPassed'] ?? false,
        wrongQuestionIds: (json['wrongQuestionIds'] as List<dynamic>?)
            ?.cast<String>().toSet() ?? {},
      );
}

class UserProgress {
  String userName;
  Map<String, SubjectProgress> subjectProgress;
  int totalStudyTimeMinutes;
  int currentStreak;
  int longestStreak;
  DateTime? lastActiveDate;
  List<String> unlockedAchievements;
  int perfectScores;

  UserProgress({
    this.userName = 'Student',
    Map<String, SubjectProgress>? subjectProgress,
    this.totalStudyTimeMinutes = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
    List<String>? unlockedAchievements,
    this.perfectScores = 0,
  }) : subjectProgress = subjectProgress ?? {},
       unlockedAchievements = unlockedAchievements ?? [];

  double get overallProgress {
    if (subjectProgress.isEmpty) return 0.0;
    double total = subjectProgress.values.fold(0.0, (sum, sp) => sum + sp.overallMastery);
    return total / 6; // 6 subjects
  }

  String toJsonString() => jsonEncode({
        'userName': userName,
        'subjectProgress': subjectProgress.map((k, v) => MapEntry(k, v.toJson())),
        'totalStudyTimeMinutes': totalStudyTimeMinutes,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastActiveDate': lastActiveDate?.toIso8601String(),
        'unlockedAchievements': unlockedAchievements,
        'perfectScores': perfectScores,
      });

  factory UserProgress.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString);
    return UserProgress(
      userName: json['userName'],
      subjectProgress: (json['subjectProgress'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, SubjectProgress.fromJson(v)),
      ),
      totalStudyTimeMinutes: json['totalStudyTimeMinutes'],
      currentStreak: json['currentStreak'],
      longestStreak: json['longestStreak'],
      lastActiveDate: json['lastActiveDate'] != null
          ? DateTime.parse(json['lastActiveDate'])
          : null,
      unlockedAchievements: (json['unlockedAchievements'] as List<dynamic>?)?.cast<String>() ?? [],
      perfectScores: json['perfectScores'] ?? 0,
    );
  }
}
