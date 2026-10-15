import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/social_auth_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_info.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/brand_logos.dart';
import '../../widgets/ui/ui.dart';
import '../auth_screen.dart';
import '../change_password_screen.dart';

/// Settings tab of the admin panel.
///
/// Before this, the admin shell had no settings at all: an admin couldn't
/// switch to dark mode, change their password or see which account they
/// were signed in as, and "Sign out" was a bare icon on the dashboard.
///
/// Sections:
///   * Account: name, email, the Administrator role and how they sign in.
///   * Appearance: light / dark / follow the phone.
///   * Sign-in methods: whether Email, Google and Facebook are switched on
///     in Supabase right now, read live, so the admin can confirm the
///     README setup worked without opening the Supabase dashboard.
///   * Security: change password (password accounts only), sign out.
///   * About: version, website, support email.
///
/// Nothing here changes data other students see.
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

  /// null while checking; otherwise the providers switched on in Supabase.
  Set<SocialProvider>? _enabledProviders;
  bool _providerCheckFailed = false;

  static const String _websiteUrl = 'https://www.crimireview.app';
  static const String _supportEmail = 'support@crimireview.app';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _checkProviders();
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

  Future<void> _checkProviders() async {
    setState(() {
      _enabledProviders = null;
      _providerCheckFailed = false;
    });
    final fresh = await SocialAuthService.instance.refreshEnabled();
    final result = fresh ?? await SocialAuthService.instance.cachedEnabled();
    if (!mounted) return;
    setState(() {
      _enabledProviders = result;
      _providerCheckFailed = fresh == null;
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
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      SlidePageRoute(page: const AuthScreen()),
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
                _signInMethods(),
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
    final methods = SupabaseService.instance.signInMethods;
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(label: 'Administrator', icon: Icons.shield_rounded, color: p.gold),
                    for (final m in methods) Pill(label: _methodName(m), color: p.textSecondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _methodName(String id) => switch (id) {
        'email' => 'Email',
        'google' => 'Google',
        'facebook' => 'Facebook',
        _ => id,
      };

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

  Widget _signInMethods() {
    final p = context.palette;
    final enabled = _enabledProviders;

    Widget status(bool? on) {
      if (on == null) {
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.textTertiary),
        );
      }
      return Pill(
        label: on ? 'On' : 'Off',
        icon: on ? Icons.check_rounded : Icons.remove_rounded,
        color: on ? p.success : p.textTertiary,
      );
    }

    Widget providerTile(SocialProvider provider, Widget logo) {
      final on = enabled?.contains(provider);
      return _LogoTile(
        logo: logo,
        title: provider.label,
        subtitle: on == null
            ? 'Checking...'
            : on
                ? 'Students see "${provider.label}" on the sign-in screen'
                : 'Hidden from students until set up (README)',
        trailing: status(on),
      );
    }

    return AppListGroup(
      title: 'Sign-in methods',
      children: [
        AppListTile(
          icon: Icons.mail_rounded,
          iconColor: p.primary,
          title: 'Email and password',
          subtitle: 'With the 6-digit email code',
          trailing: status(true),
        ),
        providerTile(SocialProvider.google, const GoogleLogo(size: 19)),
        providerTile(SocialProvider.facebook, const FacebookLogo(size: 20)),
        if (_providerCheckFailed)
          AppListTile(
            icon: Icons.cloud_off_rounded,
            iconColor: p.warning,
            title: "Couldn't reach Supabase",
            subtitle: 'Showing the last known status. Tap to check again.',
            onTap: _checkProviders,
          )
        else
          AppListTile(
            icon: Icons.refresh_rounded,
            iconColor: p.textSecondary,
            title: 'Check again',
            subtitle: 'After changing providers in the Supabase dashboard',
            onTap: enabled == null ? null : _checkProviders,
            showChevron: false,
          ),
      ],
    );
  }

  Widget _security() {
    final p = context.palette;
    final methods = SupabaseService.instance.signInMethods;
    // Unknown (no session details yet) is treated as a password account.
    final hasPassword = methods.isEmpty || SupabaseService.instance.hasPasswordSignIn;
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
          )
        else
          AppListTile(
            icon: Icons.verified_user_rounded,
            iconColor: p.success,
            title: 'No password on this account',
            subtitle: 'You sign in with ${methods.map(_methodName).join(' or ')}',
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

/// An [AppListTile]-style row with a brand logo instead of an icon badge.
class _LogoTile extends StatelessWidget {
  final Widget logo;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _LogoTile({
    required this.logo,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(36 * 0.32),
            ),
            child: logo,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 1),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
