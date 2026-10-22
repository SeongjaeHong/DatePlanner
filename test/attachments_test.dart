import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:together_date_planner/l10n/generated/app_localizations.dart';
import 'package:together_date_planner/services/attachment_service.dart';
import 'package:together_date_planner/theme/app_theme.dart';
import 'package:together_date_planner/widgets/attachments.dart';

void main() {
  group('private attachment validation', () {
    test('recognizes a PDF header and rejects a renamed non-PDF', () {
      expect(isPdfFile(Uint8List.fromList('%PDF-1.7'.codeUnits)), isTrue);
      expect(isPdfFile(Uint8List.fromList('not a pdf'.codeUnits)), isFalse);
    });

    test('accepts a PDF header after a permitted preamble', () {
      expect(
        isPdfFile(Uint8List.fromList(
            '${List.filled(100, ' ').join()}%PDF-1.4'.codeUnits)),
        isTrue,
      );
    });
  });

  group('photo preparation', () {
    test('preserves a small JPEG byte for byte', () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgb8(200, 40, 80));
      final jpeg = Uint8List.fromList(img.encodeJpg(source));

      final result = preparePhotoForUpload(jpeg);

      expect(result.compressed, isFalse);
      expect(result.bytes, orderedEquals(jpeg));
    });

    test('converts PNG to a metadata-free JPEG without claiming compression',
        () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgb8(20, 130, 70));
      final png = Uint8List.fromList(img.encodePng(source));

      final result = preparePhotoForUpload(png);

      expect(result.compressed, isFalse);
      expect(result.bytes.length, lessThanOrEqualTo(maxAttachmentBytes));
      expect(img.findDecoderForData(result.bytes)?.format, img.ImageFormat.jpg);
    });

    test('rejects undecodable input', () {
      expect(
        () => preparePhotoForUpload(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<AttachmentException>()),
      );
    });
  });

  group('card photo refresh', () {
    testWidgets('shows loading then the empty-state photo actions',
        (tester) async {
      final pending = Completer<List<SpaceAttachment>>();
      final service = _FakeAttachmentService([])..pendingList = pending;
      await tester.pumpWidget(_app(CardPhotos(
        planId: 'plan-1',
        cardId: 'card-1',
        service: service,
      )));
      await tester.pump();
      expect(find.byTooltip('Add photos'), findsNothing);

      pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add photos'), findsOneWidget);
    });

    testWidgets('offers retry when loading photos fails', (tester) async {
      final service = _FakeAttachmentService([])..failNextList = true;
      await tester.pumpWidget(_app(CardPhotos(
        planId: 'plan-1',
        cardId: 'card-1',
        service: service,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Files could not be loaded.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add photos'), findsOneWidget);
    });

    testWidgets('removes a deleted photo from the card without a reload',
        (tester) async {
      final service = _FakeAttachmentService([_photo('photo-1')]);
      await tester.pumpWidget(_app(CardPhotos(
        planId: 'plan-1',
        cardId: 'card-1',
        service: service,
      )));
      await tester.pumpAndSettle();

      final photo = find.byKey(const ValueKey('photo-photo-1'));
      expect(photo, findsOneWidget);
      await tester.tap(find.descendant(
        of: photo,
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();

      expect(photo, findsNothing);
      expect(service.listCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('failed deletion releases thumbnail space and keeps retry',
        (tester) async {
      final service = _FakeAttachmentService([_photo('photo-2')])
        ..failDeletion = true;
      await tester.pumpWidget(_app(CardPhotos(
        planId: 'plan-1',
        cardId: 'card-1',
        service: service,
      )));
      await tester.pumpAndSettle();

      final photo = find.byKey(const ValueKey('photo-photo-2'));
      await tester.tap(find.descendant(
        of: photo,
        matching: find.byIcon(Icons.close),
      ));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(photo, findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(service.listCalls, greaterThanOrEqualTo(2));

      final retryButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry'));
      expect(retryButton.onPressed, isNotNull);
    });
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

SpaceAttachment _photo(String id, {String status = 'ready'}) => SpaceAttachment(
      id: id,
      planId: 'plan-1',
      activityCardId: 'card-1',
      kind: 'photo',
      originalName: '$id.jpg',
      storagePath: id,
      contentType: 'image/jpeg',
      sizeBytes: 5,
      status: status,
    );

class _FakeAttachmentService implements AttachmentService {
  _FakeAttachmentService(this.items);

  List<SpaceAttachment> items;
  bool failDeletion = false;
  bool failNextList = false;
  Completer<List<SpaceAttachment>>? pendingList;
  int listCalls = 0;

  @override
  Future<List<SpaceAttachment>> listForCard(String cardId) {
    listCalls++;
    if (failNextList) {
      failNextList = false;
      return Future.error(StateError('fixture list failure'));
    }
    final pending = pendingList;
    if (pending != null) {
      pendingList = null;
      return pending.future;
    }
    return Future.value(List<SpaceAttachment>.of(items));
  }

  @override
  Future<void> delete(SpaceAttachment attachment) async {
    if (failDeletion) {
      items = items
          .map((item) => item.id == attachment.id
              ? _photo(item.id, status: 'deleting')
              : item)
          .toList();
      throw const AttachmentException('DELETE_FAILED');
    }
    items = items.where((item) => item.id != attachment.id).toList();
  }

  @override
  Future<Uint8List> downloadOriginal(SpaceAttachment attachment) =>
      Completer<Uint8List>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
