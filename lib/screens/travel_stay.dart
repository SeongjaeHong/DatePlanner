import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../l10n/generated/app_localizations.dart';
import '../services/booking_service.dart';
import '../services/date_plan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/attachments.dart';

const _zones = [
  'Asia/Seoul',
  'Europe/Berlin',
  'Europe/London',
  'Europe/Paris',
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Toronto',
  'Asia/Tokyo',
  'Asia/Singapore',
  'Australia/Sydney',
  'Pacific/Honolulu',
  'UTC',
];

class TravelStayScreen extends StatefulWidget {
  const TravelStayScreen(
      {required this.plan,
      this.service,
      this.attachmentsEnabled = true,
      super.key});
  final DatePlan plan;
  final BookingService? service;
  final bool attachmentsEnabled;

  @override
  State<TravelStayScreen> createState() => _TravelStayScreenState();
}

class _TravelStayScreenState extends State<TravelStayScreen> {
  late final BookingService _service = widget.service ?? BookingService();
  late Future<(List<TransportBooking>, List<AccommodationBooking>)> _data =
      _load();

  @override
  void initState() {
    super.initState();
    ZonedWallTime.initialize();
  }

  Future<(List<TransportBooking>, List<AccommodationBooking>)> _load() async =>
      (
        await _service.listTransport(widget.plan.id),
        await _service.listAccommodation(widget.plan.id),
      );

  void _reload() => setState(() => _data = _load());

  Future<void> _transport([TransportBooking? old]) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TransportDialog(old: old),
    );
    if (data == null) return;
    try {
      await _service.saveTransport(widget.plan.id, data, old: old);
      _reload();
    } catch (_) {
      if (mounted) _error();
    }
  }

  Future<void> _stay([AccommodationBooking? old]) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StayDialog(old: old),
    );
    if (data == null) return;
    try {
      await _service.saveAccommodation(widget.plan.id, data, old: old);
      _reload();
    } catch (_) {
      if (mounted) _error();
    }
  }

  void _error() => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).bookingSaveError)),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return FutureBuilder<(List<TransportBooking>, List<AccommodationBooking>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingSkeleton(lines: 4);
        }
        if (snapshot.hasError) {
          return ErrorState(
              message: s.bookingsLoadError,
              retryLabel: s.retry,
              onRetry: _reload);
        }
        final (transport, stays) = snapshot.data!;
        if (transport.isEmpty && stays.isEmpty) {
          return EmptyState(
              title: s.noBookings,
              message: s.noBookingsBody,
              action: Wrap(spacing: AppSpacing.x2, children: [
                FilledButton.icon(
                    onPressed: _transport,
                    icon: const Icon(Icons.train),
                    label: Text(s.addTransport)),
                OutlinedButton.icon(
                    onPressed: _stay,
                    icon: const Icon(Icons.hotel_outlined),
                    label: Text(s.addStay)),
              ]));
        }
        return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.x8),
            children: [
              SectionHeader(
                  title: s.transport,
                  trailing: IconButton(
                      tooltip: s.addTransport,
                      onPressed: _transport,
                      icon: const Icon(Icons.add))),
              if (transport.isEmpty) Text(s.noTransport),
              for (final item in transport)
                _TransportTile(
                    item: item,
                    attachmentsEnabled: widget.attachmentsEnabled,
                    onTap: () => _transport(item)),
              const SizedBox(height: AppSpacing.x4),
              SectionHeader(
                  title: s.accommodation,
                  trailing: IconButton(
                      tooltip: s.addStay,
                      onPressed: _stay,
                      icon: const Icon(Icons.add))),
              if (stays.isEmpty) Text(s.noAccommodation),
              for (final item in stays)
                _StayTile(
                    item: item,
                    attachmentsEnabled: widget.attachmentsEnabled,
                    onTap: () => _stay(item)),
            ]);
      },
    );
  }
}

