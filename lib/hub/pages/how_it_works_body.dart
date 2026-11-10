import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';

/// H15 canónico — quatro passos (público FleaHub e Perfil).
///
/// Detalhe de comprar / vender / segurança vive nas páginas H16–H18,
/// acedidas pelos botões abaixo — não duplicar textos longos aqui.
class HowItWorksBody extends StatelessWidget {
  const HowItWorksBody({
    super.key,
    this.embedded = false,
    this.onBuySafe,
    this.onSell,
    this.onFaq,
    this.compactPadding = false,
  });

  final bool embedded;
  final VoidCallback? onBuySafe;
  final VoidCallback? onSell;
  final VoidCallback? onFaq;

  /// Sem padding de página FleaHub (já aplicado pelo shell do Perfil).
  final bool compactPadding;

  static const title = 'Como funciona';
  static const subtitle =
      'Na Fleaber compras e vendes no mesmo sítio: diretos, loja do vendedor '
      'e marketplace — com reservas e pagamento protegido.';

  static const steps = <(String, String, IconData)>[
    (
      'Descobre',
      'Entra num directo, visita o FleaHub de um vendedor ou explora o marketplace.',
      Icons.explore_outlined,
    ),
    (
      'Reserva',
      'Marca os artigos que queres. O stock fica associado à tua conta.',
      Icons.bookmark_add_outlined,
    ),
    (
      'O teu saco',
      'Junta as reservas no saco, vê o total e prepara o envio.',
      Icons.shopping_bag_outlined,
    ),
    (
      'Compra com segurança',
      'Paga na app ou no Hub. Acompanhas a encomenda, o envio e a conversa com o vendedor.',
      Icons.payments_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: FleaberColors.text,
            fontSize: embedded ? 24 : 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            color: FleaberColors.muted,
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _StepCard(
            index: i + 1,
            title: steps[i].$1,
            body: steps[i].$2,
            icon: steps[i].$3,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Para mais detalhe:',
          style: GoogleFonts.inter(
            color: FleaberColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onBuySafe != null)
              _LinkChip(
                label: 'Comprar com segurança',
                onTap: onBuySafe!,
                filled: true,
              ),
            if (onSell != null)
              _LinkChip(label: 'Vender na Fleaber', onTap: onSell!),
            if (onFaq != null)
              _LinkChip(label: 'Perguntas Frequentes', onTap: onFaq!),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );

    if (compactPadding || embedded) {
      return content;
    }
    return content;
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
    required this.icon,
  });

  final int index;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FleaberColors.teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$index',
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: FleaberColors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          color: FleaberColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: FleaberColors.muted,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: FleaberColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FleaberRadius.md),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: FleaberColors.teal, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FleaberRadius.md),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: FleaberColors.teal,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
