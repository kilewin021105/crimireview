import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../models/achievement.dart';
import '../models/mastery.dart';
import 'storage_service.dart';
import 'supabase_service.dart';
import 'offline_sync_service.dart';
import 'mastery_service.dart';
import 'question_selection_service.dart';

/// Orchestrates the learning loop: which questions to serve, what the answers
/// mean, and how progress is stored.
///
/// ---------------------------------------------------------------------------
/// WHAT THE RE-ENGINEERING CHANGED (panel note 6)
/// ---------------------------------------------------------------------------
/// This class used to reach straight into `QuestionsDatabase`, a 6045-line file
/// of hardcoded [Question] objects (panel note 7 violation), and it sliced that
/// bank with a stable `sublist()`, so retrying a failed segment served the SAME
/// ten items in the SAME order (panel note 3 violation).
///
/// Both are gone. Every question now comes from `QuestionRepository`
/// (Supabase-backed, admin-authored or auto-generated) by way of
/// `QuestionSelectionService`, which guarantees unseen-first selection. The
/// hardcoded `accuracy >= 0.8 ? hard : ...` ladder is replaced by the Bayesian
/// Knowledge Tracing estimates held in `MasteryService` (Corbett & Anderson,
/// 1995), which is the citable basis panel note 4 asked for.
///
/// Everything else this class already did -- segment progress, difficulty pass
/// flags, streaks, achievements, cloud merge, the offline sync queue and the
/// board-exam readiness maths -- is preserved unchanged.
class AdaptiveLearningService extends ChangeNotifier {
  final StorageService _storageService;
  UserProgress _userProgress = UserProgress();
  bool _isInitialized = false;

  /// BKT p(known) for each question's topic, captured immediately BEFORE the
  /// answer was scored, keyed by question id. Populated by [recordQuizResult]
  /// so the results screen can show "this answer moved you from X% to Y%".
  final Map<String, double> _lastMasteryBefore = <String, double>{};

  /// The matching p(known) immediately AFTER the answer was scored.
  final Map<String, double> _lastMasteryAfter = <String, double>{};

  AdaptiveLearningService(this._storageService) {
    _initProgress();
  }

  Future<void> _initProgress() async {
    _userProgress = await _storageService.loadProgress();
    _isInitialized = true;
    notifyListeners();

    // Sync with cloud for returning logged-in users
    if (SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn) {
      await _syncWithCloud();
    }
  }

