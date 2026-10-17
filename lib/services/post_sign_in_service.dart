import '../models/user_progress.dart';
import 'admin_service.dart';
import 'mastery_service.dart';
import 'offline_sync_service.dart';
import 'question_selection_service.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

/// Everything that has to happen right after a successful sign-in, by
/// any method: email + password, Google or Facebook.
///
/// This used to live inside the login button's handler. Google and
/// Facebook sign-in finish somewhere else (the student comes back from
/// the browser, sometimes into a freshly restarted app), so it moved here
/// where every path can run the same steps. One copy means a Google login
/// can't skip a step an email login does.
///
/// Steps, in order:
///   1. If a different account used this phone last, upload that
///      account's unsynced results, then clear its local progress and
///      learning models so the new account never sees (or uploads)
///      someone else's scores or mastery.
///   2. Copy the cloud profile (name, email, school, photo, streak) here.
///   3. Merge cloud and local progress, keeping the higher number of each.
///   4. Push the merged totals back to the cloud.
///   5. Re-check the admin role, so routing goes to the right home screen.
class PostSignInService {
  PostSignInService._();
  static final PostSignInService instance = PostSignInService._();

  /// True when the signed-in account hasn't been set up on this phone
  /// yet: a first sign-in, or a different account than last time.
  Future<bool> needsSetup() async {
    final supabase = SupabaseService.instance;
    if (!SupabaseService.isInitialized || !supabase.isLoggedIn) return false;
    final lastUserId = await StorageService().getLastUserId();
    return lastUserId != supabase.userId;
  }

