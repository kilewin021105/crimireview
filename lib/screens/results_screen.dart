import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../services/adaptive_learning_service.dart';
import '../services/adaptive_ml_service.dart';
import '../services/ml_service.dart';
import '../services/theme_service.dart';
import '../services/supabase_service.dart';

class ResultsScreen extends StatefulWidget {
  final Subject subject;
  final List<Question> questions;
  final List<bool> results;
  final List<int> responseTimes;
  final Difficulty? difficulty;

  const ResultsScreen({
    super.key,
    required this.subject,
    required this.questions,
    required this.results,
    required this.responseTimes,
    this.difficulty,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scoreAnimation;
  bool _levelPassed = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    
    final correctCount = widget.results.where((r) => r).length;
    final percentage = correctCount / widget.questions.length;
    
    if (widget.difficulty != null && percentage >= 0.75) {
      _levelPassed = true;
      _markLevelPassed();
    }
    
    _recordForMLLearning(percentage * 100);
    _saveToSupabase(correctCount);
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _scoreAnimation = Tween<double>(begin: 0, end: percentage).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    
    _controller.forward();
  }

  Future<void> _saveToSupabase(int correctCount) async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) return;
    
    final score = correctCount * 10;
    final difficultyStr = widget.difficulty?.toString().split('.').last ?? 'medium';
    
    await SupabaseService.instance.saveQuizResult(
      subjectId: widget.subject.id,
      difficulty: difficultyStr,
      score: score,
      totalQuestions: widget.questions.length,
      correctAnswers: correctCount,
    );
  }

  /// Record quiz result for ML model self-learning
  Future<void> _recordForMLLearning(double actualScore) async {
    final mlService = AdaptiveMLService.instance;
    if (!mlService.isLoaded) return;
    


    final service = Provider.of<AdaptiveLearningService>(context, listen: false);
    final subjectProgress = service.userProgress.subjectProgress[widget.subject.id];
    
    double predictedScore;
    if (subjectProgress != null && subjectProgress.totalQuestionsAnswered > 0) {

      final historicalAccuracy = subjectProgress.totalCorrectAnswers / 
          subjectProgress.totalQuestionsAnswered;
      predictedScore = mlService.predictSubjectScore(
        subjectId: widget.subject.id,
        currentAccuracy: historicalAccuracy,
        questionsAnswered: subjectProgress.totalQuestionsAnswered,
      );
    } else {

      predictedScore = 55.0; // PRC average passing rate baseline
    }
    

    await mlService.recordQuizResult(
      subjectId: widget.subject.id,
      predictedScore: predictedScore,
      actualScore: actualScore,
      questionsAnswered: widget.questions.length,
      timestamp: DateTime.now(),
    );
    
    print('ML Learning: Subject=${widget.subject.id}, Predicted=$predictedScore, Actual=$actualScore');
  }

  void _markLevelPassed() {
    if (widget.difficulty == null) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AdaptiveLearningService>(context, listen: false).markLevelPassed(
        subjectId: widget.subject.id,
        difficulty: widget.difficulty!,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final correctCount = widget.results.where((r) => r).length;
    final percentage = (correctCount / widget.questions.length * 100).round();
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              

              AnimatedBuilder(
                animation: _scoreAnimation,
                builder: (context, child) {
                  return SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: CircularProgressIndicator(
                            value: 1,
                            strokeWidth: 12,
                            strokeCap: StrokeCap.round,
                            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(Colors.transparent),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: CircularProgressIndicator(
                            value: _scoreAnimation.value,
                            strokeWidth: 12,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation(_getScoreColor(percentage)),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(_scoreAnimation.value * 100).round()}%',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              'Score',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              

              Text(
                _getMessage(percentage),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                '$correctCount out of ${widget.questions.length} correct',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              

              if (_levelPassed && widget.difficulty != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_open_rounded, color: AppColors.success, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.difficulty!.name.toUpperCase()} Level Passed!',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatCard(
                    correctCount.toString(),
                    'Correct',
                    AppColors.success,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatCard(
                    (widget.questions.length - correctCount).toString(),
                    'Wrong',
                    AppColors.error,
                    isDark,
                  ),
                ],
              ),
              
              const Spacer(flex: 3),
              

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: BorderSide(color: AppColors.accent, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Try Again',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, Color color, bool isDark) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  String _getMessage(int percentage) {
    if (percentage >= 80) return 'Excellent!';
    if (percentage >= 60) return 'Good Job!';
    if (percentage >= 40) return 'Keep Going!';
    return 'Keep Practicing!';
  }

  Color _getScoreColor(int percentage) {
    if (percentage >= 70) return AppColors.success;
    if (percentage >= 50) return AppColors.accent;
    return AppColors.error;
  }
}
