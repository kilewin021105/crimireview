import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/mastery.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../services/adaptive_learning_service.dart';
import '../services/adaptive_ml_service.dart';
import '../services/mastery_service.dart';
import '../services/ml_service.dart';
import '../services/storage_service.dart';
import '../utils/page_transitions.dart';
import '../utils/quiz_launcher.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'achievements_screen.dart';
import 'daily_challenge_screen.dart';
import 'leaderboard_screen.dart';
import 'modules_screen.dart';
import 'profile_screen.dart';

/// The Home tab: what to do today, where you left off, and how ready you
/// are for the board exam.
///
/// Top to bottom:
///   1. Greeting, streak, leaderboard.
///   2. Today's goal: questions answered today against a goal the student
///      picks, plus this week's study days.
///   3. Continue learning: the subject studied most recently, at the level
///      and segment the student is actually on; one tap starts it.
///   4. Daily Challenge, showing whether today's is already done.
///   5. Totals: answered, accuracy, quizzes.
///   6. Board exam readiness (the ML model's recommendation and weak
///      subjects) and the weakest topics from the BKT mastery model.
///   7. Shortcuts and the study modules.
///
/// Every number comes from data the app already keeps; the only new
/// record is questions-per-day (`StorageService.addDailyActivity`).
class DashboardView extends StatefulWidget {
  /// Switches the bottom-navigation tab (1 = Quiz, 2 = Cards).
  final ValueChanged<int> onSelectTab;

