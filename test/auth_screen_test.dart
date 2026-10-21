import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/main.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  testWidgets('sign-up opens a distinct page and validates confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const _SignInHarness());

    expect(find.text('Sign in to start planning together.'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Set up your account to start planning in your private Space.'),
        findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));

    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('Enter your email address.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'planner@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 6 characters for your password.'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'strong-password');
    await tester.enterText(
        find.byType(TextField).at(2), 'a-different-password');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot-password page validates email before sending', (
    tester,
  ) async {
    await tester.pumpWidget(const _SignInHarness());
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send reset email'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password recovery validates the replacement before updating', (
    tester,
  ) async {
    await tester.pumpWidget(const _RecoveryHarness());
    await tester.enterText(find.byType(TextField).at(0), 'short');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 6 characters for your password.'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'a-strong-password');
    await tester.enterText(find.byType(TextField).at(1), 'another-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SignInHarness extends StatelessWidget {
  const _SignInHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SignInScreen(),
      );
}

class _RecoveryHarness extends StatelessWidget {
  const _RecoveryHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PasswordRecoveryScreen(),
      );
}
