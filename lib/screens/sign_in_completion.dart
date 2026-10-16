import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;

import '../services/post_sign_in_service.dart';
import '../services/supabase_service.dart';
import '../utils/error_messages.dart';
import '../utils/page_transitions.dart';
import 'admin/admin_shell_screen.dart';
import 'home_screen.dart';

/// How the sign-in page (`AuthScreen`) finishes signing in, for its email
/// button and for a Google/Facebook sign-in started from its icons, so
/// every method ends the same way: sync this account's data onto the
/// phone (PostSignInService), then open the admin or student home.
///
/// It also picks up a session that arrives by itself: a Google/Facebook
/// sign-in finishing when the student comes back from the browser, or
/// after Android restarted the app. Only the screen on top reacts, so
/// sign-up / forgot password (opened on top) keep handling their own.
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
      // Errors from the browser (cancelled, no email shared, expired) are
      // shown by SocialSignInIcons, which started that sign-in.
      onError: (Object _) {},
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
      // Removes the sign-in page underneath too, so Back can't return to it.
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
