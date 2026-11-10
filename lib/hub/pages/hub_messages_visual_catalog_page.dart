import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/hub/theme/hub_messages_theme.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_chat_product_header_card.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/price_offer_chat_card.dart';
import '/widgets/profile_avatar.dart';

/// Catálogo visual H10 — 17 famílias com componentes reais sempre que seguro.
///
/// Gate: `--dart-define=FLEABER_H10_VISUAL_CATALOG=true` ou debug/profile.
/// Sem escrita BD / sem acções comerciais.
class HubMessagesVisualCatalogPage extends StatelessWidget {
  const HubMessagesVisualCatalogPage({super.key, this.familyId});

  /// Ex.: `F07` — mostra só essa família (capturas distintas via URL).
  final String? familyId;

  static const routeName = 'H10MensagensCatalog';
  static const routePath = '/h10MensagensCatalog';

  static const familyIds = [
    'F01',
    'F02',
    'F03',
    'F04',
    'F05',
    'F06',
    'F07',
    'F08',
    'F09',
    'F10',
    'F11',
    'F12',
    'F13',
    'F14',
    'F15',
    'F16',
    'F17',
    'F07b',
  ];

  static bool get isEnabled {
    const viaDefine = bool.fromEnvironment(
      'FLEABER_H10_VISUAL_CATALOG',
      defaultValue: false,
    );
    return viaDefine || kDebugMode || kProfileMode;
  }

  static ProductsRow get _demoProduct => ProductsRow({
        'id': '00000000-0000-4000-8000-000000000001',
        'title': 'Camisola vintage M · azul',
        'price': 12.0,
        'image_urls': <String>[],
      });

