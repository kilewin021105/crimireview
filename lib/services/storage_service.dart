import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_progress.dart';

class StorageService {
  SharedPreferences? _prefs;
  static const String _progressKey = 'user_progress';
  static const String _onboardingKey = 'onboarding_completed';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _userAvatarKey = 'user_avatar';
  static const String _profileImageKey = 'profile_image';
  static const String _passwordKey = 'user_password';
  static const String _dailyStreakKey = 'daily_streak';
  static const String _lastStudyDateKey = 'last_study_date';
  static const String _totalStudyTimeKey = 'total_study_time';
  static const String _notificationsKey = 'notifications_enabled';
  static const String _soundEffectsKey = 'sound_effects_enabled';
  static const String _hapticFeedbackKey = 'haptic_feedback_enabled';
  static const String _quizTimerKey = 'quiz_timer_enabled';
  static const String _questionsPerQuizKey = 'questions_per_quiz';
  static const String _schoolKey = 'user_school';
  static const String _lastDailyChallengeKey = 'last_daily_challenge';
  static const String _dailyChallengeScoreKey = 'daily_challenge_score';

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> saveProgress(UserProgress progress) async {
    final prefs = await _getPrefs();
    await prefs.setString(_progressKey, progress.toJsonString());
  }

  Future<UserProgress> loadProgress() async {
    final prefs = await _getPrefs();
    final String? jsonString = prefs.getString(_progressKey);
    if (jsonString == null) {
      return UserProgress();
    }
    try {
      return UserProgress.fromJsonString(jsonString);
    } catch (e) {
      return UserProgress();
    }
  }

  UserProgress loadProgressSync() {
    if (_prefs == null) return UserProgress();
    final String? jsonString = _prefs!.getString(_progressKey);
    if (jsonString == null) {
      return UserProgress();
    }
    try {
      return UserProgress.fromJsonString(jsonString);
    } catch (e) {
      return UserProgress();
    }
  }

  Future<void> clearProgress() async {
    final prefs = await _getPrefs();
    await prefs.remove(_progressKey);
  }

  /// Clear all quiz progress and history (keeps user profile)
  Future<void> clearAllProgress() async {
    final prefs = await _getPrefs();
    await prefs.remove(_progressKey);
    await prefs.remove(_dailyStreakKey);
    await prefs.remove(_lastStudyDateKey);
    await prefs.remove(_totalStudyTimeKey);
    await prefs.remove(_lastDailyChallengeKey);
    await prefs.remove(_dailyChallengeScoreKey);
  }

