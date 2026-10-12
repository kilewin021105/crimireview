import 'package:flutter/material.dart';
import '../../services/theme_service.dart';

/// Keeps content readable on tablets and desktop: full width on phones,
/// centred and capped at [maxWidth] on anything wider.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// The basic surface: white (graphite in dark mode), hairline border,
/// rounded corners. Tappable cards get a ripple and a slight press-in.
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final double radius;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.gradient,
    this.radius = AppSpace.radiusLg,
    this.elevated = false,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(widget.radius);
    final decoration = BoxDecoration(
      color: widget.gradient == null ? (widget.color ?? p.surface) : null,
      gradient: widget.gradient,
      borderRadius: radius,
      border: widget.gradient == null
          ? Border.all(color: widget.borderColor ?? p.border)
          : null,
      boxShadow: widget.elevated
          ? [BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6))]
          : null,
    );

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (widget.onTap != null || widget.onLongPress != null) {
      content = InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHighlightChanged: _setPressed,
        borderRadius: radius,
        child: content,
      );
    }

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(decoration: decoration, child: content),
      ),
    );
  }
}

/// The brand-gradient card used for each screen's main call to action,
/// with two soft circles in the corner so it doesn't read as a flat block.
class GradientCard extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  const GradientCard({
    super.key,
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.all(AppSpace.xl),
    this.onTap,
    this.radius = AppSpace.radiusLg,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = gradient ?? p.heroGradient;
    final baseColor = g.colors.last;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AppCard(
        gradient: g,
        radius: radius,
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -50,
              child: _blob(150, Colors.white.withValues(alpha: 0.10)),
            ),
            Positioned(
              right: 40,
              bottom: -70,
              child: _blob(120, Colors.white.withValues(alpha: 0.06)),
            ),
            Positioned(
              left: -30,
              bottom: -60,
              child: _blob(110, baseColor.withValues(alpha: 0.25)),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// A rounded square with a tinted background and a coloured icon.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;
  final double? iconSize;
  final double? radius;

  const IconBadge({
    super.key,
    required this.icon,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.primary;
    final bg = background ??
        c.withValues(alpha: context.isDarkMode ? 0.18 : 0.11);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
      ),
      child: Icon(icon, color: c, size: iconSize ?? size * 0.5),
    );
  }
}

/// A small rounded tag: "Easy", "+1.5x", "Admin", "Offline".
class Pill extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? background;
  final IconData? icon;
  final bool solid;
  final double fontSize;

  const Pill({
    super.key,
    required this.label,
    this.color,
    this.background,
    this.icon,
    this.solid = false,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.primary;
    final fg = solid ? Colors.white : c;
    final bg = background ??
        (solid ? c : c.withValues(alpha: context.isDarkMode ? 0.18 : 0.11));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kAppFontFamily,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: fg,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum BannerTone { info, success, warning, danger, neutral }

/// An inline message box for errors, tips and confirmations.
class InlineBanner extends StatelessWidget {
  final String message;
  final String? title;
  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  const InlineBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = BannerTone.info,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    late final Color fg;
    late final Color bg;
    late final IconData defaultIcon;
    switch (tone) {
      case BannerTone.success:
        fg = p.success;
        bg = p.successSoft;
        defaultIcon = Icons.check_circle_rounded;
      case BannerTone.warning:
        fg = p.warning;
        bg = p.warningSoft;
        defaultIcon = Icons.warning_amber_rounded;
      case BannerTone.danger:
        fg = p.danger;
        bg = p.dangerSoft;
        defaultIcon = Icons.error_outline_rounded;
      case BannerTone.neutral:
        fg = p.textSecondary;
        bg = p.surfaceAlt;
        defaultIcon = Icons.info_outline_rounded;
      case BannerTone.info:
        fg = p.info;
        bg = p.infoSoft;
        defaultIcon = Icons.info_outline_rounded;
    }
    final text = context.textStyles;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: text.titleSmall?.copyWith(color: fg)),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: text.bodySmall?.copyWith(
                    color: tone == BannerTone.neutral ? p.textSecondary : fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card holding a list of rows separated by hairlines (settings,
/// account details, admin menus).
class AppListGroup extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry? margin;

  const AppListGroup({super.key, required this.children, this.title, this.margin});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Divider(height: 1, color: p.border),
        ));
      }
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title!.toUpperCase(),
                style: context.textStyles.labelSmall,
              ),
            ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

/// One row inside an [AppListGroup].
class AppListTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  const AppListTile({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final color = destructive ? p.danger : (iconColor ?? p.primary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 36, iconSize: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(
                      color: destructive ? p.danger : p.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (showChevron && onTap != null)
              Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }
}
