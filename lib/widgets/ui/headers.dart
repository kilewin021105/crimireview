import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../../utils/responsive.dart';

/// Large left-aligned title at the top of each main tab.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: text.bodyMedium),
              ],
            ],
          ),
        ),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          actions[i],
        ],
      ],
    );
  }
}

/// A section title with an optional "See all"-style action on the right.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: text.labelMedium?.copyWith(color: p.primary),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A square, outlined icon button for toolbars and headers.
class ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;
  final Widget? badge;

  const ToolbarIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = 42,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button = Material(
      color: background ?? p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
        side: background == null ? BorderSide(color: p.border) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.48, color: color ?? p.textPrimary),
        ),
      ),
    );
    if (badge != null) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [button, Positioned(right: -4, top: -4, child: badge!)],
      );
    }
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Back button used by every pushed screen.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const AppBackButton({super.key, this.onPressed, this.icon = Icons.arrow_back_rounded});

  @override
  Widget build(BuildContext context) {
    return ToolbarIconButton(
      icon: icon,
      size: 40,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}

/// The top bar for pushed screens: back button, left-aligned title with
/// an optional subtitle, and actions.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final IconData backIcon;
  final Color? backgroundColor;
  final PreferredSizeWidget? bottom;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.backIcon = Icons.arrow_back_rounded,
    this.backgroundColor,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(64 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final canPop = showBack && (onBack != null || Navigator.of(context).canPop());
    // Line the title up with the page content below it.
    final edge = Responsive.horizontalPadding(context);
    return AppBar(
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      backgroundColor: backgroundColor,
      leadingWidth: canPop ? edge + 44 : 0,
      titleSpacing: canPop ? 6 : edge,
      leading: canPop
          ? Padding(
              padding: EdgeInsets.only(left: edge),
              child: Center(child: AppBackButton(onPressed: onBack, icon: backIcon)),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(
              subtitle!,
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        if (actions != null)
          for (final a in actions!) Padding(padding: const EdgeInsets.only(left: 8), child: a),
        SizedBox(width: edge),
      ],
      bottom: bottom,
    );
  }
}
