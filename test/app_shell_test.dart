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
    testWidgets('adaptive navigation and connected shell at ${size.width} dp', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _ShellHarness());
      await tester.pumpAndSettle();

      if (size.width < AppLayout.compactBreakpoint) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('Plans'), findsWidgets);
        expect(find.text('Calendar'), findsOneWidget);
        expect(find.text('Space'), findsOneWidget);
      } else if (size.width < AppLayout.expandedBreakpoint) {
        expect(find.byType(NavigationRail), findsOneWidget);
      } else {
        expect(find.text('Together'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);
      }

      expect(find.textContaining('not available yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _ShellHarness extends StatelessWidget {
  const _ShellHarness();

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
    home: const AppShell(spaceName: 'Our Space'),
  );
}