class _TransportTile extends StatelessWidget {
  const _TransportTile(
      {required this.item,
      required this.onTap,
      required this.attachmentsEnabled});
  final TransportBooking item;
  final VoidCallback onTap;
  final bool attachmentsEnabled;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
        child: Column(children: [
      ListTile(
        leading: Icon(item.mode == 'flight'
            ? Icons.flight
            : item.mode == 'train'
                ? Icons.train
                : Icons.directions_bus),
        title: Text(
            item.provider.isEmpty ? _modeLabel(s, item.mode) : item.provider),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (item.reference.isNotEmpty)
            Text('${s.bookingReference}: ${item.reference}'),
          for (final segment in item.segments) ...[
            Text('${segment.origin} → ${segment.destination}',
                style: Theme.of(context).textTheme.bodyLarge),
            Text(
                '${_formatZoned(context, segment.departsAt, segment.departsZone)} → ${_formatZoned(context, segment.arrivesAt, segment.arrivesZone)}'),
          ],
        ]),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4, 0, AppSpacing.x4, AppSpacing.x3),
        child: attachmentsEnabled
            ? BookingAttachments(
                planId: item.planId, transportBookingId: item.id)
            : const SizedBox.shrink(),
      ),
    ]));
  }
}

class _StayTile extends StatelessWidget {
  const _StayTile(
      {required this.item,
      required this.onTap,
      required this.attachmentsEnabled});
  final AccommodationBooking item;
  final VoidCallback onTap;
  final bool attachmentsEnabled;
  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final ci = local.formatMediumDate(item.checkIn.displayDate);
    final co = local.formatMediumDate(item.checkOut.displayDate);
    return Card(
        child: Column(children: [
      ListTile(
        leading: const Icon(Icons.hotel_outlined),
        title: Text(item.name),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (item.address.isNotEmpty) Text(item.address),
          Text(
              '${item.checkInTime == null ? '' : '${item.checkInTime} · '}$ci – $co'),
          if (item.reference.isNotEmpty)
            Text(
                '${AppLocalizations.of(context).bookingReference}: ${item.reference}'),
        ]),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4, 0, AppSpacing.x4, AppSpacing.x3),
        child: attachmentsEnabled
            ? BookingAttachments(
                planId: item.planId, accommodationBookingId: item.id)
            : const SizedBox.shrink(),
      ),
    ]));
  }
}

String _formatZoned(BuildContext context, DateTime instant, String zone) {
  final zoned = tz.TZDateTime.from(instant, tz.getLocation(zone));
  final time =
      TimeOfDay(hour: zoned.hour, minute: zoned.minute).format(context);
  return '${MaterialLocalizations.of(context).formatMediumDate(DateTime(zoned.year, zoned.month, zoned.day))} $time ($zone)';
}

class _TransportDialog extends StatefulWidget {
  const _TransportDialog({this.old});
  final TransportBooking? old;
  @override
  State<_TransportDialog> createState() => _TransportDialogState();
}

class _TransportDialogState extends State<_TransportDialog> {
  late final _provider =
      TextEditingController(text: widget.old?.provider ?? '');
  late final _reference =
      TextEditingController(text: widget.old?.reference ?? '');
  late final _origin = TextEditingController(
      text: widget.old?.segments.firstOrNull?.origin ?? '');
  late final _destination = TextEditingController(
      text: widget.old?.segments.firstOrNull?.destination ?? '');
  late final _notes = TextEditingController(text: widget.old?.notes ?? '');
  late String _mode = widget.old?.mode ?? 'train';
  late String _departZone =
      widget.old?.segments.firstOrNull?.departsZone ?? 'Asia/Seoul';
  late String _arriveZone =
      widget.old?.segments.firstOrNull?.arrivesZone ?? 'Europe/Berlin';
  late DateTime _depart = _zonedWall(
      widget.old?.segments.firstOrNull?.departsAt,
      _departZone,
      const Duration(days: 1));
  late DateTime _arrive = _zonedWall(
      widget.old?.segments.firstOrNull?.arrivesAt,
      _arriveZone,
      const Duration(days: 1, hours: 2));

