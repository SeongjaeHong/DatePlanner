import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/screens/calendar.dart';
import 'package:together_date_planner/services/booking_service.dart';
import 'package:together_date_planner/services/date_plan_service.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  for (final size in <Size>[
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('Calendar populated state fits at ${size.width} dp',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plans = _CalendarPlans.withPlan();
      await tester.pumpWidget(_harness(
        plans: plans,
        loadTransport: (_) async => [],
      ));
      await tester.pumpAndSettle();
      expect(find.text('A weekend together'), findsOneWidget);
      expect(find.textContaining('Date Plan'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('travel marker displays its own zone and time', (tester) async {
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final plan = _CalendarPlans.withPlan(date: date);
    final booking = TransportBooking(
      id: 'booking-1',
      planId: 'plan-1',
      mode: 'train',
      provider: 'Rail Company',
      reference: '',
      notes: '',
      version: 1,
      segments: [
        TransportSegment(
          id: 'segment-1',
          origin: 'Berlin',
          destination: 'Airport',
          departsAt: DateTime.utc(date.year, date.month, date.day, 9, 20),
          departsZone: 'UTC',
          arrivesAt: DateTime.utc(date.year, date.month, date.day, 10, 20),
          arrivesZone: 'UTC',
          sequence: 0,
        ),
      ],
    );
    await tester.pumpWidget(_harness(
      plans: plan,
      loadTransport: (_) async => [booking],
    ));
    await tester.pumpAndSettle();
    expect(find.text('9:20 AM · UTC · Departure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan span opens its plan and Back returns to Calendar',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(
      plans: _CalendarPlans.withPlan(),
      loadTransport: (_) async => [],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('A weekend together'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing planned for this day'), findsOneWidget);
    expect(find.text('Back to calendar'), findsOneWidget);
    await tester.tap(find.text('Back to calendar'));
    await tester.pumpAndSettle();
    expect(find.text('A weekend together'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calendar load error can retry into the empty state',
      (tester) async {
    final plans = _CalendarPlans()..failList = true;
    await tester.pumpWidget(_harness(
      plans: plans,
      loadTransport: (_) async => [],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Could not load calendar events.'), findsOneWidget);

    plans.failList = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing scheduled'), findsOneWidget);
    expect(find.text('View plans'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _harness({
  required _CalendarPlans plans,
  required Future<List<TransportBooking>> Function(String planId) loadTransport,
  VoidCallback? onViewPlans,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CalendarScreen(
          spaceId: 'test-space',
          repository: plans,
          loadTransport: loadTransport,
          onViewPlans: onViewPlans ?? () {},
        ),
      ),
    );

class _CalendarPlans implements PlanRepository {
  _CalendarPlans();

  bool failList = false;
  final List<DatePlan> plans = [];

  factory _CalendarPlans.withPlan({DateTime? date}) {
    final start = date ?? DateTime.now();
    final end = start.add(const Duration(days: 1));
    return _CalendarPlans()
      ..plans.add(DatePlan(
        id: 'plan-1',
        spaceId: 'test-space',
        title: 'A weekend together',
        startDate: CalendarDate(start.year, start.month, start.day),
        endDate: CalendarDate(end.year, end.month, end.day),
        notes: '',
        version: 1,
        deletedAt: null,
      ));
  }

  @override
  Future<List<DatePlan>> listPlans(String spaceId,
      {bool includeDeleted = false}) async {
    if (failList) throw Exception('offline');
    return plans;
  }

  @override
  Future<List<PlanDay>> listDays(String planId) async => [
        PlanDay(
          id: 'day-1',
          date: plans.first.startDate,
        ),
      ];

  @override
  Future<List<ActivityCardData>> listCards(String dayId,
          {bool includeDeleted = false}) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
