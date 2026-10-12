import 'dart:async';

/// Turns any error from a network call into a sentence a student can act
/// on, instead of raw text like "AuthRetryableFetchException(...)".
///
/// Order matters: connection problems first (they look different on every
/// platform), then known Supabase Auth codes, then an `Exception('...')`
/// thrown with an already-friendly message, and finally [fallback].
String friendlyError(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is TimeoutException) {
    return 'The connection is too slow right now. Please try again.';
  }

  final raw = error.toString();
  final text = raw.toLowerCase();

  if (text.contains('timeout') || text.contains('timed out')) {
    return 'The connection is too slow right now. Please try again.';
  }
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('no address associated') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('clientexception') ||
      text.contains('retryablefetch')) {
    return 'No internet connection. Check your connection and try again.';
  }
  if (text.contains('invalid login') || text.contains('invalid_credentials')) {
    return 'Invalid email or password.';
  }
  if (text.contains('already registered') || text.contains('user_already_exists')) {
    return 'This email is already registered. Try logging in instead.';
  }
  if (text.contains('email not confirmed') || text.contains('email_not_confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  if (text.contains('weak_password') || text.contains('password should be')) {
    return 'That password is too weak. Use 8+ characters with upper and lower case letters and a number.';
  }
  if (text.contains('invalid_email') || text.contains('unable to validate email')) {
    return 'Please enter a valid email address.';
  }
  if (text.contains('rate limit') || text.contains('rate_limit') || text.contains('too many requests')) {
    return 'Too many attempts. Please wait a few minutes and try again.';
  }
  if (text.contains('database error saving new user') || text.contains('email address has not been verified')) {
    return 'Your email verification expired. Please go back and request a new code.';
  }

  // Exception('Message for the user') -> "Message for the user".
  if (raw.startsWith('Exception: ')) {
    final message = raw.substring('Exception: '.length).trim();
    if (message.isNotEmpty && !message.contains('Supabase not initialized')) {
      return message;
    }
  }
  return fallback;
}
