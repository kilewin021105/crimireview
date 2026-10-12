import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// The CrimiReview logo (the same artwork as the app icon) on a rounded
/// white tile, optionally with the wordmark underneath.
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
    final p = context.palette;
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: context.isDarkMode ? Colors.transparent : p.border),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF13286E).withValues(alpha: context.isDarkMode ? 0.5 : 0.16),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.1),
      // assets/images/logo_mark.png is the app icon artwork cropped to
      // the mark itself, so it fills the tile like the launcher icon.
      child: Image.asset(
        'assets/images/logo_mark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.balance_rounded,
          size: size * 0.5,
          color: p.primary,
        ),
      ),
    );

    if (!showText) return tile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        SizedBox(height: size * 0.22),
        const AppWordmark(),
      ],
    );
  }
}

/// "CrimiReview" set in the brand style: "Crimi" in ink, "Review" in blue.
class AppWordmark extends StatelessWidget {
  final double fontSize;
  final Color? color;

  const AppWordmark({super.key, this.fontSize = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = TextStyle(
      fontFamily: kAppFontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.1,
      color: color ?? p.textPrimary,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Crimi'),
          TextSpan(text: 'Review', style: TextStyle(color: color ?? p.primary)),
        ],
      ),
      style: base,
    );
  }
}

/// Small logo for headers and app bars.
class AppLogoIcon extends StatelessWidget {
  final double size;

  const AppLogoIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) => AppLogo(size: size, showShadow: false);
}
