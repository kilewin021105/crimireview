import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/adaptive_learning_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/ml_service.dart';
import '../services/adaptive_ml_service.dart';
import '../services/connectivity_service.dart';
import '../models/subject.dart';
import '../utils/page_transitions.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/streak_widget.dart';
import 'subjects_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'leaderboard_screen.dart';
import 'daily_challenge_screen.dart';
import 'flashcard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  String _userName = 'Student';
  String? _profileImagePath;
  int _dailyStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    ConnectivityService.instance.startMonitoring();
  }
  
  @override
  void dispose() {
    ConnectivityService.instance.stopMonitoring();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final storage = StorageService();
    final name = await storage.getUserName();
    final streak = await storage.getDailyStreak();
    final imagePath = await storage.getProfileImage();
    if (mounted) {
      setState(() {
        _userName = name;
        _dailyStreak = streak;
        _profileImagePath = imagePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: [
          ListenableBuilder(
            listenable: ConnectivityService.instance,
            builder: (context, _) {
              if (ConnectivityService.instance.isOnline) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  bottom: 8,
                  left: 16,
                  right: 16,
                ),
                color: Colors.orange.shade700,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'You\'re offline. Quiz & flashcards still work!',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  ),
                  child: child,
                );
              },
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _buildHomeContent(context),
                  const SubjectsScreen(),
                  const ProgressScreen(),
                  SettingsScreen(key: ValueKey('settings_$_currentIndex')),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(isDark),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, 'Home', isDark),
              _buildNavItem(1, Icons.quiz_rounded, 'Quiz', isDark),
              _buildNavItem(2, Icons.bar_chart_rounded, 'Progress', isDark),
              _buildNavItem(3, Icons.settings_rounded, 'Settings', isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDark) {
    final isSelected = _currentIndex == index;
    final color = isSelected 
        ? AppColors.accent
        : (isDark ? Colors.white54 : Colors.grey.shade500);
    
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress;
    
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark, progress),
            const SizedBox(height: 24),
            _buildDailyChallenge(isDark),
            const SizedBox(height: 24),
            _buildQuickStats(isDark, progress),
            const SizedBox(height: 24),
            _buildStartQuizCard(isDark),
            const SizedBox(height: 24),
            _buildStudySubjects(isDark),
            const SizedBox(height: 24),
            _buildMLInsights(isDark, service),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, dynamic progress) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [

        GestureDetector(
          onTap: () async {
            await Navigator.push(context, SlidePageRoute(page: const ProfileScreen()));
            _loadUserData();
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              image: _profileImagePath != null && _profileImagePath!.isNotEmpty
                  ? DecorationImage(
                      image: FileImage(File(_profileImagePath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _profileImagePath == null || _profileImagePath!.isEmpty
                ? Center(
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'S',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _userName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [

            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  SlidePageRoute(page: const LeaderboardScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.leaderboard_rounded,
                  color: CrimiColors.gold,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade600,
                    Colors.deepOrange.shade500,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${progress.currentStreak}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _buildQuickStats(bool isDark, dynamic progress) {
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0) as int),
    );
    final totalCorrect = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalCorrectAnswers ?? 0) as int),
    );
    final accuracy = totalQuestions > 0 ? (totalCorrect / totalQuestions * 100) : 0.0;
    
    return Row(
      children: [
        Expanded(child: _buildStatCard('Answered', '$totalQuestions', Icons.quiz_rounded, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(0)}%', Icons.check_circle_rounded, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Quizzes', '${_getTotalQuizzes(progress)}', Icons.assignment_rounded, isDark)),
      ],
    );
  }

  int _getTotalQuizzes(dynamic progress) {
    int total = 0;
    for (var subject in CriminologySubjects.all) {
      total += (progress.subjectProgress[subject.id]?.totalQuizzesTaken ?? 0) as int;
    }
    return total;
  }

  Widget _buildMLInsights(bool isDark, AdaptiveLearningService service) {
    final mlService = AdaptiveMLService.instance;
    if (!mlService.isLoaded) return const SizedBox.shrink();


    final subjectPerformance = <String, SubjectPerformance>{};
    for (final subject in CriminologySubjects.all) {
      final progress = service.userProgress.subjectProgress[subject.id];
      if (progress != null) {
        final accuracy = progress.totalQuestionsAnswered > 0
            ? progress.totalCorrectAnswers / progress.totalQuestionsAnswered
            : 0.0;
        subjectPerformance[subject.id] = SubjectPerformance(
          subjectId: subject.id,
          accuracy: accuracy,
          questionsAnswered: progress.totalQuestionsAnswered,
          correctAnswers: progress.totalCorrectAnswers,
          avgTimePerQuestion: 20.0,
          lastStudied: progress.lastStudyDate,
        );
      }
    }

    if (subjectPerformance.isEmpty) {
      return const SizedBox.shrink();
    }


    final predictedScore = mlService.predictScore(
      subjectPerformance: subjectPerformance,
      streak: service.userProgress.currentStreak,
    );
    
    final recommendedDiff = mlService.recommendDifficulty(
      subjectPerformance: subjectPerformance,
    );
    
    final weakAreas = mlService.detectWeakAreas(
      subjectPerformance: subjectPerformance,
    );
    

    final weakSubjects = weakAreas.where((w) => w.isWeak).take(2).toList();
    final strongSubjects = weakAreas.where((w) => !w.isWeak && w.accuracy > 0.7).take(2).toList();
    

    final isReady = predictedScore >= 75;
    final needsWork = predictedScore < 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Row(
          children: [
            Icon(Icons.school_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            Text(
              'Board Exam Readiness',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isReady 
                  ? AppColors.success.withOpacity(0.3)
                  : needsWork 
                      ? AppColors.error.withOpacity(0.3)
                      : AppColors.warning.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Predicted Board Exam Score',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${predictedScore.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: isReady 
                      ? AppColors.success 
                      : needsWork 
                          ? AppColors.error 
                          : AppColors.warning,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isReady 
                      ? AppColors.success 
                      : needsWork 
                          ? AppColors.error 
                          : AppColors.warning).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isReady 
                      ? 'You\'re ready to pass!' 
                      : needsWork 
                          ? 'Needs more practice' 
                          : 'Almost there!',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isReady 
                        ? AppColors.success 
                        : needsWork 
                            ? AppColors.error 
                            : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Passing score: 75%',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(recommendedDiff).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.speed_rounded, 
                  color: _getDifficultyColor(recommendedDiff), 
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended Difficulty',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      'Practice ${mlService.getDifficultyName(recommendedDiff)} questions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        

        if (weakSubjects.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Focus on These Subjects',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...weakSubjects.map((weak) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${weak.subjectName} (${(weak.accuracy * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 4),
                Text(
                  weakSubjects.first.recommendation,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
        

        if (strongSubjects.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Your Strong Subjects',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...strongSubjects.map((strong) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${strong.subjectName} (${(strong.accuracy * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getDifficultyColor(int level) {
    switch (level) {
      case 0:
        return AppColors.success;
      case 1:
        return AppColors.warning;
      case 2:
        return AppColors.error;
      default:
        return AppColors.accent;
    }
  }

  Widget _buildDailyChallenge(bool isDark) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, SlidePageRoute(page: const DailyChallengeScreen()));
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CrimiColors.gold.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CrimiColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.emoji_events_rounded,
                color: CrimiColors.gold,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Challenge',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '10 questions • 1.5x bonus points!',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CrimiColors.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: CrimiColors.gold,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartQuizCard(bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = 1),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ready to Study?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a quiz and prepare for your board exam',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Start Now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.menu_book_rounded, size: 40, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudySubjects(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            Text(
              'Study with Flashcards',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemCount: CriminologySubjects.all.length,
          itemBuilder: (context, index) {
            final subject = CriminologySubjects.all[index];
            return _buildStudySubjectCard(subject, isDark);
          },
        ),
      ],
    );
  }

  Widget _buildStudySubjectCard(Subject subject, bool isDark) {
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final colors = [
      const Color(0xFF6C5CE7),
      const Color(0xFF00B894),
      const Color(0xFFE17055),
      const Color(0xFF0984E3),
      const Color(0xFFFDAA4B),
      const Color(0xFFE84393),
    ];
    final color = colors[CriminologySubjects.all.indexOf(subject) % colors.length];
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SlidePageRoute(page: FlashcardScreen(subject: subject)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              subject.shortName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
