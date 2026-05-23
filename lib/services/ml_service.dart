import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/subject.dart';

/// Machine Learning Service for CrimiReview
/// 
/// This service provides intelligent predictions using trained ML models:
/// - Performance Prediction: Predicts expected quiz scores
/// - Weak Area Detection: Identifies subjects the user struggles with
/// - Difficulty Recommendation: Suggests appropriate difficulty level
/// - Study Priority Ranking: Recommends what to study next
/// 
/// The model was trained using Python (linear regression, statistical analysis)
/// and exported to JSON for on-device inference in Dart.
class MLService {
  static MLService? _instance;
  Map<String, dynamic>? _model;
  bool _isLoaded = false;

  MLService._();

  static MLService get instance {
    _instance ??= MLService._();
    return _instance!;
  }

  /// Load the ML model from assets
  Future<void> loadModel() async {
    if (_isLoaded) return;

    try {
      final jsonString = await rootBundle.loadString('assets/ml/ml_model.json');
      _model = json.decode(jsonString);
      _isLoaded = true;
      print('ML Model loaded successfully');
      print('Model validation: ${_model!['validation']}');
    } catch (e) {
      print('Error loading ML model: $e');
      // Use default fallback model if loading fails
      _model = _getDefaultModel();
      _isLoaded = true;
    }
  }

  /// Check if model is loaded
  bool get isLoaded => _isLoaded;

  /// Predict expected quiz score based on user performance
  /// Returns a score between 0-100
  double predictScore({
    required Map<String, SubjectPerformance> subjectPerformance,
    required int streak,
  }) {
    if (!_isLoaded || _model == null) return 50.0;

    final weights = List<double>.from(_model!['score_predictor']['weights']);
    final norm = _model!['normalization'];

    // Calculate features
    double overallAccuracy = 0;
    int totalQuestions = 0;
    double totalTime = 0;
    int weakCount = 0;
    int subjectCount = 0;

    for (final perf in subjectPerformance.values) {
      if (perf.questionsAnswered > 0) {
        overallAccuracy += perf.accuracy;
        totalQuestions += perf.questionsAnswered;
        totalTime += perf.avgTimePerQuestion;
        if (perf.accuracy < 0.5) weakCount++;
        subjectCount++;
      }
    }

    if (subjectCount == 0) return 50.0;

    overallAccuracy /= subjectCount;
    final avgTime = totalTime / subjectCount;

    // Normalize features
    final features = [
      1.0, // bias
      overallAccuracy,
      totalQuestions / (norm['max_questions'] as num).toDouble(),
      streak / (norm['max_streak'] as num).toDouble(),
      avgTime / (norm['max_time'] as num).toDouble(),
      weakCount / 6.0,
    ];

    // Calculate prediction
    double score = 0;
    for (int i = 0; i < weights.length && i < features.length; i++) {
      score += weights[i] * features[i];
    }

    // Convert to percentage and clamp
    return (score * 100).clamp(0.0, 100.0);
  }

  /// Recommend difficulty level based on performance
  /// Returns: 0 = Easy, 1 = Medium, 2 = Hard
  int recommendDifficulty({
    required Map<String, SubjectPerformance> subjectPerformance,
  }) {
    if (!_isLoaded || _model == null) return 0;

    final boundaries = List<double>.from(
      _model!['difficulty_recommender']['boundaries'],
    );

    // Calculate overall accuracy
    double totalAccuracy = 0;
    int count = 0;

    for (final perf in subjectPerformance.values) {
      if (perf.questionsAnswered > 0) {
        totalAccuracy += perf.accuracy;
        count++;
      }
    }

    if (count == 0) return 0;

    final overallAccuracy = totalAccuracy / count;

    if (overallAccuracy < boundaries[0]) {
      return 0; // Easy
    } else if (overallAccuracy < boundaries[1]) {
      return 1; // Medium
    } else {
      return 2; // Hard
    }
  }

  /// Get difficulty name from level
  String getDifficultyName(int level) {
    switch (level) {
      case 0:
        return 'Easy';
      case 1:
        return 'Medium';
      case 2:
        return 'Hard';
      default:
        return 'Easy';
    }
  }

