import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_progress.dart';
import '../services/theme_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/password_strength_indicator.dart';
import 'home_screen.dart';
import 'email_verification_screen.dart';
import 'forgot_password_screen.dart';

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
  String _password = '';
  
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _supabase = SupabaseService.instance;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
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
              displayName: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
            ),
          ),
        );
        return;
      }
      
      if (mounted && _supabase.isLoggedIn) {
        final storage = StorageService();
        
        // Load full cloud progress (profile + subject progress + achievements)
        final cloudData = await _supabase.loadFullCloudProgress();
        final cloudProfile = cloudData?['profile'];
        
        if (cloudProfile != null) {
          // Sync cloud profile data to local storage
          if (cloudProfile['display_name'] != null) {
            await storage.setUserName(cloudProfile['display_name']);
          }
          if (cloudProfile['email'] != null) {
            await storage.setUserEmail(cloudProfile['email']);
          }
          if (cloudProfile['school'] != null) {
            await storage.setSchool(cloudProfile['school']);
          }
          if (cloudProfile['current_streak'] != null) {
            await storage.setDailyStreak(cloudProfile['current_streak']);
          }
          if (cloudProfile['avatar_url'] != null) {
            await storage.setAvatarUrl(cloudProfile['avatar_url']);
          }
        }
        
        await storage.setOnboardingCompleted(true);
        
        // Load local progress for merging
        final localProgress = await storage.loadProgress();
        int localQuizzes = 0;
        int localCorrect = 0;
        for (final sp in localProgress.subjectProgress.values) {
          localQuizzes += sp.totalQuizzesTaken;
          localCorrect += sp.totalCorrectAnswers;
        }
        
        // Sync cloud subject progress to local
        final cloudSubjectProgress = cloudData?['subjectProgress'] as List<Map<String, dynamic>>?;
        if (cloudSubjectProgress != null && cloudSubjectProgress.isNotEmpty) {
          for (final cloudSp in cloudSubjectProgress) {
            final subjectId = cloudSp['subject_id'] as String?;
            if (subjectId == null) continue;
            
            final cloudAnswered = cloudSp['questions_answered'] as int? ?? 0;
            final cloudCorrectAnswers = cloudSp['correct_answers'] as int? ?? 0;
            final easyCorrect = cloudSp['easy_correct'] as int? ?? 0;
            final easyTotal = cloudSp['easy_total'] as int? ?? 0;
            final mediumCorrect = cloudSp['medium_correct'] as int? ?? 0;
            final mediumTotal = cloudSp['medium_total'] as int? ?? 0;
            final hardCorrect = cloudSp['hard_correct'] as int? ?? 0;
            final hardTotal = cloudSp['hard_total'] as int? ?? 0;
            
            // Get or create local subject progress
            final localSp = localProgress.subjectProgress[subjectId];
            
            // Compare cloud vs local and take higher values
            final mergedAnswered = (localSp?.totalQuestionsAnswered ?? 0) > cloudAnswered 
                ? (localSp?.totalQuestionsAnswered ?? 0) : cloudAnswered;
            final mergedCorrect = (localSp?.totalCorrectAnswers ?? 0) > cloudCorrectAnswers 
                ? (localSp?.totalCorrectAnswers ?? 0) : cloudCorrectAnswers;
            
            // Determine if difficulty levels are passed (70% threshold)
            final easyPassed = easyTotal > 0 && (easyCorrect / easyTotal) >= 0.7;
            final mediumPassed = mediumTotal > 0 && (mediumCorrect / mediumTotal) >= 0.7;
            final hardPassed = hardTotal > 0 && (hardCorrect / hardTotal) >= 0.7;
            
            // Create merged subject progress
            localProgress.subjectProgress[subjectId] = SubjectProgress(
              subjectId: subjectId,
              topicProgress: localSp?.topicProgress ?? {},
              totalQuizzesTaken: localSp?.totalQuizzesTaken ?? 0,
              totalQuestionsAnswered: mergedAnswered,
              totalCorrectAnswers: mergedCorrect,
              lastStudyDate: cloudSp['last_study_date'] != null 
                  ? DateTime.tryParse(cloudSp['last_study_date']) 
                  : localSp?.lastStudyDate,
              easyPassed: easyPassed || (localSp?.easyPassed ?? false),
              mediumPassed: mediumPassed || (localSp?.mediumPassed ?? false),
              hardPassed: hardPassed || (localSp?.hardPassed ?? false),
              wrongQuestionIds: localSp?.wrongQuestionIds ?? {},
            );
          }
        }
        
        // Sync cloud achievements to local
        final cloudAchievements = cloudData?['achievements'] as List<String>?;
        if (cloudAchievements != null && cloudAchievements.isNotEmpty) {
          // Merge cloud achievements with local (union of both)
          final mergedAchievements = <String>{
            ...localProgress.unlockedAchievements,
            ...cloudAchievements,
          };
          localProgress.unlockedAchievements = mergedAchievements.toList();
        }
        
        // Update streak from cloud if higher
        if (cloudProfile != null) {
          final cloudStreak = cloudProfile['current_streak'] as int? ?? 0;
          final cloudBestStreak = cloudProfile['best_streak'] as int? ?? 0;
          if (cloudStreak > localProgress.currentStreak) {
            localProgress.currentStreak = cloudStreak;
          }
          if (cloudBestStreak > localProgress.longestStreak) {
            localProgress.longestStreak = cloudBestStreak;
          }
        }
        
        // Save merged progress to local storage
        await storage.saveProgress(localProgress);
        
        final cloudQuizzes = cloudProfile?['total_quizzes'] ?? 0;
        final cloudCorrect = cloudProfile?['total_correct'] ?? 0;
        final cloudPoints = cloudProfile?['total_points'] ?? 0;
        
        // Sync the higher values to cloud
        await _supabase.syncLocalProgress(
          totalPoints: (localCorrect * 10) > cloudPoints ? (localCorrect * 10) : cloudPoints,
          totalQuizzes: localQuizzes > cloudQuizzes ? localQuizzes : cloudQuizzes,
          totalCorrect: localCorrect > cloudCorrect ? localCorrect : cloudCorrect,
          currentStreak: localProgress.currentStreak,
          bestStreak: localProgress.longestStreak,
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
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _firstNameController,
                            label: 'First Name',
                            icon: Icons.person_outline,
                            isDark: isDark,
                            validator: (v) => v!.isEmpty ? 'Enter first name' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _lastNameController,
                            label: 'Last Name',
                            icon: Icons.person_outline,
                            isDark: isDark,
                            validator: (v) => v!.isEmpty ? 'Enter last name' : null,
                          ),
                        ),
                      ],
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
                    onChanged: (v) => setState(() => _password = v),
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
                      if (!_isLogin) {
                        final result = PasswordStrengthChecker.check(v);
                        if (!result.hasMinLength) return 'At least 8 characters required';
                        if (!result.hasUppercase) return 'Add an uppercase letter';
                        if (!result.hasLowercase) return 'Add a lowercase letter';
                        if (!result.hasNumber) return 'Add a number';
                      } else {
                        if (v.length < 6) return 'Min 6 characters';
                      }
                      return null;
                    },
                  ),
                  
                  // Password strength indicator (only for signup)
                  if (!_isLogin)
                    PasswordStrengthIndicator(
                      password: _password,
                      showRequirements: true,
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
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
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
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
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
