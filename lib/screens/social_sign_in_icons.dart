import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;

import '../services/social_auth_service.dart';
import '../services/supabase_service.dart';
import '../widgets/brand_logos.dart';
import '../widgets/ui/ui.dart';
import 'sign_in_choice_screen.dart';

/// "or continue with" and a Google and a Facebook icon, under the email
/// sign-in form.
///
/// Tapping an icon opens that provider's own sign-in page in the phone's
/// browser; [SocialAuthService] explains how that stays safe. This widget
/// only starts the sign-in and shows its progress and errors. When the
/// student comes back signed in, the screen it sits in finishes the
/// sign-in through `SignInCompletion`, exactly like its email button.
///
/// Only the providers switched on in Supabase are shown, so a student
/// never taps an icon that opens an error page. With neither switched on,
/// this shows nothing.
class SocialSignInIcons extends StatefulWidget {
  /// False while the email form is signing in.
  final bool enabled;

  /// True while the screen finishes a Google or Facebook sign-in
  /// (syncing the student's progress).
  final bool completing;

  const SocialSignInIcons({super.key, required this.enabled, required this.completing});

  @override
  State<SocialSignInIcons> createState() => _SocialSignInIconsState();
}

class _SocialSignInIconsState extends State<SocialSignInIcons> {
  Set<SocialProvider> _providers = const {};

  /// Preview mode only: what Supabase really has switched on.
  Set<SocialProvider> _reallyEnabled = const {};

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
    if (SignInChoiceScreen.previewMode) _providers = SocialProvider.values.toSet();
    _loadProviders();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _authSubscription?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  /// The last check saved on this phone first, so the icons appear
  /// instantly, then a fresh check from Supabase.
  Future<void> _loadProviders() async {
    if (!SocialAuthService.isSupportedPlatform) return;
    if (!SignInChoiceScreen.previewMode) {
      final cached = await SocialAuthService.instance.cachedEnabled();
      if (!mounted) return;
      setState(() => _providers = cached);
    }
    final fresh = await SocialAuthService.instance.refreshEnabled();
    if (!mounted || fresh == null) return;
    setState(() {
      if (SignInChoiceScreen.previewMode) {
        _reallyEnabled = fresh;
      } else {
        _providers = fresh;
      }
    });
  }

  bool get _busy => !widget.enabled || widget.completing || _loading != null;

  Future<void> _start(SocialProvider provider) async {
    if (_busy) return;
    if (SignInChoiceScreen.previewMode && !_reallyEnabled.contains(provider)) {
      setState(() => _errorMessage =
          'Preview only: ${provider.label} sign-in is not switched on in Supabase yet. '
          'See README "Google and Facebook sign-in".');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _loading = provider;
      _errorMessage = null;
    });
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
    final providers = SocialProvider.values.where(_providers.contains).toList();
    if (providers.isEmpty) return const SizedBox.shrink();
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
      SocialProvider.facebook => const FacebookLogo(size: 26),
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
