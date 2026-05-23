import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../models/achievement.dart';
import '../data/questions_database.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class AdaptiveLearningService extends ChangeNotifier {
  final StorageService _storageService;
  UserProgress _userProgress = UserProgress();
  final Random _random = Random();
  bool _isInitialized = false;

  AdaptiveLearningService(this._storageService) {
    _initProgress();
  }

  Future<void> _initProgress() async {
    _userProgress = await _storageService.loadProgress();
    _isInitialized = true;
    notifyListeners();
  }

  bool get isInitialized => _isInitialized;
  UserProgress get userProgress => _userProgress;

  Future<void> resetProgress() async {
    _userProgress = UserProgress();
    _isInitialized = false;
    await _initProgress();
  }

  // Get adaptive questions based on user's performance
  List<Question> getAdaptiveQuestions({
    required String subjectId,
    int count = 10,
    String? specificTopic,
  }) {
    List<Question> availableQuestions;

    if (specificTopic != null) {
      availableQuestions = QuestionsDatabase.getByTopic(subjectId, specificTopic);
    } else {
      availableQuestions = QuestionsDatabase.getBySubject(subjectId);
    }

    if (availableQuestions.isEmpty) return [];

    // Get user's progress for this subject
    final subjectProgress = _userProgress.subjectProgress[subjectId];
    Difficulty targetDifficulty = _determineTargetDifficulty(subjectProgress);

    // Prioritize questions based on adaptive algorithm
    List<Question> selectedQuestions = _selectAdaptiveQuestions(
      availableQuestions,
      targetDifficulty,
      subjectProgress,
      count,
    );

    return selectedQuestions;
  }

  Difficulty _determineTargetDifficulty(SubjectProgress? progress) {
    if (progress == null || progress.totalQuestionsAnswered < 5) {
      return Difficulty.easy; // Start with easy for new users
    }

    double accuracy = progress.overallAccuracy;

    // Adaptive difficulty adjustment
    if (accuracy >= 0.8) {
      return Difficulty.hard;
    } else if (accuracy >= 0.6) {
      return Difficulty.medium;
    } else {
      return Difficulty.easy;
    }
  }

  List<Question> _selectAdaptiveQuestions(
    List<Question> available,
    Difficulty targetDifficulty,
    SubjectProgress? progress,
    int count,
  ) {
    List<Question> selected = [];
    
    // Group by difficulty
    final easyQuestions = available.where((q) => q.difficulty == Difficulty.easy).toList();
    final mediumQuestions = available.where((q) => q.difficulty == Difficulty.medium).toList();
    final hardQuestions = available.where((q) => q.difficulty == Difficulty.hard).toList();

    // 2026 PRC TOS Distribution: 30% Easy, 50% Moderate, 20% Hard
    // Adaptive adjustment based on user performance
    int easyCount, mediumCount, hardCount;
    
    switch (targetDifficulty) {
      case Difficulty.easy:
        // Struggling user: more easy questions
        easyCount = (count * 0.5).round();
        mediumCount = (count * 0.4).round();
        hardCount = count - easyCount - mediumCount;
        break;
      case Difficulty.medium:
        // Average user: PRC standard distribution
        easyCount = (count * 0.3).round();
        mediumCount = (count * 0.5).round();
        hardCount = count - easyCount - mediumCount;
        break;
      case Difficulty.hard:
        // Advanced user: more challenging
        easyCount = (count * 0.2).round();
        mediumCount = (count * 0.4).round();
        hardCount = count - easyCount - mediumCount;
        break;
    }

    // Add questions, prioritizing weak topics if progress exists
    _addQuestionsWithPriority(selected, easyQuestions, easyCount, progress);
    _addQuestionsWithPriority(selected, mediumQuestions, mediumCount, progress);
    _addQuestionsWithPriority(selected, hardQuestions, hardCount, progress);

    // Fill remaining slots if needed
    while (selected.length < count && selected.length < available.length) {
      final remaining = available.where((q) => !selected.contains(q)).toList();
      if (remaining.isEmpty) break;
      selected.add(remaining[_random.nextInt(remaining.length)]);
    }

    // Shuffle for variety
    selected.shuffle(_random);
    
    return selected;
  }

  void _addQuestionsWithPriority(
    List<Question> selected,
    List<Question> pool,
    int count,
    SubjectProgress? progress,
  ) {
    if (pool.isEmpty || count <= 0) return;

    List<Question> prioritized;

    if (progress != null) {
      // Prioritize topics where user is weak
      prioritized = pool.where((q) {
        final topicProgress = progress.topicProgress[q.topic];
        if (topicProgress == null) return true; // New topic = priority
        return topicProgress.accuracy < 0.6; // Weak topic = priority
      }).toList();
    } else {
      prioritized = pool;
    }

    // Add prioritized questions first
    prioritized.shuffle(_random);
    for (var q in prioritized.take(count)) {
      if (!selected.contains(q)) {
        selected.add(q);
      }
    }

    // Fill remaining from pool
    pool.shuffle(_random);
    for (var q in pool) {
      if (selected.length >= count) break;
      if (!selected.contains(q)) {
        selected.add(q);
      }
    }
  }

  // Record quiz result and update progress
  Future<void> recordQuizResult({
    required String subjectId,
    required List<Question> questions,
    required List<bool> results,
    required List<int> responseTimes,
  }) async {
    // Ensure subject progress exists
    _userProgress.subjectProgress.putIfAbsent(
      subjectId,
      () => SubjectProgress(subjectId: subjectId),
    );

    final subjectProgress = _userProgress.subjectProgress[subjectId]!;
    subjectProgress.totalQuizzesTaken++;
    subjectProgress.lastStudyDate = DateTime.now();

    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final isCorrect = results[i];
      final responseTime = responseTimes[i];

      // Update subject-level stats
      subjectProgress.totalQuestionsAnswered++;
      if (isCorrect) {
        subjectProgress.totalCorrectAnswers++;
        // Remove from wrong questions if answered correctly
        subjectProgress.wrongQuestionIds.remove(question.id);
      } else {
        // Add to wrong questions for review
        subjectProgress.wrongQuestionIds.add(question.id);
      }

      // Update topic-level stats
      subjectProgress.topicProgress.putIfAbsent(
        question.topic,
        () => TopicProgress(topicName: question.topic),
      );

      final topicProgress = subjectProgress.topicProgress[question.topic]!;
      topicProgress.totalAttempts++;
      if (isCorrect) topicProgress.correctAnswers++;

      // Record attempt
      topicProgress.recentAttempts.add(QuestionAttempt(
        questionId: question.id,
        isCorrect: isCorrect,
        timestamp: DateTime.now(),
        responseTimeMs: responseTime,
      ));

      // Keep only last 20 attempts
      if (topicProgress.recentAttempts.length > 20) {
        topicProgress.recentAttempts.removeAt(0);
      }

      // Adjust difficulty based on recent performance
      _adjustTopicDifficulty(topicProgress);
    }

    // Check for perfect score
    if (results.every((r) => r)) {
      _userProgress.perfectScores++;
    }

    // Update streak
    _updateStreak();
    
    // Check achievements
    _checkAchievements();

    // Save progress
    await _storageService.saveProgress(_userProgress);
    notifyListeners();
  }
  
  void _checkAchievements() {
    final totalQuizzes = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + (_userProgress.subjectProgress[s.id]?.totalQuizzesTaken ?? 0),
    );
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + (_userProgress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0),
    );
    
    for (final achievement in Achievements.all) {
      if (_userProgress.unlockedAchievements.contains(achievement.id)) continue;
      
      bool unlocked = false;
      switch (achievement.type) {
        case AchievementType.quizzes:
          unlocked = totalQuizzes >= achievement.requirement;
          break;
        case AchievementType.streak:
          unlocked = _userProgress.currentStreak >= achievement.requirement;
          break;
        case AchievementType.questions:
          unlocked = totalQuestions >= achievement.requirement;
          break;
        case AchievementType.perfect:
          unlocked = _userProgress.perfectScores >= achievement.requirement;
          break;
        case AchievementType.accuracy:
          break;
      }
      
      if (unlocked) {
        _userProgress.unlockedAchievements.add(achievement.id);
        _syncAchievementToCloud(achievement.id);
      }
    }
  }

  Future<void> _syncAchievementToCloud(String achievementId) async {
    try {
      if (SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn) {
        await SupabaseService.instance.unlockAchievement(achievementId);
      }
    } catch (e) {
      // Ignore sync errors
    }
  }
  
  List<Achievement> getUnlockedAchievements() {
    return Achievements.all.where((a) => _userProgress.unlockedAchievements.contains(a.id)).toList();
  }
  
  List<Achievement> getLockedAchievements() {
    return Achievements.all.where((a) => !_userProgress.unlockedAchievements.contains(a.id)).toList();
  }

  void _adjustTopicDifficulty(TopicProgress topicProgress) {
    if (topicProgress.recentAttempts.length < 5) return;

    // Check last 5 attempts
    final recentCorrect = topicProgress.recentAttempts
        .reversed
        .take(5)
        .where((a) => a.isCorrect)
        .length;

    if (recentCorrect >= 4 && topicProgress.currentDifficulty != Difficulty.hard) {
      topicProgress.currentDifficulty = Difficulty.values[
        (topicProgress.currentDifficulty.index + 1).clamp(0, 2)
      ];
    } else if (recentCorrect <= 1 && topicProgress.currentDifficulty != Difficulty.easy) {
      topicProgress.currentDifficulty = Difficulty.values[
        (topicProgress.currentDifficulty.index - 1).clamp(0, 2)
      ];
    }
  }

  void _updateStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_userProgress.lastActiveDate == null) {
      _userProgress.currentStreak = 1;
    } else {
      final lastActive = DateTime(
        _userProgress.lastActiveDate!.year,
        _userProgress.lastActiveDate!.month,
        _userProgress.lastActiveDate!.day,
      );
      
      final difference = today.difference(lastActive).inDays;
      
      if (difference == 0) {
        // Same day, no change
      } else if (difference == 1) {
        _userProgress.currentStreak++;
      } else {
        _userProgress.currentStreak = 1; // Reset streak
      }
    }

    _userProgress.lastActiveDate = now;
    
    if (_userProgress.currentStreak > _userProgress.longestStreak) {
      _userProgress.longestStreak = _userProgress.currentStreak;
    }
  }

  // Get questions by specific difficulty level - prioritizes unanswered questions
  List<Question> getQuestionsByDifficulty({
    required String subjectId,
    required Difficulty difficulty,
    int count = 40,
  }) {
    final availableQuestions = QuestionsDatabase.getBySubject(subjectId);
    if (availableQuestions.isEmpty) return [];

    // Filter by difficulty
    final filteredQuestions = availableQuestions
        .where((q) => q.difficulty == difficulty)
        .toList();

    if (filteredQuestions.isEmpty) return [];

    // Get answered question IDs for this subject
    final subjectProgress = _userProgress.subjectProgress[subjectId];
    final answeredIds = <String>{};
    if (subjectProgress != null) {
      for (var topic in subjectProgress.topicProgress.values) {
        for (var attempt in topic.recentAttempts) {
          answeredIds.add(attempt.questionId);
        }
      }
    }

    // Separate into unanswered and answered
    final unanswered = filteredQuestions.where((q) => !answeredIds.contains(q.id)).toList();
    final answered = filteredQuestions.where((q) => answeredIds.contains(q.id)).toList();

    // Shuffle both lists
    unanswered.shuffle(_random);
    answered.shuffle(_random);

    // Prioritize unanswered questions, then fill with answered if needed
    List<Question> selected = [];
    selected.addAll(unanswered.take(count));
    
    // If we need more questions, add from answered pool
    if (selected.length < count) {
      selected.addAll(answered.take(count - selected.length));
    }

    // Final shuffle to mix them up
    selected.shuffle(_random);
    return selected.take(count).toList();
  }

  // Mark a difficulty level as passed for a subject
  Future<void> markLevelPassed({
    required String subjectId,
    required Difficulty difficulty,
  }) async {
    _userProgress.subjectProgress.putIfAbsent(
      subjectId,
      () => SubjectProgress(subjectId: subjectId),
    );

    final subjectProgress = _userProgress.subjectProgress[subjectId]!;
    
    switch (difficulty) {
      case Difficulty.easy:
        subjectProgress.easyPassed = true;
        break;
      case Difficulty.medium:
        subjectProgress.mediumPassed = true;
        break;
      case Difficulty.hard:
        subjectProgress.hardPassed = true;
        break;
    }

    await _storageService.saveProgress(_userProgress);
    notifyListeners();
  }

  // Get weak topics for a subject
  List<String> getWeakTopics(String subjectId, {int limit = 3}) {
    final subjectProgress = _userProgress.subjectProgress[subjectId];
    if (subjectProgress == null) return [];

    final weakTopics = subjectProgress.topicProgress.entries
        .where((e) => e.value.accuracy < 0.6 && e.value.totalAttempts >= 3)
        .map((e) => e.key)
        .toList();

    weakTopics.sort((a, b) {
      final accuracyA = subjectProgress.topicProgress[a]!.accuracy;
      final accuracyB = subjectProgress.topicProgress[b]!.accuracy;
      return accuracyA.compareTo(accuracyB);
    });

    return weakTopics.take(limit).toList();
  }

  // Get subject stats
  Map<String, double> getSubjectAccuracies() {
    Map<String, double> accuracies = {};
    
    for (var subject in CriminologySubjects.all) {
      final progress = _userProgress.subjectProgress[subject.id];
      accuracies[subject.id] = progress?.overallAccuracy ?? 0.0;
    }
    
    return accuracies;
  }

  // Reset progress
  Future<void> resetProgress() async {
    _userProgress = UserProgress();
    await _storageService.clearProgress();
    notifyListeners();
  }
}
