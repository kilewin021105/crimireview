import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/offline_sync_service.dart';
import '../widgets/ui/ui.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import 'dashboard_view.dart';
import 'subjects_screen.dart';
import 'flashcards_home_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.startMonitoring();
    // Once Home is on screen: the one-time "allow notifications?" prompt
    // the daily study reminders need on Android 13 and newer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermissionOnce();
    });
  }

  @override
  void dispose() {
    ConnectivityService.instance.stopMonitoring();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.quiz_outlined, Icons.quiz_rounded, 'Quiz'),
    (Icons.style_outlined, Icons.style_rounded, 'Cards'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Progress'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    // Tablets in landscape and computers: a side rail, like the admin
    // panel. Phones (including a phone held sideways, which is too short
    // for five rail items) keep the bottom bar.
    final wide = size.width >= kWideLayoutWidth && size.height >= 480;

    final tabs = IndexedStack(
      index: _currentIndex,
      children: [
        DashboardView(onSelectTab: _selectTab),
        const SubjectsScreen(),
        const FlashcardsHomeScreen(),
        const ProgressScreen(),
        SettingsScreen(key: ValueKey('settings_$_currentIndex')),
      ],
    );
    final body = ListenableBuilder(
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
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _buildRail(),
            VerticalDivider(width: 1, thickness: 1, color: p.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
      ),
    );
  }

  Widget _buildRail() {
    final p = context.palette;
    final text = context.textStyles;
    return Container(
      color: p.surface,
      child: SafeArea(
        right: false,
        child: NavigationRail(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          backgroundColor: p.surface,
          labelType: NavigationRailLabelType.all,
          minWidth: 92,
          groupAlignment: -0.9,
          indicatorColor: p.primarySoft,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selectedIconTheme: IconThemeData(color: p.primary, size: 23),
          unselectedIconTheme: IconThemeData(color: p.textTertiary, size: 23),
          selectedLabelTextStyle: text.labelSmall?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800),
          unselectedLabelTextStyle: text.labelSmall?.copyWith(color: p.textTertiary),
          leading: const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 16),
            child: AppLogo(size: 44, showShadow: false),
          ),
          destinations: [
            for (final d in _destinations)
              NavigationRailDestination(
                icon: Icon(d.$1),
                selectedIcon: Icon(d.$2),
                label: Text(d.$3),
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
