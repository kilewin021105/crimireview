import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_info.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/ui/ui.dart';
import '../sign_in_choice_screen.dart';
import '../change_password_screen.dart';

/// Settings tab of the admin panel.
///
/// Before this, the admin shell had no settings at all: an admin couldn't
/// switch to dark mode, change their password or see which account they
/// were signed in as, and "Sign out" was a bare icon on the dashboard.
///
/// Sections:
///   * Account: name, email and the Administrator role.
///   * Appearance: light / dark / follow the phone.
///   * Security: change password (password accounts only), sign out.
///   * About: version, website, support email.
///
/// Nothing here changes data other students see. Sign-in methods (email,
/// Google, Facebook) are deliberately not shown here: they have their own
/// page before sign-in (`SignInChoiceScreen`).
class AdminSettingsScreen extends StatefulWidget {
  /// Signs out and returns to the login screen. The shell passes its own
  /// so the wide-screen side menu and this tab do exactly the same thing.
  final Future<void> Function()? onSignOut;

  const AdminSettingsScreen({super.key, this.onSignOut});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _storage = StorageService();
  String _name = 'Administrator';
  String? _email;
  String? _imagePath;
  String? _avatarUrl;

  static const String _websiteUrl = 'https://www.crimireview.app';
  static const String _supportEmail = 'support@crimireview.app';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    StorageService.profileChangeNotifier.addListener(_loadProfile);
  }

  @override
  void dispose() {
    StorageService.profileChangeNotifier.removeListener(_loadProfile);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final name = await _storage.getUserName();
    final email = await _storage.getUserEmail();
    final imagePath = await _storage.getProfileImage();
    final avatarUrl = await _storage.getAvatarUrl();
    if (!mounted) return;
    setState(() {
      _name = name;
      _email = SupabaseService.instance.currentUser?.email ?? email;
      _imagePath = imagePath;
      _avatarUrl = avatarUrl;
    });
  }

  Future<void> _signOut() async {
    if (widget.onSignOut != null) return widget.onSignOut!();
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
    final signIn = await SignInChoiceScreen.entry();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      SlidePageRoute(page: signIn),
      (route) => false,
    );
  }

  Future<void> _open(Uri uri, String fallback) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && mounted) showAppSnack(context, fallback, tone: BannerTone.info);
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      appBar: const AppTopBar(
        title: 'Settings',
        subtitle: 'Your admin account and this app',
        showBack: false,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 28),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _accountCard(),
                const SizedBox(height: 24),
                _appearance(),
                const SizedBox(height: 24),
                _security(),
                const SizedBox(height: 24),
                _about(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final p = context.palette;
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          UserAvatar(name: _name, imagePath: _imagePath, imageUrl: _avatarUrl, size: 56, ring: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_email != null && _email!.isNotEmpty)
                  Text(_email!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Pill(label: 'Administrator', icon: Icons.shield_rounded, color: p.gold),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearance() {
    final themeService = Provider.of<ThemeService>(context);
    const modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    final index = modes.indexOf(themeService.themeMode).clamp(0, 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('APPEARANCE', style: context.textStyles.labelSmall),
        ),
        PillTabs(
          labels: const ['Light', 'Dark', 'Phone setting'],
          index: index,
          onChanged: (i) => themeService.setThemeMode(modes[i]),
        ),
      ],
    );
  }

  Widget _security() {
    // An account without a password (it signs in another way) has nothing
    // to change; unknown (no session details yet) counts as a password one.
    final hasPassword = SupabaseService.instance.signInMethods.isEmpty ||
        SupabaseService.instance.hasPasswordSignIn;
    return AppListGroup(
      title: 'Security',
      children: [
        if (hasPassword)
          AppListTile(
            icon: Icons.lock_rounded,
            title: 'Change password',
            subtitle: 'Asks for your current password first',
            onTap: () => Navigator.push(
              context,
              SlidePageRoute(page: const ChangePasswordScreen(), direction: SlideDirection.up),
            ),
          ),
        AppListTile(
          icon: Icons.logout_rounded,
          title: 'Sign out',
          subtitle: _email,
          destructive: true,
          onTap: _signOut,
        ),
      ],
    );
  }

  Widget _about() {
    final p = context.palette;
    final text = context.textStyles;
    return Column(
      children: [
        AppListGroup(
          title: 'About',
          children: [
            AppListTile(
              icon: Icons.language_rounded,
              iconColor: p.info,
              title: 'Website',
              subtitle: 'www.crimireview.app',
              onTap: () => _open(Uri.parse(_websiteUrl), 'Open $_websiteUrl in your browser'),
            ),
            AppListTile(
              icon: Icons.support_agent_rounded,
              iconColor: p.success,
              title: 'Support email',
              subtitle: _supportEmail,
              onTap: () => _open(
                Uri(scheme: 'mailto', path: _supportEmail),
                'No email app found. Write to $_supportEmail',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const AppLogo(size: 48),
        const SizedBox(height: 10),
        const AppWordmark(fontSize: 18),
        const SizedBox(height: 2),
        Text('Admin panel · Version $kAppVersion', style: text.bodySmall),
      ],
    );
  }
}
