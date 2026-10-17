import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import '../widgets/ui/ui.dart';
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
