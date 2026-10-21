import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

const supportsClipboardImageRead = true;

Future<Uint8List?> readClipboardImagePng() async {
  final reader = await ClipboardReader.readClipboard();
  return reader.readValue(Formats.png);
}
