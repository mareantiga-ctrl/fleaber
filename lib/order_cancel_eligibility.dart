import '/utils/live_raffle_prize_copy.dart';

/// Lê `status` directamente do JSON da linha (evita desvios do getter).
String orderStatusRawFromData(Map<String, dynamic> data) {
  final v = data['status'];
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

/// Chave estável para comparações (minúsculas, trim, sem zero-width / BOM).
String normalizeOrderStatusKey(String? status) {
  var s = (status ?? '').trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\r\n\t]'), '');
  return s;
}

/// Comprador pode pedir cancelamento negociado até à expedição (`enviado`).
bool orderIsCancelled(String? status) {
  final s = normalizeOrderStatusKey(status);
  if (s.isEmpty) return false;
  const cancelled = {
    'cancelado',
    'cancelada',
    'cancelled',
    'canceled',
    'anulado',
    'anulada',
  };
  if (cancelled.contains(s)) return true;
  // Variantes vindas da BD (enum, texto composto, etc.)
  if (s.contains('cancelad')) return true;
  if (s.contains('anulad')) return true;
  return false;
}

bool orderAllowsBuyerCancelStatus(String? status) {
  final s = normalizeOrderStatusKey(status);
  if (s.isEmpty) return false;
  if (orderIsCancelled(status)) return false;
  const blocked = {
    'enviado',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolvida',
  };
  return !blocked.contains(s);
}

/// Reserva aceite pelo vendedor (bloqueia outros compradores / selo «Reservado»).
bool orderStatusIsOfficialReserved(String? status) =>
    normalizeOrderStatusKey(status) == 'reservado';

/// Encomenda que impede OUTRO comprador de avançar (não inclui `reserva_pendente`).
bool orderStatusBlocksOtherBuyers(String? status) {
  if (orderIsCancelled(status)) return false;
  final s = normalizeOrderStatusKey(status);
  const blocking = {
    'pago',
    'premio_rifa',
    'enviado',
    'reservado',
    'aguarda_confirmacao',
    'pendente',
    'pedido_devolucao',
    'em_devolucao',
  };
  return blocking.contains(s);
}

/// Pago (dinheiro) ou prémio da rifa — pronto a enviar / bloqueia stock.
bool orderStatusIsPaidOrPrize(String? status) {
  final s = normalizeOrderStatusKey(status);
  return s == 'pago' || s == 'premio_rifa';
}

bool orderStatusIsRafflePrize(String? status) =>
    normalizeOrderStatusKey(status) == 'premio_rifa';

/// Label humano único para badges (encomendas, vendas, chat).
///
/// Nunca devolve chaves internas (`snake_case` / códigos BD) ao utilizador.
String orderStatusDisplayPhrase(
  String? status, {
  String? shippingMethod,
  String? paymentMethod,
}) {
  final raw = (status ?? '').trim();
  if (orderIsCancelled(raw)) return 'Cancelado';
  switch (normalizeOrderStatusKey(raw)) {
    case 'reserva_pendente':
      return 'Pedido de Reserva';
    case 'reservado':
      return 'Reservado (Aguardando Pagamento)';
    case 'pendente':
      return 'Pagamento pendente';
    case 'aguarda_confirmacao':
      return 'Pagamento em Verificação';
    case 'pago':
      if (LiveRafflePrizeCopy.isPrizePaymentMethod(paymentMethod) &&
          LiveRafflePrizeCopy.isHandShippingMethod(shippingMethod)) {
        return LiveRafflePrizeCopy.statusHandLabel;
      }
      if (LiveRafflePrizeCopy.isPrizePaymentMethod(paymentMethod)) {
        return 'Prémio da Rifa · Envio tratado';
      }
      return 'Pago';
    case 'premio_rifa':
      return 'Prémio da Rifa · Envio a pagar';
    case 'enviado':
      return 'Artigo Enviado';
    case 'concluido':
      return 'Concluída';
    case 'pedido_devolucao':
      return 'Pedido de Devolução';
    case 'em_devolucao':
      return 'Em Devolução';
    case 'devolucao_entregue':
      return 'Devolução entregue';
    case 'disputa_devolucao_vendedor':
      return 'Problema com a devolução';
    case 'devolvida':
      return 'Devolvida / Reembolsada';
    default:
      // Fallback seguro: nunca mostrar `foo_bar` / enums crus na UI.
      if (raw.isEmpty) return '—';
      if (raw.contains('_') || RegExp(r'^[a-z0-9_]+$').hasMatch(raw)) {
        return 'Em processamento';
      }
      return raw;
  }
}

/// Encomenda «activa» no artigo para regras genéricas (ex.: duplicar checkout).
/// `reserva_pendente` não bloqueia terceiros — ver fluxo na ProductDetailPage.
bool orderStatusBlocksNewPurchase(String? status) {
  if (orderIsCancelled(status)) return false;
  final s = normalizeOrderStatusKey(status);
  if (s == 'reserva_pendente') return false;
  return orderStatusBlocksOtherBuyers(status);
}

/// Já consumiu stock (qty decrementada). Em multi-qty com `quantity > 0`,
/// estes estados **não** devem bloquear outros compradores (APP-SEC-005).
bool orderStatusAlreadyConsumedStock(String? status) {
  final s = normalizeOrderStatusKey(status);
  return s == 'pago' ||
      s == 'premio_rifa' ||
      s == 'enviado' ||
      s == 'concluido' ||
      s == 'pedido_devolucao' ||
      s == 'em_devolucao' ||
      s == 'devolvida';
}
