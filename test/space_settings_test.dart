import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/screens/space_settings.dart';
import 'package:together_date_planner/services/space_lifecycle_service.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  for (final size in <Size>[
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('settings fit at ${size.width} dp', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(const _Host()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(find.text('Leave Space'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('last member must type DELETE and acknowledge permanence',
      (tester) async {
    final actions = _FakeLifecycleActions();
    await tester.pumpWidget(_app(_Host(actions: actions, memberCount: 1)));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave Space'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 plans'), findsOneWidget);
    expect(find.textContaining('3 files'), findsOneWidget);
    final proceed = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(proceed).onPressed, isNotNull);
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(actions.leaveCount, 1);
    expect(actions.lastExpectedMemberCount, 1);
    expect(actions.lastConfirmationWord, 'DELETE');
    expect(actions.spaceChanged, isTrue);
  });

  testWidgets('two-member leave discloses partner keeps shared content',
      (tester) async {
    final actions = _FakeLifecycleActions();
    await tester.pumpWidget(_app(_Host(actions: actions, memberCount: 2)));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave Space'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your partner keeps all shared plans and files'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(actions.lastExpectedMemberCount, 2);
    expect(actions.lastConfirmationWord, isEmpty);
    expect(actions.spaceChanged, isTrue);
  });

  testWidgets('account deletion requires typed DELETE even with a partner',
      (tester) async {
    final actions = _FakeLifecycleActions();
    await tester.pumpWidget(_app(_Host(actions: actions, memberCount: 2)));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Your account and profile will be permanently removed'),
        findsOneWidget);
    final proceed = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(actions.deleteCount, 1);
    expect(actions.lastExpectedMemberCount, 2);
    expect(actions.lastConfirmationWord, 'DELETE');
  });
}

Widget _app(_Host host) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: host,
    );

class _Host extends StatelessWidget {
  const _Host({this.actions, this.memberCount = 2});
  final _FakeLifecycleActions? actions;
  final int memberCount;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SpaceSettingsScreen(
                memberCount: memberCount,
                lifecycleService: actions,
                onSpaceChanged: () async {
                  actions?.spaceChanged = true;
                },
              ),
            )),
            child: const Text('Open settings'),
          ),
        ),
      );
}

class _FakeLifecycleActions implements SpaceLifecycleActions {
  int leaveCount = 0;
  int deleteCount = 0;
  int? lastExpectedMemberCount;
  String? lastConfirmationWord;
  bool spaceChanged = false;

  @override
  Future<SpaceDeletionPreview> loadDeletionPreview() async =>
      const SpaceDeletionPreview(plans: 2, files: 3);

  @override
  Future<SpaceLeaveResult> leaveSpace({
    required int expectedMemberCount,
    required String confirmationWord,
  }) async {
    leaveCount++;
    lastExpectedMemberCount = expectedMemberCount;
    lastConfirmationWord = confirmationWord;
    return SpaceLeaveResult(
      errorCode: 'completed',
      lastMember: expectedMemberCount == 1,
    );
  }

  @override
  Future<void> deleteAccount({
    required int expectedMemberCount,
    required String confirmationWord,
  }) async {
    deleteCount++;
    lastExpectedMemberCount = expectedMemberCount;
    lastConfirmationWord = confirmationWord;
  }
}
