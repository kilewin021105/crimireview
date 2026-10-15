import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Puts a time limit on every request to Supabase (database, login,
/// functions, storage). Without it, on a very slow or stalled connection
/// a request can hang for minutes and its screen spins forever; with it,
/// the request fails with a [TimeoutException] the screens turn into a
/// "connection is slow" message.
class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner);

  final http.Client _inner;

  static const Duration _requestLimit = Duration(seconds: 25);
  // Photo uploads send more data, so they get longer on slow mobile data.
  static const Duration _storageLimit = Duration(minutes: 2);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final limit = request.url.path.contains('/storage/v1/') ? _storageLimit : _requestLimit;
    return _inner.send(request).timeout(limit);
  }

  @override
  void close() => _inner.close();
}

class SupabaseService {
  static const String _supabaseUrl = 'https://wbhobbehgqlzfborscvx.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndiaG9iYmVoZ3FsemZib3JzY3Z4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NjUwNzYsImV4cCI6MjA5MjE0MTA3Nn0.R9tGkmzOEg-zEfgNRtOqoRc9Ls6XYg1AZwQYpId9DIo';

  static SupabaseService? _instance;
  static bool _isInitialized = false;
  
  static SupabaseService get instance => _instance ??= SupabaseService._();
  
  SupabaseService._();

  static bool get isInitialized => _isInitialized;

  /// The project's base URL, used by `ConnectivityService` to test whether
  /// this app's own backend is reachable.
  static String get projectUrl => _supabaseUrl;

  /// The public (anon) key. It ships inside the app by design; row-level
  /// security is what protects the data.
  static String get publicKey => _supabaseAnonKey;

  SupabaseClient get client {
    if (!_isInitialized) {
      throw Exception('Supabase not initialized');
    }
    return Supabase.instance.client;
  }
  
  User? get currentUser {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (e) {
      return null;
    }
  }
  
  bool get isLoggedIn => _isInitialized && currentUser != null;
  String? get userId => currentUser?.id;

  /// How this account can sign in: 'email', 'google', 'facebook'. Set by
  /// Supabase Auth (app_metadata), not by the app. One account can have
  /// several when a student used both email and Google with one address.
  List<String> get signInMethods {
    final providers = currentUser?.appMetadata['providers'];
    if (providers is List) return providers.map((e) => e.toString()).toList();
    final single = currentUser?.appMetadata['provider'];
    return single == null ? const [] : [single.toString()];
  }

