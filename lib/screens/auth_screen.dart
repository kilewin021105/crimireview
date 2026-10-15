import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;
import '../widgets/app_logo.dart';
import '../widgets/brand_logos.dart';
import '../widgets/ui/ui.dart';
import '../services/supabase_service.dart';
import '../services/post_sign_in_service.dart';
import '../services/social_auth_service.dart';
import '../utils/error_messages.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/password_strength_indicator.dart';
import 'home_screen.dart';
import 'admin/admin_shell_screen.dart';
import 'email_verification_screen.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String _password = '';

  /// Google / Facebook buttons to show: only providers switched on in
  /// Supabase, so a student never taps into a "provider not enabled" page.
  Set<SocialProvider> _socialProviders = {};

  /// The provider whose browser page is open, until Supabase reports back.
  SocialProvider? _pendingSocial;

  /// Drives the spinner on that provider's button.
  SocialProvider? _socialLoading;

  /// Set while the after-sign-in sync runs, so it can only run once.
  bool _finishing = false;

  StreamSubscription<AuthState>? _authSubscription;
  Timer? _resumeTimer;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _supabase = SupabaseService.instance;

  bool get _busy => _isLoading || _socialLoading != null || _finishing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (SocialAuthService.isSupportedPlatform) _loadSocialProviders();
    if (SupabaseService.isInitialized) {
      // Google / Facebook sign-in ends here: the browser sends the student
      // back, Supabase swaps the one-time code for a session and reports it.
      _authSubscription = _supabase.authStateChanges.listen(
        _onAuthState,
        onError: _onSocialError,
      );
    }
  }

  Future<void> _loadSocialProviders() async {
    final cached = await SocialAuthService.instance.cachedEnabled();
    if (mounted && cached.isNotEmpty) setState(() => _socialProviders = cached);
    final fresh = await SocialAuthService.instance.refreshEnabled();
    if (mounted && fresh != null) setState(() => _socialProviders = fresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _resumeTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _onAuthState(AuthState state) {
    if (state.event != AuthChangeEvent.signedIn || _finishing || !mounted) return;
    final fromSocial = _pendingSocial != null;
    // A session arriving by itself while this screen is the one showing: a
    // Google/Facebook sign-in that finished after Android restarted the app
    // (slower than the splash screen). Ignored while the password sign-in
    // runs (_isLoading) or when sign-up / forgot-password is open on top,
    // because those screens finish their own sign-in.
    final arrivedOnItsOwn = !_isLoading &&
        _supabase.isLoggedIn &&
        (ModalRoute.of(context)?.isCurrent ?? false);
    if (!fromSocial && !arrivedOnItsOwn) return;
    _pendingSocial = null;
    _resumeTimer?.cancel();
    _finishSignIn();
  }

  void _onSocialError(Object error) {
    final provider = _pendingSocial;
    if (provider == null || !mounted) return;
    _pendingSocial = null;
    _resumeTimer?.cancel();
    setState(() {
      _socialLoading = null;
      _errorMessage = SocialAuthService.instance.describeError(error, provider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser without finishing (closed it, pressed back):
    // stop the spinner after a moment. The moment gives a real sign-in
    // time to arrive; if it arrives later anyway, it still completes.
    if (state != AppLifecycleState.resumed || _pendingSocial == null) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_finishing && _socialLoading != null) {
        setState(() => _socialLoading = null);
      }
    });
  }

  Future<void> _socialSignIn(SocialProvider provider) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _socialLoading = provider;
      _errorMessage = null;
    });
    try {
      _pendingSocial = provider;
      await SocialAuthService.instance.start(provider);
    } catch (e) {
      _pendingSocial = null;
      if (!mounted) return;
      setState(() {
        _socialLoading = null;
        _errorMessage = SocialAuthService.instance.describeError(e, provider);
      });
    }
  }

  /// Shared by every sign-in method: sync this account's data onto the
  /// phone (PostSignInService), then open the admin or student home.
  Future<void> _finishSignIn() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final isAdmin = await PostSignInService.instance.run();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        ScalePageRoute(page: isAdmin ? const AdminShellScreen() : const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = friendlyError(e, fallback: 'Sign in failed. Please try again.');
      });
    } finally {
      if (mounted) {
        setState(() {
          _finishing = false;
          _isLoading = false;
          _socialLoading = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    // Typing a password instead: forget an unfinished Google/Facebook try.
    _pendingSocial = null;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      if (_isLogin) {
        await _supabase.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        // For signup, go to email verification first
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          SlidePageRoute(
            page: EmailVerificationScreen(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              displayName: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
            ),
          ),
        );
        return;
      }
      
      if (!mounted) return;
      if (_supabase.isLoggedIn) {
        await _finishSignIn();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Account created! Please sign in.';
          _isLogin = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyError(e, fallback: 'Sign in failed. Please try again.');
      });
    }
  }

  void _toggleMode(bool login) {
    if (_isLogin == login) return;
    setState(() {
      _isLogin = login;
      _errorMessage = null;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final isSmall = Responsive.isSmallPhone(context);
    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + (isSmall ? 200.0 : 236.0);
    final isSuccessMessage = _errorMessage != null && _errorMessage!.contains('created');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Stack(
            children: [
              // Brand header
              Container(
                height: headerHeight,
                width: double.infinity,
                decoration: BoxDecoration(gradient: p.heroGradient),
                child: Stack(
                  children: [
                    Positioned(
                      right: -60,
                      top: -40,
                      child: _circle(200, Colors.white.withValues(alpha: 0.06)),
                    ),
                    Positioned(
                      left: -50,
                      bottom: -20,
                      child: _circle(140, Colors.white.withValues(alpha: 0.05)),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, topInset + (isSmall ? 20 : 30), 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppLogo(size: isSmall ? 44 : 52, showShadow: false),
                          SizedBox(height: isSmall ? 14 : 20),
                          Text(
                            _isLogin ? 'Welcome back' : 'Create your account',
                            style: text.headlineMedium?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isLogin
                                ? 'Sign in to continue your board exam review.'
                                : 'Start reviewing for the board exam in minutes.',
                            style: text.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Form sheet
              Container(
                margin: EdgeInsets.only(top: headerHeight - 28),
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - headerHeight + 28,
                ),
                decoration: BoxDecoration(
                  color: p.background,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpace.radiusXl)),
                ),
                child: ContentWidth(
                  maxWidth: 480,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isSmall ? 18 : 24,
                      24,
                      isSmall ? 18 : 24,
                      24 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PillTabs(
                            labels: const ['Sign in', 'Create account'],
                            index: _isLogin ? 0 : 1,
                            onChanged: (i) => _toggleMode(i == 0),
                          ),
                          const SizedBox(height: 24),
                          if (_socialProviders.isNotEmpty) ...[
                            _buildSocialButtons(),
                            const SizedBox(height: 20),
                            _orDivider(),
                            const SizedBox(height: 20),
                          ],
                          if (!_isLogin) ...[
                            _buildNameFields(),
                            const SizedBox(height: 16),
                          ],
                          AppTextField(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'you@example.com',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            validator: (v) {
                              if (v!.isEmpty) return 'Enter your email';
                              if (!v.contains('@')) return 'Invalid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: _isLogin ? 'Enter your password' : '8 to 16 characters',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: [
                              _isLogin ? AutofillHints.password : AutofillHints.newPassword,
                            ],
                            onChanged: (v) => setState(() => _password = v),
                            onSubmitted: (_) {
                              if (!_isLoading) _submit();
                            },
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) {
                              if (v!.isEmpty) return 'Enter your password';
                              if (!_isLogin) {
                                final result = PasswordStrengthChecker.check(v);
                                if (!result.hasMinLength) return 'At least 8 characters required';
                                if (!result.hasMaxLength) return 'Max 16 characters allowed';
                                if (!result.hasUppercase) return 'Add an uppercase letter';
                                if (!result.hasLowercase) return 'Add a lowercase letter';
                                if (!result.hasNumber) return 'Add a number';
                              } else {
                                if (v.length < 6) return 'Min 6 characters';
                              }
                              return null;
                            },
                          ),
                          if (_isLogin)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Forgot password?'),
                              ),
                            )
                          else
                            PasswordStrengthIndicator(
                              password: _password,
                              showRequirements: true,
                            ),
                          SizedBox(height: _isLogin ? 8 : 20),
                          if (_errorMessage != null) ...[
                            InlineBanner(
                              message: _errorMessage!,
                              tone: isSuccessMessage ? BannerTone.success : BannerTone.danger,
                            ),
                            const SizedBox(height: 16),
                          ],
                          PrimaryButton(
                            label: _isLogin ? 'Sign in' : 'Create account',
                            loading: _isLoading && _socialLoading == null,
                            onPressed: _busy ? null : _submit,
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _isLogin ? "Don't have an account? " : 'Already have an account? ',
                                style: text.bodyMedium,
                              ),
                              InkWell(
                                onTap: () => _toggleMode(!_isLogin),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                  child: Text(
                                    _isLogin ? 'Create one' : 'Sign in',
                                    style: text.labelLarge?.copyWith(color: p.primary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  /// "Google" and "Facebook" side by side (stacked on very narrow
  /// screens). The same buttons create an account on first use, so they
  /// appear on both tabs.
  Widget _buildSocialButtons() {
    final providers = SocialProvider.values.where(_socialProviders.contains).toList();
    final buttons = [
      for (final provider in providers)
        _SocialButton(
          provider: provider,
          // One provider gets the room for the full label.
          label: providers.length == 1 ? 'Continue with ${provider.label}' : provider.label,
          loading: _socialLoading == provider,
          onPressed: _busy ? null : () => _socialSignIn(provider),
        ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (buttons.length == 1) return buttons.first;
      if (c.maxWidth < 300) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [buttons[0], const SizedBox(height: 10), buttons[1]],
        );
      }
      return Row(children: [
        Expanded(child: buttons[0]),
        const SizedBox(width: 12),
        Expanded(child: buttons[1]),
      ]);
    });
  }

  Widget _orDivider() {
    final p = context.palette;
    return Row(
      children: [
        Expanded(child: Divider(color: p.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or use your email', style: context.textStyles.bodySmall),
        ),
        Expanded(child: Divider(color: p.border, height: 1)),
      ],
    );
  }

  Widget _buildNameFields() {
    final first = AppTextField(
      controller: _firstNameController,
      label: 'First name',
      hint: 'Juan',
      maxLength: 30,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.givenName],
      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter first name' : null,
    );
    final last = AppTextField(
      controller: _lastNameController,
      label: 'Last name',
      hint: 'Dela Cruz',
      maxLength: 30,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.familyName],
      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter last name' : null,
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 300) {
        return Column(children: [first, const SizedBox(height: 16), last]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: last),
        ],
      );
    });
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Outlined button with the provider's own logo, styled like the app's
/// [SecondaryButton] so it sits naturally next to the form.
class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.provider,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final logo = switch (provider) {
      SocialProvider.google => const GoogleLogo(size: 20),
      SocialProvider.facebook => const FacebookLogo(size: 21),
    };
    return Semantics(
      button: true,
      label: 'Continue with ${provider.label}',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: p.textPrimary,
          backgroundColor: p.surface,
          disabledForegroundColor: p.textSecondary,
          side: BorderSide(color: p.border, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 21,
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: p.primary),
                    )
                  : Center(child: logo),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
