import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';
import 'email_verification_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _supabase = SupabaseService.instance;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
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
              displayName: _nameController.text.trim(),
            ),
          ),
        );
        return;
      }
      
      if (mounted && _supabase.isLoggedIn) {
        final storage = StorageService();
        if (!_isLogin && _nameController.text.isNotEmpty) {
          await storage.setUserName(_nameController.text);
        }
        await storage.setOnboardingCompleted(true);
        
        final progress = await storage.loadProgress();
        int totalQuizzes = 0;
        int totalCorrect = 0;
        for (final sp in progress.subjectProgress.values) {
          totalQuizzes += sp.totalQuizzesTaken;
          totalCorrect += sp.totalCorrectAnswers;
        }
        await _supabase.syncLocalProgress(
          totalPoints: totalCorrect * 10,
          totalQuizzes: totalQuizzes,
          totalCorrect: totalCorrect,
          currentStreak: progress.currentStreak,
          bestStreak: progress.longestStreak,
        );
        
        setState(() => _isLoading = false);
        
        Navigator.of(context).pushReplacement(
          ScalePageRoute(page: const HomeScreen()),
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Account created! Please sign in.';
          _isLogin = true;
        });
      }
    } catch (e) {
      String errorMsg = e.toString();
      
      if (errorMsg.contains('Invalid login')) {
        errorMsg = 'Invalid email or password';
      } else if (errorMsg.contains('already registered')) {
        errorMsg = 'This email is already registered. Try logging in.';
      } else if (errorMsg.contains('Email not confirmed')) {
        errorMsg = 'Please check your email and confirm your account.';
      } else if (errorMsg.contains('SocketException') || 
                 errorMsg.contains('host lookup') || 
                 errorMsg.contains('Failed host lookup') ||
                 errorMsg.contains('ClientException') ||
                 errorMsg.contains('No address associated')) {
        errorMsg = 'Unable to connect. Please check your internet connection.';
      } else if (errorMsg.contains('timeout')) {
        errorMsg = 'Connection timed out. Please try again.';
      } else if (errorMsg.contains('email_not_confirmed')) {
        errorMsg = 'Please confirm your email before signing in.';
      } else if (errorMsg.contains('user_already_exists')) {
        errorMsg = 'This email is already registered.';
      } else if (errorMsg.contains('weak_password')) {
        errorMsg = 'Password is too weak. Use at least 6 characters.';
      } else if (errorMsg.contains('invalid_email')) {
        errorMsg = 'Please enter a valid email address.';
      } else if (errorMsg.contains('rate limit') || errorMsg.contains('rate_limit')) {
        errorMsg = 'Too many attempts. Please wait a moment and try again.';
      } else {
        errorMsg = errorMsg
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', '')
            .replaceAll('AuthApiException: ', '');
      }
      
      setState(() {
        _isLoading = false;
        _errorMessage = errorMsg;
      });
    }
  }

  void _showForgotPasswordDialog(bool isDark) {
    final resetEmailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reset Password',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your email address and we\'ll send you a link to reset your password.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark ? Colors.white70 : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: isDark ? Colors.white : AppColors.textDark),
              decoration: InputDecoration(
                hintText: 'Email address',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                filled: true,
                fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: isDark ? Colors.white60 : AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid email'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                await _supabase.resetPassword(email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Password reset link sent to $email'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to send reset link. Try again.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Send Link',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmall = Responsive.isSmallPhone(context);
    final logoSize = isSmall ? 80.0 : 100.0;
    final iconSize = isSmall ? 44.0 : 56.0;
    final titleSize = Responsive.fontSize(context, 28);
    final padding = Responsive.horizontalPadding(context);
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: isSmall ? 32 : 48),
                  
                  Center(
                    child: Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1a365d).withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.school,
                        size: iconSize,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: isSmall ? 24 : 32),
                  
                  Text(
                    _isLogin ? 'Welcome Back' : 'Create Account',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    _isLogin 
                      ? 'Sign in to continue' 
                      : 'Start your review journey',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 15),
                      color: isDark ? Colors.white60 : AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: isSmall ? 32 : 40),
                  
                  if (!_isLogin) ...[
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_outline,
                      isDark: isDark,
                      validator: (v) => v!.isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v!.isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    isDark: isDark,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: isDark ? Colors.white38 : Colors.grey,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v!.isEmpty) return 'Enter your password';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: AppColors.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isLogin ? 'Sign In' : 'Sign Up',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  
                  if (_isLogin) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => _showForgotPasswordDialog(isDark),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.poppins(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin ? "Don't have an account? " : "Already have an account? ",
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white60 : AppColors.textMuted,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _errorMessage = null;
                          });
                          HapticFeedback.lightImpact();
                        },
                        child: Text(
                          _isLogin ? 'Sign Up' : 'Sign In',
                          style: GoogleFonts.poppins(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: isDark ? Colors.white : AppColors.textDark,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.white60 : AppColors.textMuted,
        ),
        prefixIcon: Icon(
          icon, 
          color: AppColors.accent,
          size: 22,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}
