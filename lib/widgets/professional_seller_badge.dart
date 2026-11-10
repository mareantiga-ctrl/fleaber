import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

/// Distintivo discreto «Profissional» — só para vendedores **verificados**.
/// Sem distintivo «Particular».
class ProfessionalSellerBadge extends StatelessWidget {
  const ProfessionalSellerBadge({
    super.key,
    this.verified = true,
    this.compact = false,
  });

  /// Mantido por compatibilidade de call-sites; o badge só deve ser montado
  /// quando o vendedor está verificado.
  final bool verified;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Vendedor profissional com dados verificados pela Fleaber. '
          'Não certifica automaticamente a qualidade dos produtos.',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4F5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFB8D9DC)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: compact ? 12 : 14,
              color: FleaberColors.teal,
            ),
            SizedBox(width: compact ? 3 : 4),
            Text(
              'Profissional',
              style: GoogleFonts.inter(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: FleaberColors.teal,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
