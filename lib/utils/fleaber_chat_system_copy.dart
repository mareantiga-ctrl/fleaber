/// Textos de sistema do chat em português de Portugal (H10).
///
/// Evita mostrar kinds técnicos ou «[Mensagem do sistema]» na interface.
String fleaberChatSystemKindLabel(String? kind, {String? title, String? display}) {
  final t = _stripTechnicalNoise((title ?? '').trim());
  final d = _stripTechnicalNoise((display ?? '').trim());
  if (d.isNotEmpty && !_looksTechnical(d)) return d;
  if (t.isNotEmpty && !_looksTechnical(t)) return t;

  switch ((kind ?? '').trim().toLowerCase()) {
    case 'pending_expired_buyer_notice':
      return 'O prazo do pedido de reserva expirou.';
    case 'guaranteed_expired_buyer_notice':
      return 'A reserva garantida expirou.';
    case 'reservation_guaranteed':
      return 'Reserva confirmada';
    case 'reservation_accepted':
      return 'Reserva aceite';
    case 'reservation_rejected':
      return 'Reserva recusada';
    case 'reservation_reminder':
      return 'Lembrete: falta pouco para o prazo de pagamento.';
    case 'reservation_payment_check_reminder':
      return 'Lembrete: confirma se o pagamento já chegou.';
    case 'reservation_shipping_reminder':
      return 'Lembrete: prepara o envio desta encomenda.';
    case 'reservation_cancelled_by_seller':
      return 'A reserva foi cancelada pelo vendedor.';
    case 'cancel_request':
      return 'Pedido de cancelamento enviado.';
    case 'cancel_request_outcome':
      return 'Pedido de cancelamento actualizado.';
    case 'order_dispute_opened':
      return 'Foi aberta uma disputa nesta encomenda.';
    case 'raffle_prize_awarded':
      return 'Ganhaste um prémio da rifa.';
    case 'chat_image':
      return 'Imagem';
    case 'bundle_proposal':
    case 'bundle_proposal_counter':
    case 'bundle_purchase_request':
      return 'Proposta de conjunto';
    default:
      if (t.isNotEmpty) return t;
      return 'Actualização da conversa';
  }
}

bool _looksTechnical(String s) {
  if (s.contains('H10_TESTE') || s.contains('[H10')) return true;
  if (s.contains('FLEABER_JSON') || s.contains('bundle_id')) return true;
  if (s.contains('fleaber_res:') || s.contains('[[')) return true;
  if (RegExp(r'\bseed\b', caseSensitive: false).hasMatch(s)) return true;
  if (RegExp(r'^H11\d', caseSensitive: false).hasMatch(s)) return true;
  if (RegExp(r'^\[[^\]]+\]').hasMatch(s)) return true;
  return false;
}

String _stripTechnicalNoise(String s) => s
    .replaceAll(RegExp(r'\[H10_TESTE[^\]]*\]\s*'), '')
    .replaceAll(RegExp(r'H10_TESTE_COMPLETO_\d+\s*'), '')
    .replaceAll(RegExp(r'\(seed[^)]*\)', caseSensitive: false), '')
    .replaceAll(RegExp(r'\bseed\b', caseSensitive: false), '')
    .replaceAll(RegExp(r'\[\[fleaber_res:[^\]]*\]\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'Fleaber\s*[|·]\s*sistema\s*', caseSensitive: false), '')
    .trim();

/// `last_message` / preview de inbox relativo a conjunto (pedido, proposta, etc.).
bool fleaberChatPreviewIsBundle(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  if (t.isEmpty) return false;
  return t.contains('conjunto') ||
      t.contains('bundle_purchase_request') ||
      t.contains('bundle_proposal');
}

/// Título da linha na lista H10: preferir «Conjunto…» ao 1.º artigo âncora.
String fleaberChatInboxSubject({
  required String? lastMessage,
  String? productTitle,
}) {
  final preview = fleaberChatListPreview(lastMessage);
  if (fleaberChatPreviewIsBundle(lastMessage) ||
      fleaberChatPreviewIsBundle(preview)) {
    // Já é texto humano («Pedido de compra em conjunto · N artigos»).
    if (preview.isNotEmpty && preview != 'Actualização da conversa') {
      return preview;
    }
    return 'Conjunto';
  }
  final title = (productTitle ?? '').trim();
  if (title.isNotEmpty) return title;
  return preview;
}

/// Pré-visualização legível para last_message / lista (sem JSON cru).
String fleaberChatListPreview(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Sem mensagens ainda';
  if (text.startsWith('FLEABER_JSON_V1:') ||
      (text.startsWith('{') && text.contains('"kind"'))) {
    try {
      final jsonPart = text.startsWith('FLEABER_JSON_V1:')
          ? text.substring('FLEABER_JSON_V1:'.length)
          : text;
      // ignore: avoid_dynamic_calls — decode local sem dependência de dart:convert no caller
      final kindMatch = RegExp(r'"kind"\s*:\s*"([^"]+)"').firstMatch(jsonPart);
      final titleMatch =
          RegExp(r'"title"\s*:\s*"([^"]+)"').firstMatch(jsonPart);
      final displayMatch =
          RegExp(r'"display"\s*:\s*"([^"]+)"').firstMatch(jsonPart);
      return fleaberChatSystemKindLabel(
        kindMatch?.group(1),
        title: titleMatch?.group(1),
        display: displayMatch?.group(1),
      );
    } catch (_) {
      return 'Actualização da conversa';
    }
  }
  if (text.startsWith('http://') || text.startsWith('https://')) {
    return 'Imagem';
  }
  if (text.contains('[[fleaber_res:')) {
    return text
        .replaceAll(RegExp(r'\[\[fleaber_res:[^\]]+\]\]'), '')
        .replaceAll(RegExp(r'\[H10_TESTE[^\]]*\]\s*'), '')
        .trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(2)
        .join(' · ');
  }
  return _stripTechnicalNoise(text);
}
