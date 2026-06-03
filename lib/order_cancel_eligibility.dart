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
    'enviado',
    'reservado',
    'aguarda_confirmacao',
    'pendente',
    'pedido_devolucao',
    'em_devolucao',
  };
  return blocking.contains(s);
}

/// Encomenda «activa» no artigo para regras genéricas (ex.: duplicar checkout).
/// `reserva_pendente` não bloqueia terceiros — ver fluxo na ProductDetailPage.
bool orderStatusBlocksNewPurchase(String? status) {
  if (orderIsCancelled(status)) return false;
  final s = normalizeOrderStatusKey(status);
  if (s == 'reserva_pendente') return false;
  return orderStatusBlocksOtherBuyers(status);
}
