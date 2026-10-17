import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;

import '../services/social_auth_service.dart';
import '../services/supabase_service.dart';
import '../widgets/brand_logos.dart';
import '../widgets/ui/ui.dart';

/// "or continue with" and a Google icon, under the email sign-in form.
/// (Facebook sign-in was removed on 2026-10-17; the row still lays out one
/// icon per [SocialProvider].)
///
/// Tapping the icon opens Google's own sign-in page in the phone's
/// browser; [SocialAuthService] explains how that stays safe. This widget
/// only starts the sign-in and shows its progress and errors. When the
/// student comes back signed in, the screen it sits in finishes the
/// sign-in through `SignInCompletion`, exactly like its email button.
///
/// The icon is always shown on Android, iPhone and the web, so the page
/// looks the same before and after Google is set up. Until it is switched
/// on in Supabase, tapping it says so instead of opening an error page.
/// The desktop apps can't receive the browser's answer (see
/// [SocialAuthService.isSupportedPlatform]), so they don't show it.
class SocialSignInIcons extends StatefulWidget {
  /// False while the email form is signing in.
  final bool enabled;

  /// True while the screen finishes a Google sign-in
  /// (syncing the student's progress).
  final bool completing;

  const SocialSignInIcons({super.key, required this.enabled, required this.completing});

  @override
  State<SocialSignInIcons> createState() => _SocialSignInIconsState();
}

class _SocialSignInIconsState extends State<SocialSignInIcons> {
  /// Providers switched on in Supabase, as last checked.
  Set<SocialProvider> _enabled = const {};

  /// The provider whose page is open in the browser, until Supabase answers.
  SocialProvider? _pending;

  /// Drives the spinner on that provider's icon.
  SocialProvider? _loading;

  String? _errorMessage;
  Timer? _resumeTimer;
  StreamSubscription<AuthState>? _authSubscription;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    if (SupabaseService.isInitialized) {
      _authSubscription = SupabaseService.instance.authStateChanges.listen(
        _onAuthState,
        onError: _onBrowserSignInError,
      );
    }
    _loadEnabled();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _authSubscription?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  /// Which providers are switched on: the last check saved on this phone,
  /// then a fresh one from Supabase.
  Future<void> _loadEnabled() async {
    if (!SocialAuthService.isSupportedPlatform) return;
    final cached = await SocialAuthService.instance.cachedEnabled();
    if (!mounted) return;
    _enabled = cached;
    final fresh = await SocialAuthService.instance.refreshEnabled();
    if (mounted && fresh != null) _enabled = fresh;
  }

  bool get _busy => !widget.enabled || widget.completing || _loading != null;

  Future<void> _start(SocialProvider provider) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _loading = provider;
      _errorMessage = null;
    });
    if (!_enabled.contains(provider)) {
      // It may have been switched on since the last check.
      final fresh = await SocialAuthService.instance.refreshEnabled();
      if (!mounted) return;
      if (fresh != null) _enabled = fresh;
      if (!_enabled.contains(provider)) {
        setState(() {
          _loading = null;
          _errorMessage =
              "${provider.label} sign-in isn't available yet. Please sign in with your email.";
        });
        return;
      }
    }
    _pending = provider;
    try {
      await SocialAuthService.instance.start(provider);
    } catch (e) {
      _pending = null;
      if (!mounted) return;
      setState(() {
        _loading = null;
        _errorMessage = SocialAuthService.instance.describeError(e, provider);
      });
    }
  }

  void _onAuthState(AuthState state) {
    // Signed in: the screen takes over and shows its own progress.
    if (state.event != AuthChangeEvent.signedIn || _pending == null) return;
    _pending = null;
    _resumeTimer?.cancel();
    if (mounted) setState(() => _loading = null);
  }

  /// An error Supabase reports back from the browser (cancelled, no email
  /// shared, expired). Ignored unless the sign-in was started here.
  void _onBrowserSignInError(Object error) {
    final provider = _pending;
    if (provider == null || !mounted) return;
    _pending = null;
    _resumeTimer?.cancel();
    setState(() {
      _loading = null;
      _errorMessage = SocialAuthService.instance.describeError(error, provider);
    });
  }

  /// Back from the browser without finishing: stop the spinner after a
  /// moment. A sign-in that still arrives later completes anyway.
  void _onResume() {
    if (_pending == null) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !widget.completing && _loading != null) {
        setState(() => _loading = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SocialAuthService.isSupportedPlatform) return const SizedBox.shrink();
    const providers = SocialProvider.values;
    final text = context.textStyles;
    final names = providers.map((provider) => provider.label).join(' or ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const _OrDivider(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (i, provider) in providers.indexed) ...[
              if (i > 0) const SizedBox(width: 16),
              _ProviderIcon(
                provider: provider,
                loading: _loading == provider,
                enabled: !_busy,
                onPressed: () => _start(provider),
              ),
            ],
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          InlineBanner(message: _errorMessage!, tone: BannerTone.danger),
        ] else if (widget.completing) ...[
          const SizedBox(height: 16),
          const InlineBanner(
            message: 'Signed in. Getting your progress ready...',
            tone: BannerTone.info,
            icon: Icons.sync_rounded,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Your password stays with $names. CrimiReview only receives your name, '
          'email address and profile photo.',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// A thin line, "or continue with", and a thin line.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final line = Expanded(child: Divider(color: p.border, height: 1, thickness: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: context.textStyles.labelMedium?.copyWith(color: p.textTertiary),
          ),
        ),
        line,
      ],
    );
  }
}

/// A rounded tile with just the provider's logo. Its name is given to
/// screen readers and shown as a tooltip on a long press.
class _ProviderIcon extends StatelessWidget {
  final SocialProvider provider;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  const _ProviderIcon({
    required this.provider,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = 'Continue with ${provider.label}';
    final logo = switch (provider) {
      SocialProvider.google => const GoogleLogo(size: 24),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      side: BorderSide(color: p.border),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Opacity(
          opacity: enabled || loading ? 1 : 0.55,
          child: Material(
            color: p.surface,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                width: 76,
                height: 56,
                child: Center(
                  child: loading
                      ? SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: p.primary),
                        )
                      : logo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
