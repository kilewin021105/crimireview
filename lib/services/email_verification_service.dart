import 'package:supabase_flutter/supabase_flutter.dart';

/// Signup email-code verification and password-reset-code verification.
///
/// ---------------------------------------------------------------------------
/// SECURITY REWRITE (see supabase_security_fixes.sql)
/// ---------------------------------------------------------------------------
/// This class used to do three things itself: generate the code, read/write
/// `email_verifications` / `password_resets` directly via `.select()` /
/// `.insert()` / `.update()`, and call the Resend API with an API key that
/// was a literal string constant right here in the client.
///
/// Both of those were security bugs, not style issues:
///
///   * Comparing the code client-side REQUIRES reading the stored code back
///     from the table first, which is exactly why the old RLS policies had
///     to be `USING (true)` (readable by anyone, no filter) -- anyone with
///     the app's public anon key could `SELECT * FROM password_resets` and
///     read every pending reset code for every account, not just their own.
///   * A Resend API key shipped inside a compiled Flutter app is trivially
///     extractable (it is just a string in the binary) and lets whoever
///     finds it send email as this app through this account.
///
/// The fix moves code generation, code comparison, and the Resend HTTP call
/// into Postgres `SECURITY DEFINER` functions (`request_verification_code`,
/// `confirm_verification_code`, `request_password_reset`,
/// `confirm_password_reset_code`) that never return the stored code to any
/// caller, with the Resend key kept in Supabase Vault, never in this file.
/// The two tables now deny ALL direct client access -- this class is a thin
/// wrapper around four RPCs and nothing more.
class EmailVerificationService {
  static final EmailVerificationService _instance = EmailVerificationService._internal();
  static EmailVerificationService get instance => _instance;
  EmailVerificationService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Every RPC here returns `jsonb {success, error?}` from Postgres, which
  /// arrives as a `Map`. This normalizes it and gives one place to handle a
  /// call that fails before it even reaches the database (offline, RPC
  /// missing because supabase_security_fixes.sql has not been run yet, etc).
  Future<Map<String, dynamic>> _call(
    String function,
    Map<String, dynamic> params,
    String fallbackError,
  ) async {
    try {
      final result = await _supabase.rpc(function, params: params);
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'success': false, 'error': fallbackError};
    } catch (e) {
      return {'success': false, 'error': fallbackError};
    }
  }

  // ---------------------------------------------------------------------------
  // Signup email verification
  // ---------------------------------------------------------------------------

  /// Generates a code server-side, emails it, and stores it -- all inside
  /// `public.request_verification_code`. This call never sees the code.
  Future<Map<String, dynamic>> sendVerificationEmail(String email) {
    return _call(
      'request_verification_code',
      {'p_email': email},
      'Failed to send verification email. Please try again.',
    );
  }

  Future<Map<String, dynamic>> resendCode(String email) => sendVerificationEmail(email);

  /// Submits the student's typed code to `public.confirm_verification_code`,
  /// which does the comparison server-side and returns only pass/fail.
  Future<Map<String, dynamic>> verifyCode(String email, String code) {
    return _call(
      'confirm_verification_code',
      {'p_email': email, 'p_code': code},
      'Verification failed. Please try again.',
    );
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) {
    return _call(
      'request_password_reset',
      {'p_email': email},
      'Failed to create reset request. Please try again.',
    );
  }

  Future<Map<String, dynamic>> verifyPasswordResetCode(String email, String code) {
    return _call(
      'confirm_password_reset_code',
      {'p_email': email, 'p_code': code},
      'Verification failed. Please try again.',
    );
  }

  /// Best-effort tidy-up after a successful reset. `public.reset_user_password`
  /// (supabase_schema.sql) already deletes the matching row itself, so this is
  /// a harmless no-op in the normal path -- kept so a partial/retried flow
  /// can never leave a stray record behind.
  Future<void> cleanupPasswordResets(String email) async {
    try {
      await _supabase.rpc('cleanup_password_resets', params: {'p_email': email});
    } catch (_) {
      // Diagnostic only -- never worth failing the reset flow over.
    }
  }
}
