import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/screens/plans.dart';
import 'package:together_date_planner/services/date_plan_service.dart';
import 'package:together_date_planner/theme/app_theme.dart';

void main() {
  for (final size in <Size>[
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('Plans empty state fits at ${size.width} dp', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(_FakePlanRepository()));
      await tester.pumpAndSettle();
      expect(find.text('No plans yet'), findsOneWidget);
      expect(find.text('New plan'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop plan list opens the connected itinerary pane',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakePlanRepository();
    await repository.createPlan(
      spaceId: 'test-space',
      title: 'Desktop plan',
      start: CalendarDate.fromPicker(DateTime.now()),
      end: CalendarDate.fromPicker(DateTime.now()),
      notes: '',
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    expect(find.text('Choose a plan'), findsOneWidget);
    await tester.tap(find.text('Desktop plan').first);
    await tester.pumpAndSettle();
    expect(find.text('Desktop plan'), findsWidgets);
    expect(find.text('Nothing planned for this day'), findsOneWidget);
    expect(find.text('Add card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop itinerary date buttons scroll by mouse drag',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakePlanRepository();
    await repository.createPlan(
      spaceId: 'test-space',
      title: 'Long itinerary',
      start: CalendarDate.parse('2026-10-01'),
      end: CalendarDate.parse('2026-10-21'),
      notes: '',
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long itinerary').first);
    await tester.pumpAndSettle();

    final dateList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    expect(dateList, findsOneWidget);
    final scrollable = find.descendant(
      of: dateList,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      dateList,
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'medium layout opens and returns from a plan without losing shell',
      (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakePlanRepository();
    await repository.createPlan(
      spaceId: 'test-space',
      title: 'Tablet plan',
      start: CalendarDate.fromPicker(DateTime.now()),
      end: CalendarDate.fromPicker(DateTime.now()),
      notes: '',
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tablet plan'));
    await tester.pumpAndSettle();
    expect(find.text('Back to Plans'), findsOneWidget);
    expect(find.text('Nothing planned for this day'), findsOneWidget);
    await tester.tap(find.text('Back to Plans'));
    await tester.pumpAndSettle();
    expect(find.text('Tablet plan'), findsOneWidget);
  });

  testWidgets('plan creation continues to itinerary and accepts a text card',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakePlanRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New plan').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Weekend together');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Weekend together'), findsWidgets);
    expect(find.textContaining('Nothing planned for this day'), findsOneWidget);

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Museum visit');
    await tester.enterText(find.byType(TextField).last, 'Meet at the entrance');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Museum visit'), findsOneWidget);
    expect(find.text('Meet at the entrance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state retries into the empty state', (tester) async {
    final repository = _FakePlanRepository()..failPlanList = true;
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your plans.'), findsOneWidget);
    repository.failPlanList = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No plans yet'), findsOneWidget);
  });

  testWidgets('place fields persist through the connected card journey',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakePlanRepository();
    await repository.createPlan(
      spaceId: 'test-space',
      title: 'Place journey',
      start: CalendarDate.fromPicker(DateTime.now()),
      end: CalendarDate.fromPicker(DateTime.now()),
      notes: '',
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place journey').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Cafe');
    await tester.tap(find.text('Add place'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), 'Cafe Linden');
    await tester.enterText(fields.at(3), 'Berlin, Germany');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.cards.values.expand((items) => items).single.placeName,
        'Cafe Linden');
    expect(find.text('Cafe Linden'), findsOneWidget);
    expect(find.text('Berlin, Germany'), findsOneWidget);
    expect(find.text('Map not available · add coordinates to show a map'),
        findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);
    expect(find.text('Expand Map'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('calendar date keeps its exact ISO date value', () {
    final date = CalendarDate.parse('2026-12-01');
    expect(date.iso, '2026-12-01');
    expect(date.compareTo(CalendarDate.parse('2026-12-02')), lessThan(0));
  });
}

Widget _harness(PlanRepository repository) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _PlanSizeHost(),
      builder: (context, child) => _RepositoryScope(
        repository: repository,
        child: child!,
      ),
    );

class _RepositoryScope extends InheritedWidget {
  const _RepositoryScope({required this.repository, required super.child});
  final PlanRepository repository;
  static PlanRepository of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_RepositoryScope>()!
      .repository;
  @override
  bool updateShouldNotify(_RepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}

class _PlanSizeHost extends StatelessWidget {
  const _PlanSizeHost();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: PlansScreen(
          spaceId: 'test-space',
          repository: _RepositoryScope.of(context),
        ),
      );
}

class _FakePlanRepository implements PlanRepository {
  bool failPlanList = false;
  final plans = <String, DatePlan>{};
  final days = <String, List<PlanDay>>{};
  final cards = <String, List<ActivityCardData>>{};
  var _id = 0;

  String _next() => 'test-${_id++}';

  @override
  Future<List<DatePlan>> listPlans(String spaceId,
      {bool includeDeleted = false}) async {
    if (failPlanList) throw Exception('offline');
    return plans.values
        .where((p) => includeDeleted || p.deletedAt == null)
        .toList();
  }

  @override
  Future<DatePlan> getPlan(String planId) async => plans[planId]!;

  @override
  Future<List<PlanDay>> listDays(String planId) async => days[planId] ?? [];

  @override
  Future<List<ActivityCardData>> listCards(String dayId,
          {bool includeDeleted = false}) async =>
      (cards[dayId] ?? [])
          .where((c) => includeDeleted || c.deletedAt == null)
          .toList();

  @override
  Future<String> createPlan({
    required String spaceId,
    required String title,
    required CalendarDate start,
    required CalendarDate end,
    required String notes,
  }) async {
    final id = _next();
    plans[id] = DatePlan(
      id: id,
      spaceId: spaceId,
      title: title,
      startDate: start,
      endDate: end,
      notes: notes,
      version: 1,
      deletedAt: null,
    );
    final planDays = <PlanDay>[];
    for (var day = start.displayDate;
        !day.isAfter(end.displayDate);
        day = day.add(const Duration(days: 1))) {
      planDays.add(PlanDay(id: _next(), date: CalendarDate.fromPicker(day)));
    }
    days[id] = planDays;
    return id;
  }

  @override
  Future<DatePlan> updatePlan(DatePlan old,
          {required String title,
          required CalendarDate start,
          required CalendarDate end,
          required String notes}) async =>
      plans[old.id] = DatePlan(
        id: old.id,
        spaceId: old.spaceId,
        title: title,
        startDate: start,
        endDate: end,
        notes: notes,
        version: old.version + 1,
        deletedAt: old.deletedAt,
      );

  @override
  Future<DatePlan> setPlanDeleted(DatePlan plan, bool deleted) async =>
      plans[plan.id] = DatePlan(
        id: plan.id,
        spaceId: plan.spaceId,
        title: plan.title,
        startDate: plan.startDate,
        endDate: plan.endDate,
        notes: plan.notes,
        version: plan.version + 1,
        deletedAt: deleted ? DateTime.now().toIso8601String() : null,
      );

  @override
  Future<String> createCard(
      String dayId, String kind, String title, String body,
      {String? placeName,
      String? placeAddress,
      double? placeLatitude,
      double? placeLongitude}) async {
    final id = _next();
    cards.putIfAbsent(dayId, () => []).add(ActivityCardData(
          id: id,
          dayId: dayId,
          kind: kind,
          title: title,
          body: body,
          placeName: placeName,
          placeAddress: placeAddress,
          placeLatitude: placeLatitude,
          placeLongitude: placeLongitude,
          version: 1,
          deletedAt: null,
        ));
    return id;
  }

  @override
  Future<ActivityCardData> updateCard(ActivityCardData old,
      {required String kind,
      required String title,
      required String body,
      String? placeName,
      String? placeAddress,
      double? placeLatitude,
      double? placeLongitude,
      int? expectedVersion}) async {
    final updated = ActivityCardData(
      id: old.id,
      dayId: old.dayId,
      kind: kind,
      title: title,
      body: body,
      placeName: placeName,
      placeAddress: placeAddress,
      placeLatitude: placeLatitude,
      placeLongitude: placeLongitude,
      version: old.version + 1,
      deletedAt: old.deletedAt,
    );
    cards[old.dayId]![cards[old.dayId]!.indexWhere((c) => c.id == old.id)] =
        updated;
    return updated;
  }

  @override
  Future<void> setCardDeleted(ActivityCardData card, bool deleted) async {
    final updated = ActivityCardData(
      id: card.id,
      dayId: card.dayId,
      kind: card.kind,
      title: card.title,
      body: card.body,
      version: card.version + 1,
      deletedAt: deleted ? DateTime.now().toIso8601String() : null,
    );
    cards[card.dayId]![cards[card.dayId]!.indexWhere((c) => c.id == card.id)] =
        updated;
  }

  @override
  Future<void> moveCard(
      ActivityCardData card, String targetDayId, int index) async {
    cards[card.dayId]!.removeWhere((c) => c.id == card.id);
    final target = cards.putIfAbsent(targetDayId, () => []);
    target.insert(index.clamp(0, target.length), card);
  }
}
