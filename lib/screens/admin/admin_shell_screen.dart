import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../utils/page_transitions.dart';
import '../auth_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_questions_screen.dart';
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
/// can never drift from the database's). This shell owns its own bottom
/// navigation -- Dashboard / Questions / Students -- with no student-facing
/// tabs in it at all, and no path INTO the student experience either: an
/// admin session never sees `HomeScreen`/Quiz/Cards/Progress under any
/// circumstance. The two roles share a database (an admin's edits reach
/// students through `public.questions`, not through navigation) but never
/// share a screen.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;

  void _goToTab(int index) => setState(() => _currentIndex = index);

  Future<void> _confirmSignOut() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = [
      AdminDashboardScreen(
        showBackButton: false,
        onNavigateToTab: _goToTab,
        appBarActions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      const AdminQuestionsScreen(showBackButton: false),
      const AdminStudentsScreen(showBackButton: false),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: IndexedStack(index: _currentIndex, children: tabs),
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
              _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard', isDark),
              _buildNavItem(1, Icons.quiz_rounded, 'Questions', isDark),
              _buildNavItem(2, Icons.groups_rounded, 'Students', isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDark) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.accent : (isDark ? Colors.white54 : Colors.grey.shade500);

    return GestureDetector(
      onTap: () => _goToTab(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
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
}
