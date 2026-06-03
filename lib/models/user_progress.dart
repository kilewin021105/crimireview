import 'dart:convert';
import 'package:flutter/material.dart';
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

class SegmentProgress {
  static const int questionsPerSegment = 10;
  static const double passThreshold = 0.75;
  
  final int segmentIndex; // 0-3 (segments 1-4)
  int questionsAnswered;
  int correctAnswers;
  
  SegmentProgress({
    required this.segmentIndex,
    this.questionsAnswered = 0,
    this.correctAnswers = 0,
  });
  
  double get accuracy => questionsAnswered > 0 ? correctAnswers / questionsAnswered : 0.0;
  
  bool get isPassed => questionsAnswered >= questionsPerSegment && accuracy >= passThreshold;
  
  bool get isCompleted => questionsAnswered >= questionsPerSegment;
  
  Color get statusColor {
    if (!isCompleted) return Colors.grey;
    return isPassed ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
  }
  
  Map<String, dynamic> toJson() => {
        'segmentIndex': segmentIndex,
        'questionsAnswered': questionsAnswered,
        'correctAnswers': correctAnswers,
      };
  
  factory SegmentProgress.fromJson(Map<String, dynamic> json) => SegmentProgress(
        segmentIndex: json['segmentIndex'],
        questionsAnswered: json['questionsAnswered'] ?? 0,
        correctAnswers: json['correctAnswers'] ?? 0,
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
  static const double levelPassThreshold = 0.75;

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
  // Per-difficulty stats for cloud sync
  int easyCorrect;
  int easyTotal;
  int mediumCorrect;
  int mediumTotal;
  int hardCorrect;
  int hardTotal;
  // Segment progress: 4 segments of 10 questions each per difficulty
  List<SegmentProgress> easySegments;
  List<SegmentProgress> mediumSegments;
  List<SegmentProgress> hardSegments;
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
    this.easyCorrect = 0,
    this.easyTotal = 0,
    this.mediumCorrect = 0,
    this.mediumTotal = 0,
    this.hardCorrect = 0,
    this.hardTotal = 0,
    List<SegmentProgress>? easySegments,
    List<SegmentProgress>? mediumSegments,
    List<SegmentProgress>? hardSegments,
    Set<String>? wrongQuestionIds,
  }) : topicProgress = topicProgress ?? {},
       easySegments = easySegments ?? List.generate(4, (i) => SegmentProgress(segmentIndex: i)),
       mediumSegments = mediumSegments ?? List.generate(4, (i) => SegmentProgress(segmentIndex: i)),
       hardSegments = hardSegments ?? List.generate(4, (i) => SegmentProgress(segmentIndex: i)),
       wrongQuestionIds = wrongQuestionIds ?? {};

  // Aliases for consistency
  int get correctAnswers => totalCorrectAnswers;
  int get totalAnswered => totalQuestionsAnswered;

  double get overallAccuracy =>
      totalQuestionsAnswered > 0 ? totalCorrectAnswers / totalQuestionsAnswered : 0.0;

  double get easyAccuracy => easyTotal > 0 ? easyCorrect / easyTotal : 0.0;
  double get mediumAccuracy => mediumTotal > 0 ? mediumCorrect / mediumTotal : 0.0;
  double get hardAccuracy => hardTotal > 0 ? hardCorrect / hardTotal : 0.0;

  /// Board exam readiness based on PRC TOS weights:
  /// Easy 30%, Medium 50%, Hard 20%
  /// Unattempted difficulties penalize the score
  double get boardExamReadiness {
    // PRC TOS difficulty distribution weights
    const easyWeight = 0.30;
    const mediumWeight = 0.50;
    const hardWeight = 0.20;

    final eAcc = easyAccuracy;
    final mAcc = mediumAccuracy;
    final hAcc = hardAccuracy;

    final hasEasy = easyTotal > 0;
    final hasMedium = mediumTotal > 0;
    final hasHard = hardTotal > 0;

    if (!hasEasy && !hasMedium && !hasHard) return 0.0;

    // If difficulty not attempted, assume baseline 40% (below passing)
    final effectiveEasy = hasEasy ? eAcc : 0.40;
    final effectiveMedium = hasMedium ? mAcc : 0.40;
    final effectiveHard = hasHard ? hAcc : 0.40;

    double weighted = (effectiveEasy * easyWeight) +
                      (effectiveMedium * mediumWeight) +
                      (effectiveHard * hardWeight);

    // Completion bonus: up to +5% for completing all 3 difficulties
    int completedLevels = 0;
    if (hasEasy) completedLevels++;
    if (hasMedium) completedLevels++;
    if (hasHard) completedLevels++;
    final completionBonus = (completedLevels / 3.0) * 5.0;

    return ((weighted * 100) + completionBonus).clamp(0.0, 100.0);
  }

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
        'easyCorrect': easyCorrect,
        'easyTotal': easyTotal,
        'mediumCorrect': mediumCorrect,
        'mediumTotal': mediumTotal,
        'hardCorrect': hardCorrect,
        'hardTotal': hardTotal,
        'easySegments': easySegments.map((s) => s.toJson()).toList(),
        'mediumSegments': mediumSegments.map((s) => s.toJson()).toList(),
        'hardSegments': hardSegments.map((s) => s.toJson()).toList(),
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
        easyCorrect: json['easyCorrect'] ?? 0,
        easyTotal: json['easyTotal'] ?? 0,
        mediumCorrect: json['mediumCorrect'] ?? 0,
        mediumTotal: json['mediumTotal'] ?? 0,
        hardCorrect: json['hardCorrect'] ?? 0,
        hardTotal: json['hardTotal'] ?? 0,
        easySegments: (json['easySegments'] as List<dynamic>?)
            ?.map((s) => SegmentProgress.fromJson(s))
            .toList(),
        mediumSegments: (json['mediumSegments'] as List<dynamic>?)
            ?.map((s) => SegmentProgress.fromJson(s))
            .toList(),
        hardSegments: (json['hardSegments'] as List<dynamic>?)
            ?.map((s) => SegmentProgress.fromJson(s))
            .toList(),
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
