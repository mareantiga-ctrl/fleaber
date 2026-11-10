import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

/// Indicadores de email / telemóvel verificados (só mostra o que está verificado).
class FleaberVerificationBadges extends StatelessWidget {
  const FleaberVerificationBadges({
    super.key,
    required this.emailVerified,
    required this.phoneVerified,
    this.compact = false,
    this.ultraCompact = false,
  });

  final bool emailVerified;
  final bool phoneVerified;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (emailVerified) {
      children.add(
        _Badge(label: 'Email', compact: compact, ultraCompact: ultraCompact),
      );
    }
    if (phoneVerified) {
      children.add(
        _Badge(
          label: 'Telemóvel',
          compact: compact,
          ultraCompact: ultraCompact,
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: ultraCompact ? 4 : (compact ? 6 : 8),
      runSpacing: ultraCompact ? 0 : (compact ? 6 : 8),
      children: children,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.compact,
    this.ultraCompact = false,
  });

  final String label;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    if (ultraCompact) {
      return Text(
        '✓ $label',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: FleaberColors.teal,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: FleaberColors.teal.withValues(alpha: 0.1),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(
          color: FleaberColors.teal.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: compact ? 14 : 16,
            color: FleaberColors.teal,
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            '$label · Verificado',
            style: GoogleFonts.inter(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: FleaberColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}
