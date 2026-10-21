import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/screens/space_invitations.dart';
import 'package:together_date_planner/services/space_invitation_service.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  for (final size in <Size>[
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('join code entry fits at ${size.width} dp', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: JoinInvitationScreen(onJoined: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Join a Space'), findsOneWidget);
      expect(find.text('Invitation code'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('join operation ids are v4-shaped and distinct', () {
    const service = SpaceInvitationService();
    final first = service.newOperationId();
    final second = service.newOperationId();
    expect(
        first, matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')));
    expect(first, isNot(second));
  });
}
