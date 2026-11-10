import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_primary_button.dart';

/// Card «Comprado!» / «Conjunto comprado!» na timeline — só título + corpo (+ ícone comprador).
class BundleChatPurchaseCard extends StatelessWidget {
  const BundleChatPurchaseCard({
    super.key,
    required this.forBuyer,
    required this.primaryLine,
    this.secondaryLine,
    this.showSellerShipButton = false,
    this.sellerShipBusy = false,
    this.onSellerConfirmShipment,
    this.sellerShipLabel = 'Descarregar etiqueta de envio',
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.borderColor = const Color(0xFFE0E0E0),
  });

  final bool forBuyer;
  final String primaryLine;
  final String? secondaryLine;
  final bool showSellerShipButton;
  final bool sellerShipBusy;
  final VoidCallback? onSellerConfirmShipment;
  final String sellerShipLabel;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF007782);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    primaryLine,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      height: 1.25,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  if (secondaryLine != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      secondaryLine!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.38,
                        color: const Color(0xFF3D4A55),
                      ),
                    ),
                  ],
                  if (forBuyer) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: teal,
                          size: 28,
                        ),
                      ],
                    ),
                  ],
                  if (showSellerShipButton) ...[
                    const SizedBox(height: 14),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: sellerShipLabel,
                      loading: sellerShipBusy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      textAlign: TextAlign.center,
                      borderRadius: 10,
                      height: null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed:
                          sellerShipBusy ? null : onSellerConfirmShipment,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
