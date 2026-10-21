import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/attachment_service.dart';
import '../services/clipboard_image_reader.dart';
import '../theme/app_theme.dart';
import 'app_components.dart';

class BookingAttachments extends StatefulWidget {
  const BookingAttachments({
    required this.planId,
    this.transportBookingId,
    this.accommodationBookingId,
    super.key,
  });

  final String planId;
  final String? transportBookingId;
  final String? accommodationBookingId;

  @override
  State<BookingAttachments> createState() => _BookingAttachmentsState();
}

class _BookingAttachmentsState extends State<BookingAttachments> {
  final _service = AttachmentService();
  late Future<List<SpaceAttachment>> _items = _load();

  Future<List<SpaceAttachment>> _load() => _service.listForBooking(
        planId: widget.planId,
        transportBookingId: widget.transportBookingId,
        accommodationBookingId: widget.accommodationBookingId,
      );

  void _reload() => setState(() => _items = _load());

  Future<void> _addPdf() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final length = await file.length();
    if (length != null && length > maxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).attachmentTooLarge)));
      }
      return;
    }
    final bytes = await file.readAsBytes();
    await _upload(file.name, bytes);
  }

  Future<void> _upload(String name, Uint8List bytes, {String? retryId}) async {
    final s = AppLocalizations.of(context);
    try {
      await _service.upload(
        planId: widget.planId,
        transportBookingId: widget.transportBookingId,
        accommodationBookingId: widget.accommodationBookingId,
        kind: 'pdf',
        originalName: name,
        bytes: bytes,
        retryAttachmentId: retryId,
      );
      if (mounted) _reload();
    } catch (error) {
      if (!mounted) return;
      final message =
          error is AttachmentException && error.code == 'ATTACHMENT_TOO_LARGE'
              ? s.attachmentTooLarge
              : error is AttachmentException && error.code == 'INVALID_PDF'
                  ? s.invalidPdf
                  : s.attachmentUploadFailed;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _reload();
    }
  }

  Future<void> _retry(SpaceAttachment item) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final length = await file.length();
    if (length != null && length > maxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).attachmentTooLarge)));
      }
      return;
    }
    final bytes = await file.readAsBytes();
    await _upload(file.name, bytes, retryId: item.id);
  }

  Future<void> _preview(SpaceAttachment item) async {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => _PdfPreviewDialog(
          item: item, service: _service, onDownload: () => _download(item)),
    );
  }

  Future<void> _download(SpaceAttachment item) async {
    final s = AppLocalizations.of(context);
    try {
      final bytes = await _service.downloadOriginal(item);
      await FilePicker.saveFile(
        fileName: item.originalName,
        bytes: bytes,
        mimeType: item.contentType,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.attachmentDownloadFailed)));
      }
    }
  }

  Future<void> _delete(SpaceAttachment item) async {
    final s = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeAttachment),
        content: Text(s.removeAttachmentConfirm(item.originalName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.remove)),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service.delete(item);
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.attachmentDeleteFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SpaceAttachment>>(
        future: _items,
        builder: (context, snapshot) {
          final s = AppLocalizations.of(context);
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingSkeleton(lines: 1);
          }
          if (snapshot.hasError) {
            return ErrorState(
                message: s.attachmentsLoadFailed,
                retryLabel: s.retry,
                onRetry: _reload);
          }
          final items = snapshot.data ?? const <SpaceAttachment>[];
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: s.attachments,
                  trailing: IconButton(
                    tooltip: s.addPdf,
                    onPressed: _addPdf,
                    icon: const Icon(Icons.attach_file),
                  ),
                ),
                Text(s.spaceFileAccess,
                    style: Theme.of(context).textTheme.bodySmall),
                if (items.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                    child: Text(s.noAttachments,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                for (final item in items)
                  Card(
                    child: ListTile(
                      leading: Icon(item.status == 'ready'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.warning_amber_outlined),
                      title: Text(item.originalName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.status == 'ready'
                          ? _formatSize(item.sizeBytes)
                          : s.attachmentNeedsRetry),
                      onTap: item.status == 'ready'
                          ? () => _preview(item)
                          : () => _retry(item),
                      trailing: PopupMenuButton<String>(
                        tooltip: s.attachmentActions,
                        onSelected: (action) {
                          if (action == 'preview' && item.status == 'ready') {
                            _preview(item);
                          }
                          if (action == 'download' && item.status == 'ready') {
                            _download(item);
                          }
                          if (action == 'retry' && item.status == 'failed') {
                            _retry(item);
                          }
                          if (action == 'remove') {
                            _delete(item);
                          }
                        },
                        itemBuilder: (_) => [
                          if (item.status == 'ready')
                            PopupMenuItem(
                                value: 'preview', child: Text(s.previewPdf)),
                          if (item.status == 'ready')
                            PopupMenuItem(
                                value: 'download',
                                child: Text(s.downloadOriginal)),
                          if (item.status == 'failed')
                            PopupMenuItem(value: 'retry', child: Text(s.retry)),
                          PopupMenuItem(
                              value: 'remove', child: Text(s.removeAttachment)),
                        ],
                      ),
                    ),
                  ),
              ]);
        },
      );
}

