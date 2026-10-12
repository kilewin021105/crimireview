import 'package:flutter/material.dart';

/// Shared-axis style transition: the new page slides a short distance
/// while it fades in, and the page underneath drifts slightly the other way
/// (the motion pattern modern Material and iOS apps use).
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final SlideDirection direction;

  SlidePageRoute({
    required this.page,
    this.direction = SlideDirection.right,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // A short slide (not the full screen width) reads as modern.
            Offset begin;
            switch (direction) {
              case SlideDirection.right:
                begin = const Offset(0.16, 0.0);
                break;
              case SlideDirection.left:
                begin = const Offset(-0.16, 0.0);
                break;
              case SlideDirection.up:
                begin = const Offset(0.0, 0.10);
                break;
              case SlideDirection.down:
                begin = const Offset(0.0, -0.10);
                break;
            }

            // Curved animation for smoother feel
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Slide transition
            final slideTransition = Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(curvedAnimation);

            // Fade transition
            final fadeTransition = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ));

            // Secondary animation for the page being replaced
            final secondarySlide = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.06, 0.0),
            ).animate(CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeOutCubic,
            ));

            return SlideTransition(
              position: secondarySlide,
              child: SlideTransition(
                position: slideTransition,
                child: FadeTransition(
                  opacity: fadeTransition,
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Fade page route for subtle transitions
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            );

            return FadeTransition(
              opacity: curvedAnimation,
              child: child,
            );
          },
        );
}

/// Gentle scale + fade, used when moving between whole areas of the app
/// (onboarding -> sign in -> home). No overshoot "bounce".
class ScalePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ScalePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curvedAnimation),
              child: FadeTransition(
                opacity: curvedAnimation,
                child: child,
              ),
            );
          },
        );
}

enum SlideDirection { right, left, up, down }

/// Extension for easy navigation with transitions
extension NavigatorExtension on NavigatorState {
  Future<T?> pushSlide<T>(Widget page, {SlideDirection direction = SlideDirection.right}) {
    return push(SlidePageRoute<T>(page: page, direction: direction));
  }

  Future<T?> pushFade<T>(Widget page) {
    return push(FadePageRoute<T>(page: page));
  }

  Future<T?> pushScale<T>(Widget page) {
    return push(ScalePageRoute<T>(page: page));
  }

  Future<T?> pushReplacementSlide<T, TO>(Widget page, {SlideDirection direction = SlideDirection.right}) {
    return pushReplacement(SlidePageRoute<T>(page: page, direction: direction));
  }

  Future<T?> pushReplacementFade<T, TO>(Widget page) {
    return pushReplacement(FadePageRoute<T>(page: page));
  }
}
