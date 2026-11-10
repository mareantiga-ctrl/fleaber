import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/live_cover_image.dart';

/// Card portrait 9:16 para um directo na Home.
class HomeMuxLiveCard extends StatelessWidget {
  const HomeMuxLiveCard({
    super.key,
    required this.sellerName,
    required this.thumbnailUrl,
    required this.ratingLabel,
    required this.onOpenLive,
    this.liveTitle,
    this.fallbackAvatarUrl,
    this.width = 168,
    this.isLive = true,
    this.isRecordingPreparing = false,
    this.onOpenSellerProfile,
    this.onOpenSellerOpinions,
    this.thumbnailQuarterTurns = 0,
    this.coverId,
  });

  final String sellerName;
  final String? liveTitle;
  final String thumbnailUrl;
  final String? fallbackAvatarUrl;
  final String ratingLabel;
  final double width;
  final VoidCallback onOpenLive;
  final bool isLive;
  final bool isRecordingPreparing;
  final VoidCallback? onOpenSellerProfile;
  final VoidCallback? onOpenSellerOpinions;

  /// 1 = gravado em landscape (Fase 3) — rodar thumb para preencher card 9:16.
  final int thumbnailQuarterTurns;

  /// Capa Fleaber (asset). Se null, usa [thumbnailUrl] Mux como antes.
  final String? coverId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : width;
        final cardHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : cardWidth * 16 / 9;

        return SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onOpenLive,
                      child: Ink(
                        decoration: const BoxDecoration(
                          boxShadow: [FleaberElevation.md],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _ThumbnailLayer(
                              imageUrl: thumbnailUrl,
                              cardWidth: cardWidth,
                              cardHeight: cardHeight,
                              quarterTurns: thumbnailQuarterTurns,
                              fallbackAvatarUrl: fallbackAvatarUrl,
                              coverId: coverId,
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.08),
                                    Colors.black.withOpacity(0.72),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: isLive
                        ? _LiveBadge()
                        : isRecordingPreparing
                            ? _PreparingBadge()
                            : _ReplayBadge(),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: Builder(
                      builder: (context) {
                        // Escala suave com a largura (5/fila ~210px; Arena pequena mantém base).
                        final scale = (cardWidth / 200).clamp(1.0, 1.22);
                        // Alinhado a FleaHubSiteLayout.typeBody / typeSecondary.
                        final titleSize = 14.0 * scale;
                        final nameSize = 14.0 * scale;
                        final ratingSize = 13.0 * scale;
                        final starSize = 15.0 * scale;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (liveTitle != null &&
                                liveTitle!.trim().isNotEmpty)
                              Text(
                                liveTitle!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: titleSize,
                                  height: 1.15,
                                ),
                              ),
                            if (liveTitle != null &&
                                liveTitle!.trim().isNotEmpty)
                              SizedBox(height: 4 * scale),
                            GestureDetector(
                              onTap: onOpenSellerProfile,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                sellerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: nameSize,
                                  decoration: onOpenSellerProfile != null
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                  decorationColor:
                                      Colors.white.withOpacity(0.45),
                                ),
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            GestureDetector(
                              onTap: onOpenSellerOpinions,
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: const Color(0xFFFFD700),
                                    size: starSize,
                                  ),
                                  SizedBox(width: 4 * scale),
                                  Text(
                                    ratingLabel,
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withOpacity(0.92),
                                      fontWeight: FontWeight.w600,
                                      fontSize: ratingSize,
                                      decoration: onOpenSellerOpinions != null
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                      decorationColor:
                                          Colors.white.withOpacity(0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FleaberColors.danger,
        borderRadius: FleaberRadius.circularSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'AO VIVO',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailLayer extends StatelessWidget {
  const _ThumbnailLayer({
    required this.imageUrl,
    required this.cardWidth,
    required this.cardHeight,
    required this.quarterTurns,
    this.fallbackAvatarUrl,
    this.coverId,
  });

  final String imageUrl;
  final double cardWidth;
  final double cardHeight;
  final int quarterTurns;
  final String? fallbackAvatarUrl;
  final String? coverId;

  @override
  Widget build(BuildContext context) {
    final cid = coverId?.trim() ?? '';
    Widget image = cid.isNotEmpty
        ? SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: LiveCoverImage(
              coverId: cid,
              muxFallbackUrl: imageUrl,
              fallbackAvatarUrl: fallbackAvatarUrl,
            ),
          )
        : BatataCachedNetworkImage(
            imageUrl: imageUrl,
            width: cardWidth,
            height: cardHeight,
            fit: BoxFit.cover,
            errorWidget: fallbackAvatarUrl == null
                ? null
                : BatataCachedNetworkImage(
                    imageUrl: fallbackAvatarUrl!,
                    width: cardWidth,
                    height: cardHeight,
                    fit: BoxFit.cover,
                  ),
          );

    // Capas 9:16 não precisam de rotação landscape Mux.
    if (quarterTurns != 0 && cid.isEmpty) {
      image = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: SizedBox(
              width: cardHeight,
              height: cardWidth,
              child: image,
            ),
          ),
        ),
      );
    }

    return image;
  }
}

class _ReplayBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF007782),
        borderRadius: FleaberRadius.circularSm,
      ),
      child: Text(
        'GRAVADO',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PreparingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Text(
        'GRAVAÇÃO A PREPARAR',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 9,
        ),
      ),
    );
  }
}
