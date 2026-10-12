import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../utils/error_messages.dart';
import '../utils/responsive.dart';
import '../widgets/password_strength_indicator.dart';
import '../widgets/ui/ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String _password = '';

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService.instance.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (mounted) {
        showAppSnack(context, 'Password changed successfully!', tone: BannerTone.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyError(e, fallback: 'Could not change your password. Please try again.');
      });
    }
  }

  Widget _eye(bool obscured, VoidCallback toggle) => IconButton(
        onPressed: toggle,
        icon: Icon(
          obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Change password',
        backIcon: Icons.close_rounded,
        onBack: () => Navigator.pop(context),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 28),
        child: ContentWidth(
          maxWidth: 480,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: IconBadge(icon: Icons.lock_reset_rounded, size: 56, radius: 18),
                ),
                const SizedBox(height: 16),
                Text('Set a new password', style: text.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  'Enter your current password first, then choose a strong new one.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  InlineBanner(message: _errorMessage!, tone: BannerTone.danger),
                  const SizedBox(height: 20),
                ],

                // Current password -- re-checked by the server before the
                // change, so an unlocked phone can't be used to lock the owner out.
                AppTextField(
                  controller: _currentPasswordController,
                  label: 'Current password',
                  hint: 'Enter current password',
                  icon: Icons.lock_open_rounded,
                  obscureText: _obscureCurrentPassword,
                  autofillHints: const [AutofillHints.password],
                  suffix: _eye(_obscureCurrentPassword,
                      () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword)),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                AppTextField(
                  controller: _newPasswordController,
                  label: 'New password',
                  hint: '8 to 16 characters',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscureNewPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (v) => setState(() => _password = v),
                  suffix: _eye(_obscureNewPassword,
                      () => setState(() => _obscureNewPassword = !_obscureNewPassword)),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    final result = PasswordStrengthChecker.check(value);
                    if (!result.hasMinLength) return 'At least 8 characters required';
                    if (!result.hasMaxLength) return 'Max 16 characters allowed';
                    if (!result.hasUppercase) return 'Add an uppercase letter';
                    if (!result.hasLowercase) return 'Add a lowercase letter';
                    if (!result.hasNumber) return 'Add a number';
                    if (value == _currentPasswordController.text) {
                      return 'Choose a password different from your current one';
                    }
                    return null;
                  },
                ),
                PasswordStrengthIndicator(
                  password: _password,
                  showRequirements: true,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm new password',
                  hint: 'Type it again',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscureConfirmPassword,
                  suffix: _eye(_obscureConfirmPassword,
                      () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword)),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Update password',
                  loading: _isLoading,
                  onPressed: _changePassword,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