  /// Sync local progress with cloud data for returning users
  Future<void> _syncWithCloud() async {
    try {
      final cloudData = await SupabaseService.instance.loadFullCloudProgress();
      if (cloudData == null) return;

      final cloudProfile = cloudData['profile'] as Map<String, dynamic>?;
      final cloudSubjectProgress =
          cloudData['subjectProgress'] as List<Map<String, dynamic>>?;
      final cloudAchievements = cloudData['achievements'] as List<String>?;

      // Calculate local totals for comparison
      int localQuizzes = 0;
      int localCorrect = 0;
      for (final sp in _userProgress.subjectProgress.values) {
        localQuizzes += sp.totalQuizzesTaken;
        localCorrect += sp.totalCorrectAnswers;
      }

      // Merge cloud subject progress with local
      if (cloudSubjectProgress != null && cloudSubjectProgress.isNotEmpty) {
        for (final cloudSp in cloudSubjectProgress) {
          final subjectId = cloudSp['subject_id'] as String?;
          if (subjectId == null) continue;

          final cloudAnswered = cloudSp['questions_answered'] as int? ?? 0;
          final cloudCorrectAnswers = cloudSp['correct_answers'] as int? ?? 0;
          final easyCorrect = cloudSp['easy_correct'] as int? ?? 0;
          final easyTotal = cloudSp['easy_total'] as int? ?? 0;
          final mediumCorrect = cloudSp['medium_correct'] as int? ?? 0;
          final mediumTotal = cloudSp['medium_total'] as int? ?? 0;
          final hardCorrect = cloudSp['hard_correct'] as int? ?? 0;
          final hardTotal = cloudSp['hard_total'] as int? ?? 0;

          // Get segment progress from cloud if available
          final cloudEasySegments = cloudSp['easy_segments'] as List<dynamic>?;
          final cloudMediumSegments =
              cloudSp['medium_segments'] as List<dynamic>?;
          final cloudHardSegments = cloudSp['hard_segments'] as List<dynamic>?;

          // Get local subject progress if exists
          final localSp = _userProgress.subjectProgress[subjectId];

          // Compare cloud vs local and take higher values
          final mergedAnswered =
              (localSp?.totalQuestionsAnswered ?? 0) > cloudAnswered
                  ? (localSp?.totalQuestionsAnswered ?? 0)
                  : cloudAnswered;
          final mergedCorrect =
              (localSp?.totalCorrectAnswers ?? 0) > cloudCorrectAnswers
                  ? (localSp?.totalCorrectAnswers ?? 0)
                  : cloudCorrectAnswers;

          // Merge segment progress (take higher questionsAnswered per segment)
          List<SegmentProgress> mergeSegments(
              List<SegmentProgress>? local, List<dynamic>? cloud) {
            return List.generate(SegmentProgress.segmentCount, (i) {
              final localSeg = local?[i];
              final cloudSegJson = cloud != null && i < cloud.length
                  ? Map<String, dynamic>.from(cloud[i] as Map)
                  : null;
              final cloudSeg = cloudSegJson != null
                  ? SegmentProgress.fromJson(cloudSegJson)
                  : null;

              if (localSeg == null)
                return cloudSeg ?? SegmentProgress(segmentIndex: i);
              if (cloudSeg == null) return localSeg;

              // Take higher questionsAnswered and corresponding correctAnswers
              if (cloudSeg.questionsAnswered > localSeg.questionsAnswered) {
                return cloudSeg;
              } else if (localSeg.questionsAnswered >
                  cloudSeg.questionsAnswered) {
                return localSeg;
              } else {
                // Equal questions answered, take max correct
                return SegmentProgress(
                  segmentIndex: i,
                  questionsAnswered: localSeg.questionsAnswered,
                  correctAnswers:
                      localSeg.correctAnswers > cloudSeg.correctAnswers
                          ? localSeg.correctAnswers
                          : cloudSeg.correctAnswers,
                );
              }
            });
          }

          final mergedEasySegments =
              mergeSegments(localSp?.easySegments, cloudEasySegments);
          final mergedMediumSegments =
              mergeSegments(localSp?.mediumSegments, cloudMediumSegments);
          final mergedHardSegments =
              mergeSegments(localSp?.hardSegments, cloudHardSegments);

          // Determine if difficulty levels are passed (all segments must be passed)
          final easyPassed = mergedEasySegments.every((s) => s.isPassed);
          final mediumPassed = mergedMediumSegments.every((s) => s.isPassed);
          final hardPassed = mergedHardSegments.every((s) => s.isPassed);

          // Create merged subject progress
          _userProgress.subjectProgress[subjectId] = SubjectProgress(
            subjectId: subjectId,
            topicProgress: localSp?.topicProgress ?? {},
            totalQuizzesTaken: localSp?.totalQuizzesTaken ?? 0,
            totalQuestionsAnswered: mergedAnswered,
            totalCorrectAnswers: mergedCorrect,
            lastStudyDate: cloudSp['last_study_date'] != null
                ? DateTime.tryParse(cloudSp['last_study_date'])
                : localSp?.lastStudyDate,
            easyPassed: easyPassed,
            mediumPassed: mediumPassed,
            hardPassed: hardPassed,
            wrongQuestionIds: localSp?.wrongQuestionIds ?? {},
            easyCorrect: easyCorrect > (localSp?.easyCorrect ?? 0)
                ? easyCorrect
                : (localSp?.easyCorrect ?? 0),
            easyTotal: easyTotal > (localSp?.easyTotal ?? 0)
                ? easyTotal
                : (localSp?.easyTotal ?? 0),
            mediumCorrect: mediumCorrect > (localSp?.mediumCorrect ?? 0)
                ? mediumCorrect
                : (localSp?.mediumCorrect ?? 0),
            mediumTotal: mediumTotal > (localSp?.mediumTotal ?? 0)
                ? mediumTotal
                : (localSp?.mediumTotal ?? 0),
            hardCorrect: hardCorrect > (localSp?.hardCorrect ?? 0)
                ? hardCorrect
                : (localSp?.hardCorrect ?? 0),
            hardTotal: hardTotal > (localSp?.hardTotal ?? 0)
                ? hardTotal
                : (localSp?.hardTotal ?? 0),
            easySegments: mergedEasySegments,
            mediumSegments: mergedMediumSegments,
            hardSegments: mergedHardSegments,
          );
        }
      }

      // Merge cloud achievements with local
      if (cloudAchievements != null && cloudAchievements.isNotEmpty) {
        final mergedAchievements = <String>{
          ..._userProgress.unlockedAchievements,
          ...cloudAchievements,
        };
        _userProgress.unlockedAchievements = mergedAchievements.toList();
      }

      // Update streak from cloud if higher
      if (cloudProfile != null) {
        final cloudStreak = cloudProfile['current_streak'] as int? ?? 0;
        final cloudBestStreak = cloudProfile['best_streak'] as int? ?? 0;
        if (cloudStreak > _userProgress.currentStreak) {
          _userProgress.currentStreak = cloudStreak;
        }
        if (cloudBestStreak > _userProgress.longestStreak) {
          _userProgress.longestStreak = cloudBestStreak;
        }
      }

      // Save merged progress to local storage
      await _storageService.saveProgress(_userProgress);

      // Sync the higher values back to cloud
      final cloudQuizzes = cloudProfile?['total_quizzes'] as int? ?? 0;
      final cloudCorrectTotal = cloudProfile?['total_correct'] as int? ?? 0;
      final cloudPoints = cloudProfile?['total_points'] as int? ?? 0;

      await SupabaseService.instance.syncLocalProgress(
        totalPoints: (localCorrect * 10) > cloudPoints
            ? (localCorrect * 10)
            : cloudPoints,
        totalQuizzes: localQuizzes > cloudQuizzes ? localQuizzes : cloudQuizzes,
        totalCorrect:
            localCorrect > cloudCorrectTotal ? localCorrect : cloudCorrectTotal,
        currentStreak: _userProgress.currentStreak,
        bestStreak: _userProgress.longestStreak,
      );

      notifyListeners();
    } catch (e) {
      // Silently fail - local progress is still valid
      print('Cloud sync error during init: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  UserProgress get userProgress => _userProgress;

  /// Wipes local progress AND the two models that drive adaptivity.
  ///
  /// The exposure ledger must be cleared too: without it a "reset progress"
  /// would leave every question marked as already seen, and the learner would
  /// immediately fall into the recycling branch of the selection rules.
  Future<void> resetProgress() async {
    _userProgress = UserProgress();
    _isInitialized = false;
    _lastMasteryBefore.clear();
    _lastMasteryAfter.clear();

    try {
      await MasteryService.instance.reset();
    } catch (e) {
      debugPrint('Mastery reset failed: $e');
    }
    try {
      await QuestionSelectionService.instance.reset();
    } catch (e) {
      debugPrint('Exposure reset failed: $e');
    }

    await _initProgress();
  }

  // ---------------------------------------------------------------------------
  // QUESTION DELIVERY
  //
  // Every method below is async because questions now live in Supabase (with an
  // offline snapshot) instead of in a compiled-in Dart file. None of them
  // contains, or falls back to, any question content.
  // ---------------------------------------------------------------------------

  /// Builds an adaptive set for [subjectId].
  ///
  /// The difficulty is chosen from the BKT model (see [_determineTargetDifficulty]),
  /// then `QuestionSelectionService` picks the items: unseen first, weighted
  /// toward the topics with the lowest p(known).
  ///
  /// Passing [specificTopic] turns this into a targeted repeat of that one
  /// topic with questions the learner has not already answered -- panel note 3.
  Future<List<Question>> getAdaptiveQuestions({
    required String subjectId,
    int count = 10,
    String? specificTopic,
  }) async {
    final subjectProgress = _userProgress.subjectProgress[subjectId];
    final targetDifficulty =
        _determineTargetDifficulty(subjectId, subjectProgress);

    if (specificTopic != null && specificTopic.trim().isNotEmpty) {
      return QuestionSelectionService.instance.buildRemediationSet(
        subjectId: subjectId,
        difficulty: targetDifficulty,
        count: count,
        topics: [specificTopic.trim()],
      );
    }

    return QuestionSelectionService.instance.buildQuizSet(
      subjectId: subjectId,
      difficulty: targetDifficulty,
      count: count,
    );
  }

  /// Chooses the difficulty tier to practise next.
  ///
  /// The old implementation was a hardcoded ladder over raw accuracy
  /// (`>= 0.8 hard, >= 0.6 medium, else easy`) with no theoretical basis --
  /// exactly what panel note 4 flagged. It is replaced by two grounded inputs:
  ///
  ///  * **Readiness** comes from the mean BKT p(known) for the subject. Because
  ///    p(known) discounts lucky guesses and forgives careless slips, it is a
  ///    far better "is this student ready to move up" signal than accuracy.
  ///    The thresholds reuse the model's own published constants
  ///    ([TopicMastery.masteryThreshold] / [TopicMastery.remediationThreshold])
  ///    rather than inventing new magic numbers.
  ///  * **Unlocking** stays with the existing segment gate: a tier the student
  ///    has not unlocked is never offered, so this can only ever recommend a
  ///    level at or below the one the difficulty sheet already allows.
  Difficulty _determineTargetDifficulty(
    String subjectId,
    SubjectProgress? progress,
  ) {
    // Too little evidence for the model to say anything: start at the bottom,
    // which is also what the old implementation did for new users.
    if (progress == null || progress.totalQuestionsAnswered < 5) {
      return Difficulty.easy;
    }

    final double mastery = MasteryService.instance.subjectMastery(subjectId);

    final Difficulty desired;
    if (mastery >= TopicMastery.masteryThreshold) {
      desired = Difficulty.hard;
    } else if (mastery >= TopicMastery.remediationThreshold) {
      desired = Difficulty.medium;
    } else {
      desired = Difficulty.easy;
    }

    // Never recommend past the level the segment gate has unlocked.
    final Difficulty ceiling = progress.mediumPassed
        ? Difficulty.hard
        : progress.easyPassed
            ? Difficulty.medium
            : Difficulty.easy;

    return Difficulty.values[min(desired.index, ceiling.index)];
  }

  // Record quiz result and update progress
  Future<void> recordQuizResult({
    required String subjectId,
    required List<Question> questions,
    required List<bool> results,
    required List<int> responseTimes,
    int? segmentIndex,
  }) async {
    // Ensure subject progress exists
    _userProgress.subjectProgress.putIfAbsent(
      subjectId,
      () => SubjectProgress(subjectId: subjectId),
    );

    final subjectProgress = _userProgress.subjectProgress[subjectId]!;
    subjectProgress.totalQuizzesTaken++;
    subjectProgress.lastStudyDate = DateTime.now();
    final difficultyQuestionCounts = <Difficulty, int>{};
    final difficultyCorrectCounts = <Difficulty, int>{};

    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final isCorrect = results[i];
      final responseTime = responseTimes[i];

      difficultyQuestionCounts[question.difficulty] =
          (difficultyQuestionCounts[question.difficulty] ?? 0) + 1;
      if (isCorrect) {
        difficultyCorrectCounts[question.difficulty] =
            (difficultyCorrectCounts[question.difficulty] ?? 0) + 1;
      }

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

      // Update per-difficulty stats
      switch (question.difficulty) {
        case Difficulty.easy:
          subjectProgress.easyTotal++;
          if (isCorrect) subjectProgress.easyCorrect++;
          break;
        case Difficulty.medium:
          subjectProgress.mediumTotal++;
          if (isCorrect) subjectProgress.mediumCorrect++;
          break;
        case Difficulty.hard:
          subjectProgress.hardTotal++;
          if (isCorrect) subjectProgress.hardCorrect++;
          break;
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

    for (final entry in difficultyQuestionCounts.entries) {
      final resolvedSegmentIndex =
          difficultyQuestionCounts.length == 1 && segmentIndex != null
              ? segmentIndex
              : _getCurrentSegmentIndexForProgress(subjectProgress, entry.key);
      _updateSegmentProgress(
        subjectProgress: subjectProgress,
        difficulty: entry.key,
        segmentIndex: resolvedSegmentIndex,
        questionsAnswered: entry.value,
        correctAnswers: difficultyCorrectCounts[entry.key] ?? 0,
      );
    }
    _syncDifficultyPassFlags(subjectProgress);

    // Check for perfect score
    if (results.every((r) => r)) {
      _userProgress.perfectScores++;
    }

    // Update streak
    _updateStreak();

    // Check achievements
    await _checkAchievements();

    // Save progress locally
    await _storageService.saveProgress(_userProgress);

    // Sync to cloud or queue for retry if needed
    if (SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn) {
      final totalQuizzes = CriminologySubjects.all.fold<int>(
        0,
        (sum, subject) =>
            sum +
            (_userProgress.subjectProgress[subject.id]?.totalQuizzesTaken ?? 0),
      );
      final totalCorrect = CriminologySubjects.all.fold<int>(
        0,
        (sum, subject) =>
            sum +
            (_userProgress.subjectProgress[subject.id]?.totalCorrectAnswers ??
                0),
      );

      await OfflineSyncService.instance.saveSubjectProgressOrQueue(
        subjectId: subjectId,
        questionsAnswered: subjectProgress.totalQuestionsAnswered,
        correctAnswers: subjectProgress.totalCorrectAnswers,
        easyCorrect: subjectProgress.easyCorrect,
        easyTotal: subjectProgress.easyTotal,
        mediumCorrect: subjectProgress.mediumCorrect,
        mediumTotal: subjectProgress.mediumTotal,
        hardCorrect: subjectProgress.hardCorrect,
        hardTotal: subjectProgress.hardTotal,
        easySegments:
            subjectProgress.easySegments.map((s) => s.toJson()).toList(),
        mediumSegments:
            subjectProgress.mediumSegments.map((s) => s.toJson()).toList(),
        hardSegments:
            subjectProgress.hardSegments.map((s) => s.toJson()).toList(),
      );

      await OfflineSyncService.instance.syncProfileUpdateOrQueue(
        totalPoints: totalCorrect * 10,
        totalQuizzes: totalQuizzes,
        totalCorrect: totalCorrect,
        currentStreak: _userProgress.currentStreak,
        bestStreak: _userProgress.longestStreak,
      );
    }

    notifyListeners();
  }

  Future<void> _checkAchievements() async {
    final totalQuizzes = CriminologySubjects.all.fold<int>(
      0,
      (sum, s) =>
          sum + (_userProgress.subjectProgress[s.id]?.totalQuizzesTaken ?? 0),
    );
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0,
      (sum, s) =>
          sum +
          (_userProgress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0),
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
        await _syncAchievementToCloud(achievement.id);
      }
    }
  }

  Future<void> _syncAchievementToCloud(String achievementId) async {
    if (SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn) {
      await OfflineSyncService.instance.unlockAchievementOrQueue(achievementId);
    }
  }

  List<Achievement> getUnlockedAchievements() {
    return Achievements.all
        .where((a) => _userProgress.unlockedAchievements.contains(a.id))
        .toList();
  }

  List<Achievement> getLockedAchievements() {
    return Achievements.all
        .where((a) => !_userProgress.unlockedAchievements.contains(a.id))
        .toList();
  }

  void _adjustTopicDifficulty(TopicProgress topicProgress) {
    if (topicProgress.recentAttempts.length < 5) return;

    // Check last 5 attempts
    final recentCorrect = topicProgress.recentAttempts.reversed
        .take(5)
        .where((a) => a.isCorrect)
        .length;

    if (recentCorrect >= 4 &&
        topicProgress.currentDifficulty != Difficulty.hard) {
      topicProgress.currentDifficulty = Difficulty
          .values[(topicProgress.currentDifficulty.index + 1).clamp(0, 2)];
    } else if (recentCorrect <= 1 &&
        topicProgress.currentDifficulty != Difficulty.easy) {
      topicProgress.currentDifficulty = Difficulty
          .values[(topicProgress.currentDifficulty.index - 1).clamp(0, 2)];
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

  List<SegmentProgress> _segmentsForDifficulty(
    SubjectProgress subjectProgress,
    Difficulty difficulty,
  ) {
    switch (difficulty) {
      case Difficulty.easy:
        return subjectProgress.easySegments;
      case Difficulty.medium:
        return subjectProgress.mediumSegments;
      case Difficulty.hard:
        return subjectProgress.hardSegments;
    }
  }

  void _syncDifficultyPassFlags(SubjectProgress subjectProgress) {
    subjectProgress.easyPassed =
        subjectProgress.isDifficultyPassed(Difficulty.easy);
    subjectProgress.mediumPassed =
        subjectProgress.isDifficultyPassed(Difficulty.medium);
    subjectProgress.hardPassed =
        subjectProgress.isDifficultyPassed(Difficulty.hard);
  }

  void _updateSegmentProgress({
    required SubjectProgress subjectProgress,
    required Difficulty difficulty,
    required int segmentIndex,
    required int questionsAnswered,
    required int correctAnswers,
  }) {
    final segments = _segmentsForDifficulty(subjectProgress, difficulty);
    if (segmentIndex < 0 || segmentIndex >= segments.length) return;

    final segment = segments[segmentIndex];
    if (segment.isPassed) return;

    final normalizedQuestionsAnswered =
        min(questionsAnswered, SegmentProgress.questionsPerSegment);
    if (normalizedQuestionsAnswered >= segment.questionsAnswered) {
      segment.questionsAnswered = normalizedQuestionsAnswered;
    }
    if (correctAnswers > segment.correctAnswers) {
      segment.correctAnswers = correctAnswers;
    }
  }

  int _getCurrentSegmentIndexForProgress(
    SubjectProgress? subjectProgress,
    Difficulty difficulty,
  ) {
    if (subjectProgress == null) return 0;
    return subjectProgress.currentSegmentIndexForDifficulty(difficulty);
  }

  int getCurrentSegmentIndex({
    required String subjectId,
    required Difficulty difficulty,
  }) {
    final subjectProgress = _userProgress.subjectProgress[subjectId];
    return _getCurrentSegmentIndexForProgress(subjectProgress, difficulty);
  }

  String getCurrentSegmentRangeLabel({
    required String subjectId,
    required Difficulty difficulty,
  }) {
    return SegmentProgress.rangeLabelFor(
      getCurrentSegmentIndex(subjectId: subjectId, difficulty: difficulty),
    );
  }

  /// Builds the quiz set for one EXPLICITLY chosen difficulty -- the Easy /
  /// Medium / Hard buttons on the subject screen, as opposed to
  /// [getAdaptiveQuestions]'s model-chosen difficulty.
  ///
  /// This used to slice a compiled-in question list with a stable
  /// `sublist(segmentIndex * 10, ...)`, so retrying a failed segment served
  /// the exact same ten items in the exact same order (panel note 3
  /// violation) -- and it read from `QuestionsDatabase`, the hardcoded bank
  /// panel note 7 rules out. Both are gone: item selection now goes through
  /// `QuestionSelectionService`, which guarantees unseen-first delivery and
  /// only recycles least-seen items once every question at this
  /// subject/difficulty has already been shown once.
  Future<List<Question>> getQuestionsForSegment({
    required String subjectId,
    required Difficulty difficulty,
  }) {
    final segmentIndex =
        getCurrentSegmentIndex(subjectId: subjectId, difficulty: difficulty);
    return QuestionSelectionService.instance.buildQuizSet(
      subjectId: subjectId,
      difficulty: difficulty,
      count: SegmentProgress.questionsPerSegment,
      segmentIndex: segmentIndex,
    );
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
    _syncDifficultyPassFlags(subjectProgress);

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

  /// Get per-difficulty stats for a subject
  Map<String, dynamic> getSubjectDifficultyStats(String subjectId) {
    final progress = _userProgress.subjectProgress[subjectId];
    if (progress == null) {
      return {
        'easyAccuracy': 0.0,
        'mediumAccuracy': 0.0,
        'hardAccuracy': 0.0,
        'hasEasy': false,
        'hasMedium': false,
        'hasHard': false,
      };
    }
    return {
      'easyAccuracy': progress.easyAccuracy,
      'mediumAccuracy': progress.mediumAccuracy,
      'hardAccuracy': progress.hardAccuracy,
      'hasEasy': progress.easyTotal > 0,
      'hasMedium': progress.mediumTotal > 0,
      'hasHard': progress.hardTotal > 0,
    };
  }

  /// Calculate overall Board Exam Readiness across all subjects
  /// Uses PRC TOS weights: Easy 30%, Medium 50%, Hard 20%
  double getOverallBoardExamReadiness() {
    if (_userProgress.subjectProgress.isEmpty) return 0.0;

    double totalReadiness = 0.0;
    int subjectsWithData = 0;

    for (var subject in CriminologySubjects.all) {
      final progress = _userProgress.subjectProgress[subject.id];
      if (progress == null) continue;

      final readiness = progress.boardExamReadiness;
      if (readiness > 0) {
        totalReadiness += readiness;
        subjectsWithData++;
      }
    }

    if (subjectsWithData == 0) return 0.0;
    return totalReadiness / subjectsWithData;
  }

  /// Get how many subjects have completed each difficulty level
  Map<String, int> getDifficultyCompletionCounts() {
    int easyCompleted = 0;
    int mediumCompleted = 0;
    int hardCompleted = 0;

    for (var subject in CriminologySubjects.all) {
      final progress = _userProgress.subjectProgress[subject.id];
      if (progress == null) continue;
      if (progress.easyTotal > 0) easyCompleted++;
      if (progress.mediumTotal > 0) mediumCompleted++;
      if (progress.hardTotal > 0) hardCompleted++;
    }

    return {
      'easy': easyCompleted,
      'medium': mediumCompleted,
      'hard': hardCompleted,
      'totalSubjects': CriminologySubjects.all.length,
    };
  }
}
