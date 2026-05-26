import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailVerificationService {
  static final EmailVerificationService _instance = EmailVerificationService._internal();
  static EmailVerificationService get instance => _instance;
  EmailVerificationService._internal();

  static const String _resendApiKey = 're_QjKfe684_5jjRg6FXcPQkxRCVZceLBwLp';
  static const String _fromEmail = 'CrimiReview <noreply@crimireview.app>';
  static const int _codeExpiryMinutes = 10;
  static const int _maxAttempts = 5;

  SupabaseClient get _supabase => Supabase.instance.client;

  // Generate 6-digit verification code
  String _generateCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Send verification email and store code in Supabase
  Future<Map<String, dynamic>> sendVerificationEmail(String email) async {
    try {
      final code = _generateCode();
      final expiresAt = DateTime.now().add(const Duration(minutes: _codeExpiryMinutes));

      // Delete any existing pending verifications for this email
      try {
        await _supabase
            .from('email_verifications')
            .delete()
            .eq('email', email.toLowerCase())
            .eq('verified', false);
      } catch (e) {
        print('Delete old verifications error: $e');
        // Continue anyway
      }

      // Insert new verification record
      try {
        await _supabase.from('email_verifications').insert({
          'email': email.toLowerCase(),
          'code': code,
          'expires_at': expiresAt.toUtc().toIso8601String(),
          'verified': false,
          'attempts': 0,
        });
      } catch (e) {
        print('Supabase insert error: $e');
        return {'success': false, 'error': 'Failed to create verification. Please try again.'};
      }

      // Send email via Resend
      try {
        final response = await http.post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $_resendApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'from': _fromEmail,
            'to': [email],
            'subject': 'CrimiReview - Verify Your Email',
            'html': _buildEmailTemplate(code),
          }),
        );

        print('Resend response: ${response.statusCode} - ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true};
        } else {
          final errorBody = jsonDecode(response.body);
          final errorMsg = errorBody['message'] ?? 'Failed to send email';
          print('Resend API error: $errorMsg');
          
          // Clean up the verification record if email failed
          await _supabase
              .from('email_verifications')
              .delete()
              .eq('email', email.toLowerCase())
              .eq('code', code);
          
          return {'success': false, 'error': errorMsg};
        }
      } catch (e) {
        print('Resend API exception: $e');
        return {'success': false, 'error': 'Failed to send email. Check your internet connection.'};
      }
    } catch (e) {
      print('Email verification error: $e');
      return {'success': false, 'error': 'Something went wrong. Please try again.'};
    }
  }

  // Verify the code against Supabase
  Future<Map<String, dynamic>> verifyCode(String email, String code) async {
    try {
      // Get the verification record
      final response = await _supabase
          .from('email_verifications')
          .select()
          .eq('email', email.toLowerCase())
          .eq('verified', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return {'success': false, 'error': 'No pending verification found'};
      }

      // Check if expired
      final expiresAt = DateTime.parse(response['expires_at']);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        // Delete expired record
        await _supabase
            .from('email_verifications')
            .delete()
            .eq('id', response['id']);
        return {'success': false, 'error': 'Code has expired. Please request a new one.'};
      }

      // Check attempts
      final attempts = response['attempts'] as int;
      if (attempts >= _maxAttempts) {
        await _supabase
            .from('email_verifications')
            .delete()
            .eq('id', response['id']);
        return {'success': false, 'error': 'Too many attempts. Please request a new code.'};
      }

      // Check code
      if (response['code'] != code) {
        // Increment attempts
        await _supabase
            .from('email_verifications')
            .update({'attempts': attempts + 1})
            .eq('id', response['id']);
        
        final remaining = _maxAttempts - attempts - 1;
        return {
          'success': false, 
          'error': 'Invalid code. $remaining attempts remaining.'
        };
      }

      // Code is valid - mark as verified
      await _supabase
          .from('email_verifications')
          .update({'verified': true})
          .eq('id', response['id']);

      return {'success': true};
    } catch (e) {
      print('Verify code error: $e');
      return {'success': false, 'error': 'Verification failed. Please try again.'};
    }
  }

  // Check if email is verified (has a verified record)
  Future<bool> isEmailVerified(String email) async {
    try {
      final response = await _supabase
          .from('email_verifications')
          .select('id')
          .eq('email', email.toLowerCase())
          .eq('verified', true)
          .limit(1)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Get remaining time for current verification
  Future<Duration?> getRemainingTime(String email) async {
    try {
      final response = await _supabase
          .from('email_verifications')
          .select('expires_at')
          .eq('email', email.toLowerCase())
          .eq('verified', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final expiresAt = DateTime.parse(response['expires_at']);
      final remaining = expiresAt.difference(DateTime.now().toUtc());
      return remaining.isNegative ? null : remaining;
    } catch (e) {
      return null;
    }
  }

  // Resend code
  Future<Map<String, dynamic>> resendCode(String email) async {
    return await sendVerificationEmail(email);
  }

  // Clean up verified/expired records for an email
  Future<void> cleanupVerifications(String email) async {
    try {
      await _supabase
          .from('email_verifications')
          .delete()
          .eq('email', email.toLowerCase());
    } catch (e) {
      print('Cleanup error: $e');
    }
  }

  // ==========================================
  // PASSWORD RESET METHODS (Using Resend)
  // ==========================================

  // Send password reset email
  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    try {
      final code = _generateCode();
      final expiresAt = DateTime.now().add(const Duration(minutes: _codeExpiryMinutes));

      // Delete any existing pending resets for this email
      try {
        await _supabase
            .from('password_resets')
            .delete()
            .eq('email', email.toLowerCase())
            .eq('used', false);
      } catch (e) {
        print('Delete old resets error: $e');
      }

      // Insert new reset record
      try {
        await _supabase.from('password_resets').insert({
          'email': email.toLowerCase(),
          'code': code,
          'expires_at': expiresAt.toUtc().toIso8601String(),
          'used': false,
          'attempts': 0,
        });
      } catch (e) {
        print('Supabase insert error: $e');
        return {'success': false, 'error': 'Failed to create reset request. Please try again.'};
      }

      // Send email via Resend
      try {
        final response = await http.post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $_resendApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'from': _fromEmail,
            'to': [email],
            'subject': 'CrimiReview - Reset Your Password',
            'html': _buildPasswordResetTemplate(code),
          }),
        );

        print('Resend response: ${response.statusCode} - ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true};
        } else {
          final errorBody = jsonDecode(response.body);
          final errorMsg = errorBody['message'] ?? 'Failed to send email';
          print('Resend API error: $errorMsg');
          
          // Clean up the reset record if email failed
          await _supabase
              .from('password_resets')
              .delete()
              .eq('email', email.toLowerCase())
              .eq('code', code);
          
          return {'success': false, 'error': errorMsg};
        }
      } catch (e) {
        print('Resend API exception: $e');
        return {'success': false, 'error': 'Failed to send email. Check your internet connection.'};
      }
    } catch (e) {
      print('Password reset error: $e');
      return {'success': false, 'error': 'Something went wrong. Please try again.'};
    }
  }

  // Verify password reset code
  Future<Map<String, dynamic>> verifyPasswordResetCode(String email, String code) async {
    try {
      // Get the reset record
      final response = await _supabase
          .from('password_resets')
          .select()
          .eq('email', email.toLowerCase())
          .eq('used', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return {'success': false, 'error': 'No pending reset found. Please request a new code.'};
      }

      // Check if expired
      final expiresAt = DateTime.parse(response['expires_at']);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        await _supabase
            .from('password_resets')
            .delete()
            .eq('id', response['id']);
        return {'success': false, 'error': 'Code has expired. Please request a new one.'};
      }

      // Check attempts
      final attempts = response['attempts'] as int;
      if (attempts >= _maxAttempts) {
        await _supabase
            .from('password_resets')
            .delete()
            .eq('id', response['id']);
        return {'success': false, 'error': 'Too many attempts. Please request a new code.'};
      }

      // Check code
      if (response['code'] != code) {
        await _supabase
            .from('password_resets')
            .update({'attempts': attempts + 1})
            .eq('id', response['id']);
        
        final remaining = _maxAttempts - attempts - 1;
        return {
          'success': false, 
          'error': 'Invalid code. $remaining attempts remaining.'
        };
      }

      // Code is valid - mark as used
      await _supabase
          .from('password_resets')
          .update({'used': true})
          .eq('id', response['id']);

      return {'success': true};
    } catch (e) {
      print('Verify reset code error: $e');
      return {'success': false, 'error': 'Verification failed. Please try again.'};
    }
  }

  // Check if reset code was verified for this email
  Future<bool> isResetCodeVerified(String email) async {
    try {
      final response = await _supabase
          .from('password_resets')
          .select('id')
          .eq('email', email.toLowerCase())
          .eq('used', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Clean up password reset records
  Future<void> cleanupPasswordResets(String email) async {
    try {
      await _supabase
          .from('password_resets')
          .delete()
          .eq('email', email.toLowerCase());
    } catch (e) {
      print('Cleanup password resets error: $e');
    }
  }

  String _buildPasswordResetTemplate(String code) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #0A0F1A; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #0A0F1A; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px; background-color: #141B2D; border-radius: 16px; overflow: hidden;">
          <tr>
            <td style="padding: 40px 32px; text-align: center;">
              <h1 style="margin: 0 0 8px; font-size: 28px; font-weight: 700; color: #F5F5F5;">CrimiReview</h1>
              <p style="margin: 0; font-size: 14px; color: #9CA3AF;">Password Reset Request</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 0 32px 32px; text-align: center;">
              <p style="margin: 0 0 24px; font-size: 16px; color: #F5F5F5; line-height: 1.5;">Enter this code to reset your password:</p>
              <div style="background: linear-gradient(135deg, #EF4444 0%, #DC2626 100%); border-radius: 12px; padding: 24px; margin-bottom: 24px;">
                <span style="font-size: 36px; font-weight: 700; color: #FFFFFF; letter-spacing: 8px;">$code</span>
              </div>
              <p style="margin: 0; font-size: 14px; color: #9CA3AF; line-height: 1.5;">This code expires in $_codeExpiryMinutes minutes.<br>If you didn't request this, please ignore this email.</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 24px 32px; background-color: #0A0F1A; text-align: center; border-top: 1px solid rgba(255,255,255,0.08);">
              <p style="margin: 0; font-size: 12px; color: #6B7280;">&copy; 2026 CrimiReview. All rights reserved.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
  }

  String _buildEmailTemplate(String code) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #0A0F1A; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #0A0F1A; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px; background-color: #141B2D; border-radius: 16px; overflow: hidden;">
          <tr>
            <td style="padding: 40px 32px; text-align: center;">
              <h1 style="margin: 0 0 8px; font-size: 28px; font-weight: 700; color: #F5F5F5;">CrimiReview</h1>
              <p style="margin: 0; font-size: 14px; color: #9CA3AF;">Criminology Board Exam Reviewer</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 0 32px 32px; text-align: center;">
              <p style="margin: 0 0 24px; font-size: 16px; color: #F5F5F5; line-height: 1.5;">Enter this code to verify your email:</p>
              <div style="background: linear-gradient(135deg, #8B5CF6 0%, #7C3AED 100%); border-radius: 12px; padding: 24px; margin-bottom: 24px;">
                <span style="font-size: 36px; font-weight: 700; color: #FFFFFF; letter-spacing: 8px;">$code</span>
              </div>
              <p style="margin: 0; font-size: 14px; color: #9CA3AF; line-height: 1.5;">This code expires in $_codeExpiryMinutes minutes.<br>If you didn't request this, please ignore this email.</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 24px 32px; background-color: #0A0F1A; text-align: center; border-top: 1px solid rgba(255,255,255,0.08);">
              <p style="margin: 0; font-size: 12px; color: #6B7280;">&copy; 2026 CrimiReview. All rights reserved.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
  }
}
