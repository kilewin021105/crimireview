import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/storage_service.dart';
import '../utils/page_transitions.dart';
import '../widgets/app_logo.dart';
import '../widgets/ui/ui.dart';
import 'sign_in_choice_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = const [
    OnboardingPage(
      icon: Icons.menu_book_rounded,
      title: 'Review smarter for the board exam',
      description:
          'All six Criminology board subjects in one place, with quizzes, flashcards and study notes you can use anywhere.',
      color: Color(0xFF2449D8),
      tags: ['6 board subjects', 'Works offline'],
    ),
    OnboardingPage(
      icon: Icons.psychology_rounded,
      title: 'Practice that adapts to you',
      description:
          'CrimiReview tracks what you have mastered and serves the questions you still need, at the right difficulty.',
      color: Color(0xFF7C4DDB),
      tags: ['Finds weak spots', 'Never repeats'],
    ),
    OnboardingPage(
      icon: Icons.emoji_events_rounded,
      title: 'Stay motivated every day',
      description:
          'Keep your streak alive, take the Daily Challenge for bonus points and climb the leaderboard.',
      color: Color(0xFFC08A0E),
      tags: ['Daily streaks', 'Leaderboard'],
    ),
    OnboardingPage(
      icon: Icons.insights_rounded,
      title: 'Know when you are ready',
      description:
          'See your accuracy per subject and your overall board exam readiness, so you study where it counts.',
      color: Color(0xFF0E9F9A),
      tags: ['Exam readiness', 'Clear stats'],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding() async {
    final storageService = StorageService();
    await storageService.setOnboardingCompleted(true);
    // "Decide how you sign in" when Google/Facebook are on, else the email form.
    final signIn = await SignInChoiceScreen.entry();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      ScalePageRoute(page: signIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                child: Row(
                  children: [
                    const AppLogo(size: 34, showShadow: false),
                    const SizedBox(width: 10),
                    const AppWordmark(fontSize: 18),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        onPressed: isLast ? null : _completeOnboarding,
                        style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) => _buildPage(_pages[index]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  children: [
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.only(right: 6),
                          width: _currentPage == index ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index ? p.primary : p.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: isLast ? 'Get started' : 'Next',
                      icon: Icons.arrow_forward_rounded,
                      trailingIcon: true,
                      expand: false,
                      onPressed: _nextPage,
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

  Widget _buildPage(OnboardingPage page) {
    // Short screens get a shorter illustration; scrolling is the last
    // resort so the description is never cut off.
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = (constraints.maxHeight * 0.52).clamp(150.0, 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: art, child: _Illustration(page: page)),
                SizedBox(height: art < 220 ? 20 : 32),
                Text(page.title, style: context.textStyles.headlineMedium)
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 350.ms)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 12),
                Text(
                  page.description,
                  style: context.textStyles.bodyLarge?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 220.ms, duration: 350.ms)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Illustration extends StatelessWidget {
  final OnboardingPage page;

  const _Illustration({required this.page});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final tint = page.color.withValues(alpha: dark ? 0.22 : 0.10);
    return LayoutBuilder(builder: (context, c) {
      final circle = (c.maxHeight * 0.46).clamp(70.0, 150.0);
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(AppSpace.radiusXl),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: -c.maxHeight * 0.18,
              top: -c.maxHeight * 0.22,
              child: _ring(c.maxHeight * 0.7, page.color.withValues(alpha: 0.10)),
            ),
            Positioned(
              left: -c.maxHeight * 0.2,
              bottom: -c.maxHeight * 0.3,
              child: _ring(c.maxHeight * 0.8, page.color.withValues(alpha: 0.08)),
            ),
            Container(
              width: circle,
              height: circle,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color.lerp(page.color, Colors.white, 0.18)!, page.color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: page.color.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(page.icon, color: Colors.white, size: circle * 0.46),
            )
                .animate()
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  duration: 450.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 300.ms),
            if (c.maxHeight > 190) ...[
              Positioned(
                left: 18,
                top: c.maxHeight * 0.16,
                child: _tag(context, page.tags.first, Icons.check_circle_rounded)
                    .animate()
                    .fadeIn(delay: 250.ms, duration: 350.ms)
                    .slideX(begin: -0.2, end: 0),
              ),
              Positioned(
                right: 18,
                bottom: c.maxHeight * 0.14,
                child: _tag(context, page.tags.last, Icons.bolt_rounded)
                    .animate()
                    .fadeIn(delay: 350.ms, duration: 350.ms)
                    .slideX(begin: 0.2, end: 0),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 22),
        ),
      );

  Widget _tag(BuildContext context, String label, IconData icon) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: page.color),
          const SizedBox(width: 6),
          Text(label, style: context.textStyles.labelMedium?.copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final List<String> tags;

  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.tags,
  });
}
