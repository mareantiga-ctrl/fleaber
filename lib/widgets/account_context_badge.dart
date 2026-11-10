import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/hub/theme/hub_theme.dart';
import '/pages/staff/helper_access_page_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/seller_staff_service.dart';

/// Indicador visual do contexto activo (conta pessoal vs loja assistida).
class AccountContextBadge extends StatelessWidget {
  const AccountContextBadge({
    super.key,
    this.compact = false,
    /// Estilo Hub (web desktop). Default false = Android / mobile inalterado.
    this.hubStyle = false,
    /// Chip à largura do conteúdo (Resumo H11) — sem esticar a barra.
    this.fitContent = false,
  });

  final bool compact;
  final bool hubStyle;
  final bool fitContent;

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

        final bg = hubStyle
            ? (isPersonal
                ? HubTheme.surfaceElevated
                : HubTheme.teal.withValues(alpha: 0.18))
            : (isPersonal
                ? const Color(0xFFEFF4F7)
                : FleaberColors.teal.withValues(alpha: 0.13));
        final borderC = hubStyle
            ? (isPersonal
                ? Colors.white.withValues(alpha: 0.08)
                : HubTheme.accent.withValues(alpha: 0.4))
            : (isPersonal
                ? const Color(0xFFD7E2E5)
                : FleaberColors.teal.withValues(alpha: 0.45));
        final titleColor = hubStyle
            ? (isPersonal ? HubTheme.textPrimary : HubTheme.accent)
            : (isPersonal ? const Color(0xFF101518) : FleaberColors.teal);
        final subColor =
            hubStyle ? HubTheme.textMuted : const Color(0xFF57636C);
        final iconColor = hubStyle
            ? (isPersonal ? HubTheme.textSecondary : HubTheme.accent)
            : (isPersonal ? const Color(0xFF57636C) : FleaberColors.teal);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onTap(context, ctx),
            borderRadius: FleaberRadius.circularMd,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 7 : 9,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: FleaberRadius.circularMd,
                border: Border.all(color: borderC),
              ),
              child: Row(
                mainAxisSize:
                    fitContent ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Icon(
                    isPersonal
                        ? Icons.person_outline_rounded
                        : Icons.storefront_rounded,
                    size: compact ? 16 : 18,
                    color: iconColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: fitContent ? FlexFit.loose : FlexFit.tight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 11 : 12,
                            color: titleColor,
                          ),
                        ),
                        if (!compact)
                          Text(
                            isPersonal
                                ? subtitle
                                : '$subtitle · toca para mudar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: subColor,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isPersonal) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: compact ? 16 : 18,
                      color: hubStyle ? HubTheme.accent : FleaberColors.teal,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onTap(BuildContext context, SellerStaffContext ctx) async {
    if (ctx.isOwnerContext && ctx.myHelperLinks.isEmpty) return;

    if (!ctx.isOwnerContext) {
      final back = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: const Color(0xFF101518),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF57636C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Estás a operar: ${ctx.activeHelperRow?.displayName ?? 'loja assistida'}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Os resultados de directos e encomendas mostram esta loja. '
                  'Os teus directos pessoais ficam na tua conta.',
                  style: GoogleFonts.inter(
                      color: const Color(0xFF98A1AA), fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await ctx.switchToOwnStore();
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007782),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Voltar à minha loja pessoal'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx, false);
                    context.pushNamed(HelperAccessPageWidget.routeName);
                  },
                  child: const Text('Gerir lojas assistidas'),
                ),
              ],
            ),
          ),
        ),
      );
      if (back == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modo pessoal activo')),
        );
      }
      return;
    }

    context.pushNamed(HelperAccessPageWidget.routeName);
  }
}
