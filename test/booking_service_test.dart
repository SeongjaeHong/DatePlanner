import 'package:flutter_test/flutter_test.dart';
import 'package:together_date_planner/services/booking_service.dart';

void main() {
  test('IANA resolver distinguishes DST gaps and overlaps', () {
    expect(
      ZonedWallTime.candidates(DateTime(2026, 3, 8, 2, 30), 'America/New_York'),
      isEmpty,
    );
    final overlap = ZonedWallTime.candidates(
      DateTime(2026, 11, 1, 1, 30),
      'America/New_York',
    );
    expect(overlap, hasLength(2));
    expect(overlap.last.difference(overlap.first), const Duration(hours: 1));
  });

  test('travel endpoint instants remain independent across viewer zones', () {
    final departure = ZonedWallTime.candidates(
      DateTime(2026, 12, 20, 9),
      'Asia/Seoul',
    ).single;
    final arrival = ZonedWallTime.candidates(
      DateTime(2026, 12, 20, 13),
      'Europe/Berlin',
    ).single;
    expect(departure.toIso8601String(), '2026-12-20T00:00:00.000Z');
    expect(arrival.toIso8601String(), '2026-12-20T12:00:00.000Z');
  });
}
