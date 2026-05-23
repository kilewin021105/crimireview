import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'ml_service.dart';
import '../models/subject.dart';

/// Adaptive ML Service - Self-Learning Model
/// 
/// This service wraps the base ML model and adds online learning capabilities.
/// The model learns from each user's actual quiz results and adjusts predictions
/// to be more accurate for that specific user over time.
/// 
/// How it works:
/// 1. Makes prediction using base model
/// 2. User takes quiz, gets actual score
/// 3. Model compares prediction vs actual
/// 4. Adjusts personal bias and subject weights
/// 5. Future predictions use learned adjustments
/// 
/// No retraining needed - learns in real-time on device!
class AdaptiveMLService {
  static AdaptiveMLService? _instance;
  final MLService _baseModel = MLService.instance;
  
  // Personal learning parameters (adjusted per user)
  double _personalBias = 0.0;           // Overall score adjustment
  Map<String, double> _subjectBias = {};  // Per-subject adjustments
  List<PredictionRecord> _history = [];   // History of predictions
  
  // Learning rate - how fast the model adapts
  static const double _learningRate = 0.15;
  static const double _subjectLearningRate = 0.20;
  static const int _maxHistorySize = 50;
  
  // Storage keys
  static const String _keyPersonalBias = 'ml_personal_bias';
  static const String _keySubjectBias = 'ml_subject_bias';
  static const String _keyHistory = 'ml_prediction_history';
  static const String _keyTotalPredictions = 'ml_total_predictions';
  static const String _keyAccuracySum = 'ml_accuracy_sum';

  AdaptiveMLService._();

  static AdaptiveMLService get instance {
    _instance ??= AdaptiveMLService._();
    return _instance!;
  }

  /// Initialize and load learned parameters
  Future<void> initialize() async {
    await _baseModel.loadModel();
    await _loadLearnedParameters();
    print('Adaptive ML initialized - Personal bias: $_personalBias');
  }

  /// Load previously learned parameters from storage
  Future<void> _loadLearnedParameters() async {
    final prefs = await SharedPreferences.getInstance();
    
    _personalBias = prefs.getDouble(_keyPersonalBias) ?? 0.0;
    
    final subjectBiasJson = prefs.getString(_keySubjectBias);
    if (subjectBiasJson != null) {
      final decoded = json.decode(subjectBiasJson) as Map<String, dynamic>;
      _subjectBias = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } else {
      // Initialize with zero bias for all subjects
      for (final subject in CriminologySubjects.all) {
        _subjectBias[subject.id] = 0.0;
      }
    }
    
    final historyJson = prefs.getString(_keyHistory);
    if (historyJson != null) {
      final decoded = json.decode(historyJson) as List;
      _history = decoded.map((e) => PredictionRecord.fromJson(e)).toList();
    }
  }

