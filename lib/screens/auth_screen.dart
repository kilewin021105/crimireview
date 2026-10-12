import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/app_logo.dart';
import '../models/user_progress.dart';
import '../widgets/ui/ui.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/offline_sync_service.dart';
import '../services/admin_service.dart';
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
        final currentUserId = _supabase.userId;
        final lastUserId = await storage.getLastUserId();
        
        // Check if switching accounts
        if (lastUserId != null && lastUserId != currentUserId) {
          // Different user logging in - sync old user's pending data first
          if (OfflineSyncService.instance.hasPendingSync) {
            await OfflineSyncService.instance.syncPendingOperations();
          }
          // Clear old user's local quiz progress so new user starts fresh
          await storage.clearQuizProgress();
        }
        
        // Save current user ID
        if (currentUserId != null) {
          await storage.setLastUserId(currentUserId);
        }
        
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
            final cloudEasySegments = cloudSp['easy_segments'] as List<dynamic>?;
            final cloudMediumSegments = cloudSp['medium_segments'] as List<dynamic>?;
            final cloudHardSegments = cloudSp['hard_segments'] as List<dynamic>?;
            
            // Get or create local subject progress
            final localSp = localProgress.subjectProgress[subjectId];
            
            // Compare cloud vs local and take higher values
            final mergedAnswered = (localSp?.totalQuestionsAnswered ?? 0) > cloudAnswered 
                ? (localSp?.totalQuestionsAnswered ?? 0) : cloudAnswered;
            final mergedCorrect = (localSp?.totalCorrectAnswers ?? 0) > cloudCorrectAnswers 
                ? (localSp?.totalCorrectAnswers ?? 0) : cloudCorrectAnswers;

            List<SegmentProgress> mergeSegments(List<SegmentProgress>? local, List<dynamic>? cloud) {
              return List.generate(SegmentProgress.segmentCount, (i) {
                final localSeg = local?[i];
                final cloudSegJson = cloud != null && i < cloud.length
                    ? Map<String, dynamic>.from(cloud[i] as Map)
                    : null;
                final cloudSeg = cloudSegJson != null
                    ? SegmentProgress.fromJson(cloudSegJson)
                    : null;

                if (localSeg == null) return cloudSeg ?? SegmentProgress(segmentIndex: i);
                if (cloudSeg == null) return localSeg;

                if (cloudSeg.questionsAnswered > localSeg.questionsAnswered) {
                  return cloudSeg;
                }
                if (localSeg.questionsAnswered > cloudSeg.questionsAnswered) {
                  return localSeg;
                }

                return SegmentProgress(
                  segmentIndex: i,
                  questionsAnswered: localSeg.questionsAnswered,
                  correctAnswers: localSeg.correctAnswers > cloudSeg.correctAnswers
                      ? localSeg.correctAnswers
                      : cloudSeg.correctAnswers,
                );
              });
            }

            final mergedEasySegments = mergeSegments(localSp?.easySegments, cloudEasySegments);
            final mergedMediumSegments = mergeSegments(localSp?.mediumSegments, cloudMediumSegments);
            final mergedHardSegments = mergeSegments(localSp?.hardSegments, cloudHardSegments);
            
            // Determine if difficulty levels are passed (all segments must be passed)
            final easyPassed = mergedEasySegments.every((segment) => segment.isPassed);
            final mediumPassed = mergedMediumSegments.every((segment) => segment.isPassed);
            final hardPassed = mergedHardSegments.every((segment) => segment.isPassed);
            
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
                easyPassed: easyPassed,
                mediumPassed: mediumPassed,
                hardPassed: hardPassed,
              wrongQuestionIds: localSp?.wrongQuestionIds ?? {},
                easyCorrect: easyCorrect > (localSp?.easyCorrect ?? 0)
                  ? easyCorrect
                  : (localSp?.easyCorrect ?? 0),
                easyTotal: easyTotal > (localSp?.easyTotal ?? 0)
                  ? easyTotal
                  : (localSp?.easyTotal ?? 0),
                mediumCorrect: mediumCorrect > (localSp?.mediumCorrect ?? 0)
                  ? mediumCorrect
                  : (localSp?.mediumCorrect ?? 0),
                mediumTotal: mediumTotal > (localSp?.mediumTotal ?? 0)
                  ? mediumTotal
                  : (localSp?.mediumTotal ?? 0),
                hardCorrect: hardCorrect > (localSp?.hardCorrect ?? 0)
                  ? hardCorrect
                  : (localSp?.hardCorrect ?? 0),
                hardTotal: hardTotal > (localSp?.hardTotal ?? 0)
                  ? hardTotal
                  : (localSp?.hardTotal ?? 0),
                easySegments: mergedEasySegments,
                mediumSegments: mergedMediumSegments,
                hardSegments: mergedHardSegments,
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
        
        // Explicitly refreshed (not just left to the reactive listener) so
        // routing here can never race the network call it depends on --
        // this is the moment a role check must be certain, not eventual.
        final isAdmin = await AdminService.instance.refreshRole();
        if (!mounted) return;

        setState(() => _isLoading = false);

        Navigator.of(context).pushReplacement(
          ScalePageRoute(page: isAdmin ? const AdminShellScreen() : const HomeScreen()),
        );
      } else if (mounted) {
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
                            loading: _isLoading,
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
