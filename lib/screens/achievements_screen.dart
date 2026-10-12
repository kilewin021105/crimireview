import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/adaptive_learning_service.dart';
import '../models/achievement.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<AdaptiveLearningService>(context);
    final unlocked = service.getUnlockedAchievements();
    final unlockedIds = unlocked.map((a) => a.id).toSet();
    final earned = Achievements.all.where((a) => unlockedIds.contains(a.id)).toList();
    final locked = Achievements.all.where((a) => !unlockedIds.contains(a.id)).toList()
      ..sort((a, b) => _fraction(b, service).compareTo(_fraction(a, service)));
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Achievements',
        subtitle: '${unlocked.length} of ${Achievements.all.length} unlocked',
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(padding, 4, padding, 28),
        children: [
          ContentWidth(child: _buildSummary(context, unlocked.length, locked, service)),
          if (earned.isNotEmpty) ...[
            const SizedBox(height: AppSpace.section),
            const ContentWidth(child: SectionHeader(title: 'Earned')),
            const SizedBox(height: 12),
            for (var i = 0; i < earned.length; i++)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Appear(index: i, child: _buildAchievementTile(context, earned[i], true, service)),
                ),
              ),
          ],
          if (locked.isNotEmpty) ...[
            const SizedBox(height: AppSpace.section - 10),
            const ContentWidth(child: SectionHeader(title: 'In progress')),
            const SizedBox(height: 12),
            for (var i = 0; i < locked.length; i++)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Appear(
                    index: earned.length + i,
                    child: _buildAchievementTile(context, locked[i], false, service),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  double _fraction(Achievement a, AdaptiveLearningService service) =>
      (_getAchievementProgress(a, service) / a.requirement).clamp(0.0, 1.0);

  Widget _buildSummary(
    BuildContext context,
    int unlockedCount,
    List<Achievement> locked,
    AdaptiveLearningService service,
  ) {
    final p = context.palette;
    final text = context.textStyles;
    final total = Achievements.all.length;
    final next = locked.isEmpty ? null : locked.first;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          RingProgress(
            value: total == 0 ? 0 : unlockedCount / total,
            size: 84,
            stroke: 9,
            color: p.gold,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_rounded, color: p.gold, size: 22),
                Text('$unlockedCount/$total', style: text.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null ? 'All badges earned!' : 'Next up: ${next.name}',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  next == null
                      ? 'You have unlocked every achievement. Impressive.'
                      : next.description,
                  style: text.bodySmall,
                ),
                if (next != null) ...[
                  const SizedBox(height: 10),
                  AppProgressBar(value: _fraction(next, service), color: p.gold, height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementTile(
    BuildContext context,
    Achievement achievement,
    bool isUnlocked,
    AdaptiveLearningService service,
  ) {
    final p = context.palette;
    final text = context.textStyles;
    final progress = _getAchievementProgress(achievement, service);
    final progressValue = (progress / achievement.requirement).clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.all(14),
      borderColor: isUnlocked ? p.gold.withValues(alpha: 0.35) : null,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isUnlocked ? p.goldSoft : p.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              achievement.icon,
              color: isUnlocked ? p.gold : p.textTertiary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.name,
                        style: text.titleSmall?.copyWith(
                          color: isUnlocked ? p.textPrimary : p.textSecondary,
                        ),
                      ),
                    ),
                    if (isUnlocked)
                      Pill(label: 'Earned', icon: Icons.check_rounded, color: p.success, fontSize: 10.5),
                  ],
                ),
                const SizedBox(height: 2),
                Text(achievement.description, style: text.bodySmall),
                if (!isUnlocked) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: AppProgressBar(value: progressValue, height: 6)),
                      const SizedBox(width: 10),
                      Text(
                        '${progress.clamp(0, achievement.requirement)}/${achievement.requirement}',
                        style: text.labelMedium,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _getAchievementProgress(Achievement achievement, AdaptiveLearningService service) {
    final progress = service.userProgress;

    switch (achievement.type) {
      case AchievementType.quizzes:
        int total = 0;
        for (var sp in progress.subjectProgress.values) {
          total += sp.totalQuizzesTaken;
        }
        return total;
      case AchievementType.streak:
        return progress.currentStreak;
      case AchievementType.questions:
        int total = 0;
        for (var sp in progress.subjectProgress.values) {
          total += sp.totalQuestionsAnswered;
        }
        return total;
      case AchievementType.perfect:
        return progress.perfectScores;
      case AchievementType.accuracy:
        return 0;
    }
  }
}