  @override
  void dispose() {
    _provider.dispose();
    _reference.dispose();
    _origin.dispose();
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(bool departure, bool date) async {
    final value = departure ? _depart : _arrive;
    DateTime? next;
    if (date) {
      final chosen = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200));
      if (chosen != null) {
        next = DateTime(
            chosen.year, chosen.month, chosen.day, value.hour, value.minute);
      }
    } else {
      final chosen = await showTimePicker(
          context: context, initialTime: TimeOfDay.fromDateTime(value));
      if (chosen != null) {
        next = DateTime(
            value.year, value.month, value.day, chosen.hour, chosen.minute);
      }
    }
    if (next != null) {
      setState(() {
        if (departure) {
          _depart = next!;
        } else {
          _arrive = next!;
        }
      });
    }
  }

  Future<DateTime?> _resolve(DateTime wall, String zone) async {
    final candidates = ZonedWallTime.candidates(wall, zone);
    final s = AppLocalizations.of(context);
    if (candidates.isEmpty) {
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(s.invalidLocalTime),
                content: Text(s.dstGapBody),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.close))
                ],
              ));
      return null;
    }
    if (candidates.length == 1) return candidates.single;
    return showDialog<DateTime>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(s.ambiguousLocalTime),
              content: Text(s.dstOverlapBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, candidates.first),
                    child: Text(s.firstOccurrence)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, candidates.last),
                    child: Text(s.secondOccurrence)),
              ],
            ));
  }

  Future<void> _save() async {
    final departs = await _resolve(_depart, _departZone);
    if (departs == null || !mounted) return;
    final arrives = await _resolve(_arrive, _arriveZone);
    if (arrives == null || !mounted) return;
    if (!arrives.isAfter(departs) ||
        _origin.text.trim().isEmpty ||
        _destination.text.trim().isEmpty) {
      return;
    }
    Navigator.pop(context, {
      'mode': _mode,
      'provider_name': _provider.text.trim(),
      'booking_reference': _reference.text.trim(),
      'notes': _notes.text.trim(),
      'segments': [
        {
          'origin_text': _origin.text.trim(),
          'destination_text': _destination.text.trim(),
          'departs_at': departs.toIso8601String(),
          'departs_tz': _departZone,
          'arrives_at': arrives.toIso8601String(),
          'arrives_tz': _arriveZone
        }
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.old == null ? s.addTransport : s.editTransport),
      content: SizedBox(
          width: AppLayout.formColumn,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: InputDecoration(labelText: s.transportMode),
                items: ['train', 'flight', 'bus', 'other']
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(_modeLabel(s, m))))
                    .toList(),
                onChanged: (v) => setState(() => _mode = v ?? _mode)),
            const SizedBox(height: AppSpacing.x2),
            _field(_provider, s.providerName),
            _field(_reference, s.bookingReference),
            const Divider(),
            _field(_origin, s.origin),
            _zoneField(s.departureTimeZone, _departZone,
                (v) => setState(() => _departZone = v!)),
            _dateTimeButtons(s, true),
            _field(_destination, s.destination),
            _zoneField(s.arrivalTimeZone, _arriveZone,
                (v) => setState(() => _arriveZone = v!)),
            _dateTimeButtons(s, false),
            _field(_notes, s.bookingNotes, maxLines: 3),
          ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(onPressed: _save, child: Text(s.save))
      ],
    );
  }

  Widget _dateTimeButtons(AppLocalizations s, bool departure) {
    final value = departure ? _depart : _arrive;
    final date = MaterialLocalizations.of(context).formatMediumDate(value);
    final time = TimeOfDay.fromDateTime(value).format(context);
    return Wrap(children: [
      TextButton.icon(
          onPressed: () => _pick(departure, true),
          icon: const Icon(Icons.calendar_today),
          label: Text('${departure ? s.departure : s.arrival}: $date')),
      TextButton.icon(
          onPressed: () => _pick(departure, false),
          icon: const Icon(Icons.schedule),
          label: Text(time)),
    ]);
  }
}

