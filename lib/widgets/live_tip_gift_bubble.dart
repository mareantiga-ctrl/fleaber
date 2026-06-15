import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fee_calculator.dart';
import '/utils/live_system_chat_humanizer.dart';
import '/widgets/live_public_chat_line.dart';

/// Linha de gorjeta no chat do directo — copy social A2.
class LiveTipGiftBubble extends StatelessWidget {
  const LiveTipGiftBubble({
    super.key,
    required this.amountEur,
    this.showPrivacyNote = false,
    this.contributorLabel,
    this.animateHighlight = false,
  });

  final double amountEur;
  final bool showPrivacyNote;

  /// Só na vista da vendedora (identidade do contributo).
  final String? contributorLabel;
  final bool animateHighlight;

  @override
  Widget build(BuildContext context) {
    final amountLabel = formatEuros(amountEur);
    final parsed = LiveSystemChatHumanizer.parseTip(
      amountEur: amountEur,
      contributorName: contributorLabel,
      amountLabel: amountLabel,
    );

    final name = parsed.personName?.trim() ?? '';
    final line = parsed.line;

    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            parsed.icon ?? LiveSystemChatIcons.tip,
            size: 15,
            color: const Color(0xFF5CE1E6),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: GoogleFonts.inter(
                  color: const Color(0xFFB8E6C8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  shadows: LivePublicChatLine.kLegibilityShadow,
                ),
                children: [
                  if (name.isNotEmpty && line.contains(name)) ...[
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: line.substring(
                        line.indexOf(name) + name.length,
                      ),
                    ),
                  ] else
                    TextSpan(text: line),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (animateHighlight && parsed.highlightDuration != null) {
      content = LiveSystemChatHighlight(
        duration: parsed.highlightDuration!,
        color: const Color(0xFF5CE1E6),
        intensity: 1.35,
        child: content,
      );
    }

    return content;
  }
}
