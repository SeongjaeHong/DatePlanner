import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:together_date_planner/services/date_plan_service.dart';

void main() {
  test('createPlan executes the typed RPC and returns its id', () async {
    http.Request? captured;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode('plan-id'),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final id = await DatePlanService(client).createPlan(
      spaceId: 'space-id',
      title: '  Berlin weekend  ',
      start: const CalendarDate(2026, 10, 13),
      end: const CalendarDate(2026, 10, 14),
      notes: 'Train trip',
    );

    expect(id, 'plan-id');
    expect(captured?.method, 'POST');
    expect(captured?.url.path, '/rest/v1/rpc/create_date_plan');
    expect(jsonDecode(captured!.body), {
      'p_space_id': 'space-id',
      'p_title': 'Berlin weekend',
      'p_start_date': '2026-10-13',
      'p_end_date': '2026-10-14',
      'p_notes': 'Train trip',
    });
  });

  test('createCard executes the typed RPC and returns its id', () async {
    http.Request? captured;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode('card-id'),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final id = await DatePlanService(client).createCard(
      'day-id',
      'activity',
      'Museum',
      'Meet at noon',
    );

    expect(id, 'card-id');
    expect(captured?.method, 'POST');
    expect(captured?.url.path, '/rest/v1/rpc/create_activity_card');
  });
}
