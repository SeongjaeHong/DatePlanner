import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether [uri] is a Supabase password recovery callback for this app.
///
/// The flow marker distinguishes the web redirect from ordinary auth links;
/// a callback credential is also required so a manually opened URL cannot
/// expose the password form without a recovery session.
bool isPasswordRecoveryCallback(Uri uri) {
  final parameters = <String, String>{
    ...uri.queryParameters,
    ...Uri.splitQueryString(uri.fragment.replaceFirst(RegExp(r'^#'), '')),
  };
  final hasCallbackCredential = parameters.containsKey('code') ||
      (parameters['type'] == 'recovery' &&
          parameters.containsKey('access_token'));
  final isAppResetLink =
      uri.scheme == 'together-date-planner' && uri.host == 'reset-password';
  final isMarkedWebRedirect = parameters['auth_flow'] == 'password_recovery';
  return hasCallbackCredential && (isAppResetLink || isMarkedWebRedirect);
}

/// Whether a URL contains an auth callback credential, even if it lacks the
/// recovery marker used by newer reset emails.
bool hasAuthCallbackCredential(Uri uri) {
  final parameters = <String, String>{
    ...uri.queryParameters,
    ...Uri.splitQueryString(uri.fragment.replaceFirst(RegExp(r'^#'), '')),
  };
  return parameters.containsKey('code') ||
      parameters.containsKey('access_token') ||
      parameters.containsKey('error') ||
      parameters.containsKey('error_code');
}

/// Whether an auth event changes the app shell's signed-in or recovery view.
bool shouldRebuildAppForAuthEvent(AuthChangeEvent event) =>
    event == AuthChangeEvent.signedIn ||
    event == AuthChangeEvent.signedOut ||
    event == AuthChangeEvent.passwordRecovery;

/// Captures password-recovery auth events that Supabase emits during startup.
class PasswordRecoveryEventCapture {
  PasswordRecoveryEventCapture(Stream<AuthChangeEvent> events) {
    _subscription = events.listen((event) {
      if (event == AuthChangeEvent.passwordRecovery) {
        wasDetected = true;
        if (!_recoveryDetected.isCompleted) _recoveryDetected.complete();
      }
    });
  }

  late final StreamSubscription<AuthChangeEvent> _subscription;
  final Completer<void> _recoveryDetected = Completer<void>();
  bool wasDetected = false;

  Future<bool> waitForRecoveryEvent(Duration timeout) async {
    if (wasDetected) return true;
    try {
      await _recoveryDetected.future.timeout(timeout);
    } on TimeoutException {
      // A callback can be invalid or belong to another auth flow.
    }
    return wasDetected;
  }

  Future<void> dispose() => _subscription.cancel();
}

/// Waits for Supabase initialization and the async auth stream to deliver any
/// recovery event emitted while exchanging the initial callback URL.
Future<bool> capturePasswordRecoveryDuringStartup(
  Future<void> initialization,
  Stream<AuthChangeEvent> events, {
  bool waitForCallbackEvent = false,
}) async {
  final capture = PasswordRecoveryEventCapture(events);
  try {
    await initialization;
    // onAuthStateChange uses an asynchronous replay stream. Keep the listener
    // alive briefly for callback URLs because Supabase may finish the exchange
    // before the queued event is delivered.
    if (waitForCallbackEvent) {
      return await capture.waitForRecoveryEvent(const Duration(seconds: 1));
    }
    return capture.wasDetected;
  } finally {
    await capture.dispose();
  }
}
