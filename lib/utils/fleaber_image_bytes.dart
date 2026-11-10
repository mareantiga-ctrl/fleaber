import 'dart:typed_data';
import 'dart:ui';

/// Lado máximo ao descodificar/enviar fotos de anúncio (evita textura preta em GPUs fracas).
const int kFleaberProductPhotoMaxSide = 1600;

bool fleaberLooksLikePng(Uint8List bytes) {
  return bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

/// Reduz PNG/fotos enormes antes do upload. JPEG pequeno fica igual.
Future<Uint8List> fleaberDownsampleForUpload(
  Uint8List bytes, {
  int maxSide = kFleaberProductPhotoMaxSide,
}) async {
  if (bytes.isEmpty || maxSide < 1) return bytes;
  final png = fleaberLooksLikePng(bytes);
  if (!png && bytes.length < 350 * 1024) return bytes;

  try {
    final codec = await instantiateImageCodec(
      bytes,
      targetWidth: maxSide,
      targetHeight: maxSide,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return bytes;
    final out = data.buffer.asUint8List();
    if (out.isEmpty) return bytes;
    if (!png && out.length >= bytes.length) return bytes;
    return out;
  } catch (_) {
    return bytes;
  }
}

String fleaberUploadFileName(String original, Uint8List bytes) {
  final raw = original.trim();
  if (!fleaberLooksLikePng(bytes)) return raw.isEmpty ? 'foto.jpg' : raw;
  final base = raw.replaceAll(RegExp(r'\.[^.]+$'), '');
  final stem = base.trim().isEmpty ? 'foto' : base;
  return '$stem.png';
}