  /// Save learned parameters to storage
  Future<void> _saveLearnedParameters() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setDouble(_keyPersonalBias, _personalBias);
    await prefs.setString(_keySubjectBias, json.encode(_subjectBias));
    await prefs.setString(_keyHistory, json.encode(_history.map((e) => e.toJson()).toList()));
  }

  /// Predict score with personal adjustments
  /// Returns adjusted prediction based on user's learning history
  double predictScore({
    required Map<String, SubjectPerformance> subjectPerformance,
    required int streak,
  }) {
    // Get base model prediction
    double basePrediction = _baseModel.predictScore(
      subjectPerformance: subjectPerformance,
      streak: streak,
    );
    
    // Apply personal bias learned from user's history
    double adjustedPrediction = basePrediction + (_personalBias * 100);
    
    // Clamp to valid range
    return adjustedPrediction.clamp(0.0, 100.0);
  }

  /// Predict score for a specific subject with personal adjustments
  double predictSubjectScore({
    required String subjectId,
    required double currentAccuracy,
    required int questionsAnswered,
  }) {
    // Base prediction from accuracy
    double basePrediction = currentAccuracy * 100;
    
    // Apply subject-specific bias
    double subjectBias = _subjectBias[subjectId] ?? 0.0;
    double adjustedPrediction = basePrediction + (subjectBias * 100);
    
    return adjustedPrediction.clamp(0.0, 100.0);
  }

  /// Record actual quiz result and learn from it
  /// This is the core learning function!
  Future<void> recordQuizResult({
    required String subjectId,
    required double predictedScore,
    required double actualScore,
    required int questionsAnswered,
    required DateTime timestamp,
  }) async {
    // Calculate prediction error
    double error = actualScore - predictedScore;  // Positive = underpredicted
    
    // ===== ONLINE LEARNING STEP =====
    
    // 1. Update personal bias (overall adjustment)
    // If we consistently underpredict, bias goes up
    // If we consistently overpredict, bias goes down
    _personalBias += _learningRate * (error / 100);
    _personalBias = _personalBias.clamp(-0.3, 0.3);  // Max ±30% adjustment
    
    // 2. Update subject-specific bias
    double currentSubjectBias = _subjectBias[subjectId] ?? 0.0;
    currentSubjectBias += _subjectLearningRate * (error / 100);
    currentSubjectBias = currentSubjectBias.clamp(-0.4, 0.4);  // Max ±40%
    _subjectBias[subjectId] = currentSubjectBias;
    
    // 3. Record in history
    _history.add(PredictionRecord(
      subjectId: subjectId,
      predictedScore: predictedScore,
      actualScore: actualScore,
      error: error,
      timestamp: timestamp,
    ));
    
    // Keep history size manageable
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
    
    // 4. Save learned parameters
    await _saveLearnedParameters();
    
    print('ML Learning: Predicted=$predictedScore, Actual=$actualScore, Error=$error');
    print('  Updated personal bias: $_personalBias');
    print('  Updated $subjectId bias: ${_subjectBias[subjectId]}');
  }

  /// Get learning statistics
  LearningStats getLearningStats() {
    if (_history.isEmpty) {
      return LearningStats(
        totalPredictions: 0,
        averageError: 0,
        improvementRate: 0,
        personalBias: _personalBias,
        isLearning: false,
      );
    }
    
    // Calculate average error
    double totalError = _history.fold(0.0, (sum, r) => sum + r.error.abs());
    double avgError = totalError / _history.length;
    
    // Calculate improvement (compare recent vs old predictions)
    double improvementRate = 0;
    if (_history.length >= 10) {
      final oldErrors = _history.sublist(0, 5).map((r) => r.error.abs());
      final newErrors = _history.sublist(_history.length - 5).map((r) => r.error.abs());
      
      double oldAvg = oldErrors.fold(0.0, (a, b) => a + b) / 5;
      double newAvg = newErrors.fold(0.0, (a, b) => a + b) / 5;
      
      if (oldAvg > 0) {
        improvementRate = ((oldAvg - newAvg) / oldAvg) * 100;
      }
    }
    
    return LearningStats(
      totalPredictions: _history.length,
      averageError: avgError,
      improvementRate: improvementRate,
      personalBias: _personalBias,
      isLearning: _history.length >= 3,
    );
  }

  /// Get subject-specific learning info
  SubjectLearningInfo getSubjectLearning(String subjectId) {
    final subjectHistory = _history.where((r) => r.subjectId == subjectId).toList();
    
    if (subjectHistory.isEmpty) {
      return SubjectLearningInfo(
        subjectId: subjectId,
        bias: _subjectBias[subjectId] ?? 0.0,
        predictions: 0,
        averageError: 0,
        trend: 'No data yet',
      );
    }
    
    double avgError = subjectHistory.fold(0.0, (sum, r) => sum + r.error) / subjectHistory.length;
    double bias = _subjectBias[subjectId] ?? 0.0;
    
    String trend;
    if (bias > 0.1) {
      trend = 'You score higher than expected here';
    } else if (bias < -0.1) {
      trend = 'This subject needs more focus';
    } else {
      trend = 'Predictions are accurate';
    }
    
    return SubjectLearningInfo(
      subjectId: subjectId,
      bias: bias,
      predictions: subjectHistory.length,
      averageError: avgError,
      trend: trend,
    );
  }

  /// Get personalized insights based on learning
  List<String> getPersonalizedInsights() {
    List<String> insights = [];
    
    final stats = getLearningStats();
    
    if (stats.totalPredictions < 3) {
      insights.add('Take more quizzes to help the AI learn your patterns!');
      return insights;
    }
    
    // Overall bias insight
    if (_personalBias > 0.1) {
      insights.add('You consistently score ${(_personalBias * 100).toStringAsFixed(0)}% higher than average students. Keep it up!');
    } else if (_personalBias < -0.1) {
      insights.add('Your scores are ${(_personalBias.abs() * 100).toStringAsFixed(0)}% below predictions. More practice will help!');
    }
    
    // Find strongest and weakest subjects
    String? strongestSubject;
    String? weakestSubject;
    double maxBias = -1;
    double minBias = 1;
    
    for (final entry in _subjectBias.entries) {
      if (entry.value > maxBias) {
        maxBias = entry.value;
        strongestSubject = entry.key;
      }
      if (entry.value < minBias) {
        minBias = entry.value;
        weakestSubject = entry.key;
      }
    }
    
    if (strongestSubject != null && maxBias > 0.1) {
      final name = _getSubjectName(strongestSubject);
      insights.add('$name is your strongest subject! You score ${(maxBias * 100).toStringAsFixed(0)}% above expected.');
    }
    
    if (weakestSubject != null && minBias < -0.1) {
      final name = _getSubjectName(weakestSubject);
      insights.add('Focus on $name - you\'re ${(minBias.abs() * 100).toStringAsFixed(0)}% below expected there.');
    }
    
    // Improvement insight
    if (stats.improvementRate > 10) {
      insights.add('Great progress! Prediction accuracy improved by ${stats.improvementRate.toStringAsFixed(0)}%.');
    }
    
    return insights;
  }

  String _getSubjectName(String subjectId) {
    final subject = CriminologySubjects.all.firstWhere(
      (s) => s.id == subjectId,
      orElse: () => CriminologySubjects.all.first,
    );
    return subject.name;
  }

  /// Reset learned parameters (start fresh)
  Future<void> resetLearning() async {
    _personalBias = 0.0;
    _subjectBias = {};
    _history = [];
    
    for (final subject in CriminologySubjects.all) {
      _subjectBias[subject.id] = 0.0;
    }
    
    await _saveLearnedParameters();
    print('ML Learning reset');
  }

  // Delegate methods to base model
  int recommendDifficulty({required Map<String, SubjectPerformance> subjectPerformance}) {
    return _baseModel.recommendDifficulty(subjectPerformance: subjectPerformance);
  }

  String getDifficultyName(int level) => _baseModel.getDifficultyName(level);

  List<WeakAreaResult> detectWeakAreas({required Map<String, SubjectPerformance> subjectPerformance}) {
    return _baseModel.detectWeakAreas(subjectPerformance: subjectPerformance);
  }

  bool get isLoaded => _baseModel.isLoaded;
}

