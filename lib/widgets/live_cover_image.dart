import 'package:flutter/material.dart';

import '/utils/live_cover_catalog.dart';
import '/widgets/batata_cached_image.dart';

/// Camada de imagem do cartão: capa Fleaber (asset/CDN) com fallback Mux.
class LiveCoverImage extends StatelessWidget {
  const LiveCoverImage({
    super.key,
    required this.coverId,
    this.muxFallbackUrl,
    this.fallbackAvatarUrl,
    this.fit = BoxFit.cover,
  });

  final String coverId;
  final String? muxFallbackUrl;
  final String? fallbackAvatarUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final net = LiveCoverCatalog.networkUrl(coverId);
    if (net != null) {
      return BatataCachedNetworkImage(
        imageUrl: net,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorWidget: _assetOrMux(),
      );
    }
    return _assetOrMux();
  }

  Widget _assetOrMux() {
    return Image.asset(
      LiveCoverCatalog.assetPath(coverId),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) {
        final mux = muxFallbackUrl?.trim() ?? '';
        if (mux.isNotEmpty) {
          return BatataCachedNetworkImage(
            imageUrl: mux,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorWidget: _avatarFallback(),
          );
        }
        return _avatarFallback();
      },
    );
  }

  Widget _avatarFallback() {
    final av = fallbackAvatarUrl?.trim() ?? '';
    if (av.isEmpty) {
      return const ColoredBox(color: Color(0xFF1A2228));
    }
    return BatataCachedNetworkImage(
      imageUrl: av,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
