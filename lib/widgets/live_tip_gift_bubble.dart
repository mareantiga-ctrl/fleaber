import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fee_calculator.dart';

/// Linha de gorjeta no chat do directo — destacada e com ícone de prenda.
class LiveTipGiftBubble extends StatefulWidget {
  const LiveTipGiftBubble({
    super.key,
    required this.amountEur,
    this.showPrivacyNote = false,
    this.contributorLabel,
  });

  final double amountEur;
  final bool showPrivacyNote;
  /// Só na vista da vendedora (identidade do contributo).
  final String? contributorLabel;

  @override
  State<LiveTipGiftBubble> createState() => _LiveTipGiftBubbleState();
}

class _LiveTipGiftBubbleState extends State<LiveTipGiftBubble> {

  @override
  Widget build(BuildContext context) {
    final amountLabel = formatEuros(widget.amountEur);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '🎁 Gorjeta ',
              style: GoogleFonts.inter(
                color: const Color(0xFF00C2D1),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
            TextSpan(
              text: amountLabel,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            if (widget.contributorLabel != null &&
                widget.contributorLabel!.trim().isNotEmpty)
              TextSpan(
                text: '  de ${widget.contributorLabel!.trim()}',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
