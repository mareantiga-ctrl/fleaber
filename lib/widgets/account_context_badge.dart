import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_staff_service.dart';

/// Indicador visual do contexto activo (conta pessoal vs loja assistida).
class AccountContextBadge extends StatelessWidget {
  const AccountContextBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SellerStaffContext.instance,
      builder: (context, _) {
        final ctx = SellerStaffContext.instance;
        final isPersonal = ctx.isOwnerContext;
        final label = isPersonal
            ? 'Modo pessoal'
            : 'A operar: ${ctx.activeHelperRow?.displayName ?? 'Loja assistida'}';
        final subtitle = isPersonal
            ? 'Estás a usar a tua própria conta'
            : 'Alterações afetam a loja selecionada';

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            color: isPersonal
                ? const Color(0xFFEFF4F7)
                : FleaberColors.teal.withValues(alpha: 0.13),
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(
              color: isPersonal
                  ? const Color(0xFFD7E2E5)
                  : FleaberColors.teal.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isPersonal ? Icons.person_outline_rounded : Icons.storefront_rounded,
                size: compact ? 16 : 18,
                color: isPersonal ? const Color(0xFF57636C) : FleaberColors.teal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 11 : 12,
                        color:
                            isPersonal ? const Color(0xFF101518) : FleaberColors.teal,
                      ),
                    ),
                    if (!compact)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF57636C),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
