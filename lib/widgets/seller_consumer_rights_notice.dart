import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/seller_professional.dart';

/// Aviso pré-contratual discreto no checkout (perto de «Confirmar»).
///
/// Profissional = apenas verificado. Restantes = aviso de particular.
/// Sem telefone/email — contactar via chat interno.
class SellerConsumerRightsNotice extends StatelessWidget {
  const SellerConsumerRightsNotice({
    super.key,
    required this.info,
    this.sellerDisplayName,
  });

  final SellerTradePublicInfo info;
  final String? sellerDisplayName;

  /// Vários vendedores no mesmo saco — um bloco por vendedor.
  static Widget forSellers({
    required Map<String, SellerTradePublicInfo> bySeller,
    Map<String, String>? displayNames,
  }) {
    final entries = bySeller.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SellerConsumerRightsNotice(
            info: entries[i].value,
            sellerDisplayName: displayNames?[entries[i].key],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (sellerDisplayName ?? info.tradeName ?? 'este vendedor').trim();
    final isPro = info.showProfessionalBadge;

    final body = isPro
        ? 'Este artigo é vendido por um profissional'
            '${name.isEmpty || name == 'este vendedor' ? '' : ' ($name)'}. '
            'Tens direito legal de livre resolução em 14 dias após receberes '
            'o bem (salvo excepções legais indicadas no anúncio), distinto da '
            'Proteção Fleaber de 48 horas. A garantia legal de conformidade '
            'também se aplica quando for o caso.'
        : 'Este artigo é vendido por um particular'
            '${name.isEmpty || name == 'este vendedor' ? '' : ' ($name)'}. '
            'O regime de livre resolução de 14 dias das compras a '
            'profissionais pode não se aplicar. A Proteção Fleaber de 48 horas '
            'após confirmares a receção continua a funcionar nos termos '
            'previstos.';

    // Identificação comercial obrigatória (sem telefone/email).
    final idBits = <String>[];
    if (isPro) {
      if ((info.tradeName ?? '').trim().isNotEmpty) {
        idBits.add(info.tradeName!.trim());
      }
      final loc = [
        if ((info.city ?? '').trim().isNotEmpty) info.city!.trim(),
        if ((info.country ?? '').trim().isNotEmpty) info.country!.trim(),
      ].join(', ');
      if (loc.isNotEmpty) idBits.add(loc);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sobre esta compra',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: FleaberColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.4,
              color: const Color(0xFF57636C),
            ),
          ),
          if (idBits.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Identificação: ${idBits.join(' · ')}',
              style: GoogleFonts.inter(
                fontSize: 11,
                height: 1.35,
                color: FleaberColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
