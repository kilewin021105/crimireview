import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;

import '../services/post_sign_in_service.dart';
import '../services/supabase_service.dart';
import '../utils/error_messages.dart';
import '../utils/page_transitions.dart';
import 'admin/admin_shell_screen.dart';
import 'home_screen.dart';

/// How a sign-in screen finishes signing in. Used by both the
/// "Decide how you sign in" page (Google / Facebook) and the email form,
/// so both end the same way: sync this account's data onto the phone
/// (PostSignInService), then open the admin or student home.
///
/// It also picks up a session that arrives by itself: a Google/Facebook
/// sign-in finishing when the student comes back from the browser, or
/// after Android restarted the app. Only the screen on top reacts, so
/// two screens never finish the same sign-in, and sign-up / forgot
/// password (opened on top) keep handling their own.
mixin SignInCompletion<T extends StatefulWidget> on State<T> {
  StreamSubscription<AuthState>? _sessionSubscription;
  bool _completing = false;

  /// True while the sync after sign-in runs.
  bool get isCompletingSignIn => _completing;

  /// True while this screen is signing in by itself (the email form's own
  /// button), which then calls [completeSignIn] directly.
  bool get signingInItself => false;

  /// Shows [message] when the sync after sign-in fails.
  void onSignInFailed(String message);

  /// An error Supabase reports back from the browser (cancelled, no email
  /// shared, expired). Screens that start a browser sign-in override it.
  void onBrowserSignInError(Object error) {}

  void watchForSessions() {
    if (!SupabaseService.isInitialized) return;
    _sessionSubscription = SupabaseService.instance.authStateChanges.listen(
      (state) {
        if (state.event != AuthChangeEvent.signedIn) return;
        if (!mounted || _completing || signingInItself) return;
        if (!SupabaseService.instance.isLoggedIn) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
        completeSignIn();
      },
      onError: (Object error) {
        if (mounted) onBrowserSignInError(error);
      },
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  Future<void> completeSignIn() async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      final isAdmin = await PostSignInService.instance.run();
      if (!mounted) return;
      // Removes the sign-in pages underneath too (the email form can be
      // open on top of the choice page).
      Navigator.of(context).pushAndRemoveUntil(
        ScalePageRoute(page: isAdmin ? const AdminShellScreen() : const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) onSignInFailed(friendlyError(e, fallback: 'Sign in failed. Please try again.'));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }
}