  /// Runs the steps above. Returns whether the account is an admin.
  Future<bool> run() async {
    final supabase = SupabaseService.instance;
    final storage = StorageService();
    final currentUserId = supabase.userId;
    final lastUserId = await storage.getLastUserId();

    // Check if switching accounts
    if (lastUserId != null && lastUserId != currentUserId) {
      // Different user logging in - sync old user's pending data first
      if (OfflineSyncService.instance.hasPendingSync) {
        await OfflineSyncService.instance.syncPendingOperations();
      }
      // Clear old user's local quiz progress so new user starts fresh
      await storage.clearQuizProgress();
      // Same for the two learning models (BKT mastery and the "already
      // seen" question list): phone copy only, then the new student's own
      // copy is loaded from the cloud.
      await MasteryService.instance.forgetLocalForAccountSwitch();
      await QuestionSelectionService.instance.forgetLocalForAccountSwitch();
    }

    // Save current user ID
    if (currentUserId != null) {
      await storage.setLastUserId(currentUserId);
    }

    // Load full cloud progress (profile + subject progress + achievements)
    final cloudData = await supabase.loadFullCloudProgress();
    final cloudProfile = cloudData?['profile'];

    if (cloudProfile != null) {
      // Sync cloud profile data to local storage
      if (cloudProfile['display_name'] != null) {
        await storage.setUserName(cloudProfile['display_name']);
      }
      if (cloudProfile['email'] != null) {
        await storage.setUserEmail(cloudProfile['email']);
      }
      if (cloudProfile['school'] != null) {
        await storage.setSchool(cloudProfile['school']);
      }
      if (cloudProfile['current_streak'] != null) {
        await storage.setDailyStreak(cloudProfile['current_streak']);
      }
      if (cloudProfile['avatar_url'] != null) {
        await storage.setAvatarUrl(cloudProfile['avatar_url']);
      }
    }

    await storage.setOnboardingCompleted(true);

    // Load local progress for merging
    final localProgress = await storage.loadProgress();
    int localQuizzes = 0;
    int localCorrect = 0;
    for (final sp in localProgress.subjectProgress.values) {
      localQuizzes += sp.totalQuizzesTaken;
      localCorrect += sp.totalCorrectAnswers;
    }

    // Sync cloud subject progress to local
    final cloudSubjectProgress = cloudData?['subjectProgress'] as List<Map<String, dynamic>>?;
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
        final cloudEasySegments = cloudSp['easy_segments'] as List<dynamic>?;
        final cloudMediumSegments = cloudSp['medium_segments'] as List<dynamic>?;
        final cloudHardSegments = cloudSp['hard_segments'] as List<dynamic>?;

        // Get or create local subject progress
        final localSp = localProgress.subjectProgress[subjectId];

        // Compare cloud vs local and take higher values
        final mergedAnswered = (localSp?.totalQuestionsAnswered ?? 0) > cloudAnswered
            ? (localSp?.totalQuestionsAnswered ?? 0) : cloudAnswered;
        final mergedCorrect = (localSp?.totalCorrectAnswers ?? 0) > cloudCorrectAnswers
            ? (localSp?.totalCorrectAnswers ?? 0) : cloudCorrectAnswers;

        List<SegmentProgress> mergeSegments(List<SegmentProgress>? local, List<dynamic>? cloud) {
          return List.generate(SegmentProgress.segmentCount, (i) {
            final localSeg = local?[i];
            final cloudSegJson = cloud != null && i < cloud.length
                ? Map<String, dynamic>.from(cloud[i] as Map)
                : null;
            final cloudSeg = cloudSegJson != null
                ? SegmentProgress.fromJson(cloudSegJson)
                : null;

            if (localSeg == null) return cloudSeg ?? SegmentProgress(segmentIndex: i);
            if (cloudSeg == null) return localSeg;

            if (cloudSeg.questionsAnswered > localSeg.questionsAnswered) {
              return cloudSeg;
            }
            if (localSeg.questionsAnswered > cloudSeg.questionsAnswered) {
              return localSeg;
            }

            return SegmentProgress(
              segmentIndex: i,
              questionsAnswered: localSeg.questionsAnswered,
              correctAnswers: localSeg.correctAnswers > cloudSeg.correctAnswers
                  ? localSeg.correctAnswers
                  : cloudSeg.correctAnswers,
            );
          });
        }

        final mergedEasySegments = mergeSegments(localSp?.easySegments, cloudEasySegments);
        final mergedMediumSegments = mergeSegments(localSp?.mediumSegments, cloudMediumSegments);
        final mergedHardSegments = mergeSegments(localSp?.hardSegments, cloudHardSegments);

        // Determine if difficulty levels are passed (all segments must be passed)
        final easyPassed = mergedEasySegments.every((segment) => segment.isPassed);
        final mediumPassed = mergedMediumSegments.every((segment) => segment.isPassed);
        final hardPassed = mergedHardSegments.every((segment) => segment.isPassed);

        // Create merged subject progress
        localProgress.subjectProgress[subjectId] = SubjectProgress(
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

    // Sync cloud achievements to local
    final cloudAchievements = cloudData?['achievements'] as List<String>?;
    if (cloudAchievements != null && cloudAchievements.isNotEmpty) {
      // Merge cloud achievements with local (union of both)
      final mergedAchievements = <String>{
        ...localProgress.unlockedAchievements,
        ...cloudAchievements,
      };
      localProgress.unlockedAchievements = mergedAchievements.toList();
    }

    // Update streak from cloud if higher
    if (cloudProfile != null) {
      final cloudStreak = cloudProfile['current_streak'] as int? ?? 0;
      final cloudBestStreak = cloudProfile['best_streak'] as int? ?? 0;
      if (cloudStreak > localProgress.currentStreak) {
        localProgress.currentStreak = cloudStreak;
      }
      if (cloudBestStreak > localProgress.longestStreak) {
        localProgress.longestStreak = cloudBestStreak;
      }
    }

    // Save merged progress to local storage
    await storage.saveProgress(localProgress);

    final cloudQuizzes = cloudProfile?['total_quizzes'] ?? 0;
    final cloudCorrect = cloudProfile?['total_correct'] ?? 0;
    final cloudPoints = cloudProfile?['total_points'] ?? 0;

    // Sync the higher values to cloud
    await supabase.syncLocalProgress(
      totalPoints: (localCorrect * 10) > cloudPoints ? (localCorrect * 10) : cloudPoints,
      totalQuizzes: localQuizzes > cloudQuizzes ? localQuizzes : cloudQuizzes,
      totalCorrect: localCorrect > cloudCorrect ? localCorrect : cloudCorrect,
      currentStreak: localProgress.currentStreak,
      bestStreak: localProgress.longestStreak,
    );

    // Explicitly refreshed (not just left to the reactive listener) so
    // routing here can never race the network call it depends on --
    // this is the moment a role check must be certain, not eventual.
    return AdminService.instance.refreshRole();
  }
}
