import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SpaceLifecycleActions {
  Future<SpaceDeletionPreview> loadDeletionPreview();
  Future<SpaceLeaveResult> leaveSpace({
    required int expectedMemberCount,
    required String confirmationWord,
  });
  Future<void> deleteAccount({
    required int expectedMemberCount,
    required String confirmationWord,
  });
}

class SpaceLifecycleService implements SpaceLifecycleActions {
  const SpaceLifecycleService();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<SpaceDeletionPreview> loadDeletionPreview() async {
    final raw = await _client.rpc('space_deletion_preview');
    final result = Map<String, dynamic>.from(raw as Map);
    if (result['error_code'] != null) {
      throw SpaceLifecycleException(result['error_code'] as String);
    }
    return SpaceDeletionPreview(
      plans: (result['plan_count'] as num?)?.toInt() ?? 0,
      files: (result['file_count'] as num?)?.toInt() ?? 0,
      memberCount: (result['member_count'] as num?)?.toInt(),
    );
  }

  @override
  Future<SpaceLeaveResult> leaveSpace({
    required int expectedMemberCount,
    required String confirmationWord,
  }) async {
    final raw = await _client.rpc(
      'leave_space',
      params: {
        'p_operation_id': _newOperationId(),
        'p_expected_member_count': expectedMemberCount,
        'p_confirmation_word':
            confirmationWord.isEmpty ? null : confirmationWord,
      },
    );
    final result = Map<String, dynamic>.from(raw as Map);
    if (result['error_code'] != null) {
      throw SpaceLifecycleException(result['error_code'] as String);
    }
    final leave = SpaceLeaveResult(
      errorCode: result['result'] as String? ?? 'completed',
      lastMember: result['last_member'] == true,
      currentMemberCount: (result['current_member_count'] as num?)?.toInt(),
    );
    if (leave.lastMember) await _drainDeletionQueue();
    return leave;
  }

  @override
  Future<void> deleteAccount({
    required int expectedMemberCount,
    required String confirmationWord,
  }) async {
    final response = await _client.functions.invoke(
      'delete-account',
      body: {
        'operation_id': _newOperationId(),
        'expected_member_count': expectedMemberCount,
        'confirmation_word': confirmationWord,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw const SpaceLifecycleException('ACCOUNT_DELETE_FAILED');
    }
    await _client.auth.signOut();
  }

  Future<void> _drainDeletionQueue() async {
    // A failed storage removal remains queued for a later retry. It must not
    // undo the completed membership change or expose the object publicly.
    try {
      await _client.functions.invoke('drain-file-deletion-queue');
    } catch (_) {
      // The server queue is durable; this best-effort invocation is not.
    }
  }

  String _newOperationId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class SpaceDeletionPreview {
  const SpaceDeletionPreview(
      {required this.plans, required this.files, this.memberCount});
  final int plans;
  final int files;
  final int? memberCount;
}

class SpaceLeaveResult {
  const SpaceLeaveResult(
      {required this.errorCode,
      required this.lastMember,
      this.currentMemberCount});
  final String errorCode;
  final bool lastMember;
  final int? currentMemberCount;
}

class SpaceLifecycleException implements Exception {
  const SpaceLifecycleException(this.code);
  final String code;
}
