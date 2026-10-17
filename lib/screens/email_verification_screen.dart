import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/email_verification_service.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../services/offline_sync_service.dart';
import '../services/mastery_service.dart';
import '../services/question_selection_service.dart';
import '../utils/error_messages.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
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
  // One field behind the six boxes (see CodeInput), so pasting the whole
  // code from the email works.
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  final _emailService = EmailVerificationService.instance;
  final _supabase = SupabaseService.instance;

  bool _isLoading = false;
  bool _isResending = false;
  bool _isVerifying = false;

  /// The server accepted the code. Kept so that, if creating the account
  /// then fails (slow connection), tapping Verify again retries the
  /// account step instead of re-checking a code that is already used up.
  bool _codeAccepted = false;
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
    _codeController.dispose();
    _codeFocus.dispose();
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
          _codeAccepted = false;
          _startCooldown();
          _clearCode();
          showAppSnack(context, 'Verification code sent!', tone: BannerTone.success);
        } else {
          _errorMessage = result['error'] ?? 'Failed to resend code. Please try again.';
        }
      });
    }
  }

  void _clearCode() {
    _codeController.clear();
    _codeFocus.requestFocus();
  }

  String _getCode() {
    return _codeController.text;
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

    if (!_codeAccepted) {
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
      _codeAccepted = true;
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
        final currentUserId = _supabase.userId;
        final lastUserId = await storage.getLastUserId();

        // Check if switching accounts (new signup on device that had another user)
        if (lastUserId != null && lastUserId != currentUserId) {
          // Different user - sync old user's pending data, then clear local progress
          if (OfflineSyncService.instance.hasPendingSync) {
            await OfflineSyncService.instance.syncPendingOperations();
          }
          await storage.clearQuizProgress();
          // The previous student's learning models too (phone copy only).
          await MasteryService.instance.forgetLocalForAccountSwitch();
          await QuestionSelectionService.instance.forgetLocalForAccountSwitch();
        }

        // Save current user ID
        if (currentUserId != null) {
          await storage.setLastUserId(currentUserId);
        }

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
        // The account exists and is signed in by now, so a slow or failed
        // upload must not turn into "Could not create your account": the
        // totals are uploaded again at the next sign-in or finished quiz.
        try {
          await _supabase.syncLocalProgress(
            totalPoints: totalCorrect * 10,
            totalQuizzes: totalQuizzes,
            totalCorrect: totalCorrect,
            currentStreak: progress.currentStreak,
            bestStreak: progress.longestStreak,
          );
        } catch (e) {
          debugPrint('Progress upload after sign-up skipped: $e');
        }

        if (!mounted) return;
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
          _errorMessage = friendlyError(e, fallback: 'Could not create your account. Please try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final isSmall = Responsive.isSmallPhone(context);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(title: 'Verify email', onBack: () => Navigator.pop(context)),
      body: _isLoading
          ? const LoadingView(label: 'Sending your code...')
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 24),
                child: ContentWidth(
                  maxWidth: 480,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: isSmall ? 4 : 12),
                      IconBadge(
                        icon: Icons.mark_email_unread_rounded,
                        size: isSmall ? 56 : 64,
                        radius: 20,
                      ),
                      const SizedBox(height: 20),
                      Text('Check your email', style: text.headlineMedium),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          text: 'Enter the 6-digit code we sent to ',
                          children: [
                            TextSpan(
                              text: widget.email,
                              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      CodeInput(
                        controller: _codeController,
                        focusNode: _codeFocus,
                        autofocus: true,
                        enabled: !_isVerifying,
                        hasError: _errorMessage != null,
                        onChanged: (_) {
                          if (_errorMessage != null) setState(() => _errorMessage = null);
                        },
                        onCompleted: (_) {
                          if (!_isVerifying) _verifyCode();
                        },
                      ),
                      const SizedBox(height: 20),
                      if (_errorMessage != null) ...[
                        InlineBanner(message: _errorMessage!, tone: BannerTone.danger),
                        const SizedBox(height: 20),
                      ],
                      PrimaryButton(
                        label: 'Verify email',
                        loading: _isVerifying,
                        onPressed: _verifyCode,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.center,
                          children: [
                            Text("Didn't receive the code? ", style: text.bodyMedium),
                            if (_isResending)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: p.primary),
                              )
                            else
                              InkWell(
                                onTap: _resendCooldown > 0 ? null : _resendCode,
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                  child: Text(
                                    _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend',
                                    style: text.labelLarge?.copyWith(
                                      color: _resendCooldown > 0 ? p.textTertiary : p.primary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const InlineBanner(
                        tone: BannerTone.neutral,
                        icon: Icons.inbox_rounded,
                        message:
                            "Can't find it? Check your Spam or Promotions folder. The code expires in 10 minutes.",
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