  @override
  Widget build(BuildContext context) {
    if (!isEnabled) {
      return Scaffold(
        backgroundColor: HubMessagesTheme.bg,
        body: Center(
          child: Text(
            'Catálogo H10 indisponível neste build.',
            style: HubMessagesTheme.body,
          ),
        ),
      );
    }

    final filter = familyId?.trim().toUpperCase();
    final items = _allFamilies()
        .where((e) => filter == null || filter.isEmpty || e.id == filter)
        .toList();

    return Scaffold(
      backgroundColor: HubMessagesTheme.bg,
      appBar: AppBar(
        backgroundColor: HubMessagesTheme.surface,
        elevation: 0,
        title: Text(
          filter == null || filter.isEmpty
              ? 'H10 — Catálogo 17 famílias (115.1)'
              : 'H10 — $filter',
          style: GoogleFonts.inter(
            color: HubMessagesTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 64),
        children: [
          if (filter == null || filter.isEmpty)
            _note(
              'Usa ?family=F07 para uma família. Componentes reais assinalados; '
              'shells só quando o widget exige BD.',
            ),
          if (items.isEmpty)
            _note('Família desconhecida: $filter')
          else
            ...items.map(
              (e) => _family(
                id: e.id,
                title: e.title,
                kind: e.kind,
                child: e.child,
              ),
            ),
        ],
      ),
    );
  }

  List<({String id, String title, String kind, Widget child})> _allFamilies() {
    return [
      (
        id: 'F01',
        title: 'Chrome shell (lista + conversa)',
        kind: 'demo layout',
        child: _shellDemo(),
      ),
      (
        id: 'F02',
        title: 'Mensagem pessoal enviada',
        kind: 'tokens reais HubMessagesTheme',
        child: Align(
          alignment: Alignment.centerRight,
          child: _bubble(
            text:
                'Olá! Ainda tens a camisola M disponível? Posso reservar para amanhã.',
            sent: true,
            time: '14:02',
            read: true,
          ),
        ),
      ),
      (
        id: 'F03',
        title: 'Mensagem pessoal recebida',
        kind: 'tokens reais HubMessagesTheme',
        child: Align(
          alignment: Alignment.centerLeft,
          child: _bubble(
            text: 'Sim, está disponível. Diz-me a quantidade.',
            sent: false,
            time: '14:03',
          ),
        ),
      ),
      (
        id: 'F04',
        title: 'Imagem no chat',
        kind: 'demo placeholder (sem upload)',
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: FleaberRadius.circularMd,
                child: Container(
                  width: 180,
                  height: 120,
                  color: const Color(0xFFDDE8EA),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined,
                      color: HubMessagesTheme.teal, size: 36),
                ),
              ),
              const SizedBox(height: 4),
              Text('14:04',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: HubMessagesTheme.textMuted)),
            ],
          ),
        ),
      ),
      (
        id: 'F05',
        title: 'Separador de data',
        kind: 'mesmo chip do chat_page',
        child: Center(child: _dateChip('Hoje')),
      ),
      (
        id: 'F06',
        title: 'Sistema commerce (tons)',
        kind: 'cores Phase 7 do chat_page',
        child: Column(
          children: [
            _systemTone(
              label: 'Sucesso — reserva aceite',
              color: HubMessagesTheme.teal,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 8),
            _systemTone(
              label: 'Aviso — prazo a expirar',
              color: const Color(0xFFB45309),
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 8),
            _systemTone(
              label: 'Erro — reserva rejeitada',
              color: const Color(0xFFB42318),
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
      ),
      (
        id: 'F07',
        title: 'Cabeçalho conversa + cartão artigo',
        kind: 'widget real FleaberChatProductHeaderCard',
        child: Column(
          children: [
            _conversationHeaderDemo(),
            const SizedBox(height: 8),
            FleaberChatProductHeaderCard(
              product: _demoProduct,
              priceLabel: '12,00 €',
              showPurchaseActions: true,
              onOpenDetails: () {},
              onBuy: () {},
              onOffer: () {},
            ),
          ],
        ),
      ),
      (
        id: 'F08',
        title: 'Oferta — outcome (widget real)',
        kind: 'PriceOfferOutcomeChatCard',
        child: Column(
          children: [
            PriceOfferOutcomeChatCard(
              payload: const {'outcome': 'accepted', 'amount': 10.0},
            ),
            const SizedBox(height: 10),
            PriceOfferOutcomeChatCard(
              payload: const {'outcome': 'rejected', 'amount': 10.0},
            ),
            const SizedBox(height: 8),
            _limit(
              'PriceOfferChatCard (pending) exige offer_id na BD — '
              'não instanciado aqui.',
            ),
          ],
        ),
      ),
      (
        id: 'F09',
        title: 'Conjunto',
        kind: 'limitação — BundleProposalChatCard faz fetch',
        child: Column(
          children: [
            FleaberChatProductHeaderCard(
              product: ProductsRow({
                'title': 'Conjunto 3 artigos',
                'price': 28.5,
                'image_urls': <String>[],
              }),
              priceLabel: '28,50 €',
              showPurchaseActions: true,
              offerLabel: 'Propor valor',
              onOpenDetails: () {},
              onBuy: () {},
              onOffer: () {},
            ),
            _limit(
              'BundleProposalChatCard real não usado sem bundle_id '
              '(evita chamada Supabase).',
            ),
          ],
        ),
      ),
      (
        id: 'F10',
        title: 'Pagamento',
        kind: 'shell visual tokens pagamento',
        child: _statusCard(
          header: 'Pagamento',
          status: 'Pago',
          tone: HubMessagesTheme.paymentBg,
          body: 'Seguro Fleaber · total 14,90 €',
          amount: '14,90 €',
        ),
      ),
      (
        id: 'F11',
        title: 'Envio / receção',
        kind: 'shell visual + CTA real FleaberPrimaryButton',
        child: _statusCard(
          header: 'Envio',
          status: 'Enviado',
          tone: HubMessagesTheme.paymentBg,
          body:
              'Etiqueta gerada. Confirma a receção quando chegares o artigo.',
          cta: 'Confirmar receção',
        ),
      ),
      (
        id: 'F12',
        title: 'Disputa',
        kind: 'cores _DisputeReplyTile',
        child: Column(
          children: [
            _statusCard(
              header: 'Disputa',
              status: 'Aberta',
              tone: HubMessagesTheme.errorBg,
              body: 'Motivo: artigo danificado.',
            ),
            const SizedBox(height: 8),
            _disputeReply(mine: true, text: 'Enviei fotos do dano.'),
            const SizedBox(height: 6),
            _disputeReply(mine: false, text: 'Vamos tratar do reembolso.'),
          ],
        ),
      ),
      (
        id: 'F13',
        title: 'Feedback',
        kind: 'shell + FleaberPrimaryButton',
        child: _statusCard(
          header: 'Avaliação',
          status: 'Pendente',
          tone: HubMessagesTheme.warningBg,
          body: 'A compra foi concluída. Deixa a tua avaliação.',
          cta: 'Deixar avaliação',
        ),
      ),
      (
        id: 'F14',
        title: 'Cancelamento',
        kind: 'cores cancel Seguro do chat_page',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HubMessagesTheme.errorBg,
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: const Color(0xFFF1B0B0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cancel_outlined,
                  color: Color(0xFF7F1D1D), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pedido de cancelamento',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF7F1D1D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      (
        id: 'F15',
        title: 'Rifa / prémio',
        kind: 'shell visual',
        child: _statusCard(
          header: 'Prémio de rifa',
          status: 'Atribuído',
          tone: HubMessagesTheme.successBg,
          body: 'Ganhaste um prémio no directo.',
          cta: 'Indicar envio',
        ),
      ),
      (
        id: 'F16',
        title: 'Notificações lida / não lida',
        kind: 'tokens lista_conversas',
        child: Column(
          children: [
            _notifRow(unread: true, title: 'Nova proposta de preço'),
            const SizedBox(height: 6),
            _notifRow(unread: false, title: 'Alguém gostou do teu artigo'),
          ],
        ),
      ),
      (
        id: 'F17',
        title: 'Empty state',
        kind: 'mesmo empty Hub',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: HubMessagesTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HubMessagesTheme.borderSoft),
          ),
          child: Column(
            children: [
              const Icon(Icons.forum_outlined,
                  size: 40, color: HubMessagesTheme.teal),
              const SizedBox(height: 12),
              Text('Ainda não tens conversas.',
                  style: HubMessagesTheme.titleMd.copyWith(fontSize: 15)),
            ],
          ),
        ),
      ),
      (
        id: 'F07b',
        title: 'Área de escrita (composer)',
        kind: 'demo layout composer 115.1',
        child: _composerDemo(),
      ),
    ];
  }

  static Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: HubMessagesTheme.label.copyWith(height: 1.4)),
      );

  static Widget _limit(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: HubMessagesTheme.label
                .copyWith(height: 1.35, color: const Color(0xFF7A4E00))),
      );

  static Widget _family({
    required String id,
    required String title,
    required String kind,
    required Widget child,
  }) {
    return Padding(
      key: ValueKey('h10_family_$id'),
      padding: const EdgeInsets.only(bottom: 22),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: HubMessagesTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HubMessagesTheme.borderSoft),
            boxShadow: HubMessagesTheme.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$id · $title',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: HubMessagesTheme.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(kind,
                    style: HubMessagesTheme.label.copyWith(fontSize: 11)),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _conversationHeaderDemo() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: HubMessagesTheme.surface,
        border: Border(bottom: BorderSide(color: HubMessagesTheme.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_back_rounded,
              color: HubMessagesTheme.teal, size: 24),
          const SizedBox(width: 6),
          const FleaberProfileAvatar(
            userId: 'demo',
            fullName: 'Ana Silva',
            radius: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ana Silva',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                Text('Lisboa',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: HubMessagesTheme.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: HubMessagesTheme.textMuted),
        ],
      ),
    );
  }

  static Widget _composerDemo() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
      decoration: const BoxDecoration(
        color: HubMessagesTheme.surface,
        border: Border(top: BorderSide(color: HubMessagesTheme.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline_rounded,
              color: FleaberColors.teal, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: HubMessagesTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: HubMessagesTheme.border),
              ),
              child: Text('Escreve uma mensagem...',
                  style: GoogleFonts.inter(
                      color: HubMessagesTheme.textMuted, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: FleaberColors.teal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  static Widget _shellDemo() {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: HubMessagesTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HubMessagesTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 132,
            decoration: const BoxDecoration(
              color: HubMessagesTheme.surface,
              border: Border(
                right: BorderSide(color: HubMessagesTheme.divider),
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mensagens',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: HubMessagesTheme.teal)),
                const SizedBox(height: 10),
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: HubMessagesTheme.selectedBg,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: HubMessagesTheme.teal, width: 3),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: HubMessagesTheme.unreadBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: HubMessagesTheme.divider,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Conversa',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HubMessagesTheme.textMuted)),
                  const Spacer(),
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: HubMessagesTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: HubMessagesTheme.border),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Escreve uma mensagem...',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: HubMessagesTheme.textMuted)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bubble({
    required String text,
    required bool sent,
    required String time,
    bool read = false,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment:
            sent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sent
                  ? HubMessagesTheme.bubbleSent
                  : HubMessagesTheme.bubbleReceived,
              borderRadius: FleaberRadius.circularMd,
              border: sent ? null : Border.all(color: HubMessagesTheme.border),
              boxShadow: sent ? null : HubMessagesTheme.cardShadow,
            ),
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                height: 1.35,
                color: sent ? Colors.white : HubMessagesTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: HubMessagesTheme.textMuted)),
              if (sent && read) ...[
                const SizedBox(width: 4),
                const Icon(Icons.done_all_rounded,
                    size: 13, color: HubMessagesTheme.teal),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Widget _dateChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: HubMessagesTheme.systemChipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: HubMessagesTheme.systemChipText,
        ),
      ),
    );
  }

  static Widget _systemTone({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HubMessagesTheme.systemChipBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statusCard({
    required String header,
    required String status,
    required Color tone,
    required String body,
    String? amount,
    String? cta,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: HubMessagesTheme.commerceBorder),
        boxShadow: HubMessagesTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(header,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: FleaberColors.teal)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(status,
                    style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body,
              style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: HubMessagesTheme.textPrimary)),
          if (amount != null) ...[
            const SizedBox(height: 8),
            Text(amount,
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ],
          if (cta != null) ...[
            const SizedBox(height: 12),
            FleaberPrimaryButton(
              label: cta,
              height: 42,
              borderRadius: 12,
              fontSize: 14,
              onPressed: () {},
            ),
          ],
        ],
      ),
    );
  }

  static Widget _disputeReply({required bool mine, required String text}) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine ? HubMessagesTheme.successBg : Colors.white,
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(color: const Color(0xFFE6D8C3)),
        ),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 13, color: HubMessagesTheme.textPrimary)),
      ),
    );
  }

  static Widget _notifRow({required bool unread, required String title}) {
    return Container(
      decoration: BoxDecoration(
        color: unread ? HubMessagesTheme.unreadBg : HubMessagesTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: unread ? HubMessagesTheme.teal : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                color: HubMessagesTheme.textPrimary,
              ),
            ),
          ),
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HubMessagesTheme.teal,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Nova',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
