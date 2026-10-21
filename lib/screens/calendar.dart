import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/generated/app_localizations.dart';
import '../services/booking_service.dart';
import '../services/date_plan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import 'plans.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen(
      {required this.spaceId,
      required this.onViewPlans,
      this.repository,
      this.loadTransport,
      super.key});
  final String spaceId;
  final VoidCallback onViewPlans;
  final PlanRepository? repository;
  final Future<List<TransportBooking>> Function(String planId)? loadTransport;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final PlanRepository _plans = widget.repository ?? DatePlanService();
  late final _bookings = BookingService();
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _day(DateTime.now());
  late Future<_CalendarData> _data = _load();
  DatePlan? _openedPlan;
  bool _openedTravel = false;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  Future<_CalendarData> _load() async {
    final plans = await _plans.listPlans(widget.spaceId);
    final transports = <String, List<TransportBooking>>{};
    for (final plan in plans) {
      transports[plan.id] = widget.loadTransport == null
          ? await _bookings.listTransport(plan.id)
          : await widget.loadTransport!(plan.id);
    }
    return _CalendarData(plans, transports);
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  void _moveMonth(int amount) => setState(() {
        _month = DateTime(_month.year, _month.month + amount);
        if (_selected.month != _month.month || _selected.year != _month.year) {
          _selected = DateTime(_month.year, _month.month, 1);
        }
      });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < AppLayout.compactBreakpoint
        ? AppSpacing.x3
        : width < AppLayout.expandedBreakpoint
            ? AppSpacing.mediumScreen
            : AppSpacing.expandedScreen;
    if (_openedPlan case final plan?) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _openedPlan = null),
              icon: const Icon(Icons.arrow_back),
              label: Text(strings.calendarBack),
            ),
          ),
          Expanded(
            child: PlanDetailScreen(
              key: ValueKey('calendar-${plan.id}'),
              plan: plan,
              service: _plans,
              onChanged: _reload,
              initialTravel: _openedTravel,
              onBack: () => setState(() => _openedPlan = null),
            ),
          ),
        ]),
      );
    }
    return FutureBuilder<_CalendarData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.all(padding),
            child: const LoadingSkeleton(lines: 5),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: strings.calendarLoadError,
            retryLabel: strings.retry,
            onRetry: _reload,
          );
        }
        final data = snapshot.data!;
        final events = _eventsFor(_selected, data);
        return Padding(
          padding: EdgeInsets.all(padding),
          child: width >= 900
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 3, child: _monthView(data, strings)),
                  const SizedBox(width: AppSpacing.x6),
                  Expanded(flex: 2, child: _agenda(events, data, strings)),
                ])
              : SingleChildScrollView(
                  child: Column(children: [
                    _monthView(data, strings),
                    const SizedBox(height: AppSpacing.x4),
                    SizedBox(
                        height: 320, child: _agenda(events, data, strings)),
                  ]),
                ),
        );
      },
    );
  }

  Widget _monthView(_CalendarData data, AppLocalizations strings) {
    final material = MaterialLocalizations.of(context);
    final first = DateTime(_month.year, _month.month, 1);
    final offset = ((first.weekday % 7) - material.firstDayOfWeekIndex + 7) % 7;
    final gridStart = first.subtract(Duration(days: offset));
    final days = List.generate(42, (i) => gridStart.add(Duration(days: i)));
    final eventDates = <String>{};
    for (final plan in data.plans) {
      for (var d = plan.startDate.displayDate;
          !d.isAfter(plan.endDate.displayDate);
          d = d.add(const Duration(days: 1))) {
        eventDates.add(_key(d));
      }
    }
    for (final bookings in data.transports.values) {
      for (final booking in bookings) {
        for (final segment in booking.segments) {
          for (final instantAndZone in [
            (segment.departsAt, segment.departsZone),
            (segment.arrivesAt, segment.arrivesZone),
          ]) {
            final date = _inZone(instantAndZone.$1, instantAndZone.$2);
            eventDates.add(_key(date));
          }
        }
      }
    }
    final weekdays = List.generate(7, (i) {
      final weekday = (material.firstDayOfWeekIndex + i) % 7;
      return material.narrowWeekdays[weekday];
    });
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SectionHeader(
        title: strings.calendar,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton48(
            icon: Icons.chevron_left,
            tooltip: strings.calendarPreviousMonth,
            onPressed: () => _moveMonth(-1),
          ),
          Text(material.formatMonthYear(_month),
              style: Theme.of(context).textTheme.titleMedium),
          IconButton48(
            icon: Icons.chevron_right,
            tooltip: strings.calendarNextMonth,
            onPressed: () => _moveMonth(1),
          ),
        ]),
      ),
      Row(children: [
        for (final label in weekdays)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                child:
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          ),
      ]),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: days.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: AppTouchTarget.minimum,
        ),
        itemBuilder: (context, index) {
          final date = days[index];
          final selected = _key(date) == _key(_selected);
          final inMonth = date.month == _month.month;
          final hasEvent = eventDates.contains(_key(date));
          return Semantics(
            button: true,
            selected: selected,
            label: material.formatFullDate(date),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => setState(() => _selected = date),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${date.day}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : inMonth
                                        ? null
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: .55),
                                fontWeight: selected ? FontWeight.w700 : null,
                              )),
                    ),
                    SizedBox(
                        height: 5,
                        child: hasEvent
                            ? Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null),
                  ]),
            ),
          );
        },
      ),
      const SizedBox(height: AppSpacing.x2),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            final now = DateTime.now();
            _month = DateTime(now.year, now.month);
            _selected = _day(now);
          }),
          icon: const Icon(Icons.today),
          label: Text(strings.calendarToday),
        ),
      ),
    ]);
  }

  Widget _agenda(List<_CalendarEvent> events, _CalendarData data,
      AppLocalizations strings) {
    final material = MaterialLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: material.formatFullDate(_selected)),
      Expanded(
        child: events.isEmpty
            ? EmptyState(
                title: strings.calendarNothingScheduled,
                message: strings.calendarNothingScheduledBody,
                action: FilledButton.icon(
                  onPressed: widget.onViewPlans,
                  icon: const Icon(Icons.favorite_outline),
                  label: Text(strings.calendarViewPlans),
                ),
              )
            : ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.x2),
                itemBuilder: (context, index) {
                  final event = events[index];
                  DatePlan? plan;
                  for (final candidate in data.plans) {
                    if (candidate.id == event.planId) {
                      plan = candidate;
                      break;
                    }
                  }
                  final color = event.kind == _EventKind.plan
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                          event.kind == _EventKind.plan
                              ? Icons.favorite_outline
                              : event.kind == _EventKind.departure
                                  ? Icons.flight_takeoff
                                  : Icons.flight_land,
                          color: color),
                      title: Text(event.title),
                      subtitle: Text(event.detail),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: plan == null
                          ? null
                          : () => setState(() {
                                _openedPlan = plan;
                                _openedTravel = event.kind != _EventKind.plan;
                              }),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  List<_CalendarEvent> _eventsFor(DateTime date, _CalendarData data) {
    final events = <_CalendarEvent>[];
    for (final plan in data.plans) {
      if (!date.isBefore(plan.startDate.displayDate) &&
          !date.isAfter(plan.endDate.displayDate)) {
        events.add(_CalendarEvent(
          plan.id,
          _EventKind.plan,
          plan.title,
          '${AppLocalizations.of(context).calendarPlanPeriod} · ${MaterialLocalizations.of(context).formatMediumDate(plan.startDate.displayDate)} – ${MaterialLocalizations.of(context).formatMediumDate(plan.endDate.displayDate)}',
        ));
      }
    }
    for (final entry in data.transports.entries) {
      for (final booking in entry.value) {
        for (final segment in booking.segments) {
          final departure = _inZone(segment.departsAt, segment.departsZone);
          final arrival = _inZone(segment.arrivesAt, segment.arrivesZone);
          if (_key(departure) == _key(date)) {
            events.add(_CalendarEvent(
              entry.key,
              _EventKind.departure,
              '${segment.origin} → ${segment.destination}',
              '${_time(departure)} · ${segment.departsZone} · ${AppLocalizations.of(context).calendarDeparture}',
              sortTime: segment.departsAt,
            ));
          }
          if (_key(arrival) == _key(date)) {
            events.add(_CalendarEvent(
              entry.key,
              _EventKind.arrival,
              '${segment.origin} → ${segment.destination}',
              '${_time(arrival)} · ${segment.arrivesZone} · ${AppLocalizations.of(context).calendarArrival}',
              sortTime: segment.arrivesAt,
            ));
          }
        }
      }
    }
    events.sort((a, b) {
      if (a.sortTime == null) {
        return b.sortTime == null ? a.title.compareTo(b.title) : -1;
      }
      if (b.sortTime == null) return 1;
      return a.sortTime!.compareTo(b.sortTime!);
    });
    return events;
  }

  DateTime _inZone(DateTime instant, String zone) {
    tz_data.initializeTimeZones();
    final zoned = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return DateTime(
        zoned.year, zoned.month, zoned.day, zoned.hour, zoned.minute);
  }

  String _time(DateTime date) => MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay(hour: date.hour, minute: date.minute));

  String _key(DateTime date) => '${date.year}-${date.month}-${date.day}';
}

class _CalendarData {
  const _CalendarData(this.plans, this.transports);
  final List<DatePlan> plans;
  final Map<String, List<TransportBooking>> transports;
}

enum _EventKind { plan, departure, arrival }

class _CalendarEvent {
  const _CalendarEvent(this.planId, this.kind, this.title, this.detail,
      {this.sortTime});
  final String planId;
  final _EventKind kind;
  final String title;
  final String detail;
  final DateTime? sortTime;
}
