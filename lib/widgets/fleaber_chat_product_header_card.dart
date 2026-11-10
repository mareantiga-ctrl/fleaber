import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/hub/theme/hub_messages_theme.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

/// Cartão de artigo no topo do chat — faixa compacta (H10 117).
///
/// Só apresentação + callbacks; a lógica de compra/proposta fica no [ChatPage].
class FleaberChatProductHeaderCard extends StatelessWidget {
  const FleaberChatProductHeaderCard({
    super.key,
    required this.product,
    required this.priceLabel,
    required this.showPurchaseActions,
    required this.onOpenDetails,
    required this.onBuy,
    required this.onOffer,
    this.offerLabel = 'Fazer proposta',
    this.statusNote,
    this.proofButton,
    this.cancelButton,
    this.extraBelow,
    /// Mockup B desktop: imagem | título+preço | acções à direita.
    this.actionsTrailing = false,
    this.embedded = false,
  });

  final ProductsRow product;
  final String priceLabel;
  final bool showPurchaseActions;
  final VoidCallback onOpenDetails;
  final VoidCallback onBuy;
  final VoidCallback onOffer;
  final String offerLabel;
  final String? statusNote;
  final Widget? proofButton;
  final Widget? cancelButton;
  final Widget? extraBelow;
  final bool actionsTrailing;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final url =
        product.imageUrls.isNotEmpty ? product.imageUrls.first : null;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final trailing = actionsTrailing && !narrow;
    final imgSize = trailing ? 56.0 : (narrow ? 64.0 : 60.0);

    final image = ClipRRect(
      borderRadius: FleaberRadius.circularSm,
      child: SizedBox(
        width: imgSize,
        height: imgSize,
        child: url != null && url.isNotEmpty
            ? BatataCachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholderColor: const Color(0xFFF1F4F8),
                errorWidget: ColoredBox(
                  color: const Color(0xFFF1F4F8),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey.shade500,
                    size: 22,
                  ),
                ),
              )
            : ColoredBox(
                color: const Color(0xFFF1F4F8),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.grey.shade500,
                  size: 26,
                ),
              ),
      ),
    );

    final titlePrice = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          product.title ?? 'Artigo',
          maxLines: trailing ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: trailing ? 14.5 : 15,
            height: 1.2,
            color: HubMessagesTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          priceLabel,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: trailing ? 16 : 17,
            color: FleaberColors.teal,
          ),
        ),
        if (!showPurchaseActions &&
            statusNote != null &&
            statusNote!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            statusNote!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.3,
              color: HubMessagesTheme.textMuted,
            ),
          ),
        ],
      ],
    );

    final body = trailing
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: onOpenDetails,
                borderRadius: FleaberRadius.circularSm,
                child: image,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onOpenDetails,
                  child: titlePrice,
                ),
              ),
              if (showPurchaseActions) ...[
                const SizedBox(width: 10),
                _ActionRow(
                  narrow: false,
                  compact: true,
                  offerLabel: offerLabel,
                  onOffer: onOffer,
                  onBuy: onBuy,
                ),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onOpenDetails,
                borderRadius: FleaberRadius.circularSm,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    image,
                    const SizedBox(width: 12),
                    Expanded(child: titlePrice),
                  ],
                ),
              ),
              if (showPurchaseActions) ...[
                const SizedBox(height: 10),
                _ActionRow(
                  narrow: narrow,
                  compact: true,
                  offerLabel: offerLabel,
                  onOffer: onOffer,
                  onBuy: onBuy,
                ),
              ],
            ],
          );

    final card = Material(
      color: HubMessagesTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: embedded ? BorderRadius.zero : FleaberRadius.circularMd,
        side: BorderSide(
          color: embedded ? Colors.transparent : HubMessagesTheme.border,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          embedded ? 14 : 12,
          embedded ? 8 : 10,
          embedded ? 14 : 12,
          embedded ? 8 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (proofButton != null) ...[
              const SizedBox(height: 6),
              proofButton!,
            ],
            // Cancelamento: acção secundária compacta (nunca barra full-width).
            if (cancelButton != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: cancelButton!,
              ),
            ],
            if (extraBelow != null) extraBelow!,
          ],
        ),
      ),
    );

    if (embedded) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: HubMessagesTheme.surface,
          border: Border(
            bottom: BorderSide(color: HubMessagesTheme.divider),
          ),
        ),
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: actionsTrailing ? double.infinity : 560,
          ),
          child: card,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.narrow,
    required this.offerLabel,
    required this.onOffer,
    required this.onBuy,
    this.compact = false,
  });

  final bool narrow;
  final bool compact;
  final String offerLabel;
  final VoidCallback onOffer;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 36.0 : 42.0;
    final offerBtn = OutlinedButton(
      onPressed: onOffer,
      style: OutlinedButton.styleFrom(
        foregroundColor: FleaberColors.teal,
        side: const BorderSide(color: FleaberColors.teal, width: 1.3),
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: 0),
        minimumSize: Size(0, h),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      child: Text(
        offerLabel,
        style: GoogleFonts.inter(
          fontSize: compact ? 13 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final buyBtn = FleaberPrimaryButton(
      label: 'Comprar',
      height: h,
      borderRadius: 11,
      fontSize: compact ? 13 : 14,
      fontWeight: FontWeight.w700,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
      onPressed: onBuy,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buyBtn,
          const SizedBox(height: 6),
          offerBtn,
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        buyBtn,
        offerBtn,
      ],
    );
  }
}
