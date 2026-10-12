import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/adaptive_learning_service.dart';
import '../services/storage_service.dart';
import '../services/ml_service.dart';
import '../services/adaptive_ml_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import '../models/subject.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'subjects_screen.dart';
import 'flashcards_home_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'leaderboard_screen.dart';
import 'daily_challenge_screen.dart';
import 'modules_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  String _userName = 'Student';
  String? _profileImagePath;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    StorageService.profileChangeNotifier.addListener(_handleProfileChanged);
    ConnectivityService.instance.startMonitoring();
  }

  void _handleProfileChanged() {
    _loadUserData();
  }

  @override
  void dispose() {
    StorageService.profileChangeNotifier.removeListener(_handleProfileChanged);
    ConnectivityService.instance.stopMonitoring();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final storage = StorageService();
    final name = await storage.getUserName();
    final imagePath = await storage.getProfileImage();
    final avatarUrl = await storage.getAvatarUrl();
    if (mounted) {
      setState(() {
        _userName = name;
        _profileImagePath = imagePath;
        _avatarUrl = avatarUrl;
      });
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tabs = IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeContent(context),
        const SubjectsScreen(),
        const FlashcardsHomeScreen(),
        const ProgressScreen(),
        SettingsScreen(key: ValueKey('settings_$_currentIndex')),
      ],
    );
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([ConnectivityService.instance, OfflineSyncService.instance]),
        child: tabs,
        builder: (context, child) => Column(
          children: [
            _ConnectionBanner(topInset: MediaQuery.of(context).padding.top),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                // The banner already sits under the status bar when shown.
                removeTop: _bannerVisible,
                child: child!,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.quiz_outlined),
              selectedIcon: Icon(Icons.quiz_rounded),
              label: 'Quiz',
            ),
            NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style_rounded),
              label: 'Cards',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  bool get _bannerVisible {
    final online = ConnectivityService.instance.isOnline;
    final sync = OfflineSyncService.instance;
    return !online || sync.isSyncing || sync.droppedCount > 0;
  }

  Widget _buildHomeContent(BuildContext context) {
    final service = Provider.of<AdaptiveLearningService>(context);
    final progress = service.userProgress;
    final padding = Responsive.horizontalPadding(context);
    final isSmall = Responsive.isSmallPhone(context);
    final gap = isSmall ? 22.0 : AppSpace.section;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 12, padding, 28),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Appear(index: 0, child: _buildHeader(progress)),
              const SizedBox(height: 22),
              Appear(index: 1, child: _buildDailyChallenge()),
              const SizedBox(height: 14),
              Appear(index: 2, child: _buildQuickStats(progress)),
              SizedBox(height: gap),
              Appear(index: 3, child: _buildPracticeShortcuts()),
              SizedBox(height: gap),
              Appear(index: 4, child: _buildMLInsights(service)),
              Appear(index: 5, child: _buildStudySubjects(progress)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic progress) {
    final p = context.palette;
    final text = context.textStyles;
    final firstName = _userName.trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            await Navigator.push(context, SlidePageRoute(page: const ProfileScreen()));
            _loadUserData();
          },
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
              Text(_getGreeting(), style: text.bodySmall),
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
        ToolbarIconButton(
          icon: Icons.emoji_events_rounded,
          color: p.gold,
          tooltip: 'Leaderboard',
          onPressed: () => Navigator.push(
            context,
            SlidePageRoute(page: const LeaderboardScreen()),
          ),
        ),
        const SizedBox(width: 8),
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
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildQuickStats(dynamic progress) {
    final p = context.palette;
    final totalQuestions = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalQuestionsAnswered ?? 0) as int),
    );
    final totalCorrect = CriminologySubjects.all.fold<int>(
      0, (sum, s) => sum + ((progress.subjectProgress[s.id]?.totalCorrectAnswers ?? 0) as int),
    );
    final accuracy = totalQuestions > 0 ? (totalCorrect / totalQuestions * 100) : 0.0;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.task_alt_rounded,
            value: '$totalQuestions',
            label: 'Answered',
            color: p.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            icon: Icons.track_changes_rounded,
            value: '${accuracy.toStringAsFixed(0)}%',
            label: 'Accuracy',
            color: totalQuestions == 0 ? p.textTertiary : p.forScore(accuracy),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            icon: Icons.assignment_turned_in_rounded,
            value: '${_getTotalQuizzes(progress)}',
            label: 'Quizzes',
            color: p.info,
          ),
        ),
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

  Widget _buildDailyChallenge() {
    final text = context.textStyles;
    return GradientCard(
      onTap: () {
        Navigator.push(context, SlidePageRoute(page: const DailyChallengeScreen()));
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(
                  label: '1.5x bonus points',
                  icon: Icons.bolt_rounded,
                  color: Colors.white,
                  background: Colors.white.withValues(alpha: 0.18),
                ),
                const SizedBox(height: 12),
                Text(
                  'Daily Challenge',
                  style: text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'A fresh mixed set every day. Keep your streak going.',
                  style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpace.radiusSm + 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Play now',
                        style: text.labelLarge?.copyWith(color: const Color(0xFF13286E)),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF13286E)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFFC266), size: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeShortcuts() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Keep practicing'),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final quiz = _ShortcutCard(
            icon: Icons.quiz_rounded,
            color: p.primary,
            title: 'Take a quiz',
            subtitle: 'Pick a subject',
            onTap: () => _selectTab(1),
          );
          final cards = _ShortcutCard(
            icon: Icons.style_rounded,
            color: const Color(0xFF7C4DDB),
            title: 'Flashcards',
            subtitle: 'Quick recall',
            onTap: () => _selectTab(2),
          );
          // Side by side when there's room; stacked on the smallest phones
          // so the labels never get cut off.
          if (c.maxWidth < 340) {
            return Column(children: [quiz, const SizedBox(height: 10), cards]);
          }
          return Row(
            children: [
              Expanded(child: quiz),
              const SizedBox(width: 10),
              Expanded(child: cards),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildMLInsights(AdaptiveLearningService service) {
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

    if (subjectPerformance.isEmpty) {
      return const SizedBox.shrink();
    }

    final boardExamReadiness = service.getOverallBoardExamReadiness();
    final diffCompletion = service.getDifficultyCompletionCounts();
    final totalSubjects = diffCompletion['totalSubjects'] ?? 6;

    final recommendedDiff = mlService.recommendDifficulty(
      subjectPerformance: subjectPerformance,
    );

    final weakAreas = mlService.detectWeakAreas(
      subjectPerformance: subjectPerformance,
    );

    final weakSubjects = weakAreas.where((w) => w.isWeak).take(2).toList();
    final strongSubjects = weakAreas.where((w) => !w.isWeak && w.accuracy > 0.7).take(2).toList();

    final isReady = boardExamReadiness >= 75;
    final needsWork = boardExamReadiness < 60;
    final tone = isReady ? p.success : (needsWork ? p.danger : p.warning);
    final status = isReady
        ? "You're ready to pass!"
        : needsWork
            ? 'Needs more practice'
            : 'Almost there!';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Board exam readiness',
            subtitle: 'Based on your accuracy across all difficulties',
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    RingProgress(
                      value: boardExamReadiness / 100,
                      size: 96,
                      stroke: 10,
                      color: tone,
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${boardExamReadiness.toStringAsFixed(0)}%',
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
                          _buildDifficultyProgressBar('Easy', diffCompletion['easy'] ?? 0, totalSubjects, p.success),
                          const SizedBox(height: 8),
                          _buildDifficultyProgressBar('Medium', diffCompletion['medium'] ?? 0, totalSubjects, p.warning),
                          const SizedBox(height: 8),
                          _buildDifficultyProgressBar('Hard', diffCompletion['hard'] ?? 0, totalSubjects, p.danger),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: p.border, height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconBadge(
                      icon: Icons.speed_rounded,
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
                if (weakSubjects.isNotEmpty || strongSubjects.isNotEmpty) const SizedBox(height: 14),
                if (weakSubjects.isNotEmpty)
                  _insightList(
                    title: 'Focus on these',
                    icon: Icons.flag_rounded,
                    color: p.danger,
                    soft: p.dangerSoft,
                    items: weakSubjects
                        .map((w) => '${w.subjectName} · ${(w.accuracy * 100).toStringAsFixed(0)}%')
                        .toList(),
                    note: weakSubjects.first.recommendation,
                  ),
                if (weakSubjects.isNotEmpty && strongSubjects.isNotEmpty) const SizedBox(height: 10),
                if (strongSubjects.isNotEmpty)
                  _insightList(
                    title: 'Your strong subjects',
                    icon: Icons.verified_rounded,
                    color: p.success,
                    soft: p.successSoft,
                    items: strongSubjects
                        .map((s) => '${s.subjectName} · ${(s.accuracy * 100).toStringAsFixed(0)}%')
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightList({
    required String title,
    required IconData icon,
    required Color color,
    required Color soft,
    required List<String> items,
    String? note,
  }) {
    final text = context.textStyles;
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 6),
              Text(title, style: text.titleSmall?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item, style: text.bodySmall?.copyWith(color: p.textPrimary)),
                  ),
                ],
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: text.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildDifficultyProgressBar(String label, int completed, int total, Color color) {
    final text = context.textStyles;
    final progress = total > 0 ? completed / total : 0.0;
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
        AppProgressBar(value: progress, color: color, height: 6),
      ],
    );
  }

  Widget _buildStudySubjects(dynamic progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Study modules',
          subtitle: 'Notes and topics for each board subject',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final columns = c.maxWidth >= 560 ? 3 : 2;
          return GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 150,
            ),
            itemCount: CriminologySubjects.all.length,
            itemBuilder: (context, index) {
              final subject = CriminologySubjects.all[index];
              final sp = progress.subjectProgress[subject.id];
              final answered = (sp?.totalQuestionsAnswered ?? 0) as int;
              final correct = (sp?.totalCorrectAnswers ?? 0) as int;
              return _buildStudySubjectCard(subject, answered, correct);
            },
          );
        }),
      ],
    );
  }

  Widget _buildStudySubjectCard(Subject subject, int answered, int correct) {
    final p = context.palette;
    final text = context.textStyles;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);
    final accuracy = answered > 0 ? correct / answered : 0.0;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        Navigator.push(
          context,
          SlidePageRoute(page: ModulesScreen(subject: subject)),
        );
      },
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
          Text(
            subject.shortName,
            style: text.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            answered > 0 ? '${(accuracy * 100).round()}% accuracy' : '${subject.topics.length} topics',
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          AppProgressBar(
            value: accuracy,
            color: color,
            height: 5,
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 40, iconSize: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim status strip shown above every tab while offline or syncing.
class _ConnectionBanner extends StatelessWidget {
  final double topInset;

  const _ConnectionBanner({required this.topInset});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ConnectivityService.instance, OfflineSyncService.instance]),
      builder: (context, _) {
        final p = context.palette;
        final text = context.textStyles;
        final isOnline = ConnectivityService.instance.isOnline;
        final syncService = OfflineSyncService.instance;
        final hasPending = syncService.hasPendingSync;
        final isSyncing = syncService.isSyncing;
        final pendingCount = syncService.pendingCount;

        final droppedCount = syncService.droppedCount;

        Widget? content;
        Color? bg;
        if (droppedCount > 0) {
          // Items the server rejected for good. Shown until acknowledged, so
          // a lost result is never silent.
          bg = p.dangerSoft;
          content = InkWell(
            onTap: () => _explainDropped(context, syncService, droppedCount),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, color: p.danger, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '$droppedCount result${droppedCount == 1 ? '' : 's'} couldn\'t be saved online · Tap for details',
                    style: text.labelMedium?.copyWith(color: p.danger),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        } else if (isOnline && isSyncing) {
          bg = p.infoSoft;
          content = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: p.info),
              ),
              const SizedBox(width: 8),
              Text(
                'Syncing $pendingCount items...',
                style: text.labelMedium?.copyWith(color: p.info),
              ),
            ],
          );
        } else if (!isOnline) {
          bg = p.warningSoft;
          content = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, color: p.warning, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hasPending
                      ? 'Offline · $pendingCount items will sync when online'
                      : "You're offline. Progress is saved on this phone.",
                  style: text.labelMedium?.copyWith(color: p.warning),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: content == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  color: bg,
                  padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 8),
                  child: content,
                ),
        );
      },
    );
  }

  static Future<void> _explainDropped(
    BuildContext context,
    OfflineSyncService syncService,
    int droppedCount,
  ) async {
    final one = droppedCount == 1;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final text = ctx.textStyles;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon: Icons.cloud_off_rounded, color: ctx.palette.danger, size: 46),
                const SizedBox(height: 16),
                Text('Some progress was not saved online', style: text.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '$droppedCount item${one ? '' : 's'} saved while offline could not be uploaded because '
                  'the server rejected ${one ? 'it' : 'them'}. Your progress on this phone is unchanged; '
                  'only the online copy is missing ${one ? 'this item' : 'these items'}.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 22),
                PrimaryButton(label: 'Got it', height: 48, onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        );
      },
    );
    await syncService.acknowledgeDropped();
  }
}
