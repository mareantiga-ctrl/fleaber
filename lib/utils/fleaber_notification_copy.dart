/// Copy de inbox para `user_notifications` (Mensagens → alertas).
String fleaberNotificationInboxTitle({
  required String kind,
  String? inboxTitle,
  required String likerName,
  required String productTitle,
}) {
  final k = kind.trim();
  final isPrice = k == 'price_offer' || k == 'price_offer_counter';
  final isBundle = k == 'bundle_proposal' ||
      k == 'bundle_proposal_counter' ||
      k == 'bundle_purchase_request' ||
      k == 'bundle_quote_ready' ||
      k == 'bundle_expired' ||
      k == 'bundle_quote_invalidated';
  final isHelper = k.startsWith('helper_invitation');
  final isDelta = k.startsWith('shipping_delta') ||
      k == 'ship_deadline_auto_cancelled';
  final isWallet = k == 'wallet_funds_released' ||
      k == 'wallet_payout_sent' ||
      k == 'wallet_payout_failed';
  final isCommerce = k == 'seguro_fleaber_paid' ||
      k == 'order_paid_seller' ||
      k == 'order_paid_buyer' ||
      k == 'reservation_order_shipped' ||
      k == 'chat_message' ||
      k == 'price_offer_outcome' ||
      isDelta ||
      isWallet;
  if (isPrice || isBundle || isHelper || isCommerce) {
    final fallback = isBundle
        ? (k == 'bundle_quote_ready'
            ? 'Portes confirmados — já podes pagar'
            : k == 'bundle_expired'
                ? 'Pedido de conjunto expirado'
                : k == 'bundle_quote_invalidated'
                    ? 'O teu conjunto já não está disponível'
                    : 'Novo pedido de conjunto')
        : isHelper
            ? 'Convite de ajudante'
            : isWallet
                ? (k == 'wallet_funds_released'
                    ? 'Saldo libertado'
                    : k == 'wallet_payout_sent'
                        ? 'Levantamento enviado'
                        : 'Levantamento não concluído')
                : k == 'reservation_order_shipped'
                    ? 'Encomenda enviada'
                    : k == 'shipping_delta_requested'
                        ? 'Diferença de portes'
                        : k == 'shipping_delta_paid'
                            ? 'Diferença de portes paga'
                            : k == 'shipping_delta_expired_cancelled' ||
                                    k == 'ship_deadline_auto_cancelled'
                                ? 'Encomenda cancelada'
                                : k == 'chat_message'
                                    ? 'Nova mensagem'
                                    : k == 'price_offer_outcome'
                                        ? 'Actualização de proposta'
                                        : k.contains('paid') ||
                                                k == 'seguro_fleaber_paid'
                                            ? 'Compra paga'
                                            : 'Proposta de preço';
    final t = inboxTitle?.trim();
    return (t != null && t.isNotEmpty) ? t : fallback;
  }
  return '$likerName gostou do seu artigo: $productTitle';
}
