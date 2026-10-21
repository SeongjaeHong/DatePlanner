import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class SpaceInvitationService {
  const SpaceInvitationService();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>> createInvitation() async {
    final result = await _client.rpc(
      'create_space_invitation',
      params: const {'p_disclosure_acknowledged': true},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> listInvitations() async {
    final result = await _client.rpc('list_my_space_invitations');
    return (result as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> revokeInvitation(String invitationId) async {
    final result = await _client.rpc(
      'revoke_space_invitation',
      params: {'p_invitation_id': invitationId},
    );
    final response = Map<String, dynamic>.from(result as Map);
    if (response['error_code'] != null) {
      throw InvitationFlowException(response['error_code'] as String);
    }
  }

  Future<Map<String, dynamic>> prepareJoin({
    required String code,
    required String operationId,
  }) async {
    final result = await _client.rpc(
      'prepare_join',
      params: {'p_code': code, 'p_operation_id': operationId},
    );
    final response = Map<String, dynamic>.from(result as Map);
    if (response['error_code'] != null) {
      throw InvitationFlowException(response['error_code'] as String);
    }
    return response;
  }

  Future<void> confirmJoin({
    required String operationId,
    required int disclosureVersion,
  }) async {
    final result = await _client.rpc(
      'confirm_join',
      params: {
        'p_operation_id': operationId,
        'p_disclosure_version': disclosureVersion,
      },
    );
    final response = Map<String, dynamic>.from(result as Map);
    if (response['error_code'] != null) {
      throw InvitationFlowException(response['error_code'] as String);
    }
  }

  Future<void> cancelJoin(String operationId) async {
    await _client.rpc(
      'cancel_join',
      params: {'p_operation_id': operationId},
    );
  }

  String newOperationId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class InvitationFlowException implements Exception {
  const InvitationFlowException(this.code);
  final String code;
}
