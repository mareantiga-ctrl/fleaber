import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_elevation.dart';

/// Tokens visuais Hub web — live commerce escuro (não marketplace claro).
abstract final class HubTheme {
  static const Color bg = Color(0xFF101518);
  static const Color surface = Color(0xFF1A2228);
  static const Color surfaceElevated = Color(0xFF232B32);
  static const Color teal = Color(0xFF007782);
  static const Color accent = Color(0xFF00A3AD);
  static const Color liveRed = Color(0xFFE53935);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0x80FFFFFF);
  /// Largura móvel / telemóvel (H16 histórico). Em ecrãs largos usa
  /// [contentMaxWidthFor] — telemóvel continua ≤480 porque o viewport é menor.
  static const double maxContentWidth = 480;
  static const double maxContentWidthTablet = 720;
  static const double maxContentWidthDesktop = 840;

  /// Live Hub B1 — shell desktop (vídeo + chat à direita). Alinhado ao desktop
  /// FleaHub (≥1180). Abaixo disto mantém o layout mobile/overlay.
  static const double liveDesktopShellBreakpoint = 1180;

  /// H03 desktop — aproveitar largura útil (Home ~94%); teto em monitores 2K.
  static const double liveDesktopStageMaxWidth = 1840;

  /// Desktop shell (≥1180): 5 zonas laterais (sem faixa MP inferior).
  /// Vídeo encolhe em 9:16 se faltar largura — não comprimir texto até ilegível.
  static const double liveDesktopFiveZoneMinWidth = 1180;

  /// Gap horizontal entre zonas do shell desktop.
  static const double liveDesktopColumnGap = 8;

  /// Flex mínimo / alvo (grelha proporcional — sem colunas vazias).
  /// Surplus → produtos + chat (não só Marketplace).
  static const double liveDesktopSellerMinWidth = 210;
  static const double liveDesktopSellerFlex = 1.0;
  static const double liveDesktopProductsMinWidth = 210;
  static const double liveDesktopProductsFlex = 1.55;
  static const double liveDesktopChatMinWidth = 268;
  static const double liveDesktopChatFlex = 1.80;
  static const double liveDesktopMarketplaceMinWidth = 240;
  static const double liveDesktopMarketplaceFlex = 1.25;
  /// Compat: base do chat antes do flex (≈ +22% vs 220).
  static const double liveDesktopChatWidth = 268;
  static const double liveDesktopProductsWidth = 236;

  static bool useLiveDesktopFiveZones(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= liveDesktopFiveZoneMinWidth;

  static bool useLiveDesktopShell(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= liveDesktopShellBreakpoint;

  /// Coluna Hub: estreita no telefone; mais larga no browser desktop (sem
  /// mudar layouts mobile — o max só aplica quando a janela é maior).
  static double contentMaxWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return maxContentWidthDesktop;
    if (w >= 700) return maxContentWidthTablet;
    return maxContentWidth;
  }

  /// Marketplace shop (`/{handle}/shop`) — tokens locais à Página 04.
  /// Telemóvel / tablet estreito (&lt;1000) mantém 2 colunas; desktop densifica.
  /// Não afectar Landing / Seller / Live (`contentMaxWidthFor` / live shell).
  static const double shopMaxContentWidth = 1680;
  static const double shopGridGap = 10;
  static const double shopGridPadding = 12;
  /// Largura mínima alvo do card desktop (~220–230 px na composição aprovada).
  static const double shopMinCardWidth = 210;
  /// Aspect da grelha só em `HubShopPage` (densidade aprovada; ≠ Home/Favoritos).
  static const double shopGridChildAspectRatio = 0.58;

  static double shopContentMaxWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 700) return maxContentWidth;
    // 768 permanece em faixa estreita / 2 colunas.
    if (w < 1000) return math.min(w - 48, 900);
    // Margens ~32px; teto ultrawide (estudo densidade aprovado).
    return math.min(w - 64, shopMaxContentWidth);
  }

  /// Colunas da loja: &lt;1000 = 2; desktop cresce por largura útil do card (3–7).
  static int shopGridCrossAxisCount(BuildContext context) {
    final viewportW = MediaQuery.sizeOf(context).width;
    if (viewportW < 1000) return 2;
    final contentW = shopContentMaxWidthFor(context);
    final inner = contentW - shopGridPadding * 2;
    final cols = ((inner + shopGridGap) / (shopMinCardWidth + shopGridGap))
        .floor();
    return cols.clamp(3, 7);
  }

  /// Opiniões (`/{handle}/reviews`) — Página 05. Local; não altera Landing/Shop/Live.
  /// Desktop ≥1100: contentor ~1160 (resumo + lista 1 coluna). Mobile mantém faixa estreita.
  static const double reviewsMaxContentWidth = 1160;
  static const double reviewsSummaryDesktopWidth = 300;
  static const double reviewsDesktopSplitBreakpoint = 1100;

  static double reviewsContentMaxWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 700) return maxContentWidth;
    if (w < reviewsDesktopSplitBreakpoint) {
      return math.min(w - 48, maxContentWidthTablet);
    }
    return math.min(w - 64, reviewsMaxContentWidth);
  }

  static bool useReviewsDesktopSplit(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= reviewsDesktopSplitBreakpoint;

  /// Mensagens (P10) — split lista | conversa. Local à página; telemóvel
  /// (<1024) mantém navegação lista → chat a ecrã inteiro.
  /// Cores do chrome H10: ver [HubMessagesTheme] (não estes tokens escuros).
  /// Desktop ≥1024: Mockup B (caixa de entrada 280–320 + conversa).
  static const double messagesSplitBreakpoint = 1024;
  /// Lista desktop Mockup B ~280–320 px.
  static const double messagesListPaneMaxWidth = 320;
  static const double messagesListPaneMinWidth = 280;
  /// Compat legado — o painel direito usa a largura restante (sem teto estreito).
  static const double messagesThreadMaxWidth = 2400;
  static const double messagesNotifMaxWidth = 2400;

  static bool useMessagesDesktopSplit(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= messagesSplitBreakpoint;

  /// Lista Mockup B; o painel da conversa ocupa o resto (≥1024).
  /// 1024→280 · 1280→300 · 1440+→320.
  static double messagesListPaneWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1440) return messagesListPaneMaxWidth;
    if (w >= 1280) return 300;
    return messagesListPaneMinWidth;
  }

  /// Perfil conta app (H11) — shell desktop (sidebar) só em web ≥768.
  /// Telemóvel (&lt;768) e Android mantêm a lista clara existente.
  /// Tokens de cor da conta: [FleaberColors] (tema branco H01–H06), não o live escuro.
  static const double profileDesktopBreakpoint = 768;
  /// H113: shell Conta usa largura total; sidebar 240–280.
  static const double profileSidebarWidth = 264;
  static const double profileSidebarMinWidth = 240;
  static const double profileSidebarMaxWidth = 280;
  /// Compat testes / legado — o shell H113 já não limita o painel a este teto.
  static const double profileMaxContentWidth = 1240;

  static bool useProfileDesktopLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= profileDesktopBreakpoint;

  static double profileSidebarWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 1100) return profileSidebarMinWidth;
    if (w >= 1920) return profileSidebarMaxWidth;
    return profileSidebarWidth;
  }

  static double profileContentMaxWidthFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < profileDesktopBreakpoint) return maxContentWidth;
    return w;
  }

  static TextStyle titleLg = GoogleFonts.inter(
    color: textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static TextStyle titleMd = GoogleFonts.inter(
    color: textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  static TextStyle body = GoogleFonts.inter(
    color: textSecondary,
    fontSize: 14,
    height: 1.4,
  );

  static TextStyle label = GoogleFonts.inter(
    color: textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: const [FleaberElevation.md],
  );

  static BoxDecoration liveBadgeDecoration = BoxDecoration(
    color: liveRed,
    borderRadius: BorderRadius.circular(6),
    boxShadow: [FleaberElevation.smAccent(liveRed)],
  );
}
