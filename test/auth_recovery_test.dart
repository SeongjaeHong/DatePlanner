import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:together_date_planner/auth_recovery.dart';

void main() {
  group('isPasswordRecoveryCallback', () {
    test('accepts marked web PKCE callback', () {
      expect(
        isPasswordRecoveryCallback(Uri.parse(
          'https://example.test/?auth_flow=password_recovery&code=abc',
        )),
        isTrue,
      );
    });

    test('accepts marked web token callback', () {
      expect(
        isPasswordRecoveryCallback(Uri.parse(
          'https://example.test/?auth_flow=password_recovery#access_token=abc&type=recovery',
        )),
        isTrue,
      );
    });

    test('accepts Android recovery deep link', () {
      expect(
        isPasswordRecoveryCallback(Uri.parse(
          'together-date-planner://reset-password/?code=abc',
        )),
        isTrue,
      );
    });

    test('rejects ordinary sign-in and incomplete reset URLs', () {
      expect(isPasswordRecoveryCallback(Uri.parse('https://example.test/')),
          isFalse);
      expect(
        isPasswordRecoveryCallback(Uri.parse(
          'https://example.test/?auth_flow=password_recovery',
        )),
        isFalse,
      );
    });
  });

  test('captures recovery events emitted during startup', () async {
    final events = StreamController<AuthChangeEvent>();
    final capture = PasswordRecoveryEventCapture(events.stream);

    events.add(AuthChangeEvent.passwordRecovery);
    await Future<void>.delayed(Duration.zero);

    expect(capture.wasDetected, isTrue);
    await capture.dispose();
    await events.close();
  });

  test('refreshes the app shell after sign-in and sign-out', () {
    expect(shouldRebuildAppForAuthEvent(AuthChangeEvent.signedIn), isTrue);
    expect(shouldRebuildAppForAuthEvent(AuthChangeEvent.signedOut), isTrue);
    expect(
        shouldRebuildAppForAuthEvent(AuthChangeEvent.passwordRecovery), isTrue);
    expect(
        shouldRebuildAppForAuthEvent(AuthChangeEvent.tokenRefreshed), isFalse);
  });

  test('waits for a recovery event queued just after initialization', () async {
    final events = StreamController<AuthChangeEvent>();
    final initialized = Completer<void>();
    final detected = capturePasswordRecoveryDuringStartup(
      initialized.future,
      events.stream,
      waitForCallbackEvent: true,
    );

    initialized.complete();
    Timer(const Duration(milliseconds: 20),
        () => events.add(AuthChangeEvent.passwordRecovery));

    expect(await detected, isTrue);
    await events.close();
  });

  test('recognizes an unmarked PKCE callback URL as an auth callback', () {
    expect(
      hasAuthCallbackCredential(
        Uri.parse('http://localhost:52572/?code=placeholder'),
      ),
      isTrue,
    );
  });
}