  /// Detect weak areas - subjects the user struggles with
  /// Returns list of subject IDs sorted by weakness (most weak first)
  List<WeakAreaResult> detectWeakAreas({
    required Map<String, SubjectPerformance> subjectPerformance,
  }) {
    if (!_isLoaded || _model == null) return [];

    final weakDetector = _model!['weak_area_detector'];
    final subjects = List<String>.from(_model!['subjects']);

    // Calculate overall accuracy
    double overallAccuracy = 0;
    int count = 0;

    for (final perf in subjectPerformance.values) {
      if (perf.questionsAnswered > 0) {
        overallAccuracy += perf.accuracy;
        count++;
      }
    }

    if (count == 0) return [];
    overallAccuracy /= count;

    // Detect weak areas
    List<WeakAreaResult> results = [];

    for (int i = 0; i < subjects.length; i++) {
      final subjectId = subjects[i];
      final perf = subjectPerformance[subjectId];

      if (perf == null || perf.questionsAnswered == 0) continue;

      final detector = weakDetector[i.toString()];
      final threshold = (detector['weak_threshold'] as num).toDouble();
      final diff = perf.accuracy - overallAccuracy;

      // Subject is weak if accuracy difference is below threshold
      final isWeak = diff < threshold;
      final weaknessScore = isWeak ? (threshold - diff).abs() : 0.0;

      results.add(WeakAreaResult(
        subjectId: subjectId,
        subjectName: _getSubjectName(subjectId),
        accuracy: perf.accuracy,
        isWeak: isWeak,
        weaknessScore: weaknessScore,
        recommendation: _getWeakAreaRecommendation(perf.accuracy, isWeak),
      ));
    }

    // Sort by weakness score (most weak first)
    results.sort((a, b) => b.weaknessScore.compareTo(a.weaknessScore));

    return results;
  }

  /// Get study priority ranking - what to study next
  /// Returns subjects sorted by priority (highest priority first)
  List<StudyPriority> getStudyPriorities({
    required Map<String, SubjectPerformance> subjectPerformance,
    double targetMastery = 0.8,
  }) {
    if (!_isLoaded || _model == null) return [];

    final priorityWeights = _model!['priority_ranker'];
    final weaknessWeight = (priorityWeights['weakness_weight'] as num).toDouble();
    final recencyWeight = (priorityWeights['recency_weight'] as num).toDouble();
    final masteryGapWeight = (priorityWeights['mastery_gap_weight'] as num).toDouble();

    List<StudyPriority> priorities = [];

    for (final entry in subjectPerformance.entries) {
      final subjectId = entry.key;
      final perf = entry.value;

      // Calculate priority factors
      final weaknessFactor = 1.0 - perf.accuracy; // Lower accuracy = higher priority
      final recencyFactor = _calculateRecencyFactor(perf.lastStudied);
      final masteryGap = max(0.0, targetMastery - perf.accuracy);

      // Calculate weighted priority score
      final priorityScore = (weaknessFactor * weaknessWeight) +
          (recencyFactor * recencyWeight) +
          (masteryGap * masteryGapWeight);

      priorities.add(StudyPriority(
        subjectId: subjectId,
        subjectName: _getSubjectName(subjectId),
        priorityScore: priorityScore,
        accuracy: perf.accuracy,
        masteryGap: masteryGap,
        reason: _getPriorityReason(weaknessFactor, recencyFactor, masteryGap),
      ));
    }

    // Sort by priority score (highest first)
    priorities.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    return priorities;
  }

  /// Get personalized insights based on performance
  List<MLInsight> getInsights({
    required Map<String, SubjectPerformance> subjectPerformance,
    required int streak,
    required int totalQuizzes,
  }) {
    List<MLInsight> insights = [];

    final predictedScore = predictScore(
      subjectPerformance: subjectPerformance,
      streak: streak,
    );

    final weakAreas = detectWeakAreas(subjectPerformance: subjectPerformance);
    final priorities = getStudyPriorities(subjectPerformance: subjectPerformance);
    final recommendedDiff = recommendDifficulty(subjectPerformance: subjectPerformance);

    // Performance insight
    insights.add(MLInsight(
      type: InsightType.performance,
      title: 'Predicted Score',
      description: 'Based on your study patterns, you\'re likely to score around ${predictedScore.toStringAsFixed(0)}% on your next quiz.',
      value: predictedScore,
      icon: 'trending_up',
    ));

    // Difficulty recommendation
    insights.add(MLInsight(
      type: InsightType.difficulty,
      title: 'Recommended Difficulty',
      description: 'You should try ${getDifficultyName(recommendedDiff)} level questions based on your current performance.',
      value: recommendedDiff.toDouble(),
      icon: 'speed',
    ));

    // Weak areas insight
    final weakSubjects = weakAreas.where((w) => w.isWeak).toList();
    if (weakSubjects.isNotEmpty) {
      insights.add(MLInsight(
        type: InsightType.weakArea,
        title: 'Focus Area',
        description: 'You should focus on ${weakSubjects.first.subjectName}. Your accuracy there is ${(weakSubjects.first.accuracy * 100).toStringAsFixed(0)}%.',
        value: weakSubjects.first.accuracy * 100,
        icon: 'warning',
      ));
    }

    // Study priority insight
    if (priorities.isNotEmpty) {
      insights.add(MLInsight(
        type: InsightType.priority,
        title: 'Study Next',
        description: 'We recommend studying ${priorities.first.subjectName} next. ${priorities.first.reason}',
        value: priorities.first.priorityScore * 100,
        icon: 'school',
      ));
    }

    // Streak insight
    if (streak >= 7) {
      insights.add(MLInsight(
        type: InsightType.streak,
        title: 'Great Streak!',
        description: 'You\'ve maintained a $streak day streak! Keep it up for better retention.',
        value: streak.toDouble(),
        icon: 'local_fire_department',
      ));
    }

    return insights;
  }

