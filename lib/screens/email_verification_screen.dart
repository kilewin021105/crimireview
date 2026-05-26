import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_service.dart';
import '../services/email_verification_service.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String password;
  final String? displayName;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.password,
    this.displayName,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  
  final _emailService = EmailVerificationService.instance;
  final _supabase = SupabaseService.instance;
  
  bool _isLoading = false;
  bool _isResending = false;
  bool _isVerifying = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _sendVerificationEmail();
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendVerificationEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    final result = await _emailService.sendVerificationEmail(widget.email);
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success'] == true) {
          _startCooldown();
        } else {
          _errorMessage = result['error'] ?? 'Failed to send verification email. Please try again.';
        }
      });
    }
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;
    
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    
    final result = await _emailService.resendCode(widget.email);
    
    if (mounted) {
      setState(() {
        _isResending = false;
        if (result['success'] == true) {
          _startCooldown();
          _clearCode();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Verification code sent!', style: GoogleFonts.poppins()),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          _errorMessage = result['error'] ?? 'Failed to resend code. Please try again.';
        }
      });
    }
  }

  void _clearCode() {
    for (var c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  String _getCode() {
    return _controllers.map((c) => c.text).join();
  }

  Future<void> _verifyCode() async {
    final code = _getCode();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete code');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    final result = await _emailService.verifyCode(widget.email, code);

    if (result['success'] != true) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = result['error'] ?? 'Invalid or expired code. Please try again.';
        });
        HapticFeedback.heavyImpact();
        _clearCode();
      }
      return;
    }

    // Code is valid, proceed with signup
    try {
      final response = await _supabase.signUp(
        email: widget.email,
        password: widget.password,
        displayName: widget.displayName ?? '',
      );

      // Auto sign in after signup
      if (response.session == null) {
        await _supabase.signIn(
          email: widget.email,
          password: widget.password,
        );
      }

      if (mounted && _supabase.isLoggedIn) {
        // Ensure profile exists in database for leaderboard
        await _supabase.ensureProfileExists(displayName: widget.displayName);
        
        final storage = StorageService();
        if (widget.displayName != null && widget.displayName!.isNotEmpty) {
          await storage.setUserName(widget.displayName!);
        }
        await storage.setOnboardingCompleted(true);

        // Sync local progress
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

        HapticFeedback.heavyImpact();
        Navigator.of(context).pushAndRemoveUntil(
          ScalePageRoute(page: const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    
    // Auto-verify when all digits entered
    if (_getCode().length == 6) {
      _verifyCode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmall = Responsive.isSmallPhone(context);
    final padding = Responsive.horizontalPadding(context);
    final iconContainerSize = isSmall ? 80.0 : 100.0;
    final iconSize = isSmall ? 38.0 : 48.0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: isSmall ? 12 : 20),
                    
                    // Email icon
                    Container(
                      width: iconContainerSize,
                      height: iconContainerSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withOpacity(0.15),
                            AppColors.accentDark.withOpacity(0.15),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_email_read_rounded,
                        size: iconSize,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Title
                    Text(
                      'Verify Your Email',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Subtitle
                    Text(
                      'We sent a 6-digit code to',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.email,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Code input - responsive
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final boxSize = ((maxWidth - 40) / 6).clamp(40.0, 52.0);
                        final fontSize = boxSize * 0.45;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            return Container(
                              width: boxSize,
                              height: boxSize * 1.15,
                              margin: EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                cursorColor: AppColors.accent,
                                style: GoogleFonts.poppins(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  filled: true,
                                  fillColor: isDark ? AppColors.darkCard : Colors.white,
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: AppColors.accent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (value) => _onCodeChanged(index, value),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // Error message
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
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
                      const SizedBox(height: 24),
                    ],
                    
                    // Verify button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isVerifying ? null : _verifyCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Verify Email',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Resend code
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Didn't receive the code? ",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                        GestureDetector(
                          onTap: _resendCooldown > 0 || _isResending ? null : _resendCode,
                          child: _isResending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _resendCooldown > 0
                                      ? 'Resend in ${_resendCooldown}s'
                                      : 'Resend',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _resendCooldown > 0
                                        ? Colors.grey
                                        : AppColors.accent,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    
                    // Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Check your spam folder if you don\'t see the email in your inbox.',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
