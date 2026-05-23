import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/adaptive_learning_service.dart';
import '../services/theme_service.dart';
import '../models/achievement.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = Provider.of<AdaptiveLearningService>(context);
    final unlocked = service.getUnlockedAchievements();
    final unlockedIds = unlocked.map((a) => a.id).toSet();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Achievements',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${unlocked.length}/${Achievements.all.length} unlocked',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: unlocked.length / Achievements.all.length,
                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),


            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                itemCount: Achievements.all.length,
                itemBuilder: (context, index) {
                  final achievement = Achievements.all[index];
                  final isUnlocked = unlockedIds.contains(achievement.id);
                  return _buildAchievementTile(achievement, isUnlocked, isDark, service);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementTile(Achievement achievement, bool isUnlocked, bool isDark, AdaptiveLearningService service) {
    final progress = _getAchievementProgress(achievement, service);
    final progressValue = (progress / achievement.requirement).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: isUnlocked
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: Row(
        children: [

          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              achievement.icon,
              color: isUnlocked
                  ? AppColors.accent
                  : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isUnlocked
                              ? (isDark ? Colors.white : const Color(0xFF1A1A2E))
                              : (isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                        ),
                      ),
                    ),
                    if (isUnlocked)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                          size: 16,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
                if (!isUnlocked) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(AppColors.accent.withValues(alpha: 0.6)),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$progress/${achievement.requirement}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        ),
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
