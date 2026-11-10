/// Copy canónica — Prémio da Rifa (vencedor paga portes; incentivo a juntar compras).
abstract final class LiveRafflePrizeCopy {
  /// Card de celebração no player (subtítulo).
  static const celebrationBody =
      'O artigo é teu — pagas apenas o envio.\n'
      'Queres mais desta vendedora? Junta tudo no mesmo pacote.';

  /// Card no chat enquanto falta escolher/pagar o envio.
  static const chatCardBodyPending =
      'Este artigo é teu (Prémio da Rifa). Escolhe como o queres receber '
      '(envio ou entrega em mão). Se comprares mais nesta loja, podes pedir '
      'para ir tudo no mesmo pacote.';

  /// @Deprecated — usar [chatCardBodyPending] / [chatCardBodyHand] / [chatCardBodyPaid].
  static const chatCardBody = chatCardBodyPending;

  /// Após confirmar entrega em mão.
  static const chatCardBodyHand =
      'Prémio da Rifa — combinaste entrega em mão. '
      'Acerta o encontro com a vendedora no chat.';

  /// Após portes pagos (transportadora).
  static const chatCardBodyPaid =
      'Prémio da Rifa — envio tratado. A vendedora prepara o envio.';

  /// Pré-visualização na lista de conversas.
  static const chatListPreview = 'Prémio da Rifa · envio a teu cargo';

  /// Mensagem de sistema no chat da live (DM ao vencedor).
  static const liveDmBody =
      '🎟️ Rifa: Este artigo é teu. Pagas só o envio — '
      'e podes juntar mais peças desta vendedora no mesmo pacote.';

  /// Dica ao vendedor no chat da encomenda (antes do porte pago).
  static const sellerHint =
      'Prémio da Rifa — aguarda o vencedor pagar o envio '
      '(ou confirmar entrega em mão). Depois podes marcar como enviado.';

  /// Dica ao comprador no card de gestão (ainda premio_rifa).
  static const buyerPayHint =
      'Escolhe como queres receber o prémio. '
      'Na loja desta vendedora podes juntar mais peças ao mesmo envio.';

  /// Após entrega em mão (card gestão) — antes da vendedora confirmar.
  static const buyerHandHint =
      'Combinaste entrega em mão. Acerta o encontro. '
      'Quando tiveres o artigo, confirma a receção (podes fazer antes ou depois da vendedora).';

  /// Vendedor — após comprador escolher mão (ainda pago).
  static const sellerHandHint =
      'O vencedor escolheu entrega em mão. Combina o encontro e toca '
      '«Confirmei entrega em mão» quando entregares.';

  /// Intro do sheet de portes.
  static const shippingSheetIntro =
      'O prémio não tem custo — só o envio. '
      'Com Seguro Fleaber ficas protegido até à entrega.';

  /// Incentivo a comprar mais (mesmo vendedor, loja + live).
  static String shippingBundleHint(String sellerLabel) =>
      'Dica: se comprares mais a $sellerLabel (loja ou live), '
      'podes pedir para ir tudo no mesmo pacote e optimizas o porte.';

  /// Label de estado (encomendas / vendas) — nunca «Pago» enquanto falta envio.
  static const statusLabel = 'Prémio da Rifa · Envio a pagar';

  static const statusHandLabel = 'Prémio da Rifa · Entrega em mão';

  /// Subtítulo curto junto ao estado (quando houver espaço).
  static const statusSubtitle = 'Envio a cargo do vencedor';

  /// `orders.shipping_method` / `payment_method` legíveis.
  static const shippingMethod = 'Envio a cargo do vencedor';
  static const paymentMethod = 'Prémio da Rifa';

  static const handShippingMethod = 'Entrega em Mão (€0.00)';

  static bool isHandShippingMethod(String? method) {
    final raw = (method ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    // Normalizar acentos (mão/mao) — evita falhar copy «Artigo enviado» na mão.
    final m = raw
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
    if (m.contains('entrega em mao')) return true;
    if (m.contains('mao') && m.contains('entrega')) return true;
    // Label canónico do sheet: «Entrega em Mão (€0.00)»
    if (m.contains('0.00') && m.contains('entrega')) return true;
    return false;
  }

  static bool isPrizePaymentMethod(String? method) {
    final m = (method ?? '').trim().toLowerCase();
    return m.contains('prémio da rifa') || m.contains('premio da rifa');
  }
}
