import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/social_auth_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/brand_logos.dart';
import '../widgets/ui/ui.dart';
import 'auth_screen.dart';
import 'sign_in_completion.dart';

/// "Decide how you sign in to CrimiReview": a page of its own, shown
/// before the email form, with the Google and Facebook choices and a link
/// to use email instead. Laid out like an app-setup consent page: what
/// happens is explained in plain words first, then the choices.
///
/// Google and Facebook live only here, not inside the student or admin
/// screens. When neither is switched on in Supabase, this page is skipped
/// and the email form opens directly (see [entry]).
class SignInChoiceScreen extends StatefulWidget {
  /// Providers known to be switched on when this page was opened.
  final Set<SocialProvider> initialProviders;

  const SignInChoiceScreen({super.key, required this.initialProviders});

  /// The first sign-in page to show: this one when Google or Facebook is
  /// switched on (as last checked), otherwise the email form.
  static Future<Widget> entry() async {
    if (!SocialAuthService.isSupportedPlatform) return const AuthScreen();
    final enabled = await SocialAuthService.instance.cachedEnabled();
    if (enabled.isEmpty) return const AuthScreen();
    return SignInChoiceScreen(initialProviders: enabled);
  }

  @override
  State<SignInChoiceScreen> createState() => _SignInChoiceScreenState();
}