  // Helper methods

  double _calculateRecencyFactor(DateTime? lastStudied) {
    if (lastStudied == null) return 1.0; // Never studied = high priority

    final daysSince = DateTime.now().difference(lastStudied).inDays;
    // Normalize: 0 days = 0, 7+ days = 1
    return min(1.0, daysSince / 7.0);
  }

  String _getSubjectName(String subjectId) {
    final subject = CriminologySubjects.all.firstWhere(
      (s) => s.id == subjectId,
      orElse: () => CriminologySubjects.all.first,
    );
    return subject.name;
  }

  String _getWeakAreaRecommendation(double accuracy, bool isWeak) {
    if (!isWeak) {
      if (accuracy >= 0.8) {
        return 'Great mastery! Keep reviewing to maintain.';
      }
      return 'Good progress. Continue practicing.';
    }

    if (accuracy < 0.3) {
      return 'Start with easy questions and review fundamentals.';
    } else if (accuracy < 0.5) {
      return 'Focus on this area. Use flashcards for key concepts.';
    } else {
      return 'Almost there! A few more practice sessions will help.';
    }
  }

  String _getPriorityReason(double weakness, double recency, double gap) {
    if (weakness > 0.5) {
      return 'You need more practice here.';
    } else if (recency > 0.7) {
      return 'It\'s been a while since you studied this.';
    } else if (gap > 0.3) {
      return 'You\'re close to mastering this topic.';
    }
    return 'Regular review helps retention.';
  }

  Map<String, dynamic> _getDefaultModel() {
    return {
      'score_predictor': {
        'weights': [0.0, 0.95, 0.02, 0.01, -0.03, -0.05],
      },
      'difficulty_recommender': {
        'boundaries': [0.45, 0.70],
      },
      'weak_area_detector': {
        '0': {'weak_threshold': -0.15},
        '1': {'weak_threshold': -0.15},
        '2': {'weak_threshold': -0.15},
        '3': {'weak_threshold': -0.15},
        '4': {'weak_threshold': -0.15},
        '5': {'weak_threshold': -0.15},
      },
      'priority_ranker': {
        'weakness_weight': 0.45,
        'recency_weight': 0.25,
        'mastery_gap_weight': 0.30,
      },
      'subjects': [
        'criminal_jurisprudence',
        'law_enforcement',
        'criminalistics',
        'crime_detection',
        'corrections',
        'criminology',
      ],
      'normalization': {
        'max_questions': 500,
        'max_streak': 30,
        'max_time': 40,
      },
    };
  }
}

/// Subject performance data for ML predictions
class SubjectPerformance {
  final String subjectId;
  final double accuracy; // 0.0 - 1.0
  final int questionsAnswered;
  final int correctAnswers;
  final double avgTimePerQuestion; // seconds
  final DateTime? lastStudied;

  SubjectPerformance({
    required this.subjectId,
    required this.accuracy,
    required this.questionsAnswered,
    required this.correctAnswers,
    required this.avgTimePerQuestion,
    this.lastStudied,
  });
}

/// Result of weak area detection
class WeakAreaResult {
  final String subjectId;
  final String subjectName;
  final double accuracy;
  final bool isWeak;
  final double weaknessScore;
  final String recommendation;

  WeakAreaResult({
    required this.subjectId,
    required this.subjectName,
    required this.accuracy,
    required this.isWeak,
    required this.weaknessScore,
    required this.recommendation,
  });
}

/// Study priority ranking result
class StudyPriority {
  final String subjectId;
  final String subjectName;
  final double priorityScore;
  final double accuracy;
  final double masteryGap;
  final String reason;

  StudyPriority({
    required this.subjectId,
    required this.subjectName,
    required this.priorityScore,
    required this.accuracy,
    required this.masteryGap,
    required this.reason,
  });
}

/// ML-generated insight
class MLInsight {
  final InsightType type;
  final String title;
  final String description;
  final double value;
  final String icon;

  MLInsight({
    required this.type,
    required this.title,
    required this.description,
    required this.value,
    required this.icon,
  });
}

enum InsightType {
  performance,
  difficulty,
  weakArea,
  priority,
  streak,
}