  /// False for an account that only ever used Google or Facebook: it has
  /// no password, so "Change password" doesn't apply to it.
  bool get hasPasswordSignIn => signInMethods.contains('email');

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
        httpClient: _TimeoutHttpClient(http.Client()),
      );
      _isInitialized = true;
      _instance = SupabaseService._();
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName ?? email.split('@')[0]},
    );
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  Future<void> signOut() async {
    if (!_isInitialized) return;
    await client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    await client.auth.resetPasswordForEmail(email);
  }

  Future<void> sendPasswordResetOTP(String email) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    await client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: false,
    );
  }

  Future<bool> verifyPasswordResetOTP(String email, String token) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    try {
      final response = await client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      return response.session != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> updatePasswordAfterReset(String newPassword) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    if (!isLoggedIn) throw Exception('Not logged in');
    
    await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Final step of "Forgot password". [code] must be the same 6-digit code
  /// the user just verified -- the server checks it again, so nobody else
  /// can set the password during the reset (supabase_security_fixes_v2.sql).
  /// Throws an [Exception] carrying a user-facing message on failure.
  Future<void> resetUserPassword(String email, String code, String newPassword) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');

    final result = await client.rpc('reset_user_password', params: {
      'p_email': email.trim().toLowerCase(),
      'p_code': code.trim(),
      'p_new_password': newPassword,
    });
    if (result is! Map || result['success'] != true) {
      final error = result is Map ? result['error'] : null;
      throw Exception(error ?? 'Failed to reset password. Please try again.');
    }
  }

  /// Changes the signed-in user's password after re-checking the current
  /// one, so someone holding an unlocked phone can't lock the owner out.
  /// Throws an [Exception] with a user-facing message on failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    final email = currentUser?.email;
    if (!isLoggedIn || email == null) throw Exception('Please sign in again.');

    try {
      await client.auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid')) {
        throw Exception('Current password is incorrect.');
      }
      rethrow;
    }

    await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (!isLoggedIn) return null;
    
    final response = await client
        .from('user_profiles')
        .select()
        .eq('id', userId!)
        .maybeSingle();
    
    return response;
  }

  /// Ensure user profile exists in database (call after signup/login)
  Future<void> ensureProfileExists({String? displayName}) async {
    if (!isLoggedIn) return;
    
    try {
      final existing = await getUserProfile();
      if (existing != null) return; // Profile already exists
      
      // Create new profile
      final user = currentUser!;
      // display_name: email sign-up; full_name / name: Google, Facebook.
      final name = displayName ??
                   user.userMetadata?['display_name'] ??
                   user.userMetadata?['full_name'] ??
                   user.userMetadata?['name'] ??
                   user.email?.split('@')[0] ??
                   'User';
      
      await client.from('user_profiles').insert({
        'id': userId,
        'email': user.email,
        'display_name': name,
        'total_points': 0,
        'total_quizzes': 0,
        'total_correct': 0,
        'current_streak': 0,
        'best_streak': 0,
        'rank': 'Rookie',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // Profile might already exist due to race condition, ignore
      print('ensureProfileExists error: $e');
    }
  }

  /// Load cloud profile data and return it for syncing to local storage
  Future<Map<String, dynamic>?> loadCloudProfile() async {
    if (!isLoggedIn) return null;
    
    await ensureProfileExists();
    
    try {
      final profile = await getUserProfile();
      if (profile == null) return null;
      
      // Return profile data for local storage sync
      return {
        'display_name': profile['display_name'],
        'email': profile['email'] ?? currentUser?.email,
        'avatar_url': profile['avatar_url'],
        'school': profile['school'],
        'total_points': (profile['total_points'] as num?)?.toInt() ?? 0,
        'total_quizzes': (profile['total_quizzes'] as num?)?.toInt() ?? 0,
        'total_correct': (profile['total_correct'] as num?)?.toInt() ?? 0,
        'current_streak': (profile['current_streak'] as num?)?.toInt() ?? 0,
        'best_streak': (profile['best_streak'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      print('loadCloudProfile error: $e');
      return null;
    }
  }

  Future<void> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? school,
  }) async {
    if (!isLoggedIn) return;
    
    await ensureProfileExists();
    
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (school != null) updates['school'] = school;
    
    await client
        .from('user_profiles')
        .update(updates)
        .eq('id', userId!);
  }

  Future<void> updatePoints(int points) async {
    if (!isLoggedIn) return;
    
    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('User profile not found');
    }
    
    final currentPoints = profile['total_points'] ?? 0;
    
    await client
        .from('user_profiles')
        .update({
          'total_points': currentPoints + points,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId!);
  }

  Future<void> saveQuizResult({
    required String subjectId,
    required String difficulty,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    int? timeTakenSeconds,
  }) async {
    if (!isLoggedIn) return;
    
    // Ensure profile exists
    await ensureProfileExists();

    await client.from('quiz_results').insert({
      'user_id': userId,
      'subject_id': subjectId,
      'difficulty': difficulty,
      'score': score,
      'total_questions': totalQuestions,
      'correct_answers': correctAnswers,
      'time_taken_seconds': timeTakenSeconds,
    });
    
    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('User profile not found');
    }

    final currentQuizzes = (profile['total_quizzes'] as num?)?.toInt() ?? 0;
    final currentCorrect = (profile['total_correct'] as num?)?.toInt() ?? 0;
    final currentPoints = (profile['total_points'] as num?)?.toInt() ?? 0;
    
    await client
        .from('user_profiles')
        .update({
          'total_quizzes': currentQuizzes + 1,
          'total_correct': currentCorrect + correctAnswers,
          'total_points': currentPoints + score,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId!);
  }

  Future<void> saveSubjectProgress({
    required String subjectId,
    required int questionsAnswered,
    required int correctAnswers,
    required int easyCorrect,
    required int easyTotal,
    required int mediumCorrect,
    required int mediumTotal,
    required int hardCorrect,
    required int hardTotal,
    List<Map<String, dynamic>>? easySegments,
    List<Map<String, dynamic>>? mediumSegments,
    List<Map<String, dynamic>>? hardSegments,
  }) async {
    if (!isLoggedIn) return;
    
    final data = {
      'user_id': userId,
      'subject_id': subjectId,
      'questions_answered': questionsAnswered,
      'correct_answers': correctAnswers,
      'easy_correct': easyCorrect,
      'easy_total': easyTotal,
      'medium_correct': mediumCorrect,
      'medium_total': mediumTotal,
      'hard_correct': hardCorrect,
      'hard_total': hardTotal,
      'last_study_date': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    // Add segment progress if provided (may not exist in database yet)
    if (easySegments != null) {
      data['easy_segments'] = easySegments;
    }
    if (mediumSegments != null) {
      data['medium_segments'] = mediumSegments;
    }
    if (hardSegments != null) {
      data['hard_segments'] = hardSegments;
    }
    
    await client.from('user_progress').upsert(data, onConflict: 'user_id,subject_id');
  }

  Future<List<Map<String, dynamic>>> getSubjectProgress() async {
    if (!isLoggedIn) return [];
    
    final response = await client
        .from('user_progress')
        .select()
        .eq('user_id', userId!);
    
    return List<Map<String, dynamic>>.from(response);
  }

  /// Load all progress data from cloud and return it for restoring to local storage
  Future<Map<String, dynamic>?> loadFullCloudProgress() async {
    if (!isLoggedIn) return null;

    try {
      // Get profile data (totals)
      final profile = await getUserProfile();
      if (profile == null) return null;

      // Get subject progress
      final subjectProgress = await getSubjectProgress();

      // Get achievements
      final achievements = await getUnlockedAchievements();

      return {
        'profile': profile,
        'subjectProgress': subjectProgress,
        'achievements': achievements,
      };
    } catch (e) {
      print('loadFullCloudProgress error: $e');
      return null;
    }
  }

  /// Records one daily challenge attempt. Only the FIRST attempt of a day
  /// counts: a plain insert (not an upsert) means a retake from a second
  /// phone or a reinstall hits the `UNIQUE (user_id, challenge_date)`
  /// constraint and is ignored -- it neither replaces the first score nor
  /// awards the points a second time.
  ///
  /// [challengeDate] is the day the challenge was actually played
  /// (YYYY-MM-DD); pass it when syncing an attempt queued offline.
  Future<void> saveDailyChallengeScore({
    required int score,
    required int correctAnswers,
    int totalQuestions = 10,
    String? challengeDate,
  }) async {
    if (!isLoggedIn) return;

    final date = challengeDate ?? DateTime.now().toIso8601String().split('T')[0];

    try {
      await client.from('daily_challenge_scores').insert({
        'user_id': userId,
        'challenge_date': date,
        'score': score,
        'correct_answers': correctAnswers,
        'total_questions': totalQuestions,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        debugPrint('Daily challenge for $date already recorded; keeping the first score.');
        return;
      }
      rethrow;
    }

    await updatePoints(score);
  }

  Future<bool> hasCompletedDailyChallenge() async {
    if (!isLoggedIn) return false;
    
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    final response = await client
        .from('daily_challenge_scores')
        .select()
        .eq('user_id', userId!)
        .eq('challenge_date', today)
        .maybeSingle();
    
    return response != null;
  }

  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 100}) async {
    if (!_isInitialized) return [];
    
    try {
      // Server function returning only public fields (name, avatar, points,
      // rank) -- other students' emails and schools are no longer readable
      // (supabase_security_fixes_v2.sql). `rank` comes from the database's
      // own rank column, so it matches the rank shown everywhere else.
      final response = await client.rpc('get_leaderboard', params: {'p_limit': limit});

      final List<Map<String, dynamic>> result = [];
      int position = 1;
      for (final row in List<Map<String, dynamic>>.from(response as List)) {
        result.add({
          'user_id': row['user_id'],
          'display_name': row['display_name'] ?? 'Student',
          'avatar_url': row['avatar_url'],
          'total_points': (row['total_points'] as num?)?.toInt() ?? 0,
          'rank': row['rank'] ?? 'Rookie',
          'rank_position': position,
        });
        position++;
      }
      return result;
    } catch (e) {
      // Let the screen show its "can't load" state with a retry instead of
      // an empty leaderboard that looks like nobody has played yet.
      debugPrint('getLeaderboard failed: $e');
      rethrow;
    }
  }

  Future<int?> getUserRank() async {
    if (!isLoggedIn) return null;

    final List<Map<String, dynamic>> leaderboard;
    try {
      leaderboard = await getLeaderboard();
    } catch (_) {
      return null;
    }
    
    for (int i = 0; i < leaderboard.length; i++) {
      if (leaderboard[i]['user_id'] == userId) {
        return i + 1;
      }
    }
    
    return null;
  }

  Future<void> unlockAchievement(String achievementId) async {
    if (!isLoggedIn) return;

    await client.from('user_achievements').upsert({
      'user_id': userId,
      'achievement_id': achievementId,
    }, onConflict: 'user_id,achievement_id');
  }

  Future<List<String>> getUnlockedAchievements() async {
    if (!isLoggedIn) return [];
    
    final response = await client
        .from('user_achievements')
        .select('achievement_id')
        .eq('user_id', userId!);
    
    return List<Map<String, dynamic>>.from(response)
        .map((e) => e['achievement_id'] as String)
        .toList();
  }

  Future<void> syncLocalProgress({
    required int totalPoints,
    required int totalQuizzes,
    required int totalCorrect,
    required int currentStreak,
    required int bestStreak,
  }) async {
    if (!isLoggedIn) return;
    
    // Ensure profile exists first
    await ensureProfileExists();
    
    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('User profile not found');
    }
    
    final cloudPoints = (profile['total_points'] as num?)?.toInt() ?? 0;
    final cloudQuizzes = (profile['total_quizzes'] as num?)?.toInt() ?? 0;
    final cloudCorrect = (profile['total_correct'] as num?)?.toInt() ?? 0;
    final cloudBestStreak = (profile['best_streak'] as num?)?.toInt() ?? 0;
    
    await client
        .from('user_profiles')
        .update({
          'total_points': cloudPoints > totalPoints ? cloudPoints : totalPoints,
          'total_quizzes': cloudQuizzes > totalQuizzes ? cloudQuizzes : totalQuizzes,
          'total_correct': cloudCorrect > totalCorrect ? cloudCorrect : totalCorrect,
          'current_streak': currentStreak,
          'best_streak': cloudBestStreak > bestStreak ? cloudBestStreak : bestStreak,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId!);
  }

  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  Future<String?> uploadAvatar(File imageFile) async {
    if (!isLoggedIn) return null;

    final fileExt = imageFile.path.split('.').last;
    final fileName = 'avatar.$fileExt';
    final filePath = '$userId/$fileName';
    
    await client.storage
        .from('avatars')
        .upload(filePath, imageFile, fileOptions: const FileOptions(upsert: true));
    
    final publicUrl = client.storage
        .from('avatars')
        .getPublicUrl(filePath);
    
    await updateProfile(avatarUrl: publicUrl);
    
    return publicUrl;
  }

  Future<void> removeAvatar() async {
    if (!isLoggedIn) return;

    final extensions = ['jpg', 'jpeg', 'png', 'gif'];
    for (final ext in extensions) {
      try {
        await client.storage
            .from('avatars')
            .remove(['$userId/avatar.$ext']);
      } catch (_) {}
    }
    
    await updateProfile(avatarUrl: '');
  }
}
