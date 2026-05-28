import 'package:flutter/material.dart';

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
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecialChar;
  final int score;

  PasswordStrengthResult({
    required this.strength,
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecialChar,
    required this.score,
  });

  bool get isValid => hasMinLength && hasUppercase && hasLowercase && hasNumber;
  bool get isStrong => strength == PasswordStrength.strong;
}

class PasswordStrengthChecker {
  static PasswordStrengthResult check(String password) {
    if (password.isEmpty) {
      return PasswordStrengthResult(
        strength: PasswordStrength.empty,
        hasMinLength: false,
        hasUppercase: false,
        hasLowercase: false,
        hasNumber: false,
        hasSpecialChar: false,
        score: 0,
      );
    }

    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/`~]'));

    int score = 0;
    if (hasMinLength) score++;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (result.strength == PasswordStrength.empty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Strength bar
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _getProgressValue(result.strength),
                  backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(_getStrengthColor(result.strength)),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getStrengthColor(result.strength).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getStrengthLabel(result.strength),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getStrengthColor(result.strength),
                ),
              ),
            ),
          ],
        ),
        if (showRequirements) ...[
          const SizedBox(height: 16),
          // Requirements list
          _buildRequirement('At least 8 characters', result.hasMinLength, isDark),
          const SizedBox(height: 6),
          _buildRequirement('Uppercase letter (A-Z)', result.hasUppercase, isDark),
          const SizedBox(height: 6),
          _buildRequirement('Lowercase letter (a-z)', result.hasLowercase, isDark),
          const SizedBox(height: 6),
          _buildRequirement('Number (0-9)', result.hasNumber, isDark),
          const SizedBox(height: 6),
          _buildRequirement('Special character (!@#\$%...)', result.hasSpecialChar, isDark),
        ],
      ],
    );
  }

  Widget _buildRequirement(String text, bool isMet, bool isDark) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isMet 
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100),
            shape: BoxShape.circle,
            border: Border.all(
              color: isMet 
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white24 : Colors.grey.shade300),
              width: 1.5,
            ),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isMet
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Color(0xFF10B981),
                    )
                  : Icon(
                      Icons.remove_rounded,
                      size: 10,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isMet
                  ? (isDark ? Colors.white70 : Colors.grey.shade700)
                  : (isDark ? Colors.white38 : Colors.grey.shade500),
              fontWeight: isMet ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  double _getProgressValue(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.empty:
        return 0;
      case PasswordStrength.weak:
        return 0.25;
      case PasswordStrength.fair:
        return 0.5;
      case PasswordStrength.good:
        return 0.75;
      case PasswordStrength.strong:
        return 1.0;
    }
  }

  Color _getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.empty:
        return Colors.grey;
      case PasswordStrength.weak:
        return const Color(0xFFEF4444); // Red
      case PasswordStrength.fair:
        return const Color(0xFFF59E0B); // Orange/Amber
      case PasswordStrength.good:
        return const Color(0xFF3B82F6); // Blue
      case PasswordStrength.strong:
        return const Color(0xFF10B981); // Green
    }
  }

  String _getStrengthLabel(PasswordStrength strength) {
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

/// Compact version for inline display
class PasswordStrengthBar extends StatelessWidget {
  final String password;

  const PasswordStrengthBar({
    super.key,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    final result = PasswordStrengthChecker.check(password);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (result.strength == PasswordStrength.empty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: List.generate(4, (index) {
        final isActive = index < _getActiveSegments(result.strength);
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
            decoration: BoxDecoration(
              color: isActive
                  ? _getStrengthColor(result.strength)
                  : (isDark ? Colors.white12 : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  int _getActiveSegments(PasswordStrength strength) {
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

  Color _getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.empty:
        return Colors.grey;
      case PasswordStrength.weak:
        return const Color(0xFFEF4444);
      case PasswordStrength.fair:
        return const Color(0xFFF59E0B);
      case PasswordStrength.good:
        return const Color(0xFF3B82F6);
      case PasswordStrength.strong:
        return const Color(0xFF10B981);
    }
  }
}
