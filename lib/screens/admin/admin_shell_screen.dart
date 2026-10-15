import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/page_transitions.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/ui/ui.dart';
import '../auth_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_questions_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_students_screen.dart';

/// Root screen for an admin account -- the counterpart to `HomeScreen` for
/// students.
///
/// Before this screen existed, being an admin didn't change the app at all:
/// an admin signed in and landed on the exact same Home/Quiz/Cards/Progress
/// tabs a student sees, with "Admin Panel" buried two taps deep inside
/// Settings. That made the two roles feel entangled -- there was no real
/// separation, just one extra button.
///
/// `SplashScreen` and `AuthScreen` route an admin here instead of to
/// `HomeScreen` after login (checking `AdminService.isAdmin`, which is
/// itself resolved from `is_admin()` -- the same function the database's
/// row-level security uses, so the app's idea of "is this account an admin"
/// can never drift from the database's). This shell owns its own navigation
/// -- Dashboard / Questions / Students / Settings -- with no student-facing tabs in it
/// at all, and no path INTO the student experience either: an admin session
/// never sees `HomeScreen`/Quiz/Cards/Progress under any circumstance. The
/// two roles share a database (an admin's edits reach students through
/// `public.questions`, not through navigation) but never share a screen.
///
/// Layout: a bottom navigation bar on phones; a side navigation rail on
/// tablets, desktop and the web, where admins usually work.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;

  static const _destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Dashboard'),
    (Icons.quiz_outlined, Icons.quiz_rounded, 'Questions'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Students'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  void _goToTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to manage questions and students.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;

    await SupabaseService.instance.signOut();
    await StorageService().clearAuthData();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      SlidePageRoute(page: const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = MediaQuery.of(context).size.width >= 840;

    final tabs = [
      // Sign out now lives in the Settings tab (and the wide side menu).
      AdminDashboardScreen(showBackButton: false, onNavigateToTab: _goToTab),
      const AdminQuestionsScreen(showBackButton: false),
      const AdminStudentsScreen(showBackButton: false),
      AdminSettingsScreen(onSignOut: _confirmSignOut),
    ];

    final body = IndexedStack(index: _currentIndex, children: tabs);

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _goToTab,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _buildSideNav(),
          VerticalDivider(width: 1, thickness: 1, color: p.border),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// Side navigation for wide screens: brand, sections, sign out.
  Widget _buildSideNav() {
    final p = context.palette;
    final text = context.textStyles;
    return Container(
      width: 248,
      color: p.surface,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppLogo(size: 38, showShadow: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppWordmark(fontSize: 17),
                        Text('Admin panel', style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 8),
                child: Text('MANAGE', style: text.labelSmall),
              ),
              for (var i = 0; i < _destinations.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _sideItem(i),
                ),
              const Spacer(),
              const InlineBanner(
                tone: BannerTone.neutral,
                icon: Icons.shield_outlined,
                message: 'Changes here go live for every student.',
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _confirmSignOut,
                  borderRadius: BorderRadius.circular(AppSpace.radiusMd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: p.danger, size: 20),
                        const SizedBox(width: 12),
                        Text('Sign out', style: text.titleSmall?.copyWith(color: p.danger)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideItem(int index) {
    final p = context.palette;
    final text = context.textStyles;
    final selected = index == _currentIndex;
    final d = _destinations[index];
    return Material(
      color: selected ? p.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      child: InkWell(
        onTap: () => _goToTab(index),
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(selected ? d.$2 : d.$1, color: selected ? p.primary : p.textSecondary, size: 21),
              const SizedBox(width: 12),
              Text(
                d.$3,
                style: text.titleSmall?.copyWith(color: selected ? p.onPrimarySoft : p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
