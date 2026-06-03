import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_radius.dart';
import '/utils/fleaber_typography.dart';
import 'batata_cached_image.dart';

/// Card estilo marketplace (Fleaber / Vinted): foto portrait 3:4, texto por baixo.
class MarketplaceProductCard extends StatelessWidget {
  /// Largura:altura da foto (Vinted — mais alta que 1:1, menos corte com [BoxFit.cover]).
  static const double imageAspectRatio = 3 / 4;

  /// [SliverGridDelegateWithFixedCrossAxisCount.childAspectRatio] para grelha 2 colunas.
  static const double gridChildAspectRatio = 0.56;

  /// Altura recomendada para [ListView] horizontal de cards com [width] fixa.
  static double horizontalListHeight(double cardWidth) =>
      cardWidth / imageAspectRatio + 76;

  const MarketplaceProductCard({
    super.key,
    required this.title,
    required this.stateLabel,
    required this.priceLabel,
    required this.imageUrl,
    required this.favoritesCount,
    required this.isFavorited,
    required this.onTap,
    this.onFavoriteTap,
    this.width,
  });

  final String title;
  final String? stateLabel;
  final String priceLabel;
  final String? imageUrl;
  final int favoritesCount;
  final bool isFavorited;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteTap;

  /// Largura fixa (ex.: lista horizontal). Na grelha da Home fica a `null` e o pai define a largura.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final stateText = stateLabel?.trim();
    final hasState = stateText != null && stateText.isNotEmpty;

    final core = Material(
      color: Colors.white,
      borderRadius: FleaberRadius.circularMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: imageAspectRatio,
              child: ColoredBox(
                color: const Color(0xFFE8EDF2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: imageUrl != null && imageUrl!.isNotEmpty
                          ? BatataCachedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorWidget: const ColoredBox(
                                color: Color(0xFFE8EDF2),
                                child: Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Color(0xFF57636C),
                                    size: 36.0,
                                  ),
                                ),
                              ),
                            )
                          : const ColoredBox(
                              color: Color(0xFFE8EDF2),
                              child: Center(
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: Color(0xFF57636C),
                                  size: 36.0,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      right: 8.0,
                      bottom: 8.0,
                      child: IgnorePointer(
                        ignoring: onFavoriteTap == null,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onFavoriteTap,
                            borderRadius: FleaberRadius.circularLg,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: favoritesCount > 0 ? 8.0 : 7.0,
                                vertical: 6.0,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.48),
                                borderRadius: FleaberRadius.circularLg,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isFavorited
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 15.0,
                                    color: isFavorited
                                        ? const Color(0xFFFF4D67)
                                        : Colors.white,
                                  ),
                                  if (favoritesCount > 0) ...[
                                    const SizedBox(width: 5.0),
                                    Text(
                                      '$favoritesCount',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w600,
                                        height: 1.0,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FleaberTypography.cardTitle(),
                  ),
                  if (hasState) ...[
                    const SizedBox(height: 5.0),
                    Text(
                      stateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FleaberTypography.cardMeta(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  SizedBox(height: hasState ? 5.0 : 6.0),
                  Text(
                    priceLabel,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF101518),
                      fontSize: 15.0,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (width != null) {
      return SizedBox(width: width, child: core);
    }
    return core;
  }
}
