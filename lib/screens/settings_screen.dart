import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/feedback_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/adaptive_learning_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'change_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  String _userName = 'Student';
  String? _profileImagePath;
  bool _notificationsEnabled = true;
  bool _soundEffectsEnabled = true;
  bool _hapticFeedbackEnabled = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _updateAuthState();
    if (SupabaseService.isInitialized) {
      SupabaseService.instance.authStateChanges.listen((_) {
        if (mounted) _updateAuthState();
      });
    }
  }

  void _updateAuthState() {
    final loggedIn = SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn;
    if (_isLoggedIn != loggedIn) {
      setState(() => _isLoggedIn = loggedIn);
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAuthState();
  }

  Future<void> _loadSettings() async {
    final name = await _storage.getUserName();
    final imagePath = await _storage.getProfileImage();
    final notifications = await _storage.getNotificationsEnabled();
    final sound = await _storage.getSoundEffectsEnabled();
    final haptic = await _storage.getHapticFeedbackEnabled();
    
    if (mounted) {
      setState(() {
        _userName = name ?? 'Student';
        _profileImagePath = imagePath;
        _notificationsEnabled = notifications;
        _soundEffectsEnabled = sound;
        _hapticFeedbackEnabled = haptic;
      });
    }
  }

  Future<void> _shareApp() async {
    await Share.share(
      'Check out CrimiReview - the best app for Criminology board exam review! Download now and ace your exams!',
      subject: 'CrimiReview App',
    );
  }

  Future<void> _rateApp() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Thank you for your support! Rating feature coming soon.'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@crimireview.app',
      query: 'subject=CrimiReview Feedback',
    );
    
    try {
      await launchUrl(emailUri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open email app'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showSignOutDialog(bool isDark) {
    showDialog(
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
        content: Text(
          'Are you sure you want to sign out? Your local progress will be kept.',
          style: TextStyle(
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              await SupabaseService.instance.signOut();
              await StorageService().clearAllData();
              if (context.mounted) {
                Provider.of<AdaptiveLearningService>(context, listen: false).resetProgress();
                Navigator.pop(context);
                Navigator.of(this.context).pushAndRemoveUntil(
                  SlidePageRoute(page: const AuthScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = Provider.of<ThemeService>(context);
    final isDarkMode = themeService.themeMode == ThemeMode.dark;
    final isSmall = Responsive.isSmallPhone(context);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 28),
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your preferences',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 14),
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              
              const SizedBox(height: 24),
              
              GestureDetector(
                onTap: () async {
                  await Navigator.push(context, SlidePageRoute(page: const ProfileScreen()));
                  _loadSettings();
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
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
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accent,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Edit profile',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              

              _buildSectionHeader('Appearance', isDark),
              const SizedBox(height: 12),
              
              _buildSettingTile(
                icon: isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                title: 'Dark Mode',
                subtitle: isDarkMode ? 'On' : 'Off',
                isDark: isDark,
                trailing: _buildToggle(
                  value: isDarkMode,
                  onChanged: (value) {
                    themeService.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                  },
                  isDark: isDark,
                ),
              ),
              
              const SizedBox(height: 24),
              

              _buildSectionHeader('Notifications & Feedback', isDark),
              const SizedBox(height: 12),
              
              _buildSettingTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: _notificationsEnabled ? 'Enabled' : 'Disabled',
                isDark: isDark,
                trailing: _buildToggle(
                  value: _notificationsEnabled,
                  onChanged: (value) async {
                    await _storage.setNotificationsEnabled(value);
                    setState(() => _notificationsEnabled = value);

                    await NotificationService.instance.setupScheduledNotifications();
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildSettingTile(
                icon: Icons.volume_up_outlined,
                title: 'Sound Effects',
                subtitle: _soundEffectsEnabled ? 'Enabled' : 'Disabled',
                isDark: isDark,
                trailing: _buildToggle(
                  value: _soundEffectsEnabled,
                  onChanged: (value) async {
                    await _storage.setSoundEffectsEnabled(value);
                    setState(() => _soundEffectsEnabled = value);

                    await FeedbackService.instance.refreshSettings();
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildSettingTile(
                icon: Icons.vibration_outlined,
                title: 'Haptic Feedback',
                subtitle: _hapticFeedbackEnabled ? 'Enabled' : 'Disabled',
                isDark: isDark,
                trailing: _buildToggle(
                  value: _hapticFeedbackEnabled,
                  onChanged: (value) async {
                    await _storage.setHapticFeedbackEnabled(value);
                    setState(() => _hapticFeedbackEnabled = value);

                    await FeedbackService.instance.refreshSettings();
                    if (value) {
                      FeedbackService.instance.lightTap();
                    }
                  },
                  isDark: isDark,
                ),
              ),
              
              const SizedBox(height: 24),
              

              _buildSectionHeader('Account', isDark),
              const SizedBox(height: 12),
              
              if (_isLoggedIn) ...[
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    SlidePageRoute(page: const ChangePasswordScreen(), direction: SlideDirection.up),
                  ),
                  child: _buildSettingTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    subtitle: 'Update your password',
                    isDark: isDark,
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                GestureDetector(
                  onTap: () => _showSignOutDialog(isDark),
                  child: _buildSettingTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    subtitle: SupabaseService.instance.currentUser?.email ?? '',
                    isDark: isDark,
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.error,
                    ),
                    iconColor: AppColors.error,
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      SlidePageRoute(page: const AuthScreen()),
                    );
                  },
                  child: _buildSettingTile(
                    icon: Icons.login_rounded,
                    title: 'Sign In',
                    subtitle: 'Sync your progress to cloud',
                    isDark: isDark,
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              

              _buildSectionHeader('Support', isDark),
              const SizedBox(height: 12),
              
              GestureDetector(
                onTap: _shareApp,
                child: _buildSettingTile(
                  icon: Icons.share_outlined,
                  title: 'Share App',
                  subtitle: 'Invite friends to study',
                  isDark: isDark,
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              GestureDetector(
                onTap: _rateApp,
                child: _buildSettingTile(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate App',
                  subtitle: 'Leave a review',
                  isDark: isDark,
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              GestureDetector(
                onTap: _sendFeedback,
                child: _buildSettingTile(
                  icon: Icons.feedback_outlined,
                  title: 'Send Feedback',
                  subtitle: 'Help us improve',
                  isDark: isDark,
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF8B5CF6).withOpacity(0.12),
                      const Color(0xFF8B5CF6).withOpacity(0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [

                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1a365d).withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.school,
                        size: 44,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CrimiReview',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'For Future Criminologists',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Widget trailing,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: value 
            ? AppColors.accent 
            : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
