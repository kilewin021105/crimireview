import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

  /// The account that produced this operation. Only synced while that same
  /// account is signed in, so one student's offline results can never be
  /// uploaded under another student's account on a shared phone. Null only
  /// for operations queued by an older app version (treated as belonging to
  /// whoever is signed in, which was the old behaviour).
  final String? userId;
  int retryCount;

  SyncOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.userId,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'userId': userId,
        'retryCount': retryCount,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        id: json['id'],
        type: SyncOperationType.values[json['type']],
        data: Map<String, dynamic>.from(json['data']),
        createdAt: DateTime.parse(json['createdAt']),
        userId: json['userId'] as String?,
        retryCount: json['retryCount'] ?? 0,
      );
}

class OfflineSyncService extends ChangeNotifier {
  static final OfflineSyncService _instance = OfflineSyncService._();
  static OfflineSyncService get instance => _instance;

  OfflineSyncService._();

  static const String _queueKey = 'offline_sync_queue';
  static const String _droppedKey = 'offline_sync_dropped_count';

  /// First retry waits this long; each further failure doubles the wait, up
  /// to [_maxRetryDelay]. Network/server failures are retried forever (an
  /// offline result is never thrown away just because the phone stayed
  /// offline for a while); only errors that retrying can never fix are
  /// dropped -- see [_isPermanentFailure].
  static const Duration _retryDelay = Duration(seconds: 10);
  static const Duration _maxRetryDelay = Duration(minutes: 5);

  SharedPreferences? _prefs;
  List<SyncOperation> _pendingOperations = [];
  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;
  Timer? _retryTimer;
  bool _isListening = false;
  int _droppedCount = 0;

  bool get isSyncing => _isSyncing;

  /// Pending operations that belong to the account signed in right now.
  List<SyncOperation> get _currentUserOperations {
    final currentUserId =
        SupabaseService.isInitialized ? SupabaseService.instance.userId : null;
    return _pendingOperations
        .where((op) => op.userId == null || op.userId == currentUserId)
        .toList();
  }

  int get pendingCount => _currentUserOperations.length;
  bool get hasPendingSync => _currentUserOperations.isNotEmpty;

  /// How many queued items were discarded because the server rejected them
  /// permanently. Shown by [SyncStatusIndicator] until acknowledged, so a
  /// lost result is never silent.
  int get droppedCount => _droppedCount;

  bool get _hasAuthenticatedSession =>
      SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _droppedCount = _prefs?.getInt(_droppedKey) ?? 0;
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

    // Exponential backoff keyed off the most-retried item: 10 s, 20 s,
    // 40 s ... capped at 5 minutes, so a long outage doesn't mean a network
    // call every 10 seconds for hours.
    final attempts = _currentUserOperations
        .map((op) => op.retryCount)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final factor = 1 << (attempts.clamp(1, 16) - 1);
    var delay = _retryDelay * factor;
    if (delay > _maxRetryDelay) delay = _maxRetryDelay;

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      unawaited(syncPendingOperations());
    });
  }

  /// True for failures that will fail the same way on every retry: the
  /// server refused the data itself (constraint or permission error), or
  /// the operation's own data is unusable (e.g. the avatar file was deleted
  /// from the phone). Anything else -- no connection, timeouts, server
  /// errors -- is temporary and kept in the queue.
  bool _isPermanentFailure(Object error) {
    if (error is PostgrestException) {
      final code = error.code ?? '';
      // 22xxx = invalid data, 23xxx = constraint violation,
      // 42xxx = permission / undefined object (RLS rejects are 42501).
      return code.startsWith('22') ||
          code.startsWith('23') ||
          code.startsWith('42');
    }
    if (!kIsWeb && error is FileSystemException) return true;
    return error is FormatException || error is TypeError;
  }

  /// Clears the "N items could not be saved" warning once the user has seen it.
  Future<void> acknowledgeDropped() async {
    _droppedCount = 0;
    await _prefs?.remove(_droppedKey);
    notifyListeners();
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

  String? get _currentUserId =>
      SupabaseService.isInitialized ? SupabaseService.instance.userId : null;

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
        // Recorded now, not at sync time: a challenge finished offline on
        // Monday and synced on Tuesday must still count as Monday's.
        'challengeDate': DateTime.now().toIso8601String().split('T')[0],
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
    _pendingOperations.add(SyncOperation(
      id: operation.id,
      type: operation.type,
      data: operation.data,
      createdAt: operation.createdAt,
      userId: _currentUserId,
    ));
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
    if (_isSyncing || !hasPendingSync) return;
    if (!await _canSyncNow()) {
      _scheduleRetryIfNeeded();
      return;
    }

    _isSyncing = true;
    _retryTimer?.cancel();
    notifyListeners();

    final List<SyncOperation> completed = [];
    final List<SyncOperation> dropped = [];

    // Oldest first, and only the signed-in account's own items.
    for (final operation in _currentUserOperations) {
      try {
        await _executeOperation(operation);
        completed.add(operation);
      } catch (e) {
        if (_isPermanentFailure(e)) {
          dropped.add(operation);
          debugPrint('Sync operation ${operation.id} (${operation.type.name}) '
              'rejected permanently, removed from queue: $e');
        } else {
          operation.retryCount++;
          debugPrint('Sync operation ${operation.id} (${operation.type.name}) '
              'failed (attempt ${operation.retryCount}), will retry: $e');
          // The connection is likely down; stop here instead of failing
          // every remaining item one by one. Order is preserved.
          break;
        }
      }
    }

    _pendingOperations.removeWhere(
        (op) => completed.contains(op) || dropped.contains(op));
    await _saveQueue();

    if (dropped.isNotEmpty) {
      _droppedCount += dropped.length;
      await _prefs?.setInt(_droppedKey, _droppedCount);
    }

    _isSyncing = false;
    notifyListeners();

    _scheduleRetryIfNeeded();

    if (completed.isNotEmpty) {
      debugPrint('Synced ${completed.length} operations to cloud');
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
          challengeDate: operation.data['challengeDate'],
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
