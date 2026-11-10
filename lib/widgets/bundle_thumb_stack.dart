import 'package:flutter/material.dart';

import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';

/// Thumbnails empilhadas (estilo encomendas «Conjunto · N artigos»).
class BundleThumbStack extends StatelessWidget {
  const BundleThumbStack({
    super.key,
    required this.imageUrls,
    this.maxThumbs = 3,
    this.thumbWidth = 50,
    this.thumbHeight = 58,
    this.stackWidth = 78,
    this.stackHeight = 72,
    this.offsetX = 16,
    this.offsetY = 5,
    this.borderColor = Colors.white,
    this.borderWidth = 1.5,
  });

  final List<String> imageUrls;
  final int maxThumbs;
  final double thumbWidth;
  final double thumbHeight;
  final double stackWidth;
  final double stackHeight;
  final double offsetX;
  final double offsetY;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final thumbs = imageUrls
        .where((u) => u.trim().isNotEmpty)
        .take(maxThumbs)
        .toList();
    if (thumbs.isEmpty) {
      return SizedBox(width: stackWidth, height: stackHeight);
    }
    return SizedBox(
      width: stackWidth,
      height: stackHeight,
      child: Stack(
        children: [
          for (var i = thumbs.length - 1; i >= 0; i--)
            Positioned(
              left: i * offsetX,
              top: i * offsetY,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: FleaberRadius.circularSm,
                  border: Border.all(color: borderColor, width: borderWidth),
                ),
                child: ClipRRect(
                  borderRadius: FleaberRadius.circularSm,
                  child: SizedBox(
                    width: thumbWidth,
                    height: thumbHeight,
                    child: BatataCachedNetworkImage(
                      imageUrl: thumbs[i],
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
