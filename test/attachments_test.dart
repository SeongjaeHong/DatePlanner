import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:together_date_planner/services/attachment_service.dart';
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
}