  const DashboardView({super.key, required this.onSelectTab});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with WidgetsBindingObserver {
  final _storage = StorageService();
  AdaptiveLearningService? _service;

  String _userName = 'Student';
  String? _profileImagePath;
  String? _avatarUrl;

  Map<String, int> _activity = const {};
  int _dailyGoal = StorageService.defaultDailyGoal;
  bool _challengeDoneToday = false;
  bool _preparingQuiz = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.profileChangeNotifier.addListener(_loadProfile);
    _loadProfile();
    _loadToday();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A finished quiz updates the learning service; refresh today's count.
    final service = Provider.of<AdaptiveLearningService>(context, listen: false);
    if (!identical(service, _service)) {
      _service?.removeListener(_loadToday);
      _service = service..addListener(_loadToday);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StorageService.profileChangeNotifier.removeListener(_loadProfile);
    _service?.removeListener(_loadToday);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Opening the app on a new day starts a fresh goal.
    if (state == AppLifecycleState.resumed) _loadToday();
  }

  Future<void> _loadProfile() async {
    final name = await _storage.getUserName();
    final imagePath = await _storage.getProfileImage();
    final avatarUrl = await _storage.getAvatarUrl();
    if (!mounted) return;
    setState(() {
      _userName = name;
      _profileImagePath = imagePath;
      _avatarUrl = avatarUrl;
    });
  }

  Future<void> _loadToday() async {
    final activity = await _storage.getDailyActivity();
    final goal = await _storage.getDailyGoal();
    final lastChallenge = await _storage.getLastDailyChallengeDate();
    if (!mounted) return;
    setState(() {
      _activity = activity;
      _dailyGoal = goal;
      _challengeDoneToday = lastChallenge == StorageService.dayKey(DateTime.now());
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, SlidePageRoute(page: page));
    if (!mounted) return;
    _loadProfile();
    _loadToday();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress;
    final padding = Responsive.horizontalPadding(context);
    final gap = Responsive.isSmallPhone(context) ? 22.0 : AppSpace.section;

    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, 12, padding, 28),
            child: ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Appear(index: 0, child: _buildHeader(progress)),
                  const SizedBox(height: 20),
                  Appear(index: 1, child: _buildTodayCard(progress)),
                  const SizedBox(height: 14),
                  Appear(index: 2, child: _buildContinueCard(progress)),
                  const SizedBox(height: 12),
                  Appear(index: 3, child: _buildChallengeCard()),
                  const SizedBox(height: 12),
                  Appear(index: 4, child: _buildTotals(progress)),
                  SizedBox(height: gap),
                  Appear(index: 5, child: _buildReadiness(service)),
                  Appear(index: 6, child: _buildReviewTopics()),
                  Appear(index: 7, child: _buildShortcuts()),
                  SizedBox(height: gap),
                  Appear(index: 8, child: _buildModules(progress)),
                ],
              ),
            ),
          ),
        ),
        if (_preparingQuiz) _buildPreparingOverlay(),
      ],
    );
  }

  // 1. Header -----------------------------------------------------------------

  Widget _buildHeader(UserProgress progress) {
    final p = context.palette;
    final text = context.textStyles;
    final firstName = _userName.trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        GestureDetector(
          onTap: () => _open(const ProfileScreen()),
          child: UserAvatar(
            name: _userName,
            imagePath: _profileImagePath,
            imageUrl: _avatarUrl,
            size: 48,
            ring: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: text.bodySmall),
              const SizedBox(height: 1),
              Text(
                firstName.isEmpty ? 'Student' : firstName,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Day streak',
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: p.streakSoft,
              borderRadius: BorderRadius.circular(AppSpace.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded, color: p.streak, size: 20),
                const SizedBox(width: 4),
                Text(
                  '${progress.currentStreak}',
                  style: text.titleMedium?.copyWith(color: p.streak, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ToolbarIconButton(
          icon: Icons.emoji_events_rounded,
          color: p.gold,
          tooltip: 'Leaderboard',
          onPressed: () => _open(const LeaderboardScreen()),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // 2. Today's goal + week -----------------------------------------------------

  Widget _buildTodayCard(UserProgress progress) {
    final text = context.textStyles;
    final today = DateTime.now();
    final answeredToday = _activity[StorageService.dayKey(today)] ?? 0;
    final ratio = _dailyGoal == 0 ? 0.0 : answeredToday / _dailyGoal;
    final reached = answeredToday >= _dailyGoal;
    final left = _dailyGoal - answeredToday;
    const accent = Color(0xFFFFC266);
    final soft = Colors.white.withValues(alpha: 0.72);

    return GradientCard(
      onTap: _pickDailyGoal,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "TODAY'S GOAL",
                          style: text.labelSmall?.copyWith(color: soft, letterSpacing: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_rounded, size: 13, color: soft),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '$answeredToday',
                          style: text.displaySmall?.copyWith(color: Colors.white, height: 1),
                        ),
                        TextSpan(
                          text: '  / $_dailyGoal questions',
                          style: text.titleSmall?.copyWith(color: soft),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reached
                          ? 'Goal reached. Great work today!'
                          : answeredToday == 0
                              ? 'Answer $_dailyGoal questions to hit your goal.'
                              : '$left more to reach your goal.',
                      style: text.bodySmall?.copyWith(color: soft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              RingProgress(
                value: ratio,
                size: 78,
                stroke: 8,
                color: accent,
                trackColor: Colors.white.withValues(alpha: 0.16),
                center: reached
                    ? const Icon(Icons.check_rounded, color: accent, size: 34)
                    : Text(
                        '${(ratio * 100).clamp(0, 100).round()}%',
                        style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 14),
          _WeekStrip(days: _weekDays(today, progress)),
        ],
      ),
    );
  }

  /// Monday to Sunday of this week. A day counts as studied when this
  /// phone recorded answers that day, or when it falls inside the current
  /// streak (which is how days from before this record existed show up).
  List<_DayStatus> _weekDays(DateTime now, UserProgress progress) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));

    final streakDays = <String>{};
    final last = progress.lastActiveDate;
    if (last != null && progress.currentStreak > 0) {
      final lastDay = DateTime(last.year, last.month, last.day);
      // A streak only counts while it's alive (studied today or yesterday).
      if (today.difference(lastDay).inDays <= 1) {
        for (var i = 0; i < progress.currentStreak && i < 7; i++) {
          streakDays.add(StorageService.dayKey(DateTime(lastDay.year, lastDay.month, lastDay.day - i)));
        }
      }
    }

    return List.generate(7, (i) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final key = StorageService.dayKey(day);
      return _DayStatus(
        label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
        studied: (_activity[key] ?? 0) > 0 || streakDays.contains(key),
        isToday: day == today,
        isFuture: day.isAfter(today),
      );
    });
  }

  Future<void> _pickDailyGoal() async {
    HapticFeedback.selectionClick();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final p = ctx.palette;
        final text = ctx.textStyles;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily goal', style: text.titleLarge),
                const SizedBox(height: 4),
                Text('How many questions do you want to answer each day?', style: text.bodyMedium),
                const SizedBox(height: 16),
                for (final option in StorageService.dailyGoalOptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      borderColor: option == _dailyGoal ? p.primary : null,
                      color: option == _dailyGoal ? p.primarySoft : null,
                      onTap: () => Navigator.pop(ctx, option),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('$option questions a day', style: text.titleSmall),
                          ),
                          Text(_goalHint(option), style: text.bodySmall),
                          if (option == _dailyGoal) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.check_circle_rounded, color: p.primary, size: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || chosen == _dailyGoal) return;
    await _storage.setDailyGoal(chosen);
    if (mounted) setState(() => _dailyGoal = chosen);
  }

  String _goalHint(int goal) {
    switch (goal) {
      case 10:
        return 'Light';
      case 20:
        return 'Steady';
      case 30:
        return 'Serious';
      default:
        return 'Intense';
    }
  }

  // 3. Continue learning -------------------------------------------------------

  /// The subject studied most recently (or the first subject for a new
  /// student), at the lowest level not yet passed -- the same level the
  /// Quiz tab would let the student take next.
  _ContinueTarget _continueTarget(UserProgress progress) {
    SubjectProgress? latest;
    for (final sp in progress.subjectProgress.values) {
      final at = sp.lastStudyDate;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest.lastStudyDate!)) latest = sp;
    }
    final subject = (latest == null
            ? null
            : CriminologySubjects.all.where((s) => s.id == latest!.subjectId).firstOrNull) ??
        CriminologySubjects.all.first;
    final sp = progress.subjectProgress[subject.id];

    var difficulty = Difficulty.easy;
    if (sp != null) {
      if (!sp.isDifficultyPassed(Difficulty.easy)) {
        difficulty = Difficulty.easy;
      } else if (!sp.isDifficultyPassed(Difficulty.medium)) {
        difficulty = Difficulty.medium;
      } else {
        difficulty = Difficulty.hard;
      }
    }
    final segments = sp?.segmentsForDifficulty(difficulty) ?? const <SegmentProgress>[];
    final service = Provider.of<AdaptiveLearningService>(context, listen: false);
    return _ContinueTarget(
      subject: subject,
      difficulty: difficulty,
      segmentIndex: service.getCurrentSegmentIndex(subjectId: subject.id, difficulty: difficulty),
      segmentsPassed: segments.where((s) => s.isPassed).length,
      started: latest != null,
      allPassed: sp?.isDifficultyPassed(Difficulty.hard) ?? false,
    );
  }

  Widget _buildContinueCard(UserProgress progress) {
    final p = context.palette;
    final text = context.textStyles;
    final target = _continueTarget(progress);
    final color = AppColors.subjectColor(target.subject.id);
    final icon = AppTheme.subjectIcons[target.subject.id] ?? Icons.book_rounded;
    final level = _difficultyName(target.difficulty);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 46, iconSize: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.started ? 'CONTINUE LEARNING' : 'START HERE',
                      style: text.labelSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      target.subject.name,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      target.allPassed
                          ? 'All levels passed · review $level'
                          : '$level · Questions ${SegmentProgress.rangeLabelFor(target.segmentIndex)}',
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final segments = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppProgressBar(
                  value: target.segmentsPassed / SegmentProgress.segmentCount,
                  color: color,
                  height: 6,
                ),
                const SizedBox(height: 6),
                Text(
                  '${target.segmentsPassed} of ${SegmentProgress.segmentCount} segments passed',
                  style: text.bodySmall?.copyWith(color: p.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
            final narrow = c.maxWidth < 300;
            final button = PrimaryButton(
              label: target.started ? 'Resume' : 'Start',
              icon: Icons.play_arrow_rounded,
              expand: narrow,
              height: 44,
              loading: _preparingQuiz,
              onPressed: () => _startQuiz(target),
            );
            // Smallest phones: button under the bar so the text isn't cut off.
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [segments, const SizedBox(height: 12), button],
              );
            }
            return Row(
              children: [
                Expanded(child: segments),
                const SizedBox(width: 14),
                button,
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _startQuiz(_ContinueTarget target) async {
    if (_preparingQuiz) return;
    HapticFeedback.mediumImpact();
    await startSegmentQuiz(
      context,
      subject: target.subject,
      difficulty: target.difficulty,
      onPreparing: (preparing) {
        if (mounted) setState(() => _preparingQuiz = preparing);
      },
    );
  }

  String _difficultyName(Difficulty d) => switch (d) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };

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

  // 4. Daily Challenge -------------------------------------------------------

  Widget _buildChallengeCard() {
    final p = context.palette;
    final text = context.textStyles;
    final done = _challengeDoneToday;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _open(const DailyChallengeScreen()),
      child: Row(
        children: [
          IconBadge(
            icon: done ? Icons.task_alt_rounded : Icons.bolt_rounded,
            color: done ? p.success : p.gold,
            size: 42,
            iconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily Challenge', style: text.titleSmall),
                const SizedBox(height: 1),
                Text(
                  done ? 'Done for today · new set tomorrow' : '10 mixed questions · 1.5x points',
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          done
              ? Pill(label: 'Done', icon: Icons.check_rounded, color: p.success)
              : Pill(label: 'Play', icon: Icons.play_arrow_rounded, color: p.primary, solid: true),
        ],
      ),
    );
  }

  // 5. Totals ----------------------------------------------------------------

  Widget _buildTotals(UserProgress progress) {
    final p = context.palette;
    var answered = 0, correct = 0, quizzes = 0;
    for (final s in CriminologySubjects.all) {
      final sp = progress.subjectProgress[s.id];
      answered += sp?.totalQuestionsAnswered ?? 0;
      correct += sp?.totalCorrectAnswers ?? 0;
      quizzes += sp?.totalQuizzesTaken ?? 0;
    }
    final accuracy = answered > 0 ? correct / answered * 100 : 0.0;

    Widget cell(String value, String label, Color color, IconData icon) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(label, style: context.textStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );

    Widget divider() => Container(width: 1, height: 44, color: p.border);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Row(
        children: [
          cell('$answered', 'Answered', p.primary, Icons.task_alt_rounded),
          divider(),
          cell(
            '${accuracy.toStringAsFixed(0)}%',
            'Accuracy',
            answered == 0 ? p.textTertiary : p.forScore(accuracy),
            Icons.track_changes_rounded,
          ),
          divider(),
          cell('$quizzes', 'Quizzes', p.info, Icons.assignment_turned_in_rounded),
        ],
      ),
    );
  }

  // 6. Readiness (ML) and topics to review (BKT) -----------------------------

  Widget _buildReadiness(AdaptiveLearningService service) {
    final p = context.palette;
    final text = context.textStyles;
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
    if (subjectPerformance.isEmpty) return const SizedBox.shrink();

    final readiness = service.getOverallBoardExamReadiness();
    final diffCompletion = service.getDifficultyCompletionCounts();
    final totalSubjects = diffCompletion['totalSubjects'] ?? 6;
    final recommendedDiff = mlService.recommendDifficulty(subjectPerformance: subjectPerformance);
    final weakAreas = mlService.detectWeakAreas(subjectPerformance: subjectPerformance);
    final weakSubjects = weakAreas.where((w) => w.isWeak).take(2).toList();
    final strongSubjects = weakAreas.where((w) => !w.isWeak && w.accuracy > 0.7).take(2).toList();

    final tone = p.forScore(readiness);
    final status = readiness >= 75
        ? "You're on track to pass"
        : readiness < 60
            ? 'Needs more practice'
            : 'Almost there';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Board exam readiness',
            subtitle: 'From your accuracy across all levels',
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RingProgress(
                      value: readiness / 100,
                      size: 92,
                      stroke: 10,
                      color: tone,
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${readiness.toStringAsFixed(0)}%',
                            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text('ready', style: text.labelSmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Pill(label: status, color: tone),
                          const SizedBox(height: 12),
                          _levelBar('Easy', diffCompletion['easy'] ?? 0, totalSubjects, p.success),
                          const SizedBox(height: 8),
                          _levelBar('Medium', diffCompletion['medium'] ?? 0, totalSubjects, p.warning),
                          const SizedBox(height: 8),
                          _levelBar('Hard', diffCompletion['hard'] ?? 0, totalSubjects, p.danger),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppSpace.radiusMd),
                  ),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: Icons.auto_awesome_rounded,
                        color: p.forDifficulty(recommendedDiff),
                        size: 36,
                        iconSize: 19,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recommended next', style: text.bodySmall),
                            Text(
                              'Practice ${mlService.getDifficultyName(recommendedDiff)} questions',
                              style: text.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (weakSubjects.isNotEmpty || strongSubjects.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in weakSubjects)
                        Pill(
                          label: '${w.subjectName} · ${(w.accuracy * 100).toStringAsFixed(0)}%',
                          icon: Icons.flag_rounded,
                          color: p.danger,
                        ),
                      for (final s in strongSubjects)
                        Pill(
                          label: '${s.subjectName} · ${(s.accuracy * 100).toStringAsFixed(0)}%',
                          icon: Icons.verified_rounded,
                          color: p.success,
                        ),
                    ],
                  ),
                  if (weakSubjects.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(weakSubjects.first.recommendation, style: text.bodySmall),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelBar(String label, int completed, int total, Color color) {
    final text = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.labelMedium)),
            Text(
              '$completed/$total',
              style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AppProgressBar(value: total > 0 ? completed / total : 0, color: color, height: 6),
      ],
    );
  }

  /// The three topics the BKT model is least sure the student knows
  /// (practised at least twice, not yet mastered). Tapping one opens that
  /// subject's study notes.
  Widget _buildReviewTopics() {
    return ListenableBuilder(
      listenable: MasteryService.instance,
      builder: (context, _) {
        final topics = MasteryService.instance.all
            .where((m) => m.attempts >= 2 && !m.isMastered)
            .toList()
          ..sort((a, b) => a.pKnown.compareTo(b.pKnown));
        if (topics.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Topics to review',
                subtitle: 'Where your answers show the least mastery so far',
              ),
              const SizedBox(height: 12),
              AppListGroup(
                children: [for (final m in topics.take(3)) _topicRow(m)],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topicRow(TopicMastery m) {
    final p = context.palette;
    final text = context.textStyles;
    final subject = CriminologySubjects.all.where((s) => s.id == m.subjectId).firstOrNull;
    final percent = m.masteryPercent;
    final color = p.forScore(percent);
    return InkWell(
      onTap: subject == null ? null : () => _open(ModulesScreen(subject: subject)),
      borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBadge(
              icon: AppTheme.subjectIcons[m.subjectId] ?? Icons.menu_book_rounded,
              color: AppColors.subjectColor(m.subjectId),
              size: 36,
              iconSize: 19,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.topic, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${subject?.shortName ?? m.subjectId} · ${m.attempts} answered',
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  AppProgressBar(value: percent / 100, color: color, height: 5),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${percent.round()}%',
              style: text.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // 7. Shortcuts and modules -------------------------------------------------

  Widget _buildShortcuts() {
    final p = context.palette;
    final items = [
      (Icons.quiz_rounded, 'Quiz', p.primary, () => widget.onSelectTab(1)),
      (Icons.style_rounded, 'Cards', const Color(0xFF7C4DDB), () => widget.onSelectTab(2)),
      (Icons.leaderboard_rounded, 'Ranks', p.gold, () => _open(const LeaderboardScreen())),
      (Icons.military_tech_rounded, 'Badges', p.streak, () => _open(const AchievementsScreen())),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Shortcuts'),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  onTap: items[i].$4,
                  child: Column(
                    children: [
                      IconBadge(icon: items[i].$1, color: items[i].$3, size: 40, iconSize: 21),
                      const SizedBox(height: 8),
                      Text(
                        items[i].$2,
                        style: context.textStyles.labelMedium?.copyWith(color: p.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildModules(UserProgress progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Study modules',
          subtitle: 'Notes and topics for each board subject',
        ),
        const SizedBox(height: 12),
        // A swipeable row on phones; it simply shows more cards on wider screens.
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: CriminologySubjects.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final subject = CriminologySubjects.all[index];
              final sp = progress.subjectProgress[subject.id];
              return SizedBox(
                width: 152,
                child: _moduleCard(
                  subject,
                  sp?.totalQuestionsAnswered ?? 0,
                  sp?.totalCorrectAnswers ?? 0,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _moduleCard(Subject subject, int answered, int correct) {
    final p = context.palette;
    final text = context.textStyles;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);
    final accuracy = answered > 0 ? correct / answered : 0.0;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(ModulesScreen(subject: subject)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 38, iconSize: 20),
              const Spacer(),
              Text('${subject.weight}%', style: text.labelSmall?.copyWith(color: p.textSecondary)),
            ],
          ),
          const Spacer(),
          Text(subject.shortName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            answered > 0 ? '${(accuracy * 100).round()}% accuracy' : '${subject.topics.length} topics',
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          AppProgressBar(value: accuracy, color: color, height: 5),
        ],
      ),
    );
  }
}

class _ContinueTarget {
  final Subject subject;
  final Difficulty difficulty;
  final int segmentIndex;
  final int segmentsPassed;
  final bool started;
  final bool allPassed;

  const _ContinueTarget({
    required this.subject,
    required this.difficulty,
    required this.segmentIndex,
    required this.segmentsPassed,
    required this.started,
    required this.allPassed,
  });
}

class _DayStatus {
  final String label;
  final bool studied;
  final bool isToday;
  final bool isFuture;

  const _DayStatus({
    required this.label,
    required this.studied,
    required this.isToday,
    required this.isFuture,
  });
}

/// Seven day dots on the hero card: filled with a tick on days studied,
/// a ring around today, faint for days still ahead.
class _WeekStrip extends StatelessWidget {
  final List<_DayStatus> days;

  const _WeekStrip({required this.days});

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    const navy = Color(0xFF13286E);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          Semantics(
            label: '${d.label}: ${d.studied ? 'studied' : d.isFuture ? 'upcoming' : 'not studied'}',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  d.label,
                  style: text.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: d.isToday ? 1 : 0.6),
                    fontWeight: d.isToday ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d.studied
                        ? Colors.white
                        : Colors.white.withValues(alpha: d.isFuture ? 0.06 : 0.12),
                    border: d.isToday && !d.studied
                        ? Border.all(color: Colors.white, width: 1.6)
                        : null,
                  ),
                  child: d.studied ? const Icon(Icons.check_rounded, size: 18, color: navy) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