/// Record of a single prediction
class PredictionRecord {
  final String subjectId;
  final double predictedScore;
  final double actualScore;
  final double error;
  final DateTime timestamp;

  PredictionRecord({
    required this.subjectId,
    required this.predictedScore,
    required this.actualScore,
    required this.error,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'subjectId': subjectId,
    'predictedScore': predictedScore,
    'actualScore': actualScore,
    'error': error,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PredictionRecord.fromJson(Map<String, dynamic> json) => PredictionRecord(
    subjectId: json['subjectId'],
    predictedScore: (json['predictedScore'] as num).toDouble(),
    actualScore: (json['actualScore'] as num).toDouble(),
    error: (json['error'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp']),
  );
}

/// Learning statistics
class LearningStats {
  final int totalPredictions;
  final double averageError;
  final double improvementRate;
  final double personalBias;
  final bool isLearning;

  LearningStats({
    required this.totalPredictions,
    required this.averageError,
    required this.improvementRate,
    required this.personalBias,
    required this.isLearning,
  });
}

/// Subject-specific learning info
class SubjectLearningInfo {
  final String subjectId;
  final double bias;
  final int predictions;
  final double averageError;
  final String trend;

  SubjectLearningInfo({
    required this.subjectId,
    required this.bias,
    required this.predictions,
    required this.averageError,
    required this.trend,
  });
}
