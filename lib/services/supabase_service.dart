import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _supabaseUrl = 'https://wbhobbehgqlzfborscvx.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndiaG9iYmVoZ3FsemZib3JzY3Z4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NjUwNzYsImV4cCI6MjA5MjE0MTA3Nn0.R9tGkmzOEg-zEfgNRtOqoRc9Ls6XYg1AZwQYpId9DIo';

  static SupabaseService? _instance;
  static bool _isInitialized = false;
  
  static SupabaseService get instance => _instance ??= SupabaseService._();
  
  SupabaseService._();

  static bool get isInitialized => _isInitialized;
  
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

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
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

  Future<void> resetUserPassword(String email, String newPassword) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    
    // Call RPC function to reset password
    await client.rpc('reset_user_password', params: {
      'user_email': email.toLowerCase(),
      'new_password': newPassword,
    });
  }

  Future<void> changePassword(String newPassword) async {
    if (!_isInitialized) throw Exception('Supabase not initialized');
    if (!isLoggedIn) throw Exception('Not logged in');
    
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
      final name = displayName ?? 
                   user.userMetadata?['display_name'] ?? 
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
    if (profile == null) return;
    
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
    
    try {
      await client.from('quiz_results').insert({
        'user_id': userId,
        'subject_id': subjectId,
        'difficulty': difficulty,
        'score': score,
        'total_questions': totalQuestions,
        'correct_answers': correctAnswers,
        'time_taken_seconds': timeTakenSeconds,
      });
    } catch (e) {
      print('Quiz result insert error: $e');
    }
    
    final profile = await getUserProfile();
    if (profile != null) {
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
  }) async {
    if (!isLoggedIn) return;
    
    await client.from('user_progress').upsert({
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
    }, onConflict: 'user_id,subject_id');
  }

  Future<List<Map<String, dynamic>>> getSubjectProgress() async {
    if (!isLoggedIn) return [];
    
    final response = await client
        .from('user_progress')
        .select()
        .eq('user_id', userId!);
    
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> saveDailyChallengeScore({
    required int score,
    required int correctAnswers,
    int totalQuestions = 10,
  }) async {
    if (!isLoggedIn) return;
    
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    await client.from('daily_challenge_scores').upsert({
      'user_id': userId,
      'challenge_date': today,
      'score': score,
      'correct_answers': correctAnswers,
      'total_questions': totalQuestions,
    }, onConflict: 'user_id,challenge_date');
    
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
      final response = await client
          .from('user_profiles')
          .select('id, display_name, avatar_url, total_points, total_quizzes, total_correct')
          .order('total_points', ascending: false)
          .limit(limit);
      
      final List<Map<String, dynamic>> result = [];
      int position = 1;
      for (final row in response) {
        final points = (row['total_points'] as num?)?.toInt() ?? 0;
        String rank = 'Rookie';
        if (points >= 5000) rank = 'Legend';
        else if (points >= 2500) rank = 'Master';
        else if (points >= 1000) rank = 'Expert';
        else if (points >= 500) rank = 'Scholar';
        else if (points >= 100) rank = 'Student';
        
        result.add({
          'user_id': row['id'],
          'display_name': row['display_name'] ?? 'Anonymous',
          'avatar_url': row['avatar_url'],
          'total_points': points,
          'rank': rank,
          'rank_position': position,
        });
        position++;
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<int?> getUserRank() async {
    if (!isLoggedIn) return null;
    
    final leaderboard = await getLeaderboard();
    
    for (int i = 0; i < leaderboard.length; i++) {
      if (leaderboard[i]['user_id'] == userId) {
        return i + 1;
      }
    }
    
    return null;
  }

  Future<void> unlockAchievement(String achievementId) async {
    if (!isLoggedIn) return;
    
    try {
      await client.from('user_achievements').insert({
        'user_id': userId,
        'achievement_id': achievementId,
      });
    } catch (e) {

    }
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
    if (profile == null) return;
    
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
    
    try {
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
    } catch (e) {
      return null;
    }
  }

  Future<void> removeAvatar() async {
    if (!isLoggedIn) return;
    
    try {
      final extensions = ['jpg', 'jpeg', 'png', 'gif'];
      for (final ext in extensions) {
        try {
          await client.storage
              .from('avatars')
              .remove(['$userId/avatar.$ext']);
        } catch (_) {}
      }
      
      await updateProfile(avatarUrl: '');
    } catch (_) {}
  }
}
