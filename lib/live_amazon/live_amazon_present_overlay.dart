import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/live_amazon/live_amazon_models.dart';
import '/utils/fleaber_colors.dart';

/// Overlay temporário sobre o directo (foto + preços) e regresso à câmara.
class LiveAmazonPresentOverlay {
  LiveAmazonPresentOverlay._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static bool get isShowing => _entry != null;

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  /// Mostra [item] durante [seconds], depois remove (sem cortar o directo).
  static void show(
    BuildContext context, {
    required LiveAmazonPresentItem item,
    int seconds = 8,
    VoidCallback? onAddToVitrine,
    VoidCallback? onDismiss,
  }) {
    hide();
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (ctx) => _AmazonPresentCard(
        item: item,
        onClose: () {
          hide();
          onDismiss?.call();
        },
        onAdd: onAddToVitrine == null
            ? null
            : () {
                onAddToVitrine();
              },
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(Duration(seconds: seconds), () {
      hide();
      onDismiss?.call();
    });
  }
}

class _AmazonPresentCard extends StatelessWidget {
  const _AmazonPresentCard({
    required this.item,
    required this.onClose,
    this.onAdd,
  });

  final LiveAmazonPresentItem item;
  final VoidCallback onClose;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final amazon = item.amazonRefPriceEur;
    final market = (item.amazonRefMarket ?? '').toUpperCase();
    final fetched = item.amazonRefFetchedAt;
    final dateStr = fetched == null
        ? '—'
        : '${fetched.day.toString().padLeft(2, '0')}/'
            '${fetched.month.toString().padLeft(2, '0')}/'
            '${fetched.year}';

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
          child: Material(
            color: const Color(0xE6101518),
            borderRadius: BorderRadius.circular(16),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: item.imageUrl != null &&
                              item.imageUrl!.startsWith('http')
                          ? Image.network(
                              item.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _ph(),
                            )
                          : _ph(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.titlePt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ref ${item.refLabel} · ${item.saleCondition}',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        if (amazon != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Amazon ${market.isEmpty ? '' : '$market '} '
                            '${amazon.toStringAsFixed(2)} € · $dateStr',
                            style: GoogleFonts.inter(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        Text(
                          'Fleaber ${item.fleaberPriceEur.toStringAsFixed(2)} € '
                          '(−${item.discountPct.toStringAsFixed(0)}%)'
                          '${item.isSellableNow ? '' : ' · sem stock'}',
                          style: GoogleFonts.inter(
                            color: FleaberColors.teal,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        if (onAdd != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton(
                                onPressed: item.isSellableNow ||
                                        item.fleaberProductId != null
                                    ? onAdd
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF007782),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  'Adicionar à montra',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: onClose,
                                child: Text(
                                  'Fechar',
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFF1A2329),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.white38),
      );
}