class CardPhotos extends StatefulWidget {
  const CardPhotos({required this.planId, required this.cardId, super.key});
  final String planId;
  final String cardId;

  @override
  State<CardPhotos> createState() => _CardPhotosState();
}

class _PdfPreviewDialog extends StatefulWidget {
  const _PdfPreviewDialog({
    required this.item,
    required this.service,
    required this.onDownload,
  });
  final SpaceAttachment item;
  final AttachmentService service;
  final VoidCallback onDownload;

  @override
  State<_PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<_PdfPreviewDialog> {
  late Future<Uint8List> _bytes = widget.service.previewPdf(widget.item);

  void _retry() => setState(() {
        _bytes = widget.service.previewPdf(widget.item);
      });

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Dialog.fullscreen(
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) => Column(children: [
          AppBar(
            title: Text(widget.item.originalName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              tooltip: s.close,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            actions: [
              IconButton(
                tooltip: s.downloadOriginal,
                onPressed: widget.onDownload,
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
          Expanded(
            child: snapshot.connectionState != ConnectionState.done
                ? const LoadingSkeleton(lines: 4)
                : snapshot.hasError
                    ? ErrorState(
                        message: s.pdfPreviewFailed,
                        retryLabel: s.retry,
                        onRetry: _retry,
                      )
                    : PdfViewer.data(
                        snapshot.data!,
                        sourceName: widget.item.id,
                        useProgressiveLoading: false,
                      ),
          ),
        ]),
      ),
    );
  }
}

class _CardPhotosState extends State<CardPhotos> {
  final _service = AttachmentService();
  final _picker = ImagePicker();
  final Map<String, Future<Uint8List>> _photoBytes = {};
  late Future<List<SpaceAttachment>> _items =
      _service.listForCard(widget.cardId);

  void _reload() =>
      setState(() => _items = _service.listForCard(widget.cardId));

  Future<void> _pick({bool camera = false}) async {
    final images = camera
        ? [await _picker.pickImage(source: ImageSource.camera)]
            .whereType<XFile>()
            .toList()
        : await _picker.pickMultiImage();
    var compressedAny = false;
    for (final image in images) {
      try {
        final input = await image.readAsBytes();
        final normalized = preparePhotoForUpload(input);
        compressedAny = compressedAny || normalized.compressed;
        await _service.upload(
          planId: widget.planId,
          activityCardId: widget.cardId,
          kind: 'photo',
          originalName: _jpegName(image.name),
          bytes: normalized.bytes,
        );
      } catch (error) {
        if (!mounted) return;
        final s = AppLocalizations.of(context);
        final tooLarge = error is AttachmentException &&
            {'IMAGE_TOO_LARGE', 'ATTACHMENT_TOO_LARGE'}.contains(error.code);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(tooLarge ? s.imageCannotBeCompressed : s.invalidImage)));
      }
    }
    _reload();
    if (compressedAny && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).imageCompressed)));
    }
  }

  Future<void> _paste() async {
    final s = AppLocalizations.of(context);
    try {
      final bytes = await readClipboardImagePng();
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(s.noImageInClipboard)));
        }
        return;
      }
      final normalized = preparePhotoForUpload(bytes);
      await _service.upload(
          planId: widget.planId,
          activityCardId: widget.cardId,
          kind: 'photo',
          originalName: 'pasted-photo.jpg',
          bytes: normalized.bytes);
      _reload();
      if (normalized.compressed && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.imageCompressed)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.invalidImage)));
      }
    }
  }

  Future<void> _open(SpaceAttachment item) async {
    final bytes = await _service.downloadOriginal(item);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 720, maxHeight: 760),
                child: Stack(children: [
                  InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain)),
                  Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                          tooltip: AppLocalizations.of(context).close,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close))),
                ]),
              ),
            ));
  }

  Future<void> _remove(SpaceAttachment item) async {
    try {
      await _service.delete(item);
      _photoBytes.remove(item.id);
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context).attachmentDeleteFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SpaceAttachment>>(
        future: _items,
        builder: (context, snapshot) {
          final s = AppLocalizations.of(context);
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingSkeleton(lines: 1);
          }
          if (snapshot.hasError) {
            return ErrorState(
                message: s.attachmentsLoadFailed,
                retryLabel: s.retry,
                onRetry: _reload);
          }
          final items = snapshot.data ?? const <SpaceAttachment>[];
          return Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x2,
              children: [
                for (final item in items)
                  if (item.status == 'ready')
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(fit: StackFit.expand, children: [
                        InkWell(
                            onTap: () => _open(item),
                            child: FutureBuilder<Uint8List>(
                              future: _photoBytes.putIfAbsent(item.id,
                                  () => _service.downloadOriginal(item)),
                              builder: (context, photo) => photo.hasData
                                  ? Image.memory(photo.data!, fit: BoxFit.cover)
                                  : ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: Center(
                                          child: Icon(Icons.photo_outlined))),
                            )),
                        Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton.filledTonal(
                                tooltip: s.removeAttachment,
                                onPressed: () => _remove(item),
                                icon: const Icon(Icons.close, size: 16))),
                      ]),
                    ),
                IconButton.filledTonal(
                  tooltip: s.addPhoto,
                  onPressed: () => _pick(),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: s.takePhoto,
                  onPressed: () => _pick(camera: true),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                if (supportsClipboardImageRead)
                  IconButton.filledTonal(
                    tooltip: s.pastePhoto,
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste),
                  ),
              ]);
        },
      );
}

