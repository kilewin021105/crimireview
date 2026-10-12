import 'package:flutter/material.dart';
import '../services/theme_service.dart';

enum PasswordStrength {
  empty,
  weak,
  fair,
  good,
  strong,
}

class PasswordStrengthResult {
  final PasswordStrength strength;
  final bool hasMinLength;
  final bool hasMaxLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecialChar;
  final int score;

  PasswordStrengthResult({
    required this.strength,
    required this.hasMinLength,
    required this.hasMaxLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecialChar,
    required this.score,
  });

  bool get isValid => hasMinLength && hasMaxLength && hasUppercase && hasLowercase && hasNumber;
  bool get isStrong => strength == PasswordStrength.strong;
}

class PasswordStrengthChecker {
  static PasswordStrengthResult check(String password) {
    if (password.isEmpty) {
      return PasswordStrengthResult(
        strength: PasswordStrength.empty,
        hasMinLength: false,
        hasMaxLength: false,
        hasUppercase: false,
        hasLowercase: false,
        hasNumber: false,
        hasSpecialChar: false,
        score: 0,
      );
    }

    final hasMinLength = password.length >= 8;
    final hasMaxLength = password.length <= 16;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/`~]'));

    int score = 0;
    if (hasMinLength && hasMaxLength) score++;
    if (hasUppercase) score++;
    if (hasLowercase) score++;
    if (hasNumber) score++;
    if (hasSpecialChar) score++;
    
    // Bonus for length
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;

    PasswordStrength strength;
    if (score <= 2) {
      strength = PasswordStrength.weak;
    } else if (score <= 3) {
      strength = PasswordStrength.fair;
    } else if (score <= 5) {
      strength = PasswordStrength.good;
    } else {
      strength = PasswordStrength.strong;
    }

    return PasswordStrengthResult(
      strength: strength,
      hasMinLength: hasMinLength,
      hasMaxLength: hasMaxLength,
      hasUppercase: hasUppercase,
      hasLowercase: hasLowercase,
      hasNumber: hasNumber,
      hasSpecialChar: hasSpecialChar,
      score: score,
    );
  }
}

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final bool showRequirements;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.showRequirements = true,
  });

  @override
  Widget build(BuildContext context) {
    final result = PasswordStrengthChecker.check(password);
    final text = context.textStyles;

    if (result.strength == PasswordStrength.empty) {
      return const SizedBox.shrink();
    }

    final color = _strengthColor(context, result.strength);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: PasswordStrengthBar(password: password)),
              const SizedBox(width: 12),
              Text(
                _strengthLabel(result.strength),
                style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (showRequirements) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _requirement(context, '8-16 characters', result.hasMinLength && result.hasMaxLength),
                _requirement(context, 'Uppercase', result.hasUppercase),
                _requirement(context, 'Lowercase', result.hasLowercase),
                _requirement(context, 'Number', result.hasNumber),
                _requirement(context, 'Symbol (optional)', result.hasSpecialChar, optional: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _requirement(BuildContext context, String label, bool isMet, {bool optional = false}) {
    final p = context.palette;
    final color = isMet ? p.success : (optional ? p.textTertiary : p.textSecondary);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isMet ? p.successSoft : p.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isMet ? Icons.check_rounded : Icons.circle_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _strengthLabel(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.empty:
        return '';
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.fair:
        return 'Fair';
      case PasswordStrength.good:
        return 'Good';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }
}

Color _strengthColor(BuildContext context, PasswordStrength strength) {
  final p = context.palette;
  switch (strength) {
    case PasswordStrength.empty:
      return p.textTertiary;
    case PasswordStrength.weak:
      return p.danger;
    case PasswordStrength.fair:
      return p.warning;
    case PasswordStrength.good:
      return p.info;
    case PasswordStrength.strong:
      return p.success;
  }
}

/// Four-segment strength meter.
class PasswordStrengthBar extends StatelessWidget {
  final String password;

  const PasswordStrengthBar({
    super.key,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    final result = PasswordStrengthChecker.check(password);
    final p = context.palette;

    if (result.strength == PasswordStrength.empty) {
      return const SizedBox.shrink();
    }

    final active = _activeSegments(result.strength);
    final color = _strengthColor(context, result.strength);
    return Row(
      children: List.generate(4, (index) {
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 5,
            margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
            decoration: BoxDecoration(
              color: index < active ? color : p.surfaceAlt,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  int _activeSegments(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.empty:
        return 0;
      case PasswordStrength.weak:
        return 1;
      case PasswordStrength.fair:
        return 2;
      case PasswordStrength.good:
        return 3;
      case PasswordStrength.strong:
        return 4;
    }
  }
}
