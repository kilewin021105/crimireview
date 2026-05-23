import 'package:flutter/material.dart';

class Achievement {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final int requirement;
  final AchievementType type;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.requirement,
    required this.type,
  });
}

enum AchievementType {
  quizzes,
  streak,
  accuracy,
  questions,
  perfect,
}

class Achievements {
  static const List<Achievement> all = [
    // Quiz count achievements
    Achievement(id: 'first_quiz', name: 'First Steps', description: 'Complete your first quiz', icon: Icons.play_arrow_rounded, requirement: 1, type: AchievementType.quizzes),
    Achievement(id: 'quiz_10', name: 'Getting Started', description: 'Complete 10 quizzes', icon: Icons.trending_up_rounded, requirement: 10, type: AchievementType.quizzes),
    Achievement(id: 'quiz_50', name: 'Dedicated Learner', description: 'Complete 50 quizzes', icon: Icons.school_rounded, requirement: 50, type: AchievementType.quizzes),
    Achievement(id: 'quiz_100', name: 'Quiz Master', description: 'Complete 100 quizzes', icon: Icons.emoji_events_rounded, requirement: 100, type: AchievementType.quizzes),
    
    // Streak achievements
    Achievement(id: 'streak_3', name: 'On Fire', description: 'Reach a 3-day streak', icon: Icons.local_fire_department_rounded, requirement: 3, type: AchievementType.streak),
    Achievement(id: 'streak_7', name: 'Week Warrior', description: 'Reach a 7-day streak', icon: Icons.whatshot_rounded, requirement: 7, type: AchievementType.streak),
    Achievement(id: 'streak_30', name: 'Monthly Champion', description: 'Reach a 30-day streak', icon: Icons.military_tech_rounded, requirement: 30, type: AchievementType.streak),
    
    // Questions answered
    Achievement(id: 'questions_50', name: 'Curious Mind', description: 'Answer 50 questions', icon: Icons.help_outline_rounded, requirement: 50, type: AchievementType.questions),
    Achievement(id: 'questions_200', name: 'Knowledge Seeker', description: 'Answer 200 questions', icon: Icons.lightbulb_rounded, requirement: 200, type: AchievementType.questions),
    Achievement(id: 'questions_500', name: 'Scholar', description: 'Answer 500 questions', icon: Icons.auto_stories_rounded, requirement: 500, type: AchievementType.questions),
    
    // Perfect scores
    Achievement(id: 'perfect_1', name: 'Perfectionist', description: 'Get a perfect score', icon: Icons.star_rounded, requirement: 1, type: AchievementType.perfect),
    Achievement(id: 'perfect_5', name: 'Flawless', description: 'Get 5 perfect scores', icon: Icons.stars_rounded, requirement: 5, type: AchievementType.perfect),
    Achievement(id: 'perfect_10', name: 'Legendary', description: 'Get 10 perfect scores', icon: Icons.workspace_premium_rounded, requirement: 10, type: AchievementType.perfect),
  ];
}