class PreparedPhoto {
  const PreparedPhoto(this.bytes, this.compressed);
  final Uint8List bytes;
  final bool compressed;
}

PreparedPhoto preparePhotoForUpload(Uint8List input) {
  if (input.isEmpty) throw const AttachmentException('INVALID_IMAGE');
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const AttachmentException('INVALID_IMAGE');
  final hasGps = decoded.exif.gpsIfd.data.isNotEmpty;
  final isJpeg = img.findDecoderForData(input)?.format == img.ImageFormat.jpg;
  if (isJpeg && input.length <= maxAttachmentBytes && !hasGps) {
    return PreparedPhoto(input, false);
  }
  var current = img.bakeOrientation(decoded);
  for (var attempt = 0; attempt < 12; attempt++) {
    for (final quality in [88, 78, 68, 58, 48, 38]) {
      final bytes =
          Uint8List.fromList(img.encodeJpg(current, quality: quality));
      if (bytes.length <= maxAttachmentBytes) {
        return PreparedPhoto(bytes, input.length > maxAttachmentBytes);
      }
    }
    final nextWidth = (current.width * 0.82).round();
    final nextHeight = (current.height * 0.82).round();
    if (nextWidth < 1 || nextHeight < 1) break;
    current = img.copyResize(current,
        width: nextWidth,
        height: nextHeight,
        interpolation: img.Interpolation.average);
  }
  throw const AttachmentException('IMAGE_TOO_LARGE');
}

String _jpegName(String input) =>
    '${input.replaceFirst(RegExp(r'\.[^.]+$'), '')}.jpg';

String _formatSize(int bytes) => '${(bytes / 1024).ceil()} KB';
