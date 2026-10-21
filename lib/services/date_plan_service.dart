import 'package:supabase_flutter/supabase_flutter.dart';

/// A calendar date with no time or time-zone semantics.
class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  factory CalendarDate.parse(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return CalendarDate(parts[0], parts[1], parts[2]);
  }

  factory CalendarDate.fromPicker(DateTime value) =>
      CalendarDate(value.year, value.month, value.day);

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  DateTime get displayDate => DateTime(year, month, day);

  @override
  int compareTo(CalendarDate other) => iso.compareTo(other.iso);
}

class DatePlan {
  const DatePlan({
    required this.id,
    required this.spaceId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.notes,
    required this.version,
    required this.deletedAt,
  });

  final String id;
  final String spaceId;
  final String title;
  final CalendarDate startDate;
  final CalendarDate endDate;
  final String notes;
  final int version;
  final String? deletedAt;

  factory DatePlan.fromJson(Map<String, dynamic> row) => DatePlan(
        id: row['id'] as String,
        spaceId: row['space_id'] as String,
        title: row['title'] as String,
        startDate: CalendarDate.parse(row['start_date'] as String),
        endDate: CalendarDate.parse(row['end_date'] as String),
        notes: row['notes'] as String? ?? '',
        version: (row['version'] as num).toInt(),
        deletedAt: row['deleted_at'] as String?,
      );
}

class PlanDay {
  const PlanDay({required this.id, required this.date});
  final String id;
  final CalendarDate date;

  factory PlanDay.fromJson(Map<String, dynamic> row) => PlanDay(
        id: row['id'] as String,
        date: CalendarDate.parse(row['day_date'] as String),
      );
}

class ActivityCardData {
  const ActivityCardData({
    required this.id,
    required this.dayId,
    required this.kind,
    required this.title,
    required this.body,
    this.placeName,
    this.placeAddress,
    this.placeLatitude,
    this.placeLongitude,
    required this.version,
    required this.deletedAt,
  });

  final String id;
  final String dayId;
  final String kind;
  final String title;
  final String body;
  final String? placeName;
  final String? placeAddress;
  final double? placeLatitude;
  final double? placeLongitude;
  final int version;
  final String? deletedAt;

  factory ActivityCardData.fromJson(Map<String, dynamic> row) =>
      ActivityCardData(
        id: row['id'] as String,
        dayId: row['day_id'] as String,
        kind: row['kind'] as String,
        title: row['title'] as String? ?? '',
        body: row['body'] as String? ?? '',
        placeName: row['place_name'] as String?,
        placeAddress: row['place_address'] as String?,
        placeLatitude: (row['place_latitude'] as num?)?.toDouble(),
        placeLongitude: (row['place_longitude'] as num?)?.toDouble(),
        version: (row['version'] as num).toInt(),
        deletedAt: row['deleted_at'] as String?,
      );
}

class PlanningConflict implements Exception {
  const PlanningConflict(this.latest);
  final Map<String, dynamic> latest;
}

class PlanningRuleException implements Exception {
  const PlanningRuleException(this.code);
  final String code;
}

abstract interface class PlanRepository {
  Future<List<DatePlan>> listPlans(String spaceId,
      {bool includeDeleted = false});
  Future<DatePlan> getPlan(String planId);
  Future<List<PlanDay>> listDays(String planId);
  Future<List<ActivityCardData>> listCards(String dayId,
      {bool includeDeleted = false});
  Future<String> createPlan(
      {required String spaceId,
      required String title,
      required CalendarDate start,
      required CalendarDate end,
      required String notes});
  Future<DatePlan> updatePlan(DatePlan old,
      {required String title,
      required CalendarDate start,
      required CalendarDate end,
      required String notes});
  Future<DatePlan> setPlanDeleted(DatePlan plan, bool deleted);
  Future<String> createCard(
      String dayId, String kind, String title, String body,
      {String? placeName,
      String? placeAddress,
      double? placeLatitude,
      double? placeLongitude});
  Future<ActivityCardData> updateCard(ActivityCardData old,
      {required String kind,
      required String title,
      required String body,
      String? placeName,
      String? placeAddress,
      double? placeLatitude,
      double? placeLongitude,
      int? expectedVersion});
  Future<void> setCardDeleted(ActivityCardData card, bool deleted);
  Future<void> moveCard(ActivityCardData card, String targetDayId, int index);
}

class DatePlanService implements PlanRepository {
  DatePlanService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<List<DatePlan>> listPlans(String spaceId,
      {bool includeDeleted = false}) async {
    var query = _client.from('date_plans').select().eq('space_id', spaceId);
    if (!includeDeleted) query = query.isFilter('deleted_at', null);
    final rows = await query.order('start_date').order('title');
    return rows.map((row) => DatePlan.fromJson(row)).toList();
  }

