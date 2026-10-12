import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../models/subject.dart';
import '../models/achievement.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'achievements_screen.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 28),
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(
                  title: 'Progress',
                  subtitle: 'Track your learning journey',
                ),
                const SizedBox(height: 20),
                Appear(index: 0, child: _buildOverallStats(context, progress)),
                const SizedBox(height: 12),
                Appear(index: 1, child: _buildStreakCard(context, progress)),
                const SizedBox(height: AppSpace.section),
                Appear(index: 2, child: _buildAccuracyChart(context, service)),
                const SizedBox(height: AppSpace.section),
                Appear(index: 3, child: _buildAchievements(context, service)),
                const SizedBox(height: AppSpace.section),
                Appear(index: 4, child: _buildSubjectBreakdown(context, service)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverallStats(BuildContext context, dynamic progress) {
    final text = context.textStyles;
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0) as int),
    );
    final totalCorrect = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalCorrectAnswers ?? 0) as int),
    );
    final totalQuizzes = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalQuizzesTaken ?? 0) as int),
    );
    final accuracy = totalQuestions > 0 ? totalCorrect / totalQuestions : 0.0;

    return GradientCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVERALL ACCURACY',
                      style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(accuracy * 100).toStringAsFixed(0)}%',
                      style: text.displaySmall?.copyWith(color: Colors.white, fontSize: 40),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalQuestions == 0
                          ? 'Answer a few questions to see your stats'
                          : '$totalCorrect of $totalQuestions answers correct',
                      style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
              RingProgress(
                value: accuracy,
                size: 84,
                stroke: 9,
                color: Colors.white,
                trackColor: Colors.white.withValues(alpha: 0.18),
                center: const Icon(Icons.track_changes_rounded, color: Colors.white, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpace.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(child: _buildMiniStat(context, 'Questions', '$totalQuestions')),
                Container(width: 1, height: 30, color: Colors.white24),
                Expanded(child: _buildMiniStat(context, 'Correct', '$totalCorrect')),
                Container(width: 1, height: 30, color: Colors.white24),
                Expanded(child: _buildMiniStat(context, 'Quizzes', '$totalQuizzes')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(BuildContext context, String label, String value) {
    final text = context.textStyles;
    return Column(
      children: [
        Text(value, style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 1),
        Text(label, style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildStreakCard(BuildContext context, dynamic progress) {
    final p = context.palette;
    final text = context.textStyles;
    final int current = progress.currentStreak;
    final int best = progress.longestStreak;
    return AppCard(
      child: Row(
        children: [
          IconBadge(icon: Icons.local_fire_department_rounded, color: p.streak, size: 48, iconSize: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$current-day streak', style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  current == 0 ? 'Study today to start a new streak' : 'Study again tomorrow to keep it going',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('BEST', style: text.labelSmall),
              Text('$best', style: text.titleLarge?.copyWith(color: p.streak, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  /// Accuracy per subject as a bar chart, with the 75% pass mark drawn in.
  Widget _buildAccuracyChart(BuildContext context, AdaptiveLearningService service) {
    final p = context.palette;
    final text = context.textStyles;
    const subjects = CriminologySubjects.all;
    const pass = SubjectProgress.levelPassThreshold * 100;
    final anyData = subjects.any(
      (s) => (service.userProgress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0) > 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Accuracy by subject',
          subtitle: 'Dashed line: ${pass.toStringAsFixed(0)}% pass mark',
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(8, 20, 16, 10),
          child: !anyData
              ? const EmptyState(
                  compact: true,
                  icon: Icons.bar_chart_rounded,
                  title: 'No answers yet',
                  message: 'Take a quiz and your accuracy per subject will show up here.',
                )
              : SizedBox(
                  height: 210,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: 100,
                      alignment: BarChartAlignment.spaceAround,
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1),
                      ),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: pass,
                            color: p.success,
                            strokeWidth: 1.5,
                            dashArray: [6, 4],
                          ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: 25,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}',
                              style: text.labelSmall?.copyWith(letterSpacing: 0),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= subjects.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Icon(
                                  AppTheme.subjectIcons[subjects[i].id] ?? Icons.book_rounded,
                                  size: 17,
                                  color: AppColors.subjectColor(subjects[i].id),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBgColor: context.isDarkMode ? p.surfaceAlt : p.textPrimary,
                          tooltipRoundedRadius: 10,
                          getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                            '${subjects[group.x].shortName}\n${rod.toY.toStringAsFixed(0)}%',
                            text.labelMedium!.copyWith(
                              color: context.isDarkMode ? p.textPrimary : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < subjects.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: ((service.userProgress.subjectProgress[subjects[i].id]?.overallAccuracy ?? 0) * 100)
                                    .clamp(0, 100)
                                    .toDouble(),
                                width: 22,
                                color: AppColors.subjectColor(subjects[i].id),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: 100,
                                  color: p.surfaceAlt,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAchievements(BuildContext context, AdaptiveLearningService service) {
    final p = context.palette;
    final text = context.textStyles;
    final unlocked = service.getUnlockedAchievements();
    final unlockedIds = unlocked.map((a) => a.id).toSet();
    final displayAchievements = Achievements.all.take(8).toList();
    void open() => Navigator.push(context, SlidePageRoute(page: const AchievementsScreen()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Achievements',
          subtitle: '${unlocked.length} of ${Achievements.all.length} unlocked',
          actionLabel: 'See all',
          onAction: open,
        ),
        const SizedBox(height: 12),
        AppCard(
          onTap: open,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              AppProgressBar(
                value: Achievements.all.isEmpty ? 0 : unlocked.length / Achievements.all.length,
                color: p.gold,
                height: 6,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, c) {
                final size = ((c.maxWidth - 3 * 10) / 4).clamp(48.0, 64.0);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  children: displayAchievements.map((a) {
                    final isUnlocked = unlockedIds.contains(a.id);
                    return Tooltip(
                      message: '${a.name}: ${a.description}',
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: isUnlocked ? p.goldSoft : p.surfaceAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: isUnlocked
                              ? Border.all(color: p.gold.withValues(alpha: 0.35))
                              : null,
                        ),
                        child: Icon(
                          isUnlocked ? a.icon : Icons.lock_outline_rounded,
                          color: isUnlocked ? p.gold : p.textTertiary,
                          size: isUnlocked ? 26 : 20,
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap to see every badge and how to earn it',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectBreakdown(BuildContext context, AdaptiveLearningService service) {
    final p = context.palette;
    final text = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'By subject'),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < CriminologySubjects.all.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                Builder(builder: (context) {
                  final subject = CriminologySubjects.all[i];
                  final progress = service.userProgress.subjectProgress[subject.id];
                  final accuracy = progress?.overallAccuracy ?? 0.0;
                  final answered = progress?.totalQuestionsAnswered ?? 0;
                  final color = AppColors.subjectColor(subject.id);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        IconBadge(
                          icon: AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded,
                          color: color,
                          size: 38,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      subject.shortName,
                                      style: text.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    answered == 0 ? '—' : '${(accuracy * 100).toStringAsFixed(0)}%',
                                    style: text.titleSmall?.copyWith(
                                      color: answered == 0 ? p.textTertiary : _getAccuracyColor(context, accuracy),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              AppProgressBar(value: accuracy, color: color, height: 5),
                              const SizedBox(height: 5),
                              Text('$answered answered', style: text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _getAccuracyColor(BuildContext context, double accuracy) {
    final p = context.palette;
    if (accuracy >= SubjectProgress.levelPassThreshold) return p.success;
    if (accuracy >= 0.5) return p.warning;
    return p.danger;
  }
}
