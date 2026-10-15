import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/app_logo.dart';
import '../widgets/ui/ui.dart';
import '../services/supabase_service.dart';
import '../utils/error_messages.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/password_strength_indicator.dart';
import 'email_verification_screen.dart';
import 'forgot_password_screen.dart';
import 'sign_in_completion.dart';

/// The email + password form (sign in / create account).
///
/// Google and Facebook are not on this page: they have their own page,
/// `SignInChoiceScreen`, shown before this one when they are switched on.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SignInCompletion {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String _password = '';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _supabase = SupabaseService.instance;

  @override
  bool get signingInItself => _isLoading;

  @override
  void onSignInFailed(String message) => setState(() => _errorMessage = message);

  @override
  void initState() {
    super.initState();
    // Catches a Google/Facebook sign-in that finishes while this page is
    // the one showing (see SignInCompletion).
    watchForSessions();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading || isCompletingSignIn) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    if (!_isLogin) {
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

    try {
      await _supabase.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyError(e, fallback: 'Sign in failed. Please try again.');
      });
      return;
    }
    if (!mounted) return;

    if (_supabase.isLoggedIn) {
      // Still "loading" while the shared sync runs, so the session event
      // from this same sign-in isn't picked up a second time.
      await completeSignIn();
      if (mounted) setState(() => _isLoading = false);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Account created! Please sign in.';
        _isLogin = true;
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
                          Row(
                            children: [
                              // Back to "Decide how you sign in" when opened from it.
                              if (Navigator.of(context).canPop()) ...[
                                IconButton(
                                  tooltip: 'Back',
                                  onPressed: () => Navigator.of(context).maybePop(),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                const SizedBox(width: 12),
                              ],
                              AppLogo(size: isSmall ? 44 : 52, showShadow: false),
                            ],
                          ),
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
                            loading: _isLoading || isCompletingSignIn,
                            onPressed: _submit,
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