  // Onboarding
  Future<bool> hasCompletedOnboarding() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_onboardingKey) ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_onboardingKey, completed);
  }

  // User Profile
  Future<void> setUserName(String name) async {
    final prefs = await _getPrefs();
    await prefs.setString(_userNameKey, name);
  }

  Future<String> getUserName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_userNameKey) ?? 'Student';
  }

  String getUserNameSync() {
    return _prefs?.getString(_userNameKey) ?? 'Student';
  }

  Future<void> setUserEmail(String email) async {
    final prefs = await _getPrefs();
    await prefs.setString(_userEmailKey, email);
  }

  Future<String?> getUserEmail() async {
    final prefs = await _getPrefs();
    return prefs.getString(_userEmailKey);
  }

  Future<void> setUserAvatar(String avatarPath) async {
    final prefs = await _getPrefs();
    await prefs.setString(_userAvatarKey, avatarPath);
  }

  Future<String?> getUserAvatar() async {
    final prefs = await _getPrefs();
    return prefs.getString(_userAvatarKey);
  }

  // Profile Image (local file path)
  Future<void> setProfileImage(String imagePath) async {
    final prefs = await _getPrefs();
    await prefs.setString(_profileImageKey, imagePath);
  }

  Future<String?> getProfileImage() async {
    final prefs = await _getPrefs();
    return prefs.getString(_profileImageKey);
  }

  // Avatar URL (cloud URL from Supabase)
  static const String _avatarUrlKey = 'avatar_url';
  
  Future<void> setAvatarUrl(String? url) async {
    final prefs = await _getPrefs();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_avatarUrlKey, url);
    } else {
      await prefs.remove(_avatarUrlKey);
    }
  }

  Future<String?> getAvatarUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_avatarUrlKey);
  }

  // Password
  Future<void> setPassword(String password) async {
    final prefs = await _getPrefs();
    // In a real app, this should be hashed before storing
    await prefs.setString(_passwordKey, password);
  }

  Future<String?> getPassword() async {
    final prefs = await _getPrefs();
    return prefs.getString(_passwordKey);
  }

  Future<bool> verifyPassword(String password) async {
    final prefs = await _getPrefs();
    final storedPassword = prefs.getString(_passwordKey);
    return storedPassword == password;
  }

  // Daily Streak
  Future<int> getDailyStreak() async {
    final prefs = await _getPrefs();
    final lastStudyDate = prefs.getString(_lastStudyDateKey);
    final streak = prefs.getInt(_dailyStreakKey) ?? 0;
    
    if (lastStudyDate == null) return 0;
    
    final lastDate = DateTime.parse(lastStudyDate);
    final today = DateTime.now();
    final difference = today.difference(lastDate).inDays;
    
    if (difference > 1) {
      // Streak broken
      await prefs.setInt(_dailyStreakKey, 0);
      return 0;
    }
    
    return streak;
  }

  Future<void> setDailyStreak(int streak) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_dailyStreakKey, streak);
  }

  Future<void> updateDailyStreak() async {
    final prefs = await _getPrefs();
    final lastStudyDate = prefs.getString(_lastStudyDateKey);
    final today = DateTime.now();
    final todayString = today.toIso8601String().split('T')[0];
    
    if (lastStudyDate == null) {
      await prefs.setInt(_dailyStreakKey, 1);
      await prefs.setString(_lastStudyDateKey, todayString);
      return;
    }
    
    final lastDate = DateTime.parse(lastStudyDate);
    final lastDateString = lastDate.toIso8601String().split('T')[0];
    
    if (todayString == lastDateString) {
      // Already studied today
      return;
    }
    
    final difference = today.difference(lastDate).inDays;
    final currentStreak = prefs.getInt(_dailyStreakKey) ?? 0;
    
    if (difference == 1) {
      // Continue streak
      await prefs.setInt(_dailyStreakKey, currentStreak + 1);
    } else {
      // Streak broken, start new
      await prefs.setInt(_dailyStreakKey, 1);
    }
    
    await prefs.setString(_lastStudyDateKey, todayString);
  }

  // Study Time
  Future<int> getTotalStudyTime() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_totalStudyTimeKey) ?? 0;
  }

  Future<void> addStudyTime(int minutes) async {
    final prefs = await _getPrefs();
    final current = prefs.getInt(_totalStudyTimeKey) ?? 0;
    await prefs.setInt(_totalStudyTimeKey, current + minutes);
  }

  // Clear all data
  Future<void> clearAllData() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }

  // School/University
  Future<void> setSchool(String school) async {
    final prefs = await _getPrefs();
    await prefs.setString(_schoolKey, school);
  }

  Future<String?> getSchool() async {
    final prefs = await _getPrefs();
    return prefs.getString(_schoolKey);
  }

  // Notifications
  Future<bool> getNotificationsEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_notificationsKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_notificationsKey, enabled);
  }

  // Sound Effects
  Future<bool> getSoundEffectsEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_soundEffectsKey) ?? true;
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_soundEffectsKey, enabled);
  }

  // Haptic Feedback
  Future<bool> getHapticFeedbackEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_hapticFeedbackKey) ?? true;
  }

  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_hapticFeedbackKey, enabled);
  }

  // Quiz Timer
  Future<bool> getQuizTimerEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_quizTimerKey) ?? true;
  }

  Future<void> setQuizTimerEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_quizTimerKey, enabled);
  }

  // Questions Per Quiz
  Future<int> getQuestionsPerQuiz() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_questionsPerQuizKey) ?? 10;
  }

  Future<void> setQuestionsPerQuiz(int count) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_questionsPerQuizKey, count);
  }

  // Reset progress only (keep profile)
  Future<void> resetProgress() async {
    final prefs = await _getPrefs();
    await prefs.remove(_progressKey);
    await prefs.remove(_dailyStreakKey);
    await prefs.remove(_lastStudyDateKey);
    await prefs.remove(_totalStudyTimeKey);
  }

  // Daily Challenge
  Future<String?> getLastDailyChallengeDate() async {
    final prefs = await _getPrefs();
    return prefs.getString(_lastDailyChallengeKey);
  }

  Future<void> setLastDailyChallengeDate(String date) async {
    final prefs = await _getPrefs();
    await prefs.setString(_lastDailyChallengeKey, date);
  }

  Future<int> getDailyChallengeScore() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_dailyChallengeScoreKey) ?? 0;
  }

  Future<void> addDailyChallengeScore(int score) async {
    final prefs = await _getPrefs();
    final current = prefs.getInt(_dailyChallengeScoreKey) ?? 0;
    await prefs.setInt(_dailyChallengeScoreKey, current + score);
  }
}
