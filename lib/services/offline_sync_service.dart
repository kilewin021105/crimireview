import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'supabase_service.dart';

enum SyncOperationType {
  quizResult,
  dailyChallenge,
  subjectProgress,
  achievement,
  profileUpdate,
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

  SharedPreferences? _prefs;
  List<SyncOperation> _pendingOperations = [];
  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;

  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingOperations.length;
  bool get hasPendingSync => _pendingOperations.isNotEmpty;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadQueue();
    _startListening();
  }

  void _startListening() {
    // Listen to connectivity changes
    ConnectivityService.instance.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (ConnectivityService.instance.isOnline && hasPendingSync) {
      syncPendingOperations();
    }
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
  }) async {
    final operation = SyncOperation(
      id: _generateId(),
      type: SyncOperationType.subjectProgress,
      data: {
        'subjectId': subjectId,
        'questionsAnswered': questionsAnswered,
        'correctAnswers': correctAnswers,
        'easyCorrect': easyCorrect,
        'easyTotal': easyTotal,
        'mediumCorrect': mediumCorrect,
        'mediumTotal': mediumTotal,
        'hardCorrect': hardCorrect,
        'hardTotal': hardTotal,
      },
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

  Future<void> _addOperation(SyncOperation operation) async {
    _pendingOperations.add(operation);
    await _saveQueue();
    notifyListeners();

    // Try to sync immediately if online
    if (ConnectivityService.instance.isOnline) {
      syncPendingOperations();
    }
  }

  /// Sync all pending operations to the cloud
  Future<void> syncPendingOperations() async {
    if (_isSyncing || _pendingOperations.isEmpty) return;
    if (!SupabaseService.instance.isLoggedIn) return;

    _isSyncing = true;
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
    }
  }

  /// Clear all pending operations (use with caution)
  Future<void> clearQueue() async {
    _pendingOperations.clear();
    await _saveQueue();
    notifyListeners();
  }

  @override
  void dispose() {
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
