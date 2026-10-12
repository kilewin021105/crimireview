import 'package:flutter/material.dart';
import '../services/email_verification_service.dart';
import '../services/supabase_service.dart';
import '../utils/error_messages.dart';
import '../widgets/password_strength_indicator.dart';
import '../widgets/ui/ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  final _emailService = EmailVerificationService.instance;
  final _supabase = SupabaseService.instance;
  
  // Steps: 0 = email, 1 = code verification, 2 = new password
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _password = '';
  
  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    final result = await _emailService.sendPasswordResetEmail(email);
    
    if (mounted) {
      if (result['success'] == true) {
        setState(() {
          _isLoading = false;
          _currentStep = 1;
        });
        
        showAppSnack(context, 'Verification code sent to $email', tone: BannerTone.success);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['error'] ?? 'Failed to send code. Please try again.';
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    
    if (code.isEmpty || code.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    final result = await _emailService.verifyPasswordResetCode(
      _emailController.text.trim(),
      code,
    );
    
    if (mounted) {
      if (result['success'] == true) {
        setState(() {
          _isLoading = false;
          _currentStep = 2;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['error'] ?? 'Invalid code. Please try again.';
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    
    // Validate password strength
    final result = PasswordStrengthChecker.check(password);
    if (!result.hasMinLength) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }
    if (!result.hasMaxLength) {
      setState(() => _errorMessage = 'Password must be at most 16 characters');
      return;
    }
    if (!result.hasUppercase) {
      setState(() => _errorMessage = 'Password must contain an uppercase letter');
      return;
    }
    if (!result.hasLowercase) {
      setState(() => _errorMessage = 'Password must contain a lowercase letter');
      return;
    }
    if (!result.hasNumber) {
      setState(() => _errorMessage = 'Password must contain a number');
      return;
    }
    
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // Update password via Supabase RPC function
      await _supabase.resetUserPassword(
        _emailController.text.trim(),
        _codeController.text.trim(),
        password,
      );
      
      if (mounted) {
        showAppSnack(context, 'Password reset successfully! Please sign in.', tone: BannerTone.success);
        
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = friendlyError(e, fallback: 'Failed to reset password. Please try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    const steps = [
      (Icons.mail_outline_rounded, 'Enter your email', 'We will send a 6-digit code to the email address on your account.'),
      (Icons.pin_outlined, 'Enter the code', null),
      (Icons.key_rounded, 'Create a new password', 'Use 8 to 16 characters with uppercase, lowercase and a number.'),
    ];
    final step = steps[_currentStep];

    return Scaffold(
      appBar: AppTopBar(
        title: 'Reset password',
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ContentWidth(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StepProgress(current: _currentStep, total: 3),
                const SizedBox(height: 28),
                IconBadge(icon: step.$1, size: 56, radius: 18),
                const SizedBox(height: 18),
                Text(step.$2, style: text.headlineSmall),
                const SizedBox(height: 6),
                if (_currentStep == 1)
                  Text.rich(
                    TextSpan(
                      text: 'We sent a 6-digit code to ',
                      children: [
                        TextSpan(
                          text: _emailController.text.trim(),
                          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: '. It expires in 10 minutes.'),
                      ],
                    ),
                    style: text.bodyMedium,
                  )
                else
                  Text(step.$3!, style: text.bodyMedium),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_currentStep),
                    child: switch (_currentStep) {
                      0 => _buildEmailStep(),
                      1 => _buildCodeStep(),
                      _ => _buildPasswordStep(),
                    },
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  InlineBanner(message: _errorMessage!, tone: BannerTone.danger),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _emailController,
          label: 'Email address',
          hint: 'you@example.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_isLoading) _sendResetCode();
          },
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Send code',
          loading: _isLoading,
          onPressed: _sendResetCode,
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeInput(
          controller: _codeController,
          autofocus: true,
          hasError: _errorMessage != null,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          onCompleted: (_) {
            if (!_isLoading) _verifyCode();
          },
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Verify code',
          loading: _isLoading,
          onPressed: _verifyCode,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _sendResetCode,
            child: const Text("Didn't get it? Resend code"),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _passwordController,
          label: 'New password',
          hint: '8 to 16 characters',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (v) => setState(() => _password = v),
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        PasswordStrengthIndicator(
          password: _password,
          showRequirements: true,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _confirmPasswordController,
          label: 'Confirm password',
          hint: 'Type it again',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscureConfirmPassword,
          suffix: IconButton(
            icon: Icon(
              _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Reset password',
          loading: _isLoading,
          onPressed: _resetPassword,
        ),
      ],
    );
  }
}
