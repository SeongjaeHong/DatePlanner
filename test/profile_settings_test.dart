import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/screens/profile_settings.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  testWidgets('password change requires matching new-password confirmation',
      (tester) async {
    final actions = _FakeProfileAccountActions();
    await tester.pumpWidget(_app(actions));

    await tester.enterText(find.byType(TextField).at(0), 'current-password');
    await tester.enterText(find.byType(TextField).at(1), 'new-password');
    await tester.enterText(find.byType(TextField).at(2), 'different-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(actions.changeCount, 0);

    await tester.enterText(find.byType(TextField).at(2), 'new-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
    await tester.pumpAndSettle();
    expect(actions.changeCount, 1);
    expect(actions.lastCurrentPassword, 'current-password');
    expect(actions.lastNewPassword, 'new-password');
    expect(find.text('Your password has been changed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(ProfileAccountActions actions) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfileSettingsScreen(accountActions: actions),
    );

class _FakeProfileAccountActions implements ProfileAccountActions {
  int changeCount = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;

  @override
  String? get email => 'planner@example.com';

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changeCount++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
  }
}
