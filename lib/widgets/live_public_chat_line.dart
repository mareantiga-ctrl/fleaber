import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Linha de chat público no directo (com destaque opcional para a vendedora).
class LivePublicChatLine extends StatelessWidget {
  const LivePublicChatLine({
    super.key,
    required this.label,
    required this.text,
    this.isSeller = false,
    this.compact = false,
    this.onDarkOverlay = true,
  });

  final String label;
  final String text;
  final bool isSeller;
  final bool compact;
  final bool onDarkOverlay;

  static const List<Shadow> _kLegibilityShadow = [
    Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
    Shadow(color: Colors.black54, blurRadius: 3),
  ];

  @override
  Widget build(BuildContext context) {
    final nameColor = isSeller
        ? const Color(0xFFFFD54F)
        : onDarkOverlay
            ? const Color(0xFF4DD0E1)
            : const Color(0xFF007782);
    final bodyColor = isSeller
        ? const Color(0xFF69F0AE)
        : onDarkOverlay
            ? Colors.white
            : const Color(0xFF101518);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 5 : 7),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(
                color: nameColor,
                fontWeight: isSeller ? FontWeight.w900 : FontWeight.w700,
                fontSize: compact ? (isSeller ? 12 : 10.5) : (isSeller ? 13 : 11),
                shadows: onDarkOverlay ? _kLegibilityShadow : null,
              ),
            ),
            TextSpan(
              text: text,
              style: GoogleFonts.inter(
                color: bodyColor,
                fontSize: compact ? (isSeller ? 13 : 11.5) : (isSeller ? 14 : 12),
                fontWeight: isSeller ? FontWeight.w800 : FontWeight.w500,
                height: 1.25,
                shadows: onDarkOverlay ? _kLegibilityShadow : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
