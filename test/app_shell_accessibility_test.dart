import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/main.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  for (final size in <Size>[
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('app shell supports 200 percent text at ${size.width} dp', (
      tester,
    ) async {
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
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: const AppShell(spaceName: 'Our Space'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plans'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
