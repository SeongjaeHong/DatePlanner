import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/main.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  testWidgets('account creation validates fields before contacting Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(const _SignInHarness());

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.enterText(find.byType(TextField).last, 'a-strong-password');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'planner@example.com');
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(find.text('Please wait…'), findsNothing);
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
