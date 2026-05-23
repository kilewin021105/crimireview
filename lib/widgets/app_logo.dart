import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// CrimiReview App Logo Widget
/// Use this for consistent branding across the app
class AppLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final bool showShadow;

  const AppLogo({
    super.key,
    this.size = 64,
    this.showText = false,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6C5CE7), // Purple
                Color(0xFF4834D4), // Darker purple
              ],
            ),
            borderRadius: BorderRadius.circular(size * 0.25),
            boxShadow: showShadow ? [
              BoxShadow(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                blurRadius: size * 0.25,
                offset: Offset(0, size * 0.1),
              ),
            ] : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Book icon background
              Positioned(
                top: size * 0.15,
                child: Icon(
                  Icons.menu_book_rounded,
                  size: size * 0.45,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              // Main CR text
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'CR',
                    style: TextStyle(
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                      height: 1,
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: size * 0.02),
                    width: size * 0.5,
                    height: size * 0.04,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(size * 0.02),
                    ),
                  ),
                ],
              ),
              // Badge accent
              Positioned(
                bottom: size * 0.1,
                right: size * 0.1,
                child: Container(
                  width: size * 0.22,
                  height: size * 0.22,
                  decoration: BoxDecoration(
                    color: CrimiColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: size * 0.025,
                    ),
                  ),
                  child: Icon(
                    Icons.verified_rounded,
                    size: size * 0.12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showText) ...[
          SizedBox(height: size * 0.2),
          Text(
            'CrimiReview',
            style: TextStyle(
              fontSize: size * 0.28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ],
    );
  }
}

/// Simple icon-only version for smaller uses
class AppLogoIcon extends StatelessWidget {
  final double size;

  const AppLogoIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6C5CE7),
            Color(0xFF4834D4),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(
        child: Text(
          'CR',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
