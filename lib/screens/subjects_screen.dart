import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../utils/quiz_launcher.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

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
    final padding = Responsive.horizontalPadding(context);
    const subjects = CriminologySubjects.all;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
                  sliver: SliverToBoxAdapter(
                    child: ContentWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PageHeader(
                            title: 'Quiz',
                            subtitle: 'Choose a subject to start practicing',
                          ),
                          const SizedBox(height: 16),
                          const InlineBanner(
                            tone: BannerTone.info,
                            icon: Icons.route_rounded,
                            message:
                                'Each subject has Easy, Medium and Hard levels. Pass every segment of a level to unlock the next one.',
                          ),
                          const SizedBox(height: 20),
                          Text('${subjects.length} BOARD SUBJECTS', style: context.textStyles.labelSmall),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 28),
                  sliver: SliverList.separated(
                    itemCount: subjects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => ContentWidth(
                      child: Appear(
                        index: index,
                        child: _buildSubjectCard(context, subjects[index]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isPreparingQuiz) _buildPreparingOverlay(),
        ],
      ),
    );
  }

  /// Brief blocking indicator shown while the quiz set is pulled from the
  /// question repository (cache hit is instant; a cold start may need a fetch).
  Widget _buildPreparingOverlay() {
    final p = context.palette;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: context.isDarkMode ? 0.55 : 0.32),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusLg),
            ),
            child: const LoadingView(label: 'Preparing your questions...'),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectCard(BuildContext context, Subject subject) {
    final p = context.palette;
    final text = context.textStyles;
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress.subjectProgress[subject.id];
    final accuracy = progress?.overallAccuracy ?? 0.0;
    final questionsAnswered = progress?.totalQuestionsAnswered ?? 0;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);

    final easyPassed = progress?.isDifficultyPassed(Difficulty.easy) ?? false;
    final mediumPassed = progress?.isDifficultyPassed(Difficulty.medium) ?? false;
    final hardPassed = progress?.isDifficultyPassed(Difficulty.hard) ?? false;

    return AppCard(
      onTap: () => _showQuizOptions(context, subject),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 48, iconSize: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.name, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  questionsAnswered > 0
                      ? '${subject.weight}% of exam · $questionsAnswered answered'
                      : '${subject.weight}% of exam · Not started',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _levelStep(context, 'E', easyPassed, true, p.success),
                    _levelStep(context, 'M', mediumPassed, easyPassed, p.warning),
                    _levelStep(context, 'H', hardPassed, mediumPassed, p.danger),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (questionsAnswered > 0)
            RingProgress(
              value: accuracy,
              size: 46,
              stroke: 5,
              color: _getAccuracyColor(accuracy),
              center: Text(
                '${(accuracy * 100).toStringAsFixed(0)}%',
                style: text.labelSmall?.copyWith(color: p.textPrimary, letterSpacing: 0, fontSize: 10.5),
              ),
            )
          else
            Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
  }

  /// One step of the E · M · H level indicator on a subject card.
  Widget _levelStep(BuildContext context, String label, bool passed, bool unlocked, Color color) {
    final p = context.palette;
    final Color bg;
    final Color fg;
    if (passed) {
      bg = color;
      fg = Colors.white;
    } else if (unlocked) {
      bg = color.withValues(alpha: context.isDarkMode ? 0.2 : 0.12);
      fg = color;
    } else {
      bg = p.surfaceAlt;
      fg = p.textTertiary;
    }
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (passed) ...[
            Icon(Icons.check_rounded, size: 11, color: fg),
            const SizedBox(width: 2),
          ] else if (!unlocked) ...[
            Icon(Icons.lock_rounded, size: 10, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAccuracyColor(double accuracy) {
    final p = context.palette;
    if (accuracy >= SubjectProgress.levelPassThreshold) return p.success;
    if (accuracy >= 0.5) return p.warning;
    return p.danger;
  }

  void _showQuizOptions(BuildContext screenContext, Subject subject) {
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);
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
      isScrollControlled: true,
      builder: (context) {
        final p = context.palette;
        final text = context.textStyles;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: icon, color: color, size: 48, iconSize: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subject.name, style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text('${subject.weight}% of the board exam', style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subject.description,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Text('CHOOSE DIFFICULTY', style: text.labelSmall),
                const SizedBox(height: 10),
                _buildLevelTile(
                  context: context,
                  title: 'Easy',
                  subtitle: easyPassed
                      ? 'All segments passed'
                      : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.easy)}',
                  icon: Icons.signal_cellular_alt_1_bar_rounded,
                  color: p.success,
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
                const SizedBox(height: 10),
                _buildLevelTile(
                  context: context,
                  title: 'Medium',
                  subtitle: !mediumUnlocked
                      ? 'Pass Easy to unlock'
                      : mediumPassed
                          ? 'All segments passed'
                          : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.medium)}',
                  icon: Icons.signal_cellular_alt_2_bar_rounded,
                  color: p.warning,
                  isLocked: !mediumUnlocked,
                  isPassed: mediumPassed,
                  segments: mediumUnlocked ? progress?.mediumSegments : null,
                  onTap: mediumUnlocked ? () {
                    Navigator.pop(context);
                    _startQuizWithDifficulty(screenContext, subject, Difficulty.medium);
                  } : null,
                ),
                const SizedBox(height: 10),
                _buildLevelTile(
                  context: context,
                  title: 'Hard',
                  subtitle: !hardUnlocked
                      ? 'Pass Medium to unlock'
                      : hardPassed
                          ? 'All segments passed'
                          : 'Questions ${service.getCurrentSegmentRangeLabel(subjectId: subject.id, difficulty: Difficulty.hard)}',
                  icon: Icons.signal_cellular_alt_rounded,
                  color: p.danger,
                  isLocked: !hardUnlocked,
                  isPassed: hardPassed,
                  segments: hardUnlocked ? progress?.hardSegments : null,
                  onTap: hardUnlocked ? () {
                    Navigator.pop(context);
                    _startQuizWithDifficulty(screenContext, subject, Difficulty.hard);
                  } : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLevelTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isLocked,
    required bool isPassed,
    List<SegmentProgress>? segments,
    VoidCallback? onTap,
  }) {
    final p = context.palette;
    final text = context.textStyles;
    final showProgress = !isLocked && segments != null;
    final currentSegmentIndex = showProgress
        ? segments.indexWhere((segment) => !segment.isPassed)
        : -1;
    final activeSegmentIndex = currentSegmentIndex == -1
        ? (segments?.length ?? SegmentProgress.segmentCount) - 1
        : currentSegmentIndex;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      color: isLocked ? p.surfaceAlt : p.surface,
      borderColor: isLocked ? Colors.transparent : p.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: isLocked ? Icons.lock_rounded : icon,
                color: isLocked ? p.textTertiary : color,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        color: isLocked ? p.textTertiary : p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
              if (isPassed)
                Pill(label: 'Passed', icon: Icons.check_rounded, color: p.success)
              else if (!isLocked)
                Icon(Icons.chevron_right_rounded, color: p.textTertiary),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 14),
            Row(
              children: List.generate(segments.length, (index) {
                final segment = segments[index];
                final isActiveSegment = index == activeSegmentIndex && !isPassed;
                // Untried segments stay empty (they used to show as a full
                // red bar, which read as "failed").
                final Color barColor = segment.isPassed
                    ? p.success
                    : segment.isAttempted
                        ? p.danger
                        : p.textTertiary;
                final barValue = segment.isPassed
                    ? 1.0
                    : segment.isAttempted
                        ? segment.accuracy.clamp(0.0, 1.0)
                        : 0.0;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index < segments.length - 1 ? 8 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppProgressBar(value: barValue, color: barColor, height: 6),
                        const SizedBox(height: 6),
                        Text(
                          segment.rangeLabel,
                          style: text.labelSmall?.copyWith(
                            letterSpacing: 0,
                            color: isActiveSegment ? color : barColor,
                            fontWeight: isActiveSegment ? FontWeight.w800 : FontWeight.w600,
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
    );
  }

  Future<void> _startQuizWithDifficulty(BuildContext context, Subject subject, Difficulty difficulty) async {
    if (_isPreparingQuiz) return; // guard against a double tap re-firing the fetch
    await startSegmentQuiz(
      context,
      subject: subject,
      difficulty: difficulty,
      onPreparing: (preparing) {
        if (mounted) setState(() => _isPreparingQuiz = preparing);
      },
    );
  }
}
