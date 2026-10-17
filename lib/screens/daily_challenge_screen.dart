import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../models/question.dart';
import '../services/question_repository.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/offline_sync_service.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

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

  /// Set once the results are being saved, so a second tap (or the
  /// time-up auto-advance) can't save the challenge twice.
  bool _finishing = false;

  // Shuffled options for each question
  late List<List<String>> _shuffledOptions;
  late List<int> _shuffledCorrectIndices;
  late List<int?> _userAnswers; // Track user's selected answer for each question

  late AnimationController _timerController;
  late Animation<double> _timerAnimation;

  static const int _questionTime = 20; // seconds per question
  static const int _totalQuestions = 10;
  static const double _bonusMultiplier = 1.5;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      duration: const Duration(seconds: _questionTime),
      vsync: this,
    );
    _timerAnimation = Tween<double>(begin: 1, end: 0).animate(_timerController);
    // Added once here (it used to be re-added on every question, so the
    // listeners piled up).
    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _handleTimeUp();
      }
    });

    _checkAndLoadChallenge();
  }

  Future<void> _checkAndLoadChallenge() async {

    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastCompleted = await _storage.getLastDailyChallengeDate();

    // The phone's own record only knows about this phone. The server is
    // checked too, so reinstalling the app or switching to another phone
    // can't be used to play today's challenge a second time.
    final completed = lastCompleted == today || await _completedOnServer(today);
    if (!mounted) return;

    if (completed) {
      setState(() {
        _alreadyCompleted = true;
        _isLoading = false;
      });
      return;
    }

    await _loadDailyQuestions();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (_questions.isNotEmpty) _startTimer();
  }

  /// Panel note 7: questions come from `QuestionRepository` (Supabase-backed,
  /// admin-authored or auto-generated), never from a compiled-in file. The
  /// pool is still shuffled with a date-seeded [Random], so every student
  /// gets the SAME ten questions on a given day -- that "everyone gets the
  /// same daily puzzle" property only depends on the seed, not the source.
  Future<void> _loadDailyQuestions() async {
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    final random = Random(seed);

    final allQuestions = await QuestionRepository.instance.all();
    if (!mounted) return;

    final pool = List<Question>.from(allQuestions)..shuffle(random);
    _questions = pool.take(_totalQuestions).toList();

    // Shuffle options for each question
    _shuffledOptions = [];
    _shuffledCorrectIndices = [];
    _userAnswers = List.filled(_questions.length, null);

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
  }

  void _handleTimeUp() {
    if (_selectedAnswer == null) {
      final timedOutIndex = _currentIndex;
      _userAnswers[_currentIndex] = null; // Time ran out, no answer
      setState(() {
        _selectedAnswer = -1; // Mark as unanswered
        _showExplanation = true;
        _streak = 0;
      });

      // Moves on by itself after 2 s -- unless the student already tapped
      // "Next" in the meantime; advancing again would skip a question.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _currentIndex == timedOutIndex) _nextQuestion();
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
    // Only from an answered (or timed-out) question, and never while the
    // results are being saved.
    if (_selectedAnswer == null || _finishing) return;
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
    if (_finishing) return;
    setState(() => _finishing = true);
    _timerController.stop();

    final baseScore = _correctCount * 10;
    final bonusPoints = (baseScore * _bonusMultiplier).round() - baseScore;
    final totalScore = baseScore + bonusPoints;
    final percentage = (_correctCount / _totalQuestions * 100).round();

    // Save to local storage
    final today = DateTime.now().toIso8601String().split('T')[0];
    await _storage.setLastDailyChallengeDate(today);
    await _storage.addDailyChallengeScore(totalScore);
    await _storage.addDailyActivity(_questions.length);

    // Sync to cloud (with offline support) in the background: the results
    // must not wait for a slow connection. It queues itself on failure.
    unawaited(_syncToCloud(totalScore, _correctCount));

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
            questions: _questions,
            userAnswers: _userAnswers,
            shuffledOptions: _shuffledOptions,
            shuffledCorrectIndices: _shuffledCorrectIndices,
          ),
        ),
      );
    }
  }

  /// True when the server already has today's score for this account.
  /// Offline, logged out, or any error counts as "not completed" so the
  /// challenge still works without internet; a duplicate made that way is
  /// rejected when it syncs (see `SupabaseService.saveDailyChallengeScore`).
  Future<bool> _completedOnServer(String today) async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) return false;
    try {
      final done = await SupabaseService.instance
          .hasCompletedDailyChallenge()
          .timeout(const Duration(seconds: 5));
      if (done) await _storage.setLastDailyChallengeDate(today);
      return done;
    } catch (e) {
      debugPrint('Daily challenge server check skipped: $e');
      return false;
    }
  }

  Future<void> _syncToCloud(int score, int correctAnswers) async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) return;

    await OfflineSyncService.instance.saveDailyChallengeScoreOrQueue(
      score: score,
      correctAnswers: correctAnswers,
      totalQuestions: _totalQuestions,
    );
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: AppTopBar(title: 'Daily Challenge'),
        body: LoadingView(label: "Getting today's questions..."),
      );
    }

    if (_alreadyCompleted) {
      return _buildAlreadyCompletedScreen();
    }

    if (_questions.isEmpty) {
      return _buildEmptyState();
    }

    final p = context.palette;
    final question = _questions[_currentIndex];

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _buildProgressStrip(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuestionCard(question),
                      const SizedBox(height: 16),
                      ...List.generate(
                        _shuffledOptions[_currentIndex].length,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildOptionCard(index),
                        ),
                      ),
                      if (_selectedAnswer == -1)
                        const InlineBanner(
                          tone: BannerTone.warning,
                          icon: Icons.timer_off_rounded,
                          message: "Time's up! The right answer is highlighted.",
                        ),
                      if (_showExplanation && question.explanation.isNotEmpty)
                        _buildExplanationCard(question),
                    ],
                  ),
                ),
              ),
              if (_selectedAnswer != null)
                Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: PrimaryButton(
                    label: _currentIndex == _questions.length - 1 ? 'See results' : 'Next question',
                    icon: Icons.arrow_forward_rounded,
                    trailingIcon: true,
                    loading: _finishing,
                    onPressed: _nextQuestion,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown when `QuestionRepository` has nothing to serve yet -- an empty or
  /// still-syncing question bank -- instead of crashing on an empty list.
  /// There is no hardcoded fallback content anywhere in this app (panel note
  /// 7), so an empty bank is a real, expected state, not just a theoretical one.
  Widget _buildEmptyState() {
    return Scaffold(
      appBar: const AppTopBar(title: 'Daily Challenge'),
      body: Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No questions available right now',
          message: 'Connect to the internet and try again in a moment.',
          color: context.palette.warning,
        ),
      ),
    );
  }

  Widget _buildAlreadyCompletedScreen() {
    final p = context.palette;
    final text = context.textStyles;
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      appBar: const AppTopBar(title: 'Daily Challenge'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 12, padding, 24),
              child: ContentWidth(
                maxWidth: 560,
                child: Column(
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: p.success,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: p.success.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text("You're done for today", style: text.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      "Great job! You've already completed today's challenge. Come back tomorrow for a new one.",
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    _buildCountdownCard(),
                    const SizedBox(height: 24),
                    const AppListGroup(
                      title: 'While you wait',
                      children: [
                        AppListTile(icon: Icons.menu_book_rounded, title: 'Read a study module', subtitle: 'Strengthen what you already know'),
                        AppListTile(icon: Icons.quiz_rounded, title: 'Take a practice quiz', subtitle: 'Focus on your weaker subjects'),
                        AppListTile(icon: Icons.style_rounded, title: 'Flip through flashcards', subtitle: 'Quick recall practice'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: PrimaryButton(label: 'Back to home', onPressed: () => Navigator.pop(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownCard() {
    final text = context.textStyles;
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        final difference = tomorrow.difference(now);

        final hours = difference.inHours;
        final minutes = difference.inMinutes % 60;
        final seconds = difference.inSeconds % 60;

        return GradientCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded, color: Colors.white.withValues(alpha: 0.85), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'NEXT CHALLENGE IN',
                    style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimeBox(hours.toString().padLeft(2, '0'), 'HRS'),
                  _colon(),
                  _buildTimeBox(minutes.toString().padLeft(2, '0'), 'MIN'),
                  _colon(),
                  _buildTimeBox(seconds.toString().padLeft(2, '0'), 'SEC'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _colon() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          ':',
          style: context.textStyles.headlineMedium?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );

  Widget _buildTimeBox(String value, String label) {
    final text = context.textStyles;
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(value, style: text.headlineMedium?.copyWith(color: Colors.white)),
          Text(label, style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final p = context.palette;
    final text = context.textStyles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          ToolbarIconButton(
            icon: Icons.close_rounded,
            size: 40,
            tooltip: 'Leave',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded, color: p.streak, size: 18),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('Daily Challenge', style: text.titleSmall, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Text(
                  'Question ${_currentIndex + 1} of $_totalQuestions · ${_bonusMultiplier}x points',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_streak > 1) ...[
            Pill(label: '$_streak', icon: Icons.whatshot_rounded, color: p.streak),
            const SizedBox(width: 8),
          ],
          _buildTimer(),
        ],
      ),
    );
  }

  /// Countdown ring: green, then amber, then red as time runs out.
  Widget _buildTimer() {
    final p = context.palette;
    final text = context.textStyles;
    return AnimatedBuilder(
      animation: _timerAnimation,
      builder: (context, child) {
        final value = _timerAnimation.value;
        final color = value > 0.5 ? p.success : (value > 0.25 ? p.warning : p.danger);
        return SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: p.surfaceAlt,
                ),
              ),
              Text(
                '${(value * _questionTime).ceil()}',
                style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressStrip() {
    final p = context.palette;
    return Row(
      children: List.generate(_questions.length, (i) {
        Color color;
        if (i < _currentIndex || (i == _currentIndex && _selectedAnswer != null)) {
          final answer = _userAnswers[i];
          color = answer == null
              ? p.warning
              : (answer == _shuffledCorrectIndices[i] ? p.success : p.danger);
        } else if (i == _currentIndex) {
          color = p.primary;
        } else {
          color = p.surfaceAlt;
        }
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 6,
            margin: EdgeInsets.only(right: i == _questions.length - 1 ? 0 : 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        );
      }),
    );
  }

  Widget _buildQuestionCard(Question question) {
    final p = context.palette;
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Pill(label: question.topic, color: AppColors.subjectColor(question.subject)),
              ),
              const SizedBox(width: 8),
              Pill(
                label: question.difficulty.name[0].toUpperCase() + question.difficulty.name.substring(1),
                color: p.forDifficulty(question.difficulty.index),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            question.questionText,
            style: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(int index) {
    final p = context.palette;
    final text = context.textStyles;
    final isSelected = _selectedAnswer == index;
    final isCorrect = index == _shuffledCorrectIndices[_currentIndex];
    final showResult = _selectedAnswer != null;

    Color bg = p.surface;
    Color border = p.border;
    Color badgeBg = p.surfaceAlt;
    Color badgeFg = p.textSecondary;
    Color labelColor = p.textPrimary;
    IconData? badgeIcon;

    if (showResult) {
      if (isCorrect) {
        bg = p.successSoft;
        border = p.success;
        badgeBg = p.success;
        badgeFg = Colors.white;
        badgeIcon = Icons.check_rounded;
      } else if (isSelected) {
        bg = p.dangerSoft;
        border = p.danger;
        badgeBg = p.danger;
        badgeFg = Colors.white;
        badgeIcon = Icons.close_rounded;
      } else {
        labelColor = p.textTertiary;
        badgeFg = p.textTertiary;
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: showResult ? null : () => _selectAnswer(index),
        borderRadius: BorderRadius.circular(AppSpace.radiusMd + 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSpace.radiusMd + 2),
            border: Border.all(color: border, width: showResult && (isCorrect || isSelected) ? 1.8 : 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: badgeIcon != null
                    ? Icon(badgeIcon, color: badgeFg, size: 19)
                    : Text(String.fromCharCode(65 + index), style: text.labelLarge?.copyWith(color: badgeFg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _shuffledOptions[_currentIndex][index],
                  style: text.bodyLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplanationCard(Question question) {
    final p = context.palette;
    final text = context.textStyles;
    final isCorrect = _selectedAnswer == _shuffledCorrectIndices[_currentIndex];
    final color = isCorrect ? p.success : p.danger;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        borderColor: color.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCorrect ? Icons.check_circle_rounded : Icons.lightbulb_outline_rounded, color: color, size: 19),
                const SizedBox(width: 8),
                Text(isCorrect ? 'Correct!' : 'Here is why', style: text.titleSmall?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              question.explanation,
              style: text.bodyMedium?.copyWith(color: p.textPrimary.withValues(alpha: 0.85)),
            ),
          ],
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
    required this.questions,
    required this.userAnswers,
    required this.shuffledOptions,
    required this.shuffledCorrectIndices,
  });

  @override
  State<_ChallengeResultsScreen> createState() => _ChallengeResultsScreenState();
}

class _ChallengeResultsScreenState extends State<_ChallengeResultsScreen> {
  // Owned here (it used to be handed over from the challenge screen, which
  // disposed it while this screen still needed it for the celebration).
  late final ConfettiController _confetti = ConfettiController(duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    if (widget.percentage >= 70) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _confetti.play();
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  String _getResultMessage() {
    if (widget.percentage >= 90) return 'Outstanding!';
    if (widget.percentage >= 80) return 'Excellent!';
    if (widget.percentage >= 70) return 'Great job!';
    if (widget.percentage >= 60) return 'Good effort!';
    if (widget.percentage >= 50) return 'Keep practicing!';
    return "Don't give up!";
  }

  String _getResultSubtitle() {
    if (widget.percentage >= 90) return "You're a criminology master!";
    if (widget.percentage >= 80) return "You're doing amazing!";
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
    final p = context.palette;
    final text = context.textStyles;
    final passed = widget.percentage >= 70;
    final tone = passed ? p.gold : p.primary;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ContentWidth(
              maxWidth: 560,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                      child: Column(
                        children: [
                          Appear(
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: passed ? p.goldSoft : p.primarySoft,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(_getResultIcon(), color: tone, size: 50),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(_getResultMessage(), style: text.headlineMedium),
                          const SizedBox(height: 4),
                          Text(_getResultSubtitle(), style: text.bodyMedium),
                          const SizedBox(height: 22),
                          RingProgress(
                            value: widget.percentage / 100,
                            size: 150,
                            stroke: 12,
                            color: p.forScore(widget.percentage.toDouble()),
                            center: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${widget.percentage}%', style: text.displaySmall),
                                Text('${widget.correctCount}/${widget.totalQuestions} correct', style: text.labelSmall),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          AppCard(
                            color: p.goldSoft,
                            borderColor: p.gold.withValues(alpha: 0.35),
                            child: Row(
                              children: [
                                IconBadge(icon: Icons.stars_rounded, color: p.gold, size: 48, background: p.surface),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Points earned', style: text.bodySmall),
                                      Text(
                                        '${widget.totalScore} pts',
                                        style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                                Pill(label: '+${widget.bonusPoints} bonus', icon: Icons.bolt_rounded, color: p.gold),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const InlineBanner(
                            tone: BannerTone.neutral,
                            icon: Icons.event_repeat_rounded,
                            message: 'Come back tomorrow for a new challenge!',
                          ),
                          const SizedBox(height: AppSpace.section),
                          _buildReviewAnswersSection(),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border(top: BorderSide(color: p.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: PrimaryButton(
                      label: 'Done',
                      onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 25,
              gravity: 0.1,
              colors: [p.primary, p.gold, p.success, p.streak, p.info],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewAnswersSection() {
    final p = context.palette;
    final text = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Review answers'),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: List.generate(widget.questions.length, (index) {
              final userAnswer = widget.userAnswers[index];
              final correctIndex = widget.shuffledCorrectIndices[index];
              final isCorrect = userAnswer == correctIndex;
              final isUnanswered = userAnswer == null;
              final letter = String.fromCharCode(65 + correctIndex);
              final correctOption = widget.shuffledOptions[index][correctIndex];
              final color = isUnanswered ? p.warning : (isCorrect ? p.success : p.danger);

              return Column(
                children: [
                  if (index > 0) Divider(height: 1, color: p.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: context.isDarkMode ? 0.2 : 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.questions[index].questionText,
                                style: text.bodySmall?.copyWith(color: p.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Answer: $letter · $correctOption',
                                style: text.labelMedium?.copyWith(color: p.success),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isUnanswered
                              ? Icons.timer_off_rounded
                              : isCorrect
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                          color: color,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}
