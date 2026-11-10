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

/// Conversa de demonstração H10 — 17 famílias num único histórico.
///
/// Dados só em memória. Sem Supabase / sem envio real.
/// Gate: `FLEABER_H10_VISUAL_CATALOG` ou debug/profile.
class HubMessagesDemoThreadPage extends StatelessWidget {
  const HubMessagesDemoThreadPage({super.key});

  static const routeName = 'H10MensagensDemo';
  static const routePath = '/h10MensagensDemo';

  static bool get isEnabled {
    const viaDefine = bool.fromEnvironment(
      'FLEABER_H10_VISUAL_CATALOG',
      defaultValue: false,
    );
    return viaDefine || kDebugMode || kProfileMode;
  }

  static ProductsRow get _demoProduct => ProductsRow({
        'id': 'demo-product-h10',
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
          child: Text('Demo H10 indisponível neste build.',
              style: HubMessagesTheme.body),
        ),
      );
    }

    // Cabeçalho = estrutura original Fleaber (nome teal + chevron).
    return Scaffold(
      backgroundColor: HubMessagesTheme.bg,
      appBar: AppBar(
        backgroundColor: HubMessagesTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: FleaberColors.teal, size: 30),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Teste visual H10 — 17 famílias',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: FleaberColors.teal,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: FleaberColors.teal, size: 22),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // Cartão artigo 115.1 (preservado)
                FleaberChatProductHeaderCard(
                  product: _demoProduct,
                  priceLabel: '12,00 €',
                  showPurchaseActions: true,
                  onOpenDetails: () {},
                  onBuy: () {},
                  onOffer: () {},
                ),
                // Strip interlocutor (original)
                _participantStrip(),
                _anchor('F01', 'Chrome / shell — esta página é o chrome H10'),
                _dateChip('Hoje'),
                _anchor('F05', 'Separador de data ↑'),
                _bubble(
                  family: 'F02',
                  text:
                      'Olá! Ainda tens a camisola M disponível? Posso reservar.',
                  sent: true,
                  time: '10:01',
                  read: true,
                ),
                _bubble(
                  family: 'F03',
                  text: 'Sim, está disponível. Diz-me a quantidade.',
                  sent: false,
                  time: '10:02',
                ),
                _anchor('F04', 'Imagem (placeholder demo)'),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                        Text('10:03',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                color: HubMessagesTheme.textMuted)),
                      ],
                    ),
                  ),
                ),
                _anchor('F06', 'Sistema commerce — tons'),
                _systemTone('Sucesso — reserva aceite', HubMessagesTheme.teal,
                    Icons.check_circle_outline),
                _systemTone('Aviso — prazo a expirar', const Color(0xFFB45309),
                    Icons.warning_amber_rounded),
                _systemTone('Erro — reserva rejeitada', const Color(0xFFB42318),
                    Icons.cancel_outlined),
                _anchor('F07', 'Reserva — cartão comercial (tokens reais)'),
                _commerceCard(
                  header: 'Reserva',
                  status: 'A aguardar',
                  tone: HubMessagesTheme.warningBg,
                  body:
                      'Pedido de reserva pendente — o vendedor tem de aceitar ou recusar.',
                  amount: '12,00 €',
                  actions: true,
                ),
                _anchor('F08', 'Oferta — PriceOfferOutcomeChatCard (real)'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: PriceOfferOutcomeChatCard(
                    payload: const {'outcome': 'accepted', 'amount': 10.0},
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: PriceOfferOutcomeChatCard(
                    payload: const {'outcome': 'rejected', 'amount': 10.0},
                  ),
                ),
                _limit(
                  'F08 pending (PriceOfferChatCard) exige offer_id na BD — pendente.',
                ),
                _anchor('F09', 'Conjunto — header real; Bundle* fetch pendente'),
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
                  'BundleProposalChatCard real não instanciado (fetch BD).',
                ),
                _anchor('F10', 'Pagamento'),
                _commerceCard(
                  header: 'Pagamento',
                  status: 'Pago',
                  tone: HubMessagesTheme.paymentBg,
                  body: 'Seguro Fleaber · total pago 14,90 €',
                  amount: '14,90 €',
                ),
                _anchor('F11', 'Envio / receção'),
                _commerceCard(
                  header: 'Envio',
                  status: 'Enviado',
                  tone: HubMessagesTheme.paymentBg,
                  body: 'Etiqueta gerada. Confirma a receção.',
                  cta: 'Confirmar receção',
                ),
                _anchor('F12', 'Disputa'),
                _commerceCard(
                  header: 'Disputa',
                  status: 'Aberta',
                  tone: HubMessagesTheme.errorBg,
                  body: 'Motivo: artigo danificado.',
                ),
                _dispute(mine: true, text: 'Enviei fotos do dano.'),
                _dispute(mine: false, text: 'Vamos tratar do reembolso.'),
                _anchor('F13', 'Feedback'),
                _commerceCard(
                  header: 'Avaliação',
                  status: 'Pendente',
                  tone: HubMessagesTheme.warningBg,
                  body: 'Deixa a tua avaliação ao vendedor.',
                  cta: 'Deixar avaliação',
                ),
                _anchor('F14', 'Cancelamento'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                _anchor('F15', 'Rifa / prémio'),
                _commerceCard(
                  header: 'Prémio de rifa',
                  status: 'Atribuído',
                  tone: HubMessagesTheme.successBg,
                  body: 'Ganhaste um prémio no directo.',
                  cta: 'Indicar envio',
                ),
                _anchor('F16', 'Notificações (amostra inline)'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _notif(true, 'Nova proposta de preço'),
                      const SizedBox(height: 6),
                      _notif(false, 'Alguém gostou do teu artigo'),
                    ],
                  ),
                ),
                _anchor('F17', 'Empty (referência)'),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: HubMessagesTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: HubMessagesTheme.borderSoft),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.forum_outlined,
                            size: 36, color: HubMessagesTheme.teal),
                        const SizedBox(height: 8),
                        Text('Ainda não tens conversas.',
                            style: HubMessagesTheme.titleMd
                                .copyWith(fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Fim da conversa demo · dados só em memória',
                    style: HubMessagesTheme.label,
                  ),
                ),
              ],
            ),
          ),
          // Composer visual (não envia)
          Container(
            decoration: const BoxDecoration(
              color: HubMessagesTheme.surface,
              border: Border(top: BorderSide(color: HubMessagesTheme.divider)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline_rounded,
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
                      child: Text(
                        'Demo — envio desactivado (sem BD)',
                        style: GoogleFonts.inter(
                            color: HubMessagesTheme.textMuted, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB7C1C8),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _participantStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Material(
        color: const Color(0xFFFAFBFC),
        borderRadius: FleaberRadius.circularMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: const Color(0xFFDDE2E7), width: 0.5),
          ),
          child: Row(
            children: [
              const FleaberProfileAvatar(
                userId: 'demo-seller',
                fullName: 'Ana Silva',
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ana Silva',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text('Lisboa',
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: const Color(0xFF57636C))),
                    Text('Visto pela última vez · há 2 h',
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: const Color(0xFF57636C))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _anchor(String id, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        '$id · $label',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: FleaberColors.teal,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static Widget _limit(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(t,
            style: HubMessagesTheme.label
                .copyWith(color: const Color(0xFF7A4E00), height: 1.35)),
      );

  static Widget _dateChip(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: HubMessagesTheme.systemChipBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: HubMessagesTheme.systemChipText)),
        ),
      ),
    );
  }

  static Widget _bubble({
    required String family,
    required String text,
    required bool sent,
    required String time,
    bool read = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment:
            sent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(family,
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: HubMessagesTheme.teal)),
          const SizedBox(height: 2),
          Align(
            alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sent
                      ? HubMessagesTheme.bubbleSent
                      : HubMessagesTheme.bubbleReceived,
                  borderRadius: FleaberRadius.circularMd,
                  border: sent
                      ? null
                      : Border.all(color: HubMessagesTheme.border),
                  boxShadow: sent ? null : HubMessagesTheme.cardShadow,
                ),
                child: Text(text,
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        height: 1.35,
                        color: sent
                            ? Colors.white
                            : HubMessagesTheme.textPrimary)),
              ),
            ),
          ),
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

  static Widget _systemTone(String label, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
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
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _commerceCard({
    required String header,
    required String status,
    required Color tone,
    required String body,
    String? amount,
    bool actions = false,
    String? cta,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
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
                        fontWeight: FontWeight.w600)),
                if (amount != null) ...[
                  const SizedBox(height: 8),
                  Text(amount,
                      style: GoogleFonts.inter(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
                if (actions) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      FleaberPrimaryButton(
                        label: 'Aceitar',
                        height: 42,
                        borderRadius: 12,
                        fontSize: 14,
                        onPressed: () {},
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FleaberColors.teal,
                          side: const BorderSide(color: FleaberColors.teal),
                          minimumSize: const Size(0, 42),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ],
                  ),
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
          ),
        ),
      ),
    );
  }

  static Widget _dispute({required bool mine, required String text}) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

  static Widget _notif(bool unread, String title) {
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
      child: Text(title,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          )),
    );
  }
}
