import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../services/adaptive_ml_service.dart';
import '../widgets/ui/ui.dart';
import '../services/supabase_service.dart';
import '../services/offline_sync_service.dart';

class ResultsScreen extends StatefulWidget {
  final Subject subject;
  final List<Question> questions;
  final List<bool> results;
  final List<int> responseTimes;
  final Difficulty? difficulty;
  final int? segmentIndex;

  const ResultsScreen({
    super.key,
    required this.subject,
    required this.questions,
    required this.results,
    required this.responseTimes,
    this.difficulty,
    this.segmentIndex,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scoreAnimation;
  bool _segmentPassed = false;
  bool _difficultyCompleted = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    
    final correctCount = widget.results.where((r) => r).length;
    final percentage = correctCount / widget.questions.length;
    
    if (widget.difficulty != null && percentage >= SubjectProgress.levelPassThreshold) {
      _segmentPassed = true;
      final service = Provider.of<AdaptiveLearningService>(context, listen: false);
      final subjectProgress = service.userProgress.subjectProgress[widget.subject.id];
      if (subjectProgress != null) {
        _difficultyCompleted = subjectProgress.isDifficultyPassed(widget.difficulty!);
      }
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
    
    final score = ((correctCount / widget.questions.length) * 100).round();
    final difficultyStr = widget.difficulty?.toString().split('.').last ?? 'medium';

    await OfflineSyncService.instance.saveQuizResultOrQueue(
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
    
    debugPrint('ML Learning: Subject=${widget.subject.id}, Predicted=$predictedScore, Actual=$actualScore');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final correctCount = widget.results.where((r) => r).length;
    final total = widget.questions.length;
    final percentage = (correctCount / total * 100).round();
    final scoreColor = _getScoreColor(percentage);
    final avgSeconds = widget.responseTimes.isEmpty
        ? 0.0
        : widget.responseTimes.reduce((a, b) => a + b) / widget.responseTimes.length / 1000;

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: Column(
                    children: [
                      Pill(
                        label: '${widget.subject.shortName}${widget.difficulty != null ? ' · ${_difficultyLabel(widget.difficulty!)}' : ''}',
                        color: AppColors.subjectColor(widget.subject.id),
                      ),
                      const SizedBox(height: 22),
                      RingProgress(
                        value: correctCount / total,
                        size: 176,
                        stroke: 14,
                        color: scoreColor,
                        center: AnimatedBuilder(
                          animation: _scoreAnimation,
                          builder: (context, _) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(_scoreAnimation.value * 100).round()}%',
                                style: text.displaySmall?.copyWith(fontSize: 42),
                              ),
                              Text('score', style: text.labelSmall),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(_getMessage(percentage), style: text.headlineMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text(
                        '$correctCount out of $total correct',
                        style: text.bodyLarge?.copyWith(color: p.textSecondary),
                      ),
                      if (_segmentPassed && widget.difficulty != null) ...[
                        const SizedBox(height: 18),
                        InlineBanner(
                          tone: BannerTone.success,
                          icon: _difficultyCompleted
                              ? Icons.workspace_premium_rounded
                              : Icons.lock_open_rounded,
                          title: _difficultyCompleted
                              ? '${_difficultyLabel(widget.difficulty!)} level completed!'
                              : 'Segment ${SegmentProgress.rangeLabelFor(widget.segmentIndex ?? 0)} passed!',
                          message: _difficultyCompleted
                              ? 'Every segment of this level is passed. The next level is unlocked.'
                              : 'Nice work. The next segment is ready for you.',
                        ),
                      ] else if (widget.difficulty != null) ...[
                        const SizedBox(height: 18),
                        InlineBanner(
                          tone: BannerTone.neutral,
                          icon: Icons.flag_rounded,
                          message:
                              'Score ${(SubjectProgress.levelPassThreshold * 100).round()}% or higher to pass this segment.',
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              icon: Icons.check_circle_rounded,
                              value: '$correctCount',
                              label: 'Correct',
                              color: p.success,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StatTile(
                              icon: Icons.cancel_rounded,
                              value: '${total - correctCount}',
                              label: 'Wrong',
                              color: p.danger,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StatTile(
                              icon: Icons.timer_rounded,
                              value: '${avgSeconds.toStringAsFixed(avgSeconds < 10 ? 1 : 0)}s',
                              label: 'Per question',
                              color: p.info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildBoardExamReadiness(context),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.border)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Done',
                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _difficultyLabel(Difficulty d) => d.name[0].toUpperCase() + d.name.substring(1);

  String _getMessage(int percentage) {
    if (percentage >= 80) return 'Excellent!';
    if (percentage >= 60) return 'Good job!';
    if (percentage >= 40) return 'Keep going!';
    return 'Keep practicing!';
  }

  Color _getScoreColor(int percentage) {
    final p = context.palette;
    if (percentage >= (SubjectProgress.levelPassThreshold * 100).round()) {
      return p.success;
    }
    if (percentage >= 50) return p.warning;
    return p.danger;
  }

  Widget _buildBoardExamReadiness(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final service = Provider.of<AdaptiveLearningService>(context, listen: false);

    // Only show if user has attempted ALL subjects
    const allSubjects = CriminologySubjects.all;
    final attemptedSubjects = allSubjects.where((s) {
      final progress = service.userProgress.subjectProgress[s.id];
      return progress != null && progress.totalQuestionsAnswered > 0;
    }).length;

    if (attemptedSubjects < allSubjects.length) {
      final remaining = allSubjects.length - attemptedSubjects;
      return AppCard(
        child: Row(
          children: [
            IconBadge(icon: Icons.lock_outline_rounded, color: p.textSecondary, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Board exam readiness', style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Take a quiz in $remaining more subject${remaining > 1 ? 's' : ''} to unlock your predicted score.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  AppProgressBar(value: attemptedSubjects / allSubjects.length, height: 6),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // All subjects attempted - show the predicted score
    final readiness = service.getOverallBoardExamReadiness();
    final isReady = readiness >= 75;
    final needsWork = readiness < 60;
    final tone = isReady ? p.success : (needsWork ? p.danger : p.warning);

    return AppCard(
      child: Row(
        children: [
          RingProgress(
            value: readiness / 100,
            size: 64,
            stroke: 7,
            color: tone,
            center: Text(
              '${readiness.toStringAsFixed(0)}%',
              style: text.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Board exam readiness', style: text.titleSmall),
                const SizedBox(height: 6),
                Pill(
                  label: isReady
                      ? "You're ready to pass!"
                      : needsWork
                          ? 'Needs more practice'
                          : 'Almost there!',
                  color: tone,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
