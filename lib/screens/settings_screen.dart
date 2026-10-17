import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
import 'package:url_launcher/url_launcher.dart';
import '../services/storage_service.dart';
import '../services/feedback_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/app_info.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/ui/ui.dart';
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
  String? _userEmail;
  String? _profileImagePath;
  String? _avatarUrl;
  bool _notificationsEnabled = true;
  bool _soundEffectsEnabled = true;
  bool _hapticFeedbackEnabled = true;
  bool _isLoggedIn = false;


  @override
  void initState() {
    super.initState();
    _loadSettings();
    StorageService.profileChangeNotifier.addListener(_handleProfileChanged);
    _updateAuthState();
    if (SupabaseService.isInitialized) {
      _authSubscription = SupabaseService.instance.authStateChanges.listen((_) {
        if (mounted) _updateAuthState();
      });
    }
  }

  // Kept so dispose() can stop it; before, every visit to this tab left
  // another listener running for the rest of the session.
  StreamSubscription<AuthState>? _authSubscription;

  void _handleProfileChanged() {
    _loadSettings();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    StorageService.profileChangeNotifier.removeListener(_handleProfileChanged);
    super.dispose();
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
    final email = await _storage.getUserEmail();
    final imagePath = await _storage.getProfileImage();
    final avatarUrl = await _storage.getAvatarUrl();
    final notifications = await _storage.getNotificationsEnabled();
    final sound = await _storage.getSoundEffectsEnabled();
    final haptic = await _storage.getHapticFeedbackEnabled();

    if (mounted) {
      setState(() {
        _userName = name;
        _userEmail = email;
        _profileImagePath = imagePath;
        _avatarUrl = avatarUrl;
        _notificationsEnabled = notifications;
        _soundEffectsEnabled = sound;
        _hapticFeedbackEnabled = haptic;
      });
    }
  }

  static const String _websiteUrl = 'https://www.crimireview.app';
  static const String _supportEmail = 'support@crimireview.app';

  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Check out CrimiReview - an adaptive reviewer for the Criminologist Licensure Examination! '
            'Download it free: $_websiteUrl',
        subject: 'CrimiReview App',
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=CrimiReview Feedback',
    );

    bool opened = false;
    try {
      opened = await launchUrl(emailUri);
    } catch (_) {
      opened = false;
    }
    // launchUrl returns false (rather than throwing) when no email app is
    // set up, so the student would otherwise see nothing happen at all.
    if (!opened && mounted) {
      showAppSnack(
        context,
        'No email app found. Send your feedback to $_supportEmail',
        tone: BannerTone.info,
      );
    }
  }

  Future<void> _openPage(String url) async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showAppSnack(context, 'Open $url in your browser', tone: BannerTone.info);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your progress on this phone will be kept. Sign in again any time to sync it.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await SupabaseService.instance.signOut();
    // Keep local quiz progress, only clear auth/profile data
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
    final text = context.textStyles;
    final themeService = Provider.of<ThemeService>(context);
    final isDarkMode = themeService.themeMode == ThemeMode.dark;
    final padding = Responsive.horizontalPadding(context);
    final email = SupabaseService.instance.currentUser?.email ?? _userEmail;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 28),
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(title: 'Settings', subtitle: 'Manage your preferences'),
                const SizedBox(height: 20),

                AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () async {
                    await Navigator.push(context, SlidePageRoute(page: const ProfileScreen()));
                    _loadSettings();
                  },
                  child: Row(
                    children: [
                      UserAvatar(
                        name: _userName,
                        imagePath: _profileImagePath,
                        imageUrl: _avatarUrl,
                        size: 56,
                        ring: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_userName, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              email == null || email.isEmpty ? 'View and edit your profile' : email,
                              style: text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Pill(label: 'Edit', color: p.primary),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                AppListGroup(
                  title: 'Appearance',
                  children: [
                    AppListTile(
                      icon: isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      iconColor: const Color(0xFF7C4DDB),
                      title: 'Dark mode',
                      subtitle: isDarkMode ? 'On' : 'Off',
                      onTap: () => themeService.setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark),
                      trailing: Switch(
                        value: isDarkMode,
                        onChanged: (value) {
                          themeService.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                AppListGroup(
                  title: 'Notifications & feedback',
                  children: [
                    AppListTile(
                      icon: Icons.notifications_rounded,
                      iconColor: p.info,
                      title: 'Study reminders',
                      subtitle: _notificationsEnabled ? 'On' : 'Off',
                      onTap: () => _setNotifications(!_notificationsEnabled),
                      trailing: Switch(value: _notificationsEnabled, onChanged: _setNotifications),
                    ),
                    AppListTile(
                      icon: Icons.volume_up_rounded,
                      iconColor: p.success,
                      title: 'Sound effects',
                      subtitle: _soundEffectsEnabled ? 'On' : 'Off',
                      onTap: () => _setSound(!_soundEffectsEnabled),
                      trailing: Switch(value: _soundEffectsEnabled, onChanged: _setSound),
                    ),
                    AppListTile(
                      icon: Icons.vibration_rounded,
                      iconColor: p.streak,
                      title: 'Haptic feedback',
                      subtitle: _hapticFeedbackEnabled ? 'On' : 'Off',
                      onTap: () => _setHaptics(!_hapticFeedbackEnabled),
                      trailing: Switch(value: _hapticFeedbackEnabled, onChanged: _setHaptics),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                AppListGroup(
                  title: 'Account',
                  children: [
                    if (_isLoggedIn) ...[
                      // A Google-only account has no password to change.
                      if (SupabaseService.instance.hasPasswordSignIn)
                        AppListTile(
                          icon: Icons.lock_rounded,
                          title: 'Change password',
                          subtitle: 'Update your password',
                          onTap: () => Navigator.push(
                            context,
                            SlidePageRoute(page: const ChangePasswordScreen(), direction: SlideDirection.up),
                          ),
                        ),
                      AppListTile(
                        icon: Icons.logout_rounded,
                        title: 'Sign out',
                        subtitle: SupabaseService.instance.currentUser?.email,
                        destructive: true,
                        onTap: _confirmSignOut,
                      ),
                    ] else
                      AppListTile(
                        icon: Icons.login_rounded,
                        title: 'Sign in',
                        subtitle: 'Sync your progress to the cloud',
                        onTap: () => Navigator.pushReplacement(
                          context,
                          SlidePageRoute(page: const AuthScreen()),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),
                AppListGroup(
                  title: 'Support',
                  children: [
                    AppListTile(
                      icon: Icons.ios_share_rounded,
                      iconColor: p.info,
                      title: 'Share CrimiReview',
                      subtitle: 'Invite friends to study',
                      onTap: _shareApp,
                    ),
                    // "Rate App" removed until there is a store listing to rate.
                    AppListTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      iconColor: p.success,
                      title: 'Send feedback',
                      subtitle: 'Help us improve',
                      onTap: _sendFeedback,
                    ),
                    AppListTile(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: p.textSecondary,
                      title: 'Privacy Policy',
                      subtitle: 'What we collect and your rights',
                      onTap: () => _openPage(kPrivacyPolicyUrl),
                    ),
                    AppListTile(
                      icon: Icons.description_outlined,
                      iconColor: p.textSecondary,
                      title: 'Terms of Service',
                      onTap: () => _openPage(kTermsUrl),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                Center(
                  child: Column(
                    children: [
                      const AppLogo(size: 56),
                      const SizedBox(height: 14),
                      const AppWordmark(fontSize: 20),
                      const SizedBox(height: 4),
                      Text('Version $kAppVersion', style: text.bodySmall),
                      const SizedBox(height: 10),
                      Pill(label: 'For future criminologists', icon: Icons.balance_rounded, color: p.gold),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setNotifications(bool value) async {
    // Android 13+ shows nothing until the student allows notifications, so
    // turning reminders on asks first; if refused, the switch stays off
    // instead of claiming reminders that will never arrive.
    if (value && !await NotificationService.instance.requestPermissions()) {
      if (!mounted) return;
      showAppSnack(
        context,
        "Allow notifications for CrimiReview in your phone's settings to get study reminders.",
        tone: BannerTone.warning,
      );
      return;
    }
    await _storage.setNotificationsEnabled(value);
    setState(() => _notificationsEnabled = value);
    await NotificationService.instance.setupScheduledNotifications();
  }

  Future<void> _setSound(bool value) async {
    await _storage.setSoundEffectsEnabled(value);
    setState(() => _soundEffectsEnabled = value);
    await FeedbackService.instance.refreshSettings();
  }

  Future<void> _setHaptics(bool value) async {
    await _storage.setHapticFeedbackEnabled(value);
    setState(() => _hapticFeedbackEnabled = value);
    await FeedbackService.instance.refreshSettings();
    if (value) {
      FeedbackService.instance.lightTap();
    }
  }
}
