import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/theme_service.dart';
import '../widgets/app_logo.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/admin_service.dart';
import '../services/post_sign_in_service.dart';
import '../services/social_auth_service.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'sign_in_choice_screen.dart';
import 'admin/admin_shell_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _controller.forward();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // Ask Supabase whether Google/Facebook are switched on while the logo
    // animates, so the right sign-in page opens (see SignInChoiceScreen).
    final providerCheck = SocialAuthService.instance.refreshEnabled();
    await Future.delayed(const Duration(milliseconds: 2500));
    
    if (!mounted) return;
    
    final storageService = StorageService();
    final hasCompletedOnboarding = await storageService.hasCompletedOnboarding();
    
    if (!mounted) return;
    
    Widget nextScreen;
    if (!hasCompletedOnboarding) {
      nextScreen = const OnboardingScreen();
    } else if (SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn) {
      // The role check started in main.dart has had the whole logo
      // animation to finish; this waits at most 3 more seconds, and offline
      // uses the role last confirmed for this account.
      var isAdmin = await AdminService.instance.resolvedRole();

      // A session this phone hasn't set up yet: a Google/Facebook sign-in
      // that finished while the app was closed (Android may close it while
      // the browser is open), or a web sign-in that reloaded the page.
      // Run the same sync the login screen runs, so the right account's
      // data is on the phone before Home opens.
      if (await PostSignInService.instance.needsSetup()) {
        try {
          isAdmin = await PostSignInService.instance.run();
        } catch (e) {
          debugPrint('Post sign-in sync failed at start-up: $e');
        }
      }
      nextScreen = isAdmin ? const AdminShellScreen() : const HomeScreen();
    } else {
      // Waits at most 3 more seconds; offline, the last saved answer is used.
      await providerCheck.timeout(const Duration(seconds: 3), onTimeout: () => null);
      nextScreen = await SignInChoiceScreen.entry();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isSmall = Responsive.isSmallPhone(context);
    final logoSize = isSmall ? 96.0 : 116.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: p.heroGradient),
          child: Stack(
            children: [
              // Soft rings behind the logo.
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: logoSize * 3.2,
                    height: logoSize * 3.2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: logoSize * 2.1,
                    height: logoSize * 2.1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppLogo(size: logoSize)
                        .animate()
                        .scale(
                          begin: const Offset(0.7, 0.7),
                          end: const Offset(1.0, 1.0),
                          duration: 650.ms,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 400.ms),
                    SizedBox(height: isSmall ? 22 : 28),
                    AppWordmark(
                      fontSize: Responsive.fontSize(context, 30),
                      color: Colors.white,
                    )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
                    const SizedBox(height: 8),
                    Text(
                      'Your Criminology board exam reviewer',
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ).animate(delay: 380.ms).fadeIn(duration: 400.ms),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 48,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ).animate(delay: 700.ms).fadeIn(duration: 400.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