  @override
  Future<DatePlan> getPlan(String planId) async {
    final row = await _client
        .from('date_plans')
        .select()
        .eq('id', planId)
        .maybeSingle();
    if (row == null || row['deleted_at'] != null) {
      throw const PlanningRuleException('NOT_FOUND');
    }
    return DatePlan.fromJson(row);
  }

  @override
  Future<List<PlanDay>> listDays(String planId) async {
    final rows = await _client
        .from('plan_days')
        .select()
        .eq('plan_id', planId)
        .order('day_date');
    return rows.map((row) => PlanDay.fromJson(row)).toList();
  }

  @override
  Future<List<ActivityCardData>> listCards(String dayId,
      {bool includeDeleted = false}) async {
    var query = _client.from('activity_cards').select().eq('day_id', dayId);
    if (!includeDeleted) query = query.isFilter('deleted_at', null);
    final rows = await query.order('position').order('id');
    return rows.map((row) => ActivityCardData.fromJson(row)).toList();
  }

  @override
  Future<String> createPlan({
    required String spaceId,
    required String title,
    required CalendarDate start,
    required CalendarDate end,
    required String notes,
  }) async =>
      await _client.rpc<String>('create_date_plan', params: {
        'p_space_id': spaceId,
        'p_title': title.trim(),
        'p_start_date': start.iso,
        'p_end_date': end.iso,
        'p_notes': notes,
      });

  @override
  Future<DatePlan> updatePlan(
    DatePlan old, {
    required String title,
    required CalendarDate start,
    required CalendarDate end,
    required String notes,
  }) async {
    final response = await _client.rpc('update_date_plan', params: {
      'p_plan_id': old.id,
      'p_expected_version': old.version,
      'p_title': title.trim(),
      'p_start_date': start.iso,
      'p_end_date': end.iso,
      'p_notes': notes,
    }) as Map<String, dynamic>;
    _check(response);
    return DatePlan.fromJson(
        Map<String, dynamic>.from(response['plan'] as Map));
  }

  @override
  Future<DatePlan> setPlanDeleted(DatePlan plan, bool deleted) async {
    final response = await _client.rpc('set_date_plan_deleted', params: {
      'p_plan_id': plan.id,
      'p_expected_version': plan.version,
      'p_deleted': deleted,
    }) as Map<String, dynamic>;
    _check(response);
    return DatePlan.fromJson(
        Map<String, dynamic>.from(response['plan'] as Map));
  }

  @override
  Future<String> createCard(
          String dayId, String kind, String title, String body,
          {String? placeName,
          String? placeAddress,
          double? placeLatitude,
          double? placeLongitude}) async =>
      await _client.rpc<String>('create_activity_card', params: {
        'p_day_id': dayId,
        'p_kind': kind,
        'p_title': title,
        'p_body': body,
        'p_place_name': placeName,
        'p_place_address': placeAddress,
        'p_place_latitude': placeLatitude,
        'p_place_longitude': placeLongitude,
      });

  @override
  Future<ActivityCardData> updateCard(
    ActivityCardData old, {
    required String kind,
    required String title,
    required String body,
    String? placeName,
    String? placeAddress,
    double? placeLatitude,
    double? placeLongitude,
    int? expectedVersion,
  }) async {
    final response = await _client.rpc('update_activity_card', params: {
      'p_card_id': old.id,
      'p_expected_version': expectedVersion ?? old.version,
      'p_kind': kind,
      'p_title': title,
      'p_body': body,
      'p_place_name': placeName,
      'p_place_address': placeAddress,
      'p_place_latitude': placeLatitude,
      'p_place_longitude': placeLongitude,
    }) as Map<String, dynamic>;
    _check(response);
    return ActivityCardData.fromJson(
        Map<String, dynamic>.from(response['card'] as Map));
  }

  @override
  Future<void> setCardDeleted(ActivityCardData card, bool deleted) async {
    final response = await _client.rpc('set_activity_card_deleted', params: {
      'p_card_id': card.id,
      'p_expected_version': card.version,
      'p_deleted': deleted,
    }) as Map<String, dynamic>;
    _check(response);
  }

  @override
  Future<void> moveCard(
      ActivityCardData card, String targetDayId, int index) async {
    final response = await _client.rpc('move_activity_card', params: {
      'p_card_id': card.id,
      'p_target_day_id': targetDayId,
      'p_target_index': index,
    }) as Map<String, dynamic>;
    _check(response);
  }

  void _check(Map<String, dynamic> response) {
    if (response['error_code'] == 'CONFLICT') {
      throw PlanningConflict(
          Map<String, dynamic>.from(response['latest'] as Map));
    }
    if (response['error_code'] != null) {
      throw PlanningRuleException(response['error_code'] as String);
    }
  }
}
