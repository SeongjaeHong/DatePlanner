import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'date_plan_service.dart';

class TransportSegment {
  const TransportSegment(
      {required this.id,
      required this.origin,
      required this.destination,
      required this.departsAt,
      required this.departsZone,
      required this.arrivesAt,
      required this.arrivesZone,
      required this.sequence});
  final String id, origin, destination, departsZone, arrivesZone;
  final DateTime departsAt, arrivesAt;
  final int sequence;
  factory TransportSegment.fromJson(Map<String, dynamic> row) =>
      TransportSegment(
        id: row['id'] as String,
        origin: row['origin_text'] as String,
        destination: row['destination_text'] as String,
        departsAt: DateTime.parse(row['departs_at'] as String).toUtc(),
        departsZone: row['departs_tz'] as String,
        arrivesAt: DateTime.parse(row['arrives_at'] as String).toUtc(),
        arrivesZone: row['arrives_tz'] as String,
        sequence: (row['sequence'] as num).toInt(),
      );
}

class TransportBooking {
  const TransportBooking(
      {required this.id,
      required this.planId,
      required this.mode,
      required this.provider,
      required this.reference,
      required this.notes,
      required this.version,
      required this.segments});
  final String id, planId, mode, provider, reference, notes;
  final int version;
  final List<TransportSegment> segments;
  factory TransportBooking.fromJson(
          Map<String, dynamic> row, List<TransportSegment> segments) =>
      TransportBooking(
        id: row['id'] as String,
        planId: row['plan_id'] as String,
        mode: row['mode'] as String,
        provider: row['provider_name'] as String? ?? '',
        reference: row['booking_reference'] as String? ?? '',
        notes: row['notes'] as String? ?? '',
        version: (row['version'] as num).toInt(),
        segments: segments,
      );
}

class AccommodationBooking {
  const AccommodationBooking(
      {required this.id,
      required this.planId,
      required this.name,
      required this.address,
      required this.checkIn,
      required this.checkOut,
      required this.checkInTime,
      required this.reference,
      required this.notes,
      required this.version});
  final String id, planId, name, address, reference, notes;
  final CalendarDate checkIn, checkOut;
  final String? checkInTime;
  final int version;
  factory AccommodationBooking.fromJson(Map<String, dynamic> row) =>
      AccommodationBooking(
        id: row['id'] as String,
        planId: row['plan_id'] as String,
        name: row['name'] as String,
        address: row['address_text'] as String? ?? '',
        checkIn: CalendarDate.parse(row['check_in_date'] as String),
        checkOut: CalendarDate.parse(row['check_out_date'] as String),
        checkInTime: row['check_in_local_time'] as String?,
        reference: row['booking_reference'] as String? ?? '',
        notes: row['notes'] as String? ?? '',
        version: (row['version'] as num).toInt(),
      );
}

class BookingConflict implements Exception {
  const BookingConflict();
}

/// IANA wall-time resolver. Zero matches is a DST gap; two matches is an
/// overlap and must be explicitly resolved by the editor.
class ZonedWallTime {
  static bool _initialized = false;
  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static List<DateTime> candidates(DateTime local, String zone) {
    initialize();
    final location = tz.getLocation(zone);
    final wall = DateTime.utc(
        local.year, local.month, local.day, local.hour, local.minute);
    final offsets = <Duration>{};
    for (var minute = -36 * 60; minute <= 36 * 60; minute += 30) {
      final instant = wall.add(Duration(minutes: minute));
      offsets.add(tz.TZDateTime.from(instant, location).timeZoneOffset);
    }
    final matches = <DateTime>[];
    for (final offset in offsets) {
      final instant = wall.subtract(offset);
      final zoned = tz.TZDateTime.from(instant, location);
      if (zoned.year == local.year &&
          zoned.month == local.month &&
          zoned.day == local.day &&
          zoned.hour == local.hour &&
          zoned.minute == local.minute) {
        matches.add(instant.toUtc());
      }
    }
    matches.sort();
    return matches;
  }
}

class BookingService {
  BookingService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<List<TransportBooking>> listTransport(String planId) async {
    final rows = await _client
        .from('transport_bookings')
        .select()
        .eq('plan_id', planId)
        .isFilter('deleted_at', null)
        .order('created_at');
    final result = <TransportBooking>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final segments = await _client
          .from('transport_segments')
          .select()
          .eq('booking_id', row['id'])
          .order('sequence');
      result.add(TransportBooking.fromJson(
          row,
          segments
              .map((item) =>
                  TransportSegment.fromJson(Map<String, dynamic>.from(item)))
              .toList()));
    }
    return result;
  }

  Future<List<AccommodationBooking>> listAccommodation(String planId) async {
    final rows = await _client
        .from('accommodation_bookings')
        .select()
        .eq('plan_id', planId)
        .isFilter('deleted_at', null)
        .order('check_in_date');
    return rows
        .map((row) =>
            AccommodationBooking.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> saveTransport(String planId, Map<String, dynamic> data,
      {TransportBooking? old}) async {
    final response = Map<String, dynamic>.from(
        await _client.rpc('save_transport_booking', params: {
      'p_plan_id': planId,
      'p_booking_id': old?.id,
      'p_expected_version': old?.version,
      'p_data': data,
    }) as Map);
    if (response['error_code'] == 'CONFLICT') throw const BookingConflict();
    if (response['error_code'] != null) throw Exception(response['error_code']);
  }

  Future<void> setTransportDeleted(TransportBooking booking) async {
    final response = Map<String, dynamic>.from(
        await _client.rpc('set_transport_booking_deleted', params: {
      'p_booking_id': booking.id,
      'p_expected_version': booking.version,
      'p_deleted': true,
    }) as Map);
    if (response['error_code'] != null) throw Exception(response['error_code']);
  }

  Future<void> saveAccommodation(String planId, Map<String, dynamic> data,
      {AccommodationBooking? old}) async {
    final response = Map<String, dynamic>.from(
        await _client.rpc('save_accommodation_booking', params: {
      'p_plan_id': planId,
      'p_booking_id': old?.id,
      'p_expected_version': old?.version,
      'p_data': data,
    }) as Map);
    if (response['error_code'] == 'CONFLICT') throw const BookingConflict();
    if (response['error_code'] != null) throw Exception(response['error_code']);
  }
}
