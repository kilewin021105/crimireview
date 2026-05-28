import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/email_verification_service.dart';
import '../services/supabase_service.dart';
import '../services/theme_service.dart';
import '../widgets/password_strength_indicator.dart';

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
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $email'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
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
        password,
      );
      
      // Clean up reset records
      await _emailService.cleanupPasswordResets(_emailController.text.trim());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password reset successfully! Please login.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to reset password. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeService>(context).isDarkMode;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reset Password',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress indicator
              _buildProgressIndicator(isDark),
              const SizedBox(height: 32),
              
              // Step content
              if (_currentStep == 0) _buildEmailStep(isDark),
              if (_currentStep == 1) _buildCodeStep(isDark),
              if (_currentStep == 2) _buildPasswordStep(isDark),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.poppins(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(bool isDark) {
    return Row(
      children: [
        _buildStepDot(0, isDark),
        Expanded(child: _buildStepLine(0, isDark)),
        _buildStepDot(1, isDark),
        Expanded(child: _buildStepLine(1, isDark)),
        _buildStepDot(2, isDark),
      ],
    );
  }

  Widget _buildStepDot(int step, bool isDark) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? AppColors.accent : (isDark ? AppColors.darkCard : Colors.grey[300]),
        border: isCurrent ? Border.all(color: AppColors.accent, width: 3) : null,
      ),
      child: Center(
        child: isActive && !isCurrent
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '${step + 1}',
                style: GoogleFonts.poppins(
                  color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.grey[600]),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  Widget _buildStepLine(int afterStep, bool isDark) {
    final isActive = _currentStep > afterStep;
    
    return Container(
      height: 3,
      color: isActive ? AppColors.accent : (isDark ? AppColors.darkCard : Colors.grey[300]),
    );
  }

  Widget _buildEmailStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your email',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We\'ll send a 6-digit verification code to your email address.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: isDark ? Colors.white60 : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 32),
        
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: isDark ? Colors.white60 : AppColors.textMuted,
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendResetCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Send Code',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter verification code',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code sent to ${_emailController.text}',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: isDark ? Colors.white60 : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 32),
        
        // OTP Input
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 12,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
              color: isDark ? Colors.white24 : Colors.grey[300],
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Verify Code',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _sendResetCode,
            child: Text(
              'Didn\'t receive the code? Resend',
              style: GoogleFonts.poppins(
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create new password',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Create a strong password with at least 8 characters.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: isDark ? Colors.white60 : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 32),
        
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: (v) => setState(() => _password = v),
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            labelText: 'New Password',
            labelStyle: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: isDark ? Colors.white60 : AppColors.textMuted,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: isDark ? Colors.white60 : AppColors.textMuted,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
        
        // Password strength indicator
        PasswordStrengthIndicator(
          password: _password,
          showRequirements: true,
        ),
        
        const SizedBox(height: 20),
        
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            labelStyle: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: isDark ? Colors.white60 : AppColors.textMuted,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                color: isDark ? Colors.white60 : AppColors.textMuted,
              ),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Reset Password',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
