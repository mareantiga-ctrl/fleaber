import 'dart:typed_data';

import 'package:fleaber/utils/fleaber_image_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PNG magic', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
    expect(fleaberLooksLikePng(png), isTrue);
    expect(fleaberLooksLikePng(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isFalse);
  });

  test('JPEG pequeno não é reescrito', () async {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    final out = await fleaberDownsampleForUpload(jpeg);
    expect(identical(out, jpeg) || out.length == jpeg.length, isTrue);
  });

  test('nome PNG no upload', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
    expect(fleaberUploadFileName('1000004907.png', png), '1000004907.png');
    expect(fleaberUploadFileName('foto.PNG', png), 'foto.png');
  });
}
