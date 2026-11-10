import 'package:fleaber/widgets/batata_cached_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('URL Supabase ganha width/quality', () {
    const raw =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/a.png';
    final out = batataOptimizedImageUrl(raw, width: 400, quality: 85);
    expect(out, contains('width=400'));
    expect(out, contains('quality=85'));
  });

  test('decode box: widget width × dpr, com tecto 1600', () {
    expect(
      batataImageDecodeBoxPx(
        devicePixelRatio: 2.75,
        widgetWidth: 56,
      ),
      154,
    );
    expect(
      batataImageDecodeBoxPx(
        devicePixelRatio: 3,
        layoutWidth: 1080,
        layoutHeight: 2400,
      ),
      kFleaberImageDecodeMaxSide,
    );
  });

  test('decode box: ecrã curto se o layout é infinito', () {
    expect(
      batataImageDecodeBoxPx(
        devicePixelRatio: 2,
        layoutWidth: double.infinity,
        layoutHeight: double.infinity,
        screenShortestSide: 360,
      ),
      720,
    );
  });
}
