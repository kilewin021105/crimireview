import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/theme_service.dart';
import 'inputs.dart';
import 'surfaces.dart';

/// A small metric card: icon, big number, label.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final c = color ?? context.palette.primary;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: c, size: 34, iconSize: 18),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 1),
          Text(label, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// A rounded progress bar that animates to its value.
class AppProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final Color? trackColor;
  final double height;

  const AppProgressBar({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) => Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: trackColor ?? p.surfaceAlt)),
              FractionallySizedBox(
                widthFactor: animated,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color ?? p.primary,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A circular progress ring with anything in the middle.
class RingProgress extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Color? trackColor;
  final Widget? center;

  const RingProgress({
    super.key,
    required this.value,
    this.size = 88,
    this.stroke = 9,
    this.color,
    this.trackColor,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, animated, child) => CustomPaint(
          painter: _RingPainter(
            value: animated,
            stroke: stroke,
            color: color ?? p.primary,
            track: trackColor ?? p.surfaceAlt,
          ),
          child: Center(child: child),
        ),
        child: center,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double stroke;
  final Color color;
  final Color track;

  _RingPainter({required this.value, required this.stroke, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// What a list shows when it has nothing in it.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;
  final bool compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: compact ? 20 : 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, color: color, size: compact ? 56 : 72, radius: compact ? 18 : 24),
          const SizedBox(height: 18),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            PrimaryButton(label: actionLabel!, onPressed: onAction, expand: false, height: 48),
          ],
        ],
      ),
    );
  }
}

/// A centred spinner with an optional caption.
class LoadingView extends StatelessWidget {
  final String? label;

  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: context.palette.primary),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: context.textStyles.bodyMedium, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Profile picture with a fallback to the person's initial. Prefers a
/// local file, then a URL, then the initial.
class UserAvatar extends StatelessWidget {
  final String name;
  final String? imagePath;
  final String? imageUrl;
  final double size;
  final bool ring;
  final Color? color;

  /// Overrides for the initials tile, e.g. translucent white on a
  /// gradient card.
  final Color? background;
  final Color? foreground;

  const UserAvatar({
    super.key,
    required this.name,
    this.imagePath,
    this.imageUrl,
    this.size = 44,
    this.ring = false,
    this.color,
    this.background,
    this.foreground,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.primary;
    Widget initials() => Container(
          // Opaque, so a gradient ring behind it never shows through.
          color: background ??
              Color.alphaBlend(
                c.withValues(alpha: context.isDarkMode ? 0.22 : 0.12),
                p.surface,
              ),
          alignment: Alignment.center,
          child: Text(
            _initials,
            style: TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
              color: foreground ?? (context.isDarkMode ? Color.lerp(c, Colors.white, 0.45) : c),
            ),
          ),
        );

    Widget image = initials();
    if (imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        image = Image.file(file, fit: BoxFit.cover, width: size, height: size);
      }
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      image = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => initials(),
        loadingBuilder: (_, child, progress) => progress == null ? child : initials(),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: ring ? const EdgeInsets.all(2.5) : null,
      decoration: ring
          ? BoxDecoration(shape: BoxShape.circle, gradient: p.heroGradient)
          : null,
      child: Container(
        decoration: ring
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.surface, width: 2),
              )
            : null,
        child: ClipOval(child: SizedBox.expand(child: image)),
      ),
    );
  }
}

/// Fades and slides a child in, staggered by [index], so a screen's
/// sections arrive in order instead of all at once.
class Appear extends StatelessWidget {
  final Widget child;
  final int index;

  const Appear({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: 40 * index.clamp(0, 10));
    return child
        .animate()
        .fadeIn(delay: delay, duration: 320.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, delay: delay, duration: 320.ms, curve: Curves.easeOutCubic);
  }
}

/// A label/value line used in summaries and detail sheets.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const InfoRow({super.key, required this.label, required this.value, this.icon, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: p.textTertiary),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: text.titleSmall?.copyWith(color: valueColor ?? p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yes/no confirmation dialog in the app's style. Returns true on confirm.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      final text = ctx.textStyles;
      final tone = destructive ? p.danger : p.primary;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
                color: tone,
                size: 46,
              ),
              const SizedBox(height: 16),
              Text(title, style: text.titleLarge),
              const SizedBox(height: 6),
              Text(message, style: text.bodyMedium),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: cancelLabel,
                      height: 48,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: confirmLabel,
                      height: 48,
                      color: tone,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// Shows a floating snackbar in the app's style.
void showAppSnack(BuildContext context, String message, {BannerTone tone = BannerTone.neutral, IconData? icon}) {
  final p = context.palette;
  final Color? accent = switch (tone) {
    BannerTone.success => p.success,
    BannerTone.danger => p.danger,
    BannerTone.warning => p.warning,
    BannerTone.info => p.info,
    BannerTone.neutral => null,
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null || accent != null) ...[
              Icon(
                icon ??
                    switch (tone) {
                      BannerTone.success => Icons.check_circle_rounded,
                      BannerTone.danger => Icons.error_outline_rounded,
                      BannerTone.warning => Icons.warning_amber_rounded,
                      _ => Icons.info_outline_rounded,
                    },
                color: accent ?? Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
