import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const int _kBatataFeedImageWidth = 400;
const int _kBatataFeedImageQuality = 85;

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
    return CachedNetworkImage(
      imageUrl: batataOptimizedImageUrl(
        imageUrl,
        width: maxWidth,
        quality: quality,
      ),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholder: (_, __) => batataImagePlaceholder(color: placeholderColor),
      errorWidget: (_, __, ___) =>
          errorWidget ?? ColoredBox(color: placeholderColor),
    );
  }
}

ImageProvider batataCachedNetworkImageProvider(
  String url, {
  int width = _kBatataFeedImageWidth,
  int quality = _kBatataFeedImageQuality,
}) {
  return CachedNetworkImageProvider(
    batataOptimizedImageUrl(url, width: width, quality: quality),
  );
}
