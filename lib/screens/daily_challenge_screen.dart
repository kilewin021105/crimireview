import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/question.dart';
import '../data/questions_database.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';

class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> with TickerProviderStateMixin {
  final _storage = StorageService();
  late List<Question> _questions;
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _showExplanation = false;
  int _correctCount = 0;
  int _streak = 0;
  bool _isLoading = true;
  bool _alreadyCompleted = false;
  
  // Shuffled options for each question
  late List<List<String>> _shuffledOptions;
  late List<int> _shuffledCorrectIndices;
  late List<int?> _userAnswers; // Track user's selected answer for each question
  
  late AnimationController _timerController;
  late Animation<double> _timerAnimation;
  late ConfettiController _confettiController;
  
  static const int _questionTime = 20; // seconds per question
  static const int _totalQuestions = 10;
  static const double _bonusMultiplier = 1.5;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _timerController = AnimationController(
      duration: const Duration(seconds: _questionTime),
      vsync: this,
    );
    _timerAnimation = Tween<double>(begin: 1, end: 0).animate(_timerController);
    
    _checkAndLoadChallenge();
  }

  Future<void> _checkAndLoadChallenge() async {

    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastCompleted = await _storage.getLastDailyChallengeDate();
    
    if (lastCompleted == today) {
      setState(() {
        _alreadyCompleted = true;
        _isLoading = false;
      });
      return;
    }
    
    _loadDailyQuestions();
    setState(() => _isLoading = false);
    _startTimer();
  }

  void _loadDailyQuestions() {
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    final random = Random(seed);
    
    final allQuestions = List<Question>.from(QuestionsDatabase.allQuestions);
    allQuestions.shuffle(random);
    
    _questions = allQuestions.take(_totalQuestions).toList();
    
    // Shuffle options for each question
    _shuffledOptions = [];
    _shuffledCorrectIndices = [];
    _userAnswers = List.filled(_totalQuestions, null);
    
    for (final question in _questions) {
      final indices = List.generate(question.options.length, (i) => i);
      indices.shuffle(random);
      final shuffled = indices.map((i) => question.options[i]).toList();
      _shuffledOptions.add(shuffled);
      _shuffledCorrectIndices.add(indices.indexOf(question.correctAnswerIndex));
    }
  }

  void _startTimer() {
    _timerController.reset();
    _timerController.forward();
    
    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {

        _handleTimeUp();
      }
    });
  }

  void _handleTimeUp() {
    if (_selectedAnswer == null) {
      _userAnswers[_currentIndex] = null; // Time ran out, no answer
      setState(() {
        _selectedAnswer = -1; // Mark as unanswered
        _showExplanation = true;
        _streak = 0;
      });
      
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _nextQuestion();
      });
    }
  }

  void _selectAnswer(int index) {
    if (_selectedAnswer != null) return;
    
    _timerController.stop();
    
    // Use shuffled correct index
    final isCorrect = index == _shuffledCorrectIndices[_currentIndex];
    _userAnswers[_currentIndex] = index;
    
    setState(() {
      _selectedAnswer = index;
      _showExplanation = true;
      
      if (isCorrect) {
        _correctCount++;
        _streak++;
      } else {
        _streak = 0;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _showExplanation = false;
      });
      _startTimer();
    } else {
      _showResults();
    }
  }

  Future<void> _showResults() async {
    _timerController.stop();
    
    final baseScore = _correctCount * 10;
    final bonusPoints = (baseScore * _bonusMultiplier).round() - baseScore;
    final totalScore = baseScore + bonusPoints;
    final percentage = (_correctCount / _totalQuestions * 100).round();
    
    // Save to local storage
    final today = DateTime.now().toIso8601String().split('T')[0];
    await _storage.setLastDailyChallengeDate(today);
    await _storage.addDailyChallengeScore(totalScore);
    
    // Sync to cloud (with offline support)
    await _syncToCloud(totalScore, _correctCount);
    
    if (percentage >= 70) {
      _confettiController.play();
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => _ChallengeResultsScreen(
            correctCount: _correctCount,
            totalQuestions: _totalQuestions,
            percentage: percentage,
            baseScore: baseScore,
            bonusPoints: bonusPoints,
            totalScore: totalScore,
            confettiController: _confettiController,
            questions: _questions,
            userAnswers: _userAnswers,
            shuffledOptions: _shuffledOptions,
            shuffledCorrectIndices: _shuffledCorrectIndices,
          ),
        ),
      );
    }
  }

  Future<void> _syncToCloud(int score, int correctAnswers) async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) return;
    
    final isOnline = ConnectivityService.instance.isOnline;
    
    if (isOnline) {
      // Online: save directly to Supabase
      await SupabaseService.instance.saveDailyChallengeScore(
        score: score,
        correctAnswers: correctAnswers,
        totalQuestions: _totalQuestions,
      );
    } else {
      // Offline: queue for later sync
      await OfflineSyncService.instance.queueDailyChallengeScore(
        score: score,
        correctAnswers: correctAnswers,
        totalQuestions: _totalQuestions,
      );
    }
  }

  @override
  void dispose() {
    _timerController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_alreadyCompleted) {
      return _buildAlreadyCompletedScreen(isDark);
    }

    final question = _questions[_currentIndex];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            _buildTimer(isDark),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQuestionCard(question, isDark),
                    const SizedBox(height: 20),
                    ...List.generate(
                      _shuffledOptions[_currentIndex].length,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildOptionCard(index, isDark),
                      ),
                    ),
                    if (_showExplanation && question.explanation != null)
                      _buildExplanationCard(question, isDark),
                  ],
                ),
              ),
            ),
            if (_selectedAnswer != null)
              _buildNextButton(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadyCompletedScreen(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
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
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Daily Challenge',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    

                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withValues(alpha: 0.2),
                            AppColors.accent.withValues(alpha: 0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    

                    Text(
                      'Challenge Complete!',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Great job! You\'ve already conquered today\'s challenge. Rest up and come back tomorrow for a new one!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          height: 1.6,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    

                    _buildCountdownCard(isDark),
                    
                    const SizedBox(height: 24),
                    

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: AppColors.warning,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'While You Wait...',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTipItem(Icons.menu_book_rounded, 'Study modules to strengthen memory', isDark),
                          const SizedBox(height: 12),
                          _buildTipItem(Icons.quiz_rounded, 'Take a practice quiz on weak subjects', isDark),
                          const SizedBox(height: 12),
                          _buildTipItem(Icons.replay_rounded, 'Review your wrong answers', isDark),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Back to Home',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTipItem(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownCard(bool isDark) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        final difference = tomorrow.difference(now);
        
        final hours = difference.inHours;
        final minutes = difference.inMinutes % 60;
        final seconds = difference.inSeconds % 60;
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accent.withValues(alpha: 0.15),
                AppColors.accent.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Next Challenge In',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimeBox(hours.toString().padLeft(2, '0'), 'HRS', isDark),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  _buildTimeBox(minutes.toString().padLeft(2, '0'), 'MIN', isDark),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  _buildTimeBox(seconds.toString().padLeft(2, '0'), 'SEC', isDark),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeBox(String value, String label, bool isDark) {
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      'Daily Challenge',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${_bonusMultiplier}x bonus points!',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (_streak > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.whatshot_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$_streak',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_currentIndex + 1}/$_totalQuestions',
              style: GoogleFonts.poppins(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _timerAnimation,
        builder: (context, child) {
          final value = _timerAnimation.value;
          final color = value > 0.5 
              ? AppColors.success 
              : (value > 0.25 ? AppColors.warning : AppColors.error);
          
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(value * _questionTime).ceil()}s',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuestionCard(Question question, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.12),
            AppColors.accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  question.topic,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(question.difficulty).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  question.difficulty.name.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _getDifficultyColor(question.difficulty),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            question.questionText,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDifficultyColor(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:
        return AppColors.success;
      case Difficulty.medium:
        return AppColors.warning;
      case Difficulty.hard:
        return AppColors.error;
    }
  }

  Widget _buildOptionCard(int index, bool isDark) {
    final isSelected = _selectedAnswer == index;
    final isCorrect = index == _shuffledCorrectIndices[_currentIndex];
    final showResult = _selectedAnswer != null;
    
    Color? borderColor;
    Color? bgColor;
    
    if (showResult) {
      if (isCorrect) {
        borderColor = AppColors.success;
        bgColor = AppColors.success.withValues(alpha: 0.1);
      } else if (isSelected && !isCorrect) {
        borderColor = AppColors.error;
        bgColor = AppColors.error.withValues(alpha: 0.1);
      }
    } else if (isSelected) {
      borderColor = AppColors.accent;
      bgColor = AppColors.accent.withValues(alpha: 0.1);
    }

    return GestureDetector(
      onTap: () => _selectAnswer(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor ?? (isDark ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor ?? (isDark ? Colors.white10 : Colors.grey.shade200),
            width: showResult && (isCorrect || isSelected) ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: showResult && isCorrect
                    ? AppColors.success
                    : (showResult && isSelected && !isCorrect
                        ? AppColors.error
                        : (isDark ? Colors.white10 : Colors.grey.shade200)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: showResult && (isCorrect || (isSelected && !isCorrect))
                    ? Icon(
                        isCorrect ? Icons.check_rounded : Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : Text(
                        String.fromCharCode(65 + index),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _shuffledOptions[_currentIndex][index],
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: isSelected || (showResult && isCorrect) 
                      ? FontWeight.w600 
                      : FontWeight.w400,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationCard(Question question, bool isDark) {
    final isCorrect = _selectedAnswer == _shuffledCorrectIndices[_currentIndex];
    final correctLetter = String.fromCharCode(65 + _shuffledCorrectIndices[_currentIndex]);
    final correctOption = _shuffledOptions[_currentIndex][_shuffledCorrectIndices[_currentIndex]];
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect 
          ? AppColors.success.withValues(alpha: 0.08)
          : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCorrect 
            ? AppColors.success.withValues(alpha: 0.3)
            : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: isCorrect ? AppColors.success : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect ? 'Correct!' : 'Wrong Answer',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCorrect ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
          if (!isCorrect) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Text(
                'Correct Answer: $correctLetter - $correctOption',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            question.explanation!,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton(bool isDark) {
    final isLastQuestion = _currentIndex == _questions.length - 1;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _nextQuestion,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              isLastQuestion ? 'See Results' : 'Next Question',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _ChallengeResultsScreen extends StatefulWidget {
  final int correctCount;
  final int totalQuestions;
  final int percentage;
  final int baseScore;
  final int bonusPoints;
  final int totalScore;
  final ConfettiController confettiController;
  final List<Question> questions;
  final List<int?> userAnswers;
  final List<List<String>> shuffledOptions;
  final List<int> shuffledCorrectIndices;
  
  const _ChallengeResultsScreen({
    required this.correctCount,
    required this.totalQuestions,
    required this.percentage,
    required this.baseScore,
    required this.bonusPoints,
    required this.totalScore,
    required this.confettiController,
    required this.questions,
    required this.userAnswers,
    required this.shuffledOptions,
    required this.shuffledCorrectIndices,
  });
  
  @override
  State<_ChallengeResultsScreen> createState() => _ChallengeResultsScreenState();
}

class _ChallengeResultsScreenState extends State<_ChallengeResultsScreen> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    
    _animController.forward();
    

    if (widget.percentage >= 70) {
      Future.delayed(const Duration(milliseconds: 300), () {
        widget.confettiController.play();
      });
    }
  }
  
  @override
  void dispose() {
    _animController.dispose();
    widget.confettiController.dispose();
    super.dispose();
  }
  
  String _getResultMessage() {
    if (widget.percentage >= 90) return 'Outstanding!';
    if (widget.percentage >= 80) return 'Excellent!';
    if (widget.percentage >= 70) return 'Great Job!';
    if (widget.percentage >= 60) return 'Good Effort!';
    if (widget.percentage >= 50) return 'Keep Practicing!';
    return 'Don\'t Give Up!';
  }
  
  String _getResultSubtitle() {
    if (widget.percentage >= 90) return 'You\'re a criminology master!';
    if (widget.percentage >= 80) return 'You\'re doing amazing!';
    if (widget.percentage >= 70) return 'You passed the challenge!';
    if (widget.percentage >= 60) return 'Almost there, keep going!';
    if (widget.percentage >= 50) return 'Practice makes perfect!';
    return 'Review and try again tomorrow!';
  }
  
  IconData _getResultIcon() {
    if (widget.percentage >= 80) return Icons.emoji_events_rounded;
    if (widget.percentage >= 60) return Icons.star_rounded;
    return Icons.trending_up_rounded;
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [

                const SizedBox(height: 20),
                

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _fadeAnimation.value,
                          child: Transform.scale(
                            scale: _scaleAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          const SizedBox(height: 30),
                          

                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.percentage >= 70 
                                    ? [const Color(0xFFFFD700), const Color(0xFFFFA500)]
                                    : [AppColors.accent, AppColors.accentDark],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (widget.percentage >= 70 
                                      ? const Color(0xFFFFD700) 
                                      : AppColors.accent).withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              _getResultIcon(),
                              color: Colors.white,
                              size: 70,
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          

                          Text(
                            _getResultMessage(),
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          Text(
                            _getResultSubtitle(),
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                          
                          const SizedBox(height: 40),
                          

                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.accent.withValues(alpha: 0.15),
                                  AppColors.accent.withValues(alpha: 0.05),
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                width: 3,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${widget.percentage}%',
                                  style: GoogleFonts.poppins(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                                Text(
                                  'Score',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          

                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildStatItem(
                                    'Correct',
                                    '${widget.correctCount}/${widget.totalQuestions}',
                                    AppColors.success,
                                    Icons.check_circle_rounded,
                                    isDark,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 50,
                                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                                ),
                                Expanded(
                                  child: _buildStatItem(
                                    'Bonus',
                                    '+${widget.bonusPoints}',
                                    const Color(0xFFFFD700),
                                    Icons.auto_awesome_rounded,
                                    isDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.stars_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Points Earned',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      '${widget.totalScore} pts',
                                      style: GoogleFonts.poppins(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          

                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.05) 
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Come back tomorrow for a new challenge!',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          

                          // Review Answers Section
                          _buildReviewAnswersSection(isDark),
                          
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
                

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Done',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          

          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: widget.confettiController,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 25,
              gravity: 0.1,
              colors: const [
                Color(0xFF8B5CF6),
                Color(0xFFFFD700),
                Color(0xFF00C853),
                Color(0xFFFF6B6B),
                Color(0xFF4ECDC4),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildReviewAnswersSection(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_rounded,
                color: AppColors.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Review Answers',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(widget.questions.length, (index) {
            final question = widget.questions[index];
            final userAnswer = widget.userAnswers[index];
            final correctIndex = widget.shuffledCorrectIndices[index];
            final isCorrect = userAnswer == correctIndex;
            final isUnanswered = userAnswer == null;
            final letter = String.fromCharCode(65 + correctIndex);
            final correctOption = widget.shuffledOptions[index][correctIndex];
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUnanswered
                    ? (isDark ? Colors.orange.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.05))
                    : isCorrect
                      ? AppColors.success.withValues(alpha: 0.08)
                      : AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isUnanswered
                      ? Colors.orange.withValues(alpha: 0.3)
                      : isCorrect
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.error.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isUnanswered
                          ? Colors.orange.withValues(alpha: 0.15)
                          : isCorrect
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.error.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isUnanswered
                              ? Colors.orange
                              : isCorrect
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUnanswered
                              ? 'Time ran out'
                              : isCorrect
                                ? 'Correct'
                                : 'Wrong',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isUnanswered
                                ? Colors.orange
                                : isCorrect
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Answer: $letter - $correctOption',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isUnanswered
                        ? Icons.timer_off_rounded
                        : isCorrect
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: isUnanswered
                        ? Colors.orange
                        : isCorrect
                          ? AppColors.success
                          : AppColors.error,
                      size: 22,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, Color color, IconData icon, bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
