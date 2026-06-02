import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../services/theme_service.dart';
import '../models/subject.dart';
import '../models/achievement.dart';
import '../utils/page_transitions.dart';
import 'achievements_screen.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track your learning journey',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              _buildOverallStats(isDark, progress),
              const SizedBox(height: 24),
              _buildStreakCard(isDark, progress),
              const SizedBox(height: 24),
              _buildAchievements(context, isDark, service),
              const SizedBox(height: 24),
              _buildSubjectBreakdown(isDark, service),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverallStats(bool isDark, dynamic progress) {
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0) as int),
    );
    final totalCorrect = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalCorrectAnswers ?? 0) as int),
    );
    final accuracy = totalQuestions > 0 ? totalCorrect / totalQuestions : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            '${(accuracy * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Overall Accuracy',
            style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildMiniStat('Questions', '$totalQuestions')),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(child: _buildMiniStat('Correct', '$totalCorrect')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildStreakCard(bool isDark, dynamic progress) {
    const accentColor = AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(20),
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
            child: Icon(Icons.local_fire_department_rounded, color: accentColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${progress.currentStreak} Day Streak',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Best: ${progress.longestStreak} days',
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements(BuildContext context, bool isDark, AdaptiveLearningService service) {
    final unlocked = service.getUnlockedAchievements();
    final unlockedIds = unlocked.map((a) => a.id).toSet();
    

    final displayAchievements = Achievements.all.take(8).toList();
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SlidePageRoute(page: const AchievementsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achievements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${unlocked.length}/${Achievements.all.length} unlocked',
                      style: TextStyle(
                        fontSize: 13, 
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: displayAchievements.take(4).map((a) {
                final isUnlocked = unlockedIds.contains(a.id);
                return _buildAchievementIcon(a, isUnlocked, isDark);
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: displayAchievements.skip(4).take(4).map((a) {
                final isUnlocked = unlockedIds.contains(a.id);
                return _buildAchievementIcon(a, isUnlocked, isDark);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAchievementIcon(Achievement achievement, bool unlocked, bool isDark) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: unlocked 
            ? AppColors.accent.withValues(alpha: 0.15)
            : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        achievement.icon,
        color: unlocked 
            ? AppColors.accent 
            : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
        size: 26,
      ),
    );
  }

  Widget _buildSubjectBreakdown(bool isDark, AdaptiveLearningService service) {
    const accentColor = AppColors.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'By Subject',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        ...CriminologySubjects.all.map((subject) {
          final progress = service.userProgress.subjectProgress[subject.id];
          final accuracy = progress?.overallAccuracy ?? 0.0;
          final answered = progress?.totalQuestionsAnswered ?? 0;
          final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.shortName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$answered answered',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(accuracy * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getAccuracyColor(accuracy),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= SubjectProgress.levelPassThreshold) return AppColors.success;
    if (accuracy >= 0.5) return AppColors.primary;
    return AppColors.error;
  }
}
