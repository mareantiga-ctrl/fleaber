import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';

/// Card portrait 9:16 para um direto Mux na Home.
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
    this.onOpenSellerProfile,
    this.onOpenSellerOpinions,
    this.thumbnailQuarterTurns = 0,
  });

  final String sellerName;
  final String? liveTitle;
  final String thumbnailUrl;
  final String? fallbackAvatarUrl;
  final String ratingLabel;
  final double width;
  final VoidCallback onOpenLive;
  final bool isLive;
  final VoidCallback? onOpenSellerProfile;
  final VoidCallback? onOpenSellerOpinions;

  /// 1 = gravado em landscape (Fase 3) — rodar thumb para preencher card 9:16.
  final int thumbnailQuarterTurns;

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
                    child: isLive ? _LiveBadge() : _ReplayBadge(),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (liveTitle != null && liveTitle!.trim().isNotEmpty)
                          Text(
                            liveTitle!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              height: 1.15,
                            ),
                          ),
                        if (liveTitle != null && liveTitle!.trim().isNotEmpty)
                          const SizedBox(height: 4),
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
                              fontSize: 14,
                              decoration: onOpenSellerProfile != null
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: Colors.white.withOpacity(0.45),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: onOpenSellerOpinions,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFD700),
                                size: 15,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ratingLabel,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
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
            'LIVE',
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
  });

  final String imageUrl;
  final double cardWidth;
  final double cardHeight;
  final int quarterTurns;
  final String? fallbackAvatarUrl;

  @override
  Widget build(BuildContext context) {
    Widget image = BatataCachedNetworkImage(
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

    if (quarterTurns != 0) {
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
