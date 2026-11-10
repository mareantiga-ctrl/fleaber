import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Textos do saco da live: artigos (linhas) vs unidades (quantidades).
/// Não altera a lógica das reservas — só a apresentação.
abstract final class LiveBagCopy {
  static String _n(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';

  /// Cabeçalho: «2 artigos · 3 unidades» (+ cancelados se houver).
  static String headerSubtitle({
    required int articleCount,
    required int unitCount,
    int cancelledCount = 0,
  }) {
    final core =
        '${_n(articleCount, 'artigo', 'artigos')} · ${_n(unitCount, 'unidade', 'unidades')}';
    if (cancelledCount <= 0) return core;
    return '$core · ${_n(cancelledCount, 'cancelado', 'cancelados')}';
  }

  /// Contagem entre parêntesis nas secções («No saco (2 artigos · 3 unidades)»).
  static String sectionCount({
    required int articleCount,
    required int unitCount,
  }) =>
      headerSubtitle(articleCount: articleCount, unitCount: unitCount);
}

/// Copy canónica dos estados comerciais do saco (Fase 3 — buyer UI).
///
/// Queue/posição pode existir no backend e no Seller Studio — **nunca** à buyer.
abstract final class LiveBagBuyerStateCopy {
  static const approvalPending = 'A aguardar aprovação';
  static const immediatePayment = 'Pagamento imediato';
  static const unavailable = 'Indisponível';
  static const guaranteedFallback = 'Reservado';

  static const approvalPendingInfo =
      'O pedido foi enviado à vendedora. Enquanto aguarda aprovação, o artigo '
      'continua disponível e só fica reservado depois de ser aceite.';

  static const immediatePaymentInfo =
      'Este artigo não fica reservado. A compra fica garantida quando concluir o '
      'pagamento. Clientes de confiança podem ter acesso a reserva automática.';

  static String guaranteedUntil(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Reservado até às $hh:$mm';
  }

  /// Info ⓘ só onde a diferença pode não ser óbvia.
  static String? infoTextForLineState(String lineState) {
    return switch (lineState) {
      'approval_pending' => approvalPendingInfo,
      'bag_unguaranteed' || 'bag_hold_none' => immediatePaymentInfo,
      _ => null,
    };
  }

  static bool showsInfoIcon(String lineState) =>
      infoTextForLineState(lineState) != null;
}

/// Chip de estado buyer + ⓘ opcional (tap/click → diálogo leve; não hover-only).
class LiveBagBuyerStateChip extends StatelessWidget {
  const LiveBagBuyerStateChip({
    super.key,
    required this.label,
    required this.color,
    this.infoText,
    this.fontSize = 9,
    /// Hub / saco claro: texto escuro sobre fundo pastel (não cyan/âmbar claro).
    this.onLightBackground = false,
  });

  final String label;
  final Color color;
  final String? infoText;
  final double fontSize;
  final bool onLightBackground;

  static Color _textOnLight(Color accent) {
    final r = accent.r;
    final g = accent.g;
    final b = accent.b;
    // Verde / aceite
    if (g > r && g > b) return const Color(0xFF1B5E20);
    // Âmbar / pendente
    if (r > g && g >= b * 0.6) return const Color(0xFF7A4E00);
    // Vermelho / indisponível
    if (r > g && r > b) return const Color(0xFF7F1D1D);
    // Teal / neutro
    if (b > r * 0.9 && g > r * 0.9) return const Color(0xFF007782);
    return const Color(0xFF101518);
  }

  static Color _bgOnLight(Color accent) {
    final text = _textOnLight(accent);
    if (text == const Color(0xFF1B5E20)) return const Color(0xFFE8F5E9);
    if (text == const Color(0xFF7A4E00)) return const Color(0xFFFFF3E0);
    if (text == const Color(0xFF7F1D1D)) return const Color(0xFFFFEBEE);
    if (text == const Color(0xFF007782)) return const Color(0xFFE0F4F5);
    return const Color(0xFFEEF2F4);
  }

  @override
  Widget build(BuildContext context) {
    final hasInfo = (infoText ?? '').trim().isNotEmpty;
    final fg = onLightBackground ? _textOnLight(color) : color;
    final bg = onLightBackground
        ? _bgOnLight(color)
        : color.withValues(alpha: 0.2);
    final border = onLightBackground
        ? fg.withValues(alpha: 0.35)
        : color.withValues(alpha: 0.55);
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (hasInfo)
          Semantics(
            button: true,
            label: 'Mais informação: $label',
            child: InkWell(
              onTap: () => showLiveBagBuyerStateInfo(
                context,
                title: label,
                body: infoText!.trim(),
                accent: color,
                onLightBackground: onLightBackground,
              ),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: fg.withValues(alpha: 0.95),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void showLiveBagBuyerStateInfo(
  BuildContext context, {
  required String title,
  required String body,
  Color accent = const Color(0xFF00A3AD),
  bool onLightBackground = false,
}) {
  final dialogBg =
      onLightBackground ? Colors.white : const Color(0xFF1A2329);
  final titleFg =
      onLightBackground ? const Color(0xFF101518) : Colors.white;
  final bodyFg = onLightBackground
      ? const Color(0xFF57636C)
      : Colors.white.withValues(alpha: 0.88);
  final accentFg = onLightBackground
      ? (accent == const Color(0xFF00A3AD)
          ? const Color(0xFF007782)
          : LiveBagBuyerStateChip._textOnLight(accent))
      : accent;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: dialogBg,
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: titleFg,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      content: Text(
        body,
        style: GoogleFonts.inter(
          color: bodyFg,
          fontSize: 13,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Percebi',
            style: GoogleFonts.inter(
              color: accentFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
