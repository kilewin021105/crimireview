import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../services/question_repository.dart';
import '../services/theme_service.dart';
import '../utils/page_transitions.dart';
import 'study_notes_screen.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  /// Questions now come from Supabase (+ the offline snapshot) instead of a
  /// compiled-in list, so building a quiz set is asynchronous. This guards the
  /// tap and drives the brief loading overlay.
  bool _isPreparingQuiz = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quiz',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose a subject to start',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: CriminologySubjects.all.length,
                    itemBuilder: (context, index) {
                      return _buildSubjectCard(context, CriminologySubjects.all[index], isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_isPreparingQuiz) _buildPreparingOverlay(isDark),
        ],
      ),
    );
  }

  /// Brief blocking indicator shown while the quiz set is pulled from the
  /// question repository (cache hit is instant; a cold start may need a fetch).
  Widget _buildPreparingOverlay(bool isDark) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.35),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Preparing your questions...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectCard(BuildContext context, Subject subject, bool isDark) {
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress.subjectProgress[subject.id];
    final accuracy = progress?.overallAccuracy ?? 0.0;
    final questionsAnswered = progress?.totalQuestionsAnswered ?? 0;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    const accentColor = AppColors.accent;
    
    return GestureDetector(
      onTap: () => _showQuizOptions(context, subject, isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    questionsAnswered > 0 ? '$questionsAnswered answered' : 'Start learning',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (questionsAnswered > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getAccuracyColor(accuracy).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(accuracy * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _getAccuracyColor(accuracy),
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= SubjectProgress.levelPassThreshold) return AppColors.success;
    if (accuracy >= 0.5) return AppColors.primary;
    return AppColors.error;
  }

  void _showQuizOptions(BuildContext screenContext, Subject subject, bool isDark) {
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    const accentColor = AppColors.accent;
    final service = Provider.of<AdaptiveLearningService>(screenContext, listen: false);
    final progress = service.userProgress.subjectProgress[subject.id];
    
    // Determine if all segments are passed for each difficulty
    final easyPassed = progress?.isDifficultyPassed(Difficulty.easy) ?? false;
    final mediumPassed = progress?.isDifficultyPassed(Difficulty.medium) ?? false;
    final hardPassed = progress?.isDifficultyPassed(Difficulty.hard) ?? false;
    
    // Medium is locked if Easy not passed
    final mediumUnlocked = easyPassed;
    // Hard is locked if Medium not passed
    final hardUnlocked = mediumPassed;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    subject.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Quiz Difficulty',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            

            _buildLevelTile(
              context: context,
              isDark: isDark,
              title: 'Easy',
              subtitle: easyPassed
                  ? 'All segments passed'
                  : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.easy)}',
              icon: Icons.sentiment_satisfied_rounded,
              color: const Color(0xFF22C55E),
              isLocked: false,
              isPassed: easyPassed,
              segments: progress?.easySegments ??
                  List.generate(
                    SegmentProgress.segmentCount,
                    (index) => SegmentProgress(segmentIndex: index),
                  ),
              onTap: () {
                Navigator.pop(context);
                _startQuizWithDifficulty(screenContext, subject, Difficulty.easy);
              },
            ),
            const SizedBox(height: 12),
            

            _buildLevelTile(
              context: context,
              isDark: isDark,
              title: 'Medium',
              subtitle: !mediumUnlocked
                  ? 'Pass Easy to unlock'
                  : mediumPassed
                      ? 'All segments passed'
                      : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.medium)}',
              icon: Icons.sentiment_neutral_rounded,
              color: const Color(0xFFF59E0B),
              isLocked: !mediumUnlocked,
              isPassed: mediumPassed,
              segments: mediumUnlocked ? progress?.mediumSegments : null,
              onTap: mediumUnlocked ? () {
                Navigator.pop(context);
                _startQuizWithDifficulty(screenContext, subject, Difficulty.medium);
              } : null,
            ),
            const SizedBox(height: 12),
            

            _buildLevelTile(
              context: context,
              isDark: isDark,
              title: 'Hard',
              subtitle: !hardUnlocked
                  ? 'Pass Medium to unlock'
                  : hardPassed
                      ? 'All segments passed'
                      : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.hard)}',
              icon: Icons.sentiment_very_dissatisfied_rounded,
              color: const Color(0xFFEF4444),
              isLocked: !hardUnlocked,
              isPassed: hardPassed,
              segments: hardUnlocked ? progress?.hardSegments : null,
              onTap: hardUnlocked ? () {
                Navigator.pop(context);
                _startQuizWithDifficulty(screenContext, subject, Difficulty.hard);
              } : null,
            ),
            
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelTile({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isLocked,
    required bool isPassed,
    List<SegmentProgress>? segments,
    VoidCallback? onTap,
  }) {
    final showProgress = !isLocked && segments != null;
    final currentSegmentIndex = showProgress
        ? segments.indexWhere((segment) => !segment.isPassed)
        : -1;
    final activeSegmentIndex = currentSegmentIndex == -1
        ? (segments?.length ?? SegmentProgress.segmentCount) - 1
        : currentSegmentIndex;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLocked 
            ? (isDark ? Colors.grey.shade900 : Colors.grey.shade100)
            : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLocked 
              ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300)
              : color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isLocked 
                      ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                      : color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_rounded : icon,
                    color: isLocked 
                      ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
                      : color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isLocked 
                            ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
                            : (isDark ? Colors.white : const Color(0xFF1A1A2E)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isLocked 
                            ? (isDark ? Colors.grey.shade700 : Colors.grey.shade500)
                            : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPassed)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF22C55E),
                      size: 20,
                    ),
                  )
                else if (!isLocked)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                  ),
              ],
            ),
            if (showProgress) ...[
              const SizedBox(height: 14),
              Row(
                children: List.generate(segments.length, (index) {
                  final segment = segments[index];
                  final barColor = segment.isPassed
                      ? AppColors.success
                      : AppColors.error;
                  final barValue = segment.isAttempted
                      ? segment.accuracy.clamp(0.0, 1.0)
                      : 1.0;
                  final isActiveSegment = index == activeSegmentIndex && !isPassed;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index < segments.length - 1 ? 8 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: isActiveSegment
                                  ? Border.all(
                                      color: color.withValues(alpha: 0.35),
                                    )
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                value: barValue,
                                backgroundColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation(barColor),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            segment.rangeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActiveSegment
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: barColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startQuizWithDifficulty(BuildContext context, Subject subject, Difficulty difficulty) async {
    if (_isPreparingQuiz) return; // guard against a double tap re-firing the fetch
    final service = Provider.of<AdaptiveLearningService>(context, listen: false);
    final segmentIndex = service.getCurrentSegmentIndex(
      subjectId: subject.id,
      difficulty: difficulty,
    );

    setState(() => _isPreparingQuiz = true);
    List<Question> questions;
    try {
      questions = await service.getQuestionsForSegment(
        subjectId: subject.id,
        difficulty: difficulty,
      );
    } finally {
      if (mounted) setState(() => _isPreparingQuiz = false);
    }

    if (!context.mounted) return;

    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ${difficulty.name} questions available for ${SegmentProgress.rangeLabelFor(segmentIndex)}',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      SlidePageRoute(
        page: StudyNotesScreen(
          subject: subject,
          questions: questions,
          difficulty: difficulty,
          segmentIndex: segmentIndex,
        ),
      ),
    );
  }
}