class _StayDialog extends StatefulWidget {
  const _StayDialog({this.old});
  final AccommodationBooking? old;
  @override
  State<_StayDialog> createState() => _StayDialogState();
}

class _StayDialogState extends State<_StayDialog> {
  late final _name = TextEditingController(text: widget.old?.name ?? '');
  late final _address = TextEditingController(text: widget.old?.address ?? '');
  late final _reference =
      TextEditingController(text: widget.old?.reference ?? '');
  late final _notes = TextEditingController(text: widget.old?.notes ?? '');
  late CalendarDate _checkIn = widget.old?.checkIn ??
      CalendarDate.fromPicker(DateTime.now().add(const Duration(days: 1)));
  late CalendarDate _checkOut = widget.old?.checkOut ??
      CalendarDate.fromPicker(DateTime.now().add(const Duration(days: 2)));
  TimeOfDay? _time;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool checkIn) async {
    final value = checkIn ? _checkIn : _checkOut;
    final date = await showDatePicker(
        context: context,
        initialDate: value.displayDate,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200));
    if (date != null) {
      setState(() {
        if (checkIn) {
          _checkIn = CalendarDate.fromPicker(date);
        } else {
          _checkOut = CalendarDate.fromPicker(date);
        }
      });
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
        context: context,
        initialTime: _time ?? const TimeOfDay(hour: 15, minute: 0));
    if (selected != null) setState(() => _time = selected);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final local = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.old == null ? s.addStay : s.editStay),
      content: SizedBox(
          width: AppLayout.formColumn,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(_name, s.accommodationName),
            _field(_address, s.address),
            TextButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.login),
                label: Text(
                    '${s.checkIn}: ${local.formatMediumDate(_checkIn.displayDate)}')),
            TextButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.logout),
                label: Text(
                    '${s.checkOut}: ${local.formatMediumDate(_checkOut.displayDate)}')),
            TextButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(
                    '${s.checkInTime}: ${_time?.format(context) ?? s.optional}')),
            _field(_reference, s.bookingReference),
            _field(_notes, s.bookingNotes, maxLines: 3),
          ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty ||
                  _checkOut.compareTo(_checkIn) < 0) {
                return;
              }
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'address_text': _address.text.trim(),
                'check_in_date': _checkIn.iso,
                'check_out_date': _checkOut.iso,
                'check_in_local_time': _time == null
                    ? ''
                    : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}:00',
                'booking_reference': _reference.text.trim(),
                'notes': _notes.text.trim()
              });
            },
            child: Text(s.save))
      ],
    );
  }
}

Widget _field(TextEditingController controller, String label,
        {int maxLines = 1}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label)),
    );

Widget _zoneField(
        String label, String value, ValueChanged<String?> onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: _zones
          .map((zone) => DropdownMenuItem(value: zone, child: Text(zone)))
          .toList(),
      onChanged: onChanged,
    );

String _modeLabel(AppLocalizations s, String mode) => switch (mode) {
      'flight' => s.flight,
      'bus' => s.bus,
      'other' => s.other,
      _ => s.train,
    };

DateTime _zonedWall(DateTime? instant, String zone, Duration fallback) {
  ZonedWallTime.initialize();
  if (instant == null) {
    final local =
        tz.TZDateTime.from(DateTime.now().add(fallback), tz.getLocation(zone));
    return DateTime(
        local.year, local.month, local.day, local.hour, local.minute);
  }
  final local = tz.TZDateTime.from(instant, tz.getLocation(zone));
  return DateTime(local.year, local.month, local.day, local.hour, local.minute);
}
