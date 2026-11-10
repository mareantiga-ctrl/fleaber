import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/live_amazon/live_amazon_live_bridge.dart';
import '/live_amazon/live_amazon_present_overlay.dart';
import '/live_amazon/live_amazon_scan_sheet.dart';

/// Botão Hub — mesmo fluxo Android: ler → overlay → montra.
class HubLiveAmazonScanButton extends StatelessWidget {
  const HubLiveAmazonScanButton({
    super.key,
    required this.liveId,
    required this.sellerId,
    this.onAdded,
  });

  final String liveId;
  final String sellerId;
  final Future<void> Function(String liveItemId)? onAdded;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final item = await LiveAmazonScanSheet.open(context);
        if (item == null || !context.mounted) return;
        LiveAmazonPresentOverlay.show(
          context,
          item: item,
          seconds: 10,
          onAddToVitrine: () async {
            try {
              final id = await LiveAmazonLiveBridge.instance.addToVitrine(
                liveId: liveId,
                sellerId: sellerId,
                item: item,
              );
              if (id == null || id.isEmpty) return;
              await LiveAmazonLiveBridge.instance.setActiveLiveItem(
                liveId: liveId,
                liveItemId: id,
              );
              LiveAmazonPresentOverlay.hide();
              await onAdded?.call(id);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Montra Hub: $e')),
                );
              }
            }
          },
        );
      },
      icon: const Icon(Icons.qr_code_scanner, size: 18),
      label: Text(
        'Ler Amazon',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
