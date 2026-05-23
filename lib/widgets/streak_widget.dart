import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/adaptive_learning_service.dart';

class DailyStreakWidget extends StatelessWidget {
  const DailyStreakWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AdaptiveLearningService>(
      builder: (context, service, _) {
        final streak = service.userProgress.currentStreak;
        final longestStreak = service.userProgress.longestStreak;
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.orange.withOpacity(0.3),
                Colors.deepOrange.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.orange.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Fire icon with animation
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.orange,
                          Colors.deepOrange,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .shimmer(
                        duration: const Duration(seconds: 2),
                        color: Colors.white.withOpacity(0.3),
                      ),
                  
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$streak Day${streak != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Current Streak',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            color: CrimiColors.gold,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$longestStreak',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: CrimiColors.gold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Best Streak',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Week progress
              _buildWeekProgress(),
              
              const SizedBox(height: 16),
              
              // Motivational message
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: CrimiColors.gold,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getMotivationalMessage(streak),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeekProgress() {
    final now = DateTime.now();
    final weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final currentWeekday = now.weekday; // 1-7 (Monday to Sunday)
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (index) {
        final dayNumber = index + 1;
        final isCompleted = dayNumber < currentWeekday; // Days before today are "completed"
        final isToday = dayNumber == currentWeekday;
        final isFuture = dayNumber > currentWeekday;
        
        return Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? Colors.green.withOpacity(0.8)
                    : isToday
                        ? Colors.orange
                        : Colors.white.withOpacity(0.1),
                border: isToday
                    ? Border.all(color: Colors.orange, width: 3)
                    : null,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                    : isToday
                        ? const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 18)
                        : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              weekdays[index],
              style: TextStyle(
                color: isToday ? Colors.orange : Colors.white.withOpacity(0.6),
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        );
      }),
    );
  }

  String _getMotivationalMessage(int streak) {
    if (streak == 0) {
      return "Start your streak today! Every journey begins with a single step.";
    } else if (streak < 3) {
      return "Great start! Keep going and build your momentum!";
    } else if (streak < 7) {
      return "You're on fire! A week of consistency is within reach!";
    } else if (streak < 14) {
      return "Amazing dedication! You're building strong study habits!";
    } else if (streak < 30) {
      return "Incredible! You're a true criminology scholar in the making!";
    } else {
      return "Legendary! Your commitment to excellence is truly inspiring!";
    }
  }
}

class CompactStreakWidget extends StatelessWidget {
  const CompactStreakWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AdaptiveLearningService>(
      builder: (context, service, _) {
        final streak = service.userProgress.currentStreak;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.orange.withOpacity(0.3),
                Colors.deepOrange.withOpacity(0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.orange.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.orange,
                size: 20,
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: const Duration(seconds: 2)),
              const SizedBox(width: 8),
              Text(
                '$streak',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'day${streak != 1 ? 's' : ''}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StreakMilestoneCard extends StatelessWidget {
  final int targetDays;
  final String reward;
  final int currentStreak;

  const StreakMilestoneCard({
    super.key,
    required this.targetDays,
    required this.reward,
    required this.currentStreak,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentStreak / targetDays).clamp(0.0, 1.0);
    final isCompleted = currentStreak >= targetDays;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCompleted
            ? Colors.green.withOpacity(0.2)
            : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? Colors.green
                  : Colors.white.withOpacity(0.1),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : Text(
                      '$targetDays',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$targetDays Day Streak',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reward,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                if (!isCompleted) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation(Colors.orange),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCompleted)
            Icon(
              Icons.emoji_events_rounded,
              color: CrimiColors.gold,
              size: 28,
            ),
        ],
      ),
    );
  }
}
