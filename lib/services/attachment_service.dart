import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const attachmentBucket = 'space-attachments';
const maxAttachmentBytes = 3 * 1024 * 1024;
const attachmentUrlTtlSeconds = 300;

class SpaceAttachment {
  const SpaceAttachment({
    required this.id,
    required this.planId,
    required this.kind,
    required this.originalName,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.status,
    this.activityCardId,
    this.transportBookingId,
    this.accommodationBookingId,
  });

  final String id;
  final String planId;
  final String? activityCardId;
  final String? transportBookingId;
  final String? accommodationBookingId;
  final String kind;
  final String originalName;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String status;

  factory SpaceAttachment.fromJson(Map<String, dynamic> row) => SpaceAttachment(
        id: row['id'] as String,
        planId: row['plan_id'] as String,
        activityCardId: row['activity_card_id'] as String?,
        transportBookingId: row['transport_booking_id'] as String?,
        accommodationBookingId: row['accommodation_booking_id'] as String?,
        kind: row['kind'] as String,
        originalName: row['original_name'] as String,
        storagePath: row['storage_path'] as String,
        contentType: row['content_type'] as String,
        sizeBytes: (row['size_bytes'] as num).toInt(),
        status: row['status'] as String,
      );
}

class AttachmentException implements Exception {
  const AttachmentException(this.code);
  final String code;
}

class AttachmentService {
  AttachmentService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<SpaceAttachment>> listForPlan(String planId) async {
    final rows = await _client
        .from('attachments')
        .select()
        .eq('plan_id', planId)
        .inFilter(
            'status', ['ready', 'failed', 'deleting']).order('created_at');
    return rows
        .map((row) => SpaceAttachment.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<SpaceAttachment>> listForCard(String cardId) async {
    final rows = await _client
        .from('attachments')
        .select()
        .eq('activity_card_id', cardId)
        .inFilter(
            'status', ['ready', 'failed', 'deleting']).order('created_at');
    return rows
        .map((row) => SpaceAttachment.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<SpaceAttachment>> listForBooking({
    required String planId,
    String? transportBookingId,
    String? accommodationBookingId,
  }) async {
    var query = _client
        .from('attachments')
        .select()
        .eq('plan_id', planId)
        .inFilter('status', ['ready', 'failed', 'deleting']);
    if (transportBookingId != null) {
      query = query.eq('transport_booking_id', transportBookingId);
    } else if (accommodationBookingId != null) {
      query = query.eq('accommodation_booking_id', accommodationBookingId);
    } else {
      return const [];
    }
    final rows = await query.order('created_at');
    return rows
        .map((row) => SpaceAttachment.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<SpaceAttachment> upload({
    required String planId,
    String? activityCardId,
    String? transportBookingId,
    String? accommodationBookingId,
    required String kind,
    required String originalName,
    required Uint8List bytes,
    String? retryAttachmentId,
  }) async {
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw const AttachmentException('ATTACHMENT_TOO_LARGE');
    }
    final contentType = kind == 'pdf' ? 'application/pdf' : 'image/jpeg';
    if (kind == 'pdf' && !isPdfFile(bytes)) {
      throw const AttachmentException('INVALID_PDF');
    }

    String? id = retryAttachmentId;
    try {
      final raw = await _client.rpc('begin_space_attachment_upload', params: {
        'p_plan_id': planId,
        'p_activity_card_id': activityCardId,
        'p_transport_booking_id': transportBookingId,
        'p_accommodation_booking_id': accommodationBookingId,
        'p_kind': kind,
        'p_original_name': originalName,
        'p_content_type': contentType,
        'p_size_bytes': bytes.length,
        'p_attachment_id': retryAttachmentId,
      });
      final row = Map<String, dynamic>.from(raw as Map);
      id = row['id'] as String;
      final path = row['storage_path'] as String;
      await _client.storage.from(attachmentBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      final finished = await _client.rpc('finish_space_attachment_upload',
          params: {'p_attachment_id': id});
      return SpaceAttachment.fromJson(
          Map<String, dynamic>.from(finished as Map));
    } catch (_) {
      if (id != null) {
        try {
          final raw = await _client
              .from('attachments')
              .select('storage_path')
              .eq('id', id)
              .maybeSingle();
          final path = raw?['storage_path'] as String?;
          if (path != null) {
            await _client.storage.from(attachmentBucket).remove([path]);
          }
        } catch (_) {}
        try {
          await _client.rpc('fail_space_attachment_upload',
              params: {'p_attachment_id': id});
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Uint8List> previewPdf(SpaceAttachment attachment) async {
    if (attachment.kind != 'pdf' || attachment.status != 'ready') {
      throw const AttachmentException('ATTACHMENT_UNAVAILABLE');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final signed = await _client.storage
            .from(attachmentBucket)
            .createSignedUrl(attachment.storagePath, attachmentUrlTtlSeconds);
        final response = await http.get(Uri.parse(signed));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        if (attempt == 0 &&
            const {400, 401, 403}.contains(response.statusCode)) {
          continue;
        }
      } catch (_) {
        if (attempt == 1) break;
      }
    }
    throw const AttachmentException('PDF_PREVIEW_FAILED');
  }

  Future<Uint8List> downloadOriginal(SpaceAttachment attachment) async {
    if (attachment.status != 'ready') {
      throw const AttachmentException('ATTACHMENT_UNAVAILABLE');
    }
    try {
      return await _client.storage
          .from(attachmentBucket)
          .download(attachment.storagePath);
    } catch (_) {
      throw const AttachmentException('ATTACHMENT_DOWNLOAD_FAILED');
    }
  }

  Future<void> delete(SpaceAttachment attachment) async {
    await _client.rpc('mark_space_attachment_deleting',
        params: {'p_attachment_id': attachment.id});

    // Storage removal and its database row are not always visible to the
    // following Postgres RPC in the same instant. If finalization reports
    // that the object still exists, repeat the idempotent Storage delete and
    // check again instead of leaving the attachment stuck in `deleting`.
    for (var attempt = 0; attempt < 3; attempt++) {
      await _client.storage
          .from(attachmentBucket)
          .remove([attachment.storagePath]);
      try {
        await _client.rpc('finish_space_attachment_delete',
            params: {'p_attachment_id': attachment.id});
        return;
      } on PostgrestException catch (error) {
        final objectStillExists =
            error.message.contains('ATTACHMENT_OBJECT_REMAINS');
        if (!objectStillExists || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
  }
}

bool isPdfFile(Uint8List bytes) {
  final limit = bytes.length < 1024 ? bytes.length - 4 : 1020;
  for (var i = 0; i <= limit; i++) {
    if (bytes[i] == 0x25 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x44 &&
        bytes[i + 3] == 0x46 &&
        bytes[i + 4] == 0x2d) {
      return true;
    }
  }
  return false;
}
