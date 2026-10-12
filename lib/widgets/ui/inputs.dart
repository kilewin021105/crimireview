import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/theme_service.dart';

/// The main button on a screen: full width, brand colour, with a
/// loading state that keeps its size.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool trailingIcon;
  final bool loading;
  final bool expand;
  final Color? color;
  final Color? foreground;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon = false,
    this.loading = false,
    this.expand = true,
    this.color,
    this.foreground,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Colors.white;
    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null && !trailingIcon) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (icon != null && trailingIcon) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 20),
              ],
            ],
          );
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(64, height),
        backgroundColor: color,
        foregroundColor: fg,
        disabledBackgroundColor: loading ? color ?? (context.isDarkMode ? context.palette.primaryStrong : context.palette.primary) : null,
        disabledForegroundColor: loading ? fg : null,
      ),
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The secondary action next to a [PrimaryButton]: outlined, neutral.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Color? color;
  final double height;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.color,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(64, height),
        foregroundColor: color ?? p.textPrimary,
        backgroundColor: p.surface,
        side: BorderSide(color: color?.withValues(alpha: 0.5) ?? p.border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A text field with its label above it (not floating inside), the
/// pattern most modern apps use because the label never gets in the way.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final int? maxLength;
  final int maxLines;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? helperText;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.maxLines = 1,
    this.enabled = true,
    this.autofillHints,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.helperText,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(label, style: text.labelMedium?.copyWith(color: p.textPrimary)),
        ),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          maxLength: maxLength,
          maxLines: obscureText ? 1 : maxLines,
          enabled: enabled,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            helperText: helperText,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

/// One-time code entry drawn as separate boxes over a single hidden
/// field, so typing, deleting and pasting the whole code all just work.
class CodeInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final bool autofocus;
  final bool enabled;

  const CodeInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
    this.autofocus = false,
    this.enabled = true,
  });

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.removeListener(_rebuild);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = widget.controller.text;
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final box = ((c.maxWidth - gap * (widget.length - 1)) / widget.length).clamp(34.0, 54.0);
      final rowWidth = box * widget.length + gap * (widget.length - 1);
      return Center(
        child: SizedBox(
          width: rowWidth,
          height: box * 1.18,
          child: Stack(
            children: [
              Row(
                children: List.generate(widget.length, (i) {
                  final filled = i < text.length;
                  final active = _focus.hasFocus &&
                      (i == text.length || (i == widget.length - 1 && text.length == widget.length));
                  final borderColor = widget.hasError
                      ? p.danger
                      : active
                          ? p.primary
                          : filled
                              ? p.textTertiary.withValues(alpha: 0.6)
                              : p.border;
                  return Padding(
                    padding: EdgeInsets.only(right: i == widget.length - 1 ? 0 : gap),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: box,
                      height: box * 1.18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? p.primarySoft.withValues(alpha: 0.5) : p.surface,
                        borderRadius: BorderRadius.circular(AppSpace.radiusMd - 2),
                        border: Border.all(color: borderColor, width: active ? 1.8 : 1.2),
                      ),
                      child: Text(
                        filled ? text[i] : '',
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          fontSize: box * 0.46,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.0,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    maxLength: widget.length,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      widget.onChanged?.call(value);
                      if (value.length == widget.length) widget.onCompleted?.call(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// "Step 2 of 3" with a segmented progress bar.
class StepProgress extends StatelessWidget {
  final int current; // zero-based
  final int total;
  final List<String>? labels;

  const StepProgress({super.key, required this.current, required this.total, this.labels});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'STEP ${current + 1} OF $total',
              style: text.labelSmall?.copyWith(color: p.primary),
            ),
            if (labels != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  labels![current],
                  style: text.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(total, (i) {
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 5,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                decoration: BoxDecoration(
                  color: i <= current ? p.primary : p.surfaceAlt,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// A segmented pill control: "Easy | Medium | Hard", "All | Week".
class PillTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final List<Color?>? activeColors;

  const PillTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.activeColors,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != index) {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? p.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpace.radiusSm),
                    boxShadow: i == index
                        ? [BoxShadow(color: p.shadow, blurRadius: 6, offset: const Offset(0, 1))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: i == index
                          ? (activeColors?[i] ?? p.textPrimary)
                          : p.textTertiary,
                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
