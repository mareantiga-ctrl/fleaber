import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

const int _kBatataFeedImageWidth = 400;
const int _kBatataFeedImageQuality = 85;

/// Web: reescreve URLs absolutas `/fleahub/assets/…` para a origem + base-href
/// actuais (evita falha Canvaskit CORS em preview/localhost).
String? normalizeProductImageUrl(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (!kIsWeb) return t;

  // Absolute fleahub / fleahub-p13-preview asset → origem + base-href actuais
  // (evita cinzento/CORS quando a URL aponta para outro path do Hub).
  final m = RegExp(
    r'https?://[^/]+/fleahub(?:-p13-preview)?/(assets/.+)$',
    caseSensitive: false,
  ).firstMatch(t);
  if (m != null) {
    final assetPath = m.group(1)!;
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}$path$assetPath';
  }

  // Relative asset path stored in BD.
  if (t.startsWith('assets/') || t.startsWith('/assets/')) {
    final assetPath = t.startsWith('/') ? t.substring(1) : t;
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}$path$assetPath';
  }
  return t;
}

/// Tecto GPU: PNG enormes (prints de ecrã) pintavam preto no Redmi se
/// descodificassem em tamanho nativo.
const int kFleaberImageDecodeMaxSide = 1600;

bool _isSupabaseStorageImageUrl(Uri uri) {
  return uri.host.contains('supabase.co') &&
      uri.path.contains('/storage/v1/object/');
}

/// Adds Supabase Storage image transformation params to dynamic media URLs.
String batataOptimizedImageUrl(
  String url, {
  int width = _kBatataFeedImageWidth,
  int quality = _kBatataFeedImageQuality,
}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !_isSupabaseStorageImageUrl(uri)) {
    return trimmed;
  }

  final query = Map<String, String>.from(uri.queryParameters);
  query['width'] = width.toString();
  query['quality'] = quality.toString();

  return uri.replace(queryParameters: query).toString();
}

int batataImageDecodeBoxPx({
  required double devicePixelRatio,
  double? widgetWidth,
  double? widgetHeight,
  double? layoutWidth,
  double? layoutHeight,
  double? screenShortestSide,
  int cap = kFleaberImageDecodeMaxSide,
}) {
  final dpr = devicePixelRatio <= 0 ? 2.0 : devicePixelRatio;
  double logical = 0;
  if (widgetWidth != null && widgetWidth > 0) {
    logical = widgetWidth;
  } else if (widgetHeight != null && widgetHeight > 0) {
    logical = widgetHeight;
  } else {
    final lw = layoutWidth != null && layoutWidth.isFinite ? layoutWidth : 0.0;
    final lh =
        layoutHeight != null && layoutHeight.isFinite ? layoutHeight : 0.0;
    logical = lw > lh ? lw : lh;
    if (logical <= 0) {
      logical = screenShortestSide ?? 400;
    }
  }
  final px = (logical * dpr).round();
  if (px < 64) return 64;
  if (px > cap) return cap;
  return px;
}

Widget batataImagePlaceholder({
  Color color = const Color(0xFFE8EDF2),
  Color spinnerColor = const Color(0xFF007782),
}) {
  return ColoredBox(
    color: color,
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
        ),
      ),
    ),
  );
}

class BatataCachedNetworkImage extends StatelessWidget {
  const BatataCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholderColor = const Color(0xFFE8EDF2),
    this.errorWidget,
    this.maxWidth = _kBatataFeedImageWidth,
    this.quality = _kBatataFeedImageQuality,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Color placeholderColor;
  final Widget? errorWidget;
  final int maxWidth;
  final int quality;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeProductImageUrl(imageUrl);
    if (normalized == null) {
      return errorWidget ?? ColoredBox(color: placeholderColor);
    }
    final url = batataOptimizedImageUrl(
      normalized,
      width: maxWidth,
      quality: quality,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.maybeOf(context);
        final px = batataImageDecodeBoxPx(
          devicePixelRatio: mq?.devicePixelRatio ?? 2.0,
          widgetWidth: width,
          widgetHeight: height,
          layoutWidth: constraints.maxWidth,
          layoutHeight: constraints.maxHeight,
          screenShortestSide: mq?.size.shortestSide,
        );
        return Image(
          image: ResizeImage(
            CachedNetworkImageProvider(url),
            width: px,
            height: px,
            policy: ResizeImagePolicy.fit,
          ),
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return batataImagePlaceholder(color: placeholderColor);
          },
          errorBuilder: (_, __, ___) =>
              errorWidget ?? ColoredBox(color: placeholderColor),
        );
      },
    );
  }
}

ImageProvider batataCachedNetworkImageProvider(
  String url, {
  int width = _kBatataFeedImageWidth,
  int quality = _kBatataFeedImageQuality,
}) {
  final px = width < 64 ? 64 : (width > kFleaberImageDecodeMaxSide
      ? kFleaberImageDecodeMaxSide
      : width);
  return ResizeImage(
    CachedNetworkImageProvider(
      batataOptimizedImageUrl(url, width: width, quality: quality),
    ),
    width: px,
    height: px,
    policy: ResizeImagePolicy.fit,
  );
}
