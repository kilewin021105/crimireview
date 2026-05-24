import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EmailVerificationService {
  static final EmailVerificationService _instance = EmailVerificationService._internal();
  static EmailVerificationService get instance => _instance;
  EmailVerificationService._internal();

  static const String _resendApiKey = 're_5FEuM4u3_35u49aUZFiExpYFHpP9YqQ7e';
  static const String _fromEmail = 'CrimiReview <onboarding@resend.dev>';
  
  String? _currentCode;
  String? _currentEmail;
  DateTime? _codeExpiry;

  // Generate 6-digit verification code
  String _generateCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Send verification email
  Future<bool> sendVerificationEmail(String email) async {
    try {
      _currentCode = _generateCode();
      _currentEmail = email;
      _codeExpiry = DateTime.now().add(const Duration(minutes: 10));

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
          'html': '''
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
                <span style="font-size: 36px; font-weight: 700; color: #FFFFFF; letter-spacing: 8px;">$_currentCode</span>
              </div>
              <p style="margin: 0; font-size: 14px; color: #9CA3AF; line-height: 1.5;">This code expires in 10 minutes.<br>If you didn't request this, please ignore this email.</p>
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
''',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Store pending verification
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_verification_email', email);
        await prefs.setString('pending_verification_code', _currentCode!);
        await prefs.setString('pending_verification_expiry', _codeExpiry!.toIso8601String());
        return true;
      } else {
        print('Resend API error: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Email verification error: $e');
      return false;
    }
  }

  // Verify the code
  Future<bool> verifyCode(String email, String code) async {
    // Load from prefs if not in memory
    if (_currentCode == null || _currentEmail == null) {
      final prefs = await SharedPreferences.getInstance();
      _currentEmail = prefs.getString('pending_verification_email');
      _currentCode = prefs.getString('pending_verification_code');
      final expiryStr = prefs.getString('pending_verification_expiry');
      if (expiryStr != null) {
        _codeExpiry = DateTime.parse(expiryStr);
      }
    }

    if (_currentEmail != email) {
      return false;
    }

    if (_codeExpiry != null && DateTime.now().isAfter(_codeExpiry!)) {
      return false;
    }

    if (_currentCode == code) {
      // Mark email as verified
      final prefs = await SharedPreferences.getInstance();
      final verifiedEmails = prefs.getStringList('verified_emails') ?? [];
      if (!verifiedEmails.contains(email)) {
        verifiedEmails.add(email);
        await prefs.setStringList('verified_emails', verifiedEmails);
      }
      
      // Clear pending verification
      await prefs.remove('pending_verification_email');
      await prefs.remove('pending_verification_code');
      await prefs.remove('pending_verification_expiry');
      
      _currentCode = null;
      _currentEmail = null;
      _codeExpiry = null;
      
      return true;
    }

    return false;
  }

  // Check if email is verified
  Future<bool> isEmailVerified(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final verifiedEmails = prefs.getStringList('verified_emails') ?? [];
    return verifiedEmails.contains(email);
  }

  // Check if there's a pending verification
  Future<String?> getPendingVerificationEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pending_verification_email');
  }

  // Get remaining time for code expiry
  Duration? getRemainingTime() {
    if (_codeExpiry == null) return null;
    final remaining = _codeExpiry!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  // Resend code
  Future<bool> resendCode(String email) async {
    return await sendVerificationEmail(email);
  }
}