class _SignInChoiceScreenState extends State<SignInChoiceScreen>
    with SignInCompletion, WidgetsBindingObserver {
  late Set<SocialProvider> _providers = widget.initialProviders;

  /// The provider whose page is open in the browser, until Supabase answers.
  SocialProvider? _pending;

  /// Drives the spinner on that provider's button.
  SocialProvider? _loading;

  String? _errorMessage;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    watchForSessions();
    _refreshProviders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    super.dispose();
  }

  /// Re-checks Supabase. If both were switched off since the last check,
  /// this page has nothing to offer, so the email form replaces it.
  Future<void> _refreshProviders() async {
    final fresh = await SocialAuthService.instance.refreshEnabled();
    if (!mounted || fresh == null) return;
    if (fresh.isEmpty) {
      // Only while this page is the one showing (not under the email form).
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      Navigator.of(context).pushReplacement(SlidePageRoute(page: const AuthScreen()));
      return;
    }
    setState(() => _providers = fresh);
  }

  bool get _busy => _loading != null || isCompletingSignIn;

  /// Text column width on tablets and desktop.
  static const double _contentWidth = 568;

  Future<void> _choose(SocialProvider provider) async {
    if (_busy) return;
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

  void _useEmail() {
    if (isCompletingSignIn) return;
    _pending = null;
    _resumeTimer?.cancel();
    setState(() {
      _loading = null;
      _errorMessage = null;
    });
    Navigator.of(context).push(SlidePageRoute(page: const AuthScreen()));
  }

  @override
  void onBrowserSignInError(Object error) {
    final provider = _pending;
    if (provider == null) return;
    _pending = null;
    _resumeTimer?.cancel();
    setState(() {
      _loading = null;
      _errorMessage = SocialAuthService.instance.describeError(error, provider);
    });
  }

  @override
  void onSignInFailed(String message) {
    setState(() {
      _loading = null;
      _errorMessage = message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser without finishing: stop the spinner after a
    // moment. A sign-in that still arrives later completes anyway.
    if (state != AppLifecycleState.resumed || _pending == null) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !isCompletingSignIn && _loading != null) {
        setState(() => _loading = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isSmall = Responsive.isSmallPhone(context);
    final side = isSmall ? 20.0 : 26.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (context.isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: p.surface,
        // Fills the screen with the choices at the bottom; scrolls when the
        // phone is too short for everything.
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        MediaQuery.of(context).padding.top + (isSmall ? 18 : 28),
                        side,
                        24,
                      ),
                      child: ContentWidth(maxWidth: _contentWidth, child: _buildExplanation(isSmall)),
                    ),
                    const Spacer(),
                    _buildChoices(side),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplanation(bool isSmall) {
    final p = context.palette;
    final text = context.textStyles;
    final body = text.bodyMedium?.copyWith(color: p.textSecondary, height: 1.55);
    final strong = body?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppLogo(size: isSmall ? 40 : 44, showShadow: false),
            const Spacer(),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
            Text('Secure sign-in', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        SizedBox(height: isSmall ? 22 : 30),
        Text(
          'Decide how you sign in to CrimiReview',
          style: (isSmall ? text.headlineSmall : text.headlineMedium)?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(style: body, children: [
            const TextSpan(text: 'Sign in with one tap using your '),
            TextSpan(text: _providerNames(), style: strong),
            const TextSpan(
              text: ' account. You pick the account on their own sign-in page, so '
                  'CrimiReview ',
            ),
            TextSpan(text: 'never sees your password', style: strong),
            const TextSpan(text: '.'),
          ]),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(style: body, children: [
            const TextSpan(text: 'We only receive your '),
            TextSpan(text: 'name, email address and profile photo', style: strong),
            const TextSpan(
              text: ', for your profile and the leaderboard. Nothing is ever posted '
                  'to your account.',
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          'Already reviewing with that email? You will open your same account, '
          'with all your progress.',
          style: body,
        ),
        // Left out on the smallest phones so the choices stay in reach.
        if (!isSmall) ...[
          const SizedBox(height: 10),
          Text(
            'Note: your quiz results are saved to your own account only. '
            'You can sign out any time in Settings.',
            style: text.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ],
    );
  }

  String _providerNames() {
    final names = [
      for (final provider in SocialProvider.values)
        if (_providers.contains(provider)) provider.label
    ];
    return names.join(' or ');
  }

  Widget _buildChoices(double side) {
    final p = context.palette;
    final text = context.textStyles;
    final providers = SocialProvider.values.where(_providers.contains).toList();
    final buttons = [
      for (final provider in providers)
        _ChoiceButton(
          provider: provider,
          loading: _loading == provider,
          enabled: !_busy,
          onPressed: () => _choose(provider),
        ),
    ];

    // Full-width grey band; its content lines up with the text above.
    return Container(
      decoration: BoxDecoration(
        color: p.background,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: EdgeInsets.fromLTRB(side, 24, side, 20 + MediaQuery.of(context).padding.bottom),
      child: ContentWidth(
        maxWidth: _contentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              InlineBanner(message: _errorMessage!, tone: BannerTone.danger),
              const SizedBox(height: 16),
            ],
            if (isCompletingSignIn) ...[
              const InlineBanner(
                message: 'Signed in. Getting your progress ready...',
                tone: BannerTone.info,
                icon: Icons.sync_rounded,
              ),
              const SizedBox(height: 16),
            ],
            // Wide pills one above the other on phones; side by side on wider
            // screens. Measured from the screen width: a LayoutBuilder can't
            // sit inside the page's fill-the-screen layout (IntrinsicHeight).
            if (buttons.length == 1)
              buttons.first
            else if (math.min(MediaQuery.sizeOf(context).width - 2 * side, _contentWidth) < 520)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [buttons[0], const SizedBox(height: 12), buttons[1]],
              )
            else
              Row(
                children: [
                  Expanded(child: buttons[0]),
                  const SizedBox(width: 14),
                  Expanded(child: buttons[1]),
                ],
              ),
            const SizedBox(height: 18),
            Center(
              child: InkWell(
                onTap: _busy ? null : _useEmail,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    children: [
                      Text(
                        'Use my email instead',
                        style: text.titleMedium?.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '(sign in or create an account with your email and password)',
                        textAlign: TextAlign.center,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A large rounded choice: logo and name, with what it does underneath.
class _ChoiceButton extends StatelessWidget {
  final SocialProvider provider;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  const _ChoiceButton({
    required this.provider,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final logo = switch (provider) {
      SocialProvider.google => const GoogleLogo(size: 22),
      SocialProvider.facebook => const FacebookLogo(size: 23),
    };
    final shape = StadiumBorder(
      side: BorderSide(color: p.textPrimary.withValues(alpha: 0.55), width: 1.2),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Continue with ${provider.label}',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || loading ? 1 : 0.55,
        child: Material(
          color: p.surface,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 24,
                        child: loading
                            ? Padding(
                                padding: const EdgeInsets.all(2),
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: p.primary),
                              )
                            : Center(child: logo),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          provider.label,
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '(use your ${provider.label} account)',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
