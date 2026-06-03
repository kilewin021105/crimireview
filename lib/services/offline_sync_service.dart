import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

enum SyncOperationType {
  quizResult,
  dailyChallenge,
  subjectProgress,
  achievement,
  profileUpdate,
  profileDetails,
  avatarUpload,
  avatarRemove,
}

class SyncOperation {
  final String id;
  final SyncOperationType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int retryCount;

  SyncOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        id: json['id'],
        type: SyncOperationType.values[json['type']],
        data: Map<String, dynamic>.from(json['data']),
        createdAt: DateTime.parse(json['createdAt']),
        retryCount: json['retryCount'] ?? 0,
      );
}

class OfflineSyncService extends ChangeNotifier {
  static final OfflineSyncService _instance = OfflineSyncService._();
  static OfflineSyncService get instance => _instance;

  OfflineSyncService._();

  static const String _queueKey = 'offline_sync_queue';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 10);

  SharedPreferences? _prefs;
  List<SyncOperation> _pendingOperations = [];
  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;
  Timer? _retryTimer;
  bool _isListening = false;

  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingOperations.length;
  bool get hasPendingSync => _pendingOperations.isNotEmpty;
  bool get _hasAuthenticatedSession =>
      SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadQueue();
    _startListening();
    await syncPendingOperations();
  }

  void _startListening() {
    if (_isListening) return;
    ConnectivityService.instance.addListener(_onConnectivityChanged);
    _isListening = true;
  }

  void _onConnectivityChanged() {
    if (ConnectivityService.instance.isOnline && hasPendingSync) {
      unawaited(syncPendingOperations());
    }
  }

  Future<bool> _canSyncNow() async {
    if (!_hasAuthenticatedSession) {
      return false;
    }

    return ConnectivityService.instance.checkConnectivity();
  }

  void _scheduleRetryIfNeeded() {
    if (!hasPendingSync) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      unawaited(syncPendingOperations());
    });
  }

  Future<void> _loadQueue() async {
    final String? queueJson = _prefs?.getString(_queueKey);
    if (queueJson != null) {
      try {
        final List<dynamic> list = jsonDecode(queueJson);
        _pendingOperations = list
            .map((e) => SyncOperation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        notifyListeners();
      } catch (e) {
        _pendingOperations = [];
      }
    }
  }

  Future<void> _saveQueue() async {
    final String queueJson =
        jsonEncode(_pendingOperations.map((e) => e.toJson()).toList());
    await _prefs?.setString(_queueKey, queueJson);
  }

  String _generateId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_pendingOperations.length}';

  /// Queue a quiz result for sync
  Future<void> queueQuizResult({
    required String subjectId,
    required String difficulty,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    int? timeTakenSeconds,
  }) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.quizResult,
      data: {
        'subjectId': subjectId,
        'difficulty': difficulty,
        'score': score,
        'totalQuestions': totalQuestions,
        'correctAnswers': correctAnswers,
        'timeTakenSeconds': timeTakenSeconds,
      },
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  /// Queue a daily challenge score for sync
  Future<void> queueDailyChallengeScore({
    required int score,
    required int correctAnswers,
    int totalQuestions = 10,
  }) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.dailyChallenge,
      data: {
        'score': score,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
      },
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  /// Queue subject progress for sync
  Future<void> queueSubjectProgress({
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
    final data = {
      'subjectId': subjectId,
      'questionsAnswered': questionsAnswered,
      'correctAnswers': correctAnswers,
      'easyCorrect': easyCorrect,
      'easyTotal': easyTotal,
      'mediumCorrect': mediumCorrect,
      'mediumTotal': mediumTotal,
      'hardCorrect': hardCorrect,
      'hardTotal': hardTotal,
    };
    
    // Add segment progress if provided
    if (easySegments != null) {
      data['easySegments'] = easySegments;
    }
    if (mediumSegments != null) {
      data['mediumSegments'] = mediumSegments;
    }
    if (hardSegments != null) {
      data['hardSegments'] = hardSegments;
    }
    
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.subjectProgress,
      data: data,
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  /// Queue achievement unlock for sync
  Future<void> queueAchievement(String achievementId) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.achievement,
      data: {'achievementId': achievementId},
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  /// Queue profile update for sync
  Future<void> queueProfileUpdate({
    int? totalPoints,
    int? totalQuizzes,
    int? totalCorrect,
    int? currentStreak,
    int? bestStreak,
  }) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.profileUpdate,
      data: {
        if (totalPoints != null) 'totalPoints': totalPoints,
        if (totalQuizzes != null) 'totalQuizzes': totalQuizzes,
        if (totalCorrect != null) 'totalCorrect': totalCorrect,
        if (currentStreak != null) 'currentStreak': currentStreak,
        if (bestStreak != null) 'bestStreak': bestStreak,
      },
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  Future<void> queueProfileDetails({
    String? displayName,
    String? school,
  }) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.profileDetails,
      data: {
        if (displayName != null) 'displayName': displayName,
        if (school != null) 'school': school,
      },
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  Future<void> queueAvatarUpload(String avatarLocalPath) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.avatarUpload,
      data: {'avatarLocalPath': avatarLocalPath},
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  Future<void> queueAvatarRemoval() async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.avatarRemove,
      data: const {},
      createdAt: DateTime.now(),
    );

    await _addOperation(operation);
  }

  Future<void> _addOperation(SyncOperation operation) async {
    _pendingOperations.add(operation);
    await _saveQueue();
    notifyListeners();

    unawaited(syncPendingOperations());
  }

  Future<void> saveQuizResultOrQueue({
    required String subjectId,
    required String difficulty,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    int? timeTakenSeconds,
  }) async {
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.saveQuizResult(
          subjectId: subjectId,
          difficulty: difficulty,
          score: score,
          totalQuestions: totalQuestions,
          correctAnswers: correctAnswers,
          timeTakenSeconds: timeTakenSeconds,
        );
        return;
      } catch (e) {
        debugPrint('saveQuizResult failed, queueing for retry: $e');
      }
    }

    await queueQuizResult(
      subjectId: subjectId,
      difficulty: difficulty,
      score: score,
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
      timeTakenSeconds: timeTakenSeconds,
    );
  }

  Future<void> saveDailyChallengeScoreOrQueue({
    required int score,
    required int correctAnswers,
    int totalQuestions = 10,
  }) async {
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.saveDailyChallengeScore(
          score: score,
          correctAnswers: correctAnswers,
          totalQuestions: totalQuestions,
        );
        return;
      } catch (e) {
        debugPrint('saveDailyChallengeScore failed, queueing for retry: $e');
      }
    }

    await queueDailyChallengeScore(
      score: score,
      correctAnswers: correctAnswers,
      totalQuestions: totalQuestions,
    );
  }

  Future<void> saveSubjectProgressOrQueue({
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
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.saveSubjectProgress(
          subjectId: subjectId,
          questionsAnswered: questionsAnswered,
          correctAnswers: correctAnswers,
          easyCorrect: easyCorrect,
          easyTotal: easyTotal,
          mediumCorrect: mediumCorrect,
          mediumTotal: mediumTotal,
          hardCorrect: hardCorrect,
          hardTotal: hardTotal,
          easySegments: easySegments,
          mediumSegments: mediumSegments,
          hardSegments: hardSegments,
        );
        return;
      } catch (e) {
        debugPrint('saveSubjectProgress failed, queueing for retry: $e');
      }
    }

    await queueSubjectProgress(
      subjectId: subjectId,
      questionsAnswered: questionsAnswered,
      correctAnswers: correctAnswers,
      easyCorrect: easyCorrect,
      easyTotal: easyTotal,
      mediumCorrect: mediumCorrect,
      mediumTotal: mediumTotal,
      hardCorrect: hardCorrect,
      hardTotal: hardTotal,
      easySegments: easySegments,
      mediumSegments: mediumSegments,
      hardSegments: hardSegments,
    );
  }

  Future<void> unlockAchievementOrQueue(String achievementId) async {
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.unlockAchievement(achievementId);
        return;
      } catch (e) {
        debugPrint('unlockAchievement failed, queueing for retry: $e');
      }
    }

    await queueAchievement(achievementId);
  }

  Future<void> syncProfileUpdateOrQueue({
    required int totalPoints,
    required int totalQuizzes,
    required int totalCorrect,
    required int currentStreak,
    required int bestStreak,
  }) async {
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.syncLocalProgress(
          totalPoints: totalPoints,
          totalQuizzes: totalQuizzes,
          totalCorrect: totalCorrect,
          currentStreak: currentStreak,
          bestStreak: bestStreak,
        );
        return;
      } catch (e) {
        debugPrint('syncLocalProgress failed, queueing for retry: $e');
      }
    }

    await queueProfileUpdate(
      totalPoints: totalPoints,
      totalQuizzes: totalQuizzes,
      totalCorrect: totalCorrect,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
    );
  }

  Future<void> saveProfileDetailsOrQueue({
    String? displayName,
    String? school,
  }) async {
    if (!_hasAuthenticatedSession) return;

    final normalizedSchool = (school != null && school.isEmpty) ? null : school;

    if (await _canSyncNow()) {
      try {
        await SupabaseService.instance.updateProfile(
          displayName: displayName,
          school: normalizedSchool,
        );
        return;
      } catch (e) {
        debugPrint('updateProfile failed, queueing for retry: $e');
      }
    }

    await queueProfileDetails(
      displayName: displayName,
      school: normalizedSchool,
    );
  }

  Future<String?> uploadAvatarOrQueue(String avatarLocalPath) async {
    if (!_hasAuthenticatedSession) return null;

    if (await _canSyncNow()) {
      try {
        final avatarUrl = await _uploadAvatarFromPath(avatarLocalPath);
        return avatarUrl;
      } catch (e) {
        debugPrint('uploadAvatar failed, queueing for retry: $e');
      }
    }

    await queueAvatarUpload(avatarLocalPath);
    return null;
  }

  Future<void> removeAvatarOrQueue() async {
    if (!_hasAuthenticatedSession) return;

    if (await _canSyncNow()) {
      try {
        await _removeAvatarFromCloud();
        return;
      } catch (e) {
        debugPrint('removeAvatar failed, queueing for retry: $e');
      }
    }

    await queueAvatarRemoval();
  }

  Future<String> _uploadAvatarFromPath(String avatarLocalPath) async {
    final avatarFile = File(avatarLocalPath);
    if (!await avatarFile.exists()) {
      throw Exception('Avatar file no longer exists');
    }

    final avatarUrl = await SupabaseService.instance.uploadAvatar(avatarFile);
    if (avatarUrl == null || avatarUrl.isEmpty) {
      throw Exception('Avatar upload failed');
    }

    await StorageService().setAvatarUrl(avatarUrl);
    return avatarUrl;
  }

  Future<void> _removeAvatarFromCloud() async {
    await SupabaseService.instance.removeAvatar();
    await StorageService().setAvatarUrl(null);
  }

  /// Sync all pending operations to the cloud
  Future<void> syncPendingOperations() async {
    if (_isSyncing || _pendingOperations.isEmpty) return;
    if (!await _canSyncNow()) return;

    _isSyncing = true;
    _retryTimer?.cancel();
    notifyListeners();

    final List<SyncOperation> completed = [];
    final List<SyncOperation> failed = [];

    for (final operation in List.from(_pendingOperations)) {
      try {
        await _executeOperation(operation);
        completed.add(operation);
      } catch (e) {
        operation.retryCount++;
        if (operation.retryCount >= _maxRetries) {
          // Max retries reached, remove from queue
          failed.add(operation);
          print('Sync operation ${operation.id} failed after $_maxRetries retries: $e');
        }
      }
    }

    // Remove completed and failed operations
    _pendingOperations.removeWhere(
        (op) => completed.contains(op) || failed.contains(op));
    await _saveQueue();

    _isSyncing = false;
    notifyListeners();

    _scheduleRetryIfNeeded();

    if (completed.isNotEmpty) {
      print('Synced ${completed.length} operations to cloud');
    }
  }

  Future<void> _executeOperation(SyncOperation operation) async {
    final supabase = SupabaseService.instance;

    switch (operation.type) {
      case SyncOperationType.quizResult:
        await supabase.saveQuizResult(
          subjectId: operation.data['subjectId'],
          difficulty: operation.data['difficulty'],
          score: operation.data['score'],
          totalQuestions: operation.data['totalQuestions'],
          correctAnswers: operation.data['correctAnswers'],
          timeTakenSeconds: operation.data['timeTakenSeconds'],
        );
        break;

      case SyncOperationType.dailyChallenge:
        await supabase.saveDailyChallengeScore(
          score: operation.data['score'],
          correctAnswers: operation.data['correctAnswers'],
          totalQuestions: operation.data['totalQuestions'],
        );
        break;

      case SyncOperationType.subjectProgress:
        await supabase.saveSubjectProgress(
          subjectId: operation.data['subjectId'],
          questionsAnswered: operation.data['questionsAnswered'],
          correctAnswers: operation.data['correctAnswers'],
          easyCorrect: operation.data['easyCorrect'],
          easyTotal: operation.data['easyTotal'],
          mediumCorrect: operation.data['mediumCorrect'],
          mediumTotal: operation.data['mediumTotal'],
          hardCorrect: operation.data['hardCorrect'],
          hardTotal: operation.data['hardTotal'],
        );
        break;

      case SyncOperationType.achievement:
        await supabase.unlockAchievement(operation.data['achievementId']);
        break;

      case SyncOperationType.profileUpdate:
        final data = operation.data;
        if (data.isNotEmpty) {
          await supabase.syncLocalProgress(
            totalPoints: data['totalPoints'] ?? 0,
            totalQuizzes: data['totalQuizzes'] ?? 0,
            totalCorrect: data['totalCorrect'] ?? 0,
            currentStreak: data['currentStreak'] ?? 0,
            bestStreak: data['bestStreak'] ?? 0,
          );
        }
        break;

      case SyncOperationType.profileDetails:
        await supabase.updateProfile(
          displayName: operation.data['displayName'],
          school: operation.data['school'],
        );
        break;

      case SyncOperationType.avatarUpload:
        await _uploadAvatarFromPath(operation.data['avatarLocalPath']);
        break;

      case SyncOperationType.avatarRemove:
        await _removeAvatarFromCloud();
        break;
    }
  }

  /// Clear all pending operations (use with caution)
  Future<void> clearQueue() async {
    _pendingOperations.clear();
    _retryTimer?.cancel();
    _retryTimer = null;
    await _saveQueue();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isListening) {
      ConnectivityService.instance.removeListener(_onConnectivityChanged);
      _isListening = false;
    }
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
