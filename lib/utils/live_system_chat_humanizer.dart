import 'package:flutter/material.dart';

/// Visibilidade da mensagem de sistema no chat público.
enum LiveSystemChatVisibility {
  /// Frase social — aparece no chat público (comprador + vendedora).
  publicSocial,

  /// Operacional — não deve parecer chat público (saco, painel, snackbar).
  backoffice,
}

/// Tipo de evento reconhecido (UX only — não altera emissores).
enum LiveSystemChatEventKind {
  reserve,
  reserveQueue,
  bagAdd,
  purchase,
  reserveAcceptedPublic,
  priceDefined,
  lastUnit,
  soldOut,
  cancel,
  tip,
  raffle,
  backofficeOverStock,
  backofficeRejected,
  backofficeSellerAccept,
  unknown,
}

enum LiveSystemChatEmphasis { normal, social, fomo }

/// Tom visual alinhado com [LivePublicChatSystemTone] no widget de chat.
enum LiveSystemChatTone { success, pending, cancel, neutral }

class LiveSystemChatParsed {
  const LiveSystemChatParsed({
    required this.kind,
    required this.visibility,
    required this.tone,
    required this.line,
    this.personName,
    this.itemLabel,
    this.priceLabel,
    this.icon,
    this.emphasis = LiveSystemChatEmphasis.normal,
    this.highlightDuration,
    this.snackbarLine,
  });

  final LiveSystemChatEventKind kind;
  final LiveSystemChatVisibility visibility;
  final LiveSystemChatTone tone;
  final String line;
  final String? personName;
  final String? itemLabel;
  final String? priceLabel;
  final IconData? icon;
  final LiveSystemChatEmphasis emphasis;
  final Duration? highlightDuration;
  final String? snackbarLine;

  bool get showInPublicChat => visibility == LiveSystemChatVisibility.publicSocial;
}

/// Chave para evitar duas linhas sociais para o mesmo evento (ex. compra).
String? liveSystemChatSocialDedupKey(LiveSystemChatParsed parsed) {
  final name = parsed.personName?.trim().toLowerCase() ?? '';
  final item = parsed.itemLabel?.trim().toLowerCase() ?? '';
  switch (parsed.kind) {
    case LiveSystemChatEventKind.purchase:
      if (name.isEmpty && item.isEmpty) return null;
      return 'purchase|$name|$item';
    case LiveSystemChatEventKind.reserveAcceptedPublic:
      if (name.isEmpty && item.isEmpty) return null;
      return 'accepted|$name|$item';
    case LiveSystemChatEventKind.bagAdd:
      if (name.isEmpty && item.isEmpty) return null;
      return 'bag|$name|$item';
    case LiveSystemChatEventKind.raffle:
      final line = parsed.line.trim().toLowerCase();
      if (line.isEmpty) return null;
      return 'raffle|$line';
    default:
      return null;
  }
}

/// Ícones uniformes do chat sistema (V2.1.1).
abstract final class LiveSystemChatIcons {
  static const IconData reserve = Icons.shopping_bag_outlined;
  static const IconData purchase = Icons.shopping_cart_checkout_outlined;
  static const IconData tip = Icons.card_giftcard_outlined;
  static const IconData lastUnit = Icons.local_fire_department_outlined;
  static const IconData price = Icons.sell_outlined;
  static const IconData soldOut = Icons.block_outlined;
  static const IconData raffle = Icons.confirmation_number_outlined;
}

/// Parser/humanizer único para mensagens de sistema do chat live (A2 UX).
class LiveSystemChatHumanizer {
  LiveSystemChatHumanizer._();

  static LiveSystemChatParsed parse(
    String raw, {
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
    bool forCurrentBuyerPrivate = false,
  }) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      return const LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.unknown,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.neutral,
        line: '',
      );
    }

    String normLabel(String label) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return trimmed;
      final mapped = normalizeItemLabel?.call(trimmed);
      return (mapped != null && mapped.trim().isNotEmpty)
          ? mapped.trim()
          : trimmed;
    }

    String buyerName(String raw) {
      final trimmed = raw.trim();
      final resolved = resolveBuyerName?.call(trimmed);
      if (resolved != null && resolved.trim().isNotEmpty) {
        return resolved.trim();
      }
      return trimmed.isEmpty ? '' : trimmed;
    }

    // --- Ocultar recusas técnicas (sem valor no histórico social) ---
    if (RegExp(r'rejeitou\s+reserva', caseSensitive: false).hasMatch(text) ||
        RegExp(r'vendedora\s+rejeitou', caseSensitive: false).hasMatch(text)) {
      return const LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.backofficeRejected,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.cancel,
        line: '',
      );
    }

    // --- Backoffice: pedido acima do stock ---
    final pedidoQty = RegExp(
      r'📋\s*Pedido de (\d+)\s*un\.(?:\s*·\s*(.+?))?\s*[—-]\s*só\s*(\d+)\s*dispon',
      caseSensitive: false,
    ).firstMatch(text);
    if (pedidoQty != null) {
      final req = pedidoQty.group(1) ?? '1';
      final avail = pedidoQty.group(3) ?? '0';
      final rawLabel = (pedidoQty.group(2) ?? '').trim();
      final label = rawLabel.isEmpty ? null : normLabel(rawLabel);
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.backofficeOverStock,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.pending,
        line: '',
        itemLabel: label,
        snackbarLine: 'Pediste $req — só há $avail disponível',
      );
    }

    // --- Backoffice: recusa vendedora ---
    if (RegExp(r'recusaste\s+o\s+pedido', caseSensitive: false).hasMatch(text) ||
        (RegExp(r'acima\s+do\s+stock', caseSensitive: false).hasMatch(text) &&
            RegExp(r'pedido', caseSensitive: false).hasMatch(text))) {
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.backofficeRejected,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.cancel,
        line: '',
        snackbarLine: 'Pedido recusado — stock insuficiente',
      );
    }

    // --- Backoffice: aceite vendedora (painel operacional) ---
    final sellerAccept = RegExp(
      r'✅\s*Aceitaste vender (\d+)\s*un\.(?:\s*·\s*(.+?))?\s*—',
      caseSensitive: false,
    ).firstMatch(text);
    if (sellerAccept != null) {
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.backofficeSellerAccept,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.success,
        line: '',
      );
    }

    // --- Reserva aceite (formato painel: Nome — reserva aceite · Ref · Prazo) ---
    final acceptNamed = RegExp(
      r'🔒\s*(.+?)\s*—\s*reserva aceite\s*·\s*(.+?)(?:\s*·\s*Prazo:\s*\d+\s*d)?\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (acceptNamed != null) {
      final name = buyerName(acceptNamed.group(1) ?? '');
      final label = normLabel(acceptNamed.group(2) ?? '');
      final displayName = name.isEmpty ? '' : _short(name, 18);
      if (forCurrentBuyerPrivate) {
        final privateLine = label.isEmpty
            ? 'Ficaste com o artigo — 5 dias para pagar'
            : 'Ficaste com $label — 5 dias para pagar';
        return LiveSystemChatParsed(
          kind: LiveSystemChatEventKind.reserveAcceptedPublic,
          visibility: LiveSystemChatVisibility.publicSocial,
          tone: LiveSystemChatTone.success,
          line: privateLine,
          personName: displayName.isEmpty ? null : displayName,
          itemLabel: label.isEmpty ? null : label,
          icon: LiveSystemChatIcons.reserve,
          emphasis: LiveSystemChatEmphasis.social,
        );
      }
      final socialLine = displayName.isEmpty
          ? (label.isEmpty ? 'Reserva aceite' : '$label — reservado')
          : (label.isEmpty
              ? '$displayName ficou com o artigo'
              : '$displayName ficou com $label');
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.reserveAcceptedPublic,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: _short(socialLine, 64),
        personName: displayName.isEmpty ? null : displayName,
        itemLabel: label.isEmpty ? null : label,
        icon: LiveSystemChatIcons.reserve,
        emphasis: LiveSystemChatEmphasis.social,
      );
    }

    // --- Reserva aceite broadcast SQL (social público; prazo só no overlay comprador) ---
    final acceptBroadcast = RegExp(
      r'🔒\s*Reserva aceite\s*—\s*(?:(\d+)\s*un\.\s*·\s*)?(.+?)\s*·\s*(.+?)(?:\s+tem\s+\d+\s+dias|\s*$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (acceptBroadcast != null) {
      final label = normLabel(acceptBroadcast.group(2) ?? '');
      final name = buyerName(acceptBroadcast.group(3) ?? '');
      if (forCurrentBuyerPrivate) {
        final privateLine = label.isEmpty
            ? 'Ficaste com o artigo — 5 dias para pagar'
            : 'Ficaste com $label — 5 dias para pagar';
        return LiveSystemChatParsed(
          kind: LiveSystemChatEventKind.reserveAcceptedPublic,
          visibility: LiveSystemChatVisibility.publicSocial,
          tone: LiveSystemChatTone.success,
          line: privateLine,
          personName: name.isEmpty ? null : name,
          itemLabel: label.isEmpty ? null : label,
          icon: LiveSystemChatIcons.reserve,
          emphasis: LiveSystemChatEmphasis.social,
        );
      }
      final socialLine = name.isEmpty
          ? (label.isEmpty ? 'Reserva aceite' : '$label — reservado')
          : (label.isEmpty ? '$name ficou com o artigo' : '$name ficou com $label');
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.reserveAcceptedPublic,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: _short(socialLine, 64),
        personName: name.isEmpty ? null : name,
        itemLabel: label.isEmpty ? null : label,
        icon: LiveSystemChatIcons.reserve,
        emphasis: LiveSystemChatEmphasis.social,
      );
    }

    // --- Preço definido ---
    final priceDef = RegExp(
      r'💶\s*Preço definido\s*·\s*(.+?)\s*·\s*([\d.,]+)\s*€',
      caseSensitive: false,
    ).firstMatch(text);
    if (priceDef != null) {
      final label = normLabel(priceDef.group(1) ?? '');
      final price = '${priceDef.group(2)!.trim()} €';
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.priceDefined,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: label.isEmpty ? price : '$label — $price',
        itemLabel: label.isEmpty ? null : label,
        priceLabel: price,
        icon: LiveSystemChatIcons.price,
        emphasis: LiveSystemChatEmphasis.normal,
      );
    }

    // --- Última unidade ---
    final lastUnit = RegExp(
      r'🔥\s*(?:Ultima|Última)\s+unidade(?:\s+disponível!?|\s*—\s*(.+))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (lastUnit != null) {
      final rawRef = (lastUnit.group(1) ?? '').trim();
      final label = rawRef.isEmpty ? 'este artigo' : normLabel(rawRef);
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.lastUnit,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: 'Última unidade de $label',
        itemLabel: label,
        icon: LiveSystemChatIcons.lastUnit,
        emphasis: LiveSystemChatEmphasis.fomo,
        highlightDuration: const Duration(seconds: 5),
      );
    }

    // --- Esgotado ---
    final soldOut = RegExp(
      r'🔴\s*(.+?)\s+esgotado',
      caseSensitive: false,
    ).firstMatch(text);
    if (soldOut != null) {
      final label = normLabel(soldOut.group(1) ?? '');
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.soldOut,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.cancel,
        line: label.isEmpty ? 'Artigo esgotou' : '$label esgotou',
        itemLabel: label.isEmpty ? null : label,
        icon: LiveSystemChatIcons.soldOut,
        emphasis: LiveSystemChatEmphasis.fomo,
        highlightDuration: const Duration(seconds: 3),
      );
    }

    // --- Rifa da Live (broadcast SQL: 🎟️ Rifa: …) ---
    final raffleMsg = RegExp(
      r'^🎟️\s*Rifa:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (raffleMsg != null) {
      final body = (raffleMsg.group(1) ?? '').trim();
      if (body.isEmpty) {
        return const LiveSystemChatParsed(
          kind: LiveSystemChatEventKind.raffle,
          visibility: LiveSystemChatVisibility.backoffice,
          tone: LiveSystemChatTone.neutral,
          line: '',
        );
      }
      final nameMatch = RegExp(
        r'^(.+?)\s+ganhou\b',
        caseSensitive: false,
      ).firstMatch(body);
      final name = buyerName(nameMatch?.group(1) ?? '');
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.raffle,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: _short(body, 64),
        personName: name.isEmpty ? null : _short(name, 18),
        icon: LiveSystemChatIcons.raffle,
        emphasis: LiveSystemChatEmphasis.social,
      );
    }

    // --- Adicionou ao saco / carrinho ---
    final bagAdd = RegExp(
      r'^(?:🛍️\s*)?(.*?)\s+adicionou\s+(.+?)\s+ao\s+saco\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (bagAdd != null) {
      final name = buyerName(bagAdd.group(1) ?? '');
      final label = normLabel((bagAdd.group(2) ?? '').trim());
      final displayName = name.isEmpty ? 'Alguém' : _short(name, 18);
      final line = label.isEmpty
          ? '$displayName mostrou interesse neste artigo'
          : '$displayName adicionou ${_short(label, 28)} ao carrinho';
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.bagAdd,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.pending,
        line: line,
        personName: name.isEmpty ? null : displayName,
        itemLabel: label.isEmpty ? null : label,
        icon: LiveSystemChatIcons.reserve,
        emphasis: LiveSystemChatEmphasis.normal,
      );
    }

    // --- Reserva criada ---
    final reserve = RegExp(
      r'^(?:🛍️\s*)?(.*?)\s+reservou\s+(.*)$',
    ).firstMatch(text);
    if (reserve != null) {
      final name = buyerName(reserve.group(1) ?? '');
      final rawItem = (reserve.group(2) ?? '')
          .replaceAll('para o saco da live', '')
          .trim();
      final label = normLabel(rawItem);
      final displayName = name.isEmpty ? 'Alguém' : _short(name, 18);
      if (label.isEmpty ||
          label.toLowerCase().contains('saco') ||
          rawItem.toLowerCase().contains('saco')) {
        return LiveSystemChatParsed(
          kind: LiveSystemChatEventKind.reserveQueue,
          visibility: LiveSystemChatVisibility.publicSocial,
          tone: LiveSystemChatTone.pending,
          line: '$displayName entrou na fila deste artigo',
          personName: name.isEmpty ? null : displayName,
          icon: LiveSystemChatIcons.reserve,
          emphasis: LiveSystemChatEmphasis.normal,
        );
      }
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.reserve,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.pending,
        line: '$displayName reservou ${_short(label, 28)}',
        personName: name.isEmpty ? null : displayName,
        itemLabel: label,
        icon: LiveSystemChatIcons.reserve,
        emphasis: LiveSystemChatEmphasis.normal,
      );
    }

    // --- Compra (ignora preço/ref no texto — detalhe fica em «Ver pagamento») ---
    final bought = RegExp(
      r'^(?:(?:✅|💳)\s*)?(.*?)\s+comprou\s+(.*)$',
    ).firstMatch(text);
    if (bought != null) {
      final name = buyerName(bought.group(1) ?? '');
      var rawItem = (bought.group(2) ?? '').trim();
      rawItem = rawItem.replaceAll(
        RegExp(r'\s*\([\d.,]+\s*€\)\s*$'),
        '',
      );
      final label = normLabel(rawItem);
      final displayName = name.isEmpty ? 'Alguém' : _short(name, 18);
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.purchase,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.success,
        line: label.isEmpty
            ? '$displayName comprou'
            : '$displayName comprou ${_short(label, 28)}',
        personName: name.isEmpty ? null : displayName,
        itemLabel: label.isEmpty ? null : label,
        icon: LiveSystemChatIcons.purchase,
        emphasis: LiveSystemChatEmphasis.social,
        highlightDuration: const Duration(milliseconds: 2500),
      );
    }

    // --- Cancelamento ---
    final cancelNamed = RegExp(
      r'^(?:↩\s*)?(.*?)\s+cancelou\s+(?:a\s+)?reserva(?:\s+de\s+|\s*·\s*)(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (cancelNamed != null) {
      final name = buyerName(cancelNamed.group(1) ?? '');
      final label = normLabel(cancelNamed.group(2) ?? '');
      final displayName = name.isEmpty ? '' : _short(name, 18);
      final line = displayName.isNotEmpty && label.isNotEmpty
          ? '$displayName cancelou a reserva de ${_short(label, 24)}'
          : (label.isNotEmpty
              ? 'Reserva de ${_short(label, 28)} cancelada'
              : 'Reserva cancelada');
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.cancel,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.cancel,
        line: line,
        personName: displayName.isEmpty ? null : displayName,
        itemLabel: label.isEmpty ? null : label,
        emphasis: LiveSystemChatEmphasis.normal,
      );
    }

    final cancelBuyer = RegExp(
      r'↩\s*Reserva cancelada(?:\s+pelo comprador)?(?:\s*·\s*(.+))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (cancelBuyer != null || RegExp(r'cancel', caseSensitive: false).hasMatch(text)) {
      final rawLabel = (cancelBuyer?.group(1) ?? '').trim();
      final label = rawLabel.isEmpty ? null : normLabel(rawLabel);
      final line = label != null && label.isNotEmpty
          ? 'Reserva de ${_short(label, 28)} cancelada'
          : 'Reserva cancelada';
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.cancel,
        visibility: LiveSystemChatVisibility.publicSocial,
        tone: LiveSystemChatTone.cancel,
        line: line,
        itemLabel: label,
        emphasis: LiveSystemChatEmphasis.normal,
      );
    }

    // --- Backoffice heurístico ---
    if (_isBackofficeHeuristic(text)) {
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.unknown,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.neutral,
        line: '',
      );
    }

    // --- Aceite genérico residual (sem prazo nem refs no chat público) ---
    if (RegExp(r'(?:reserva\s+)?aceite|aceitou', caseSensitive: false)
        .hasMatch(text)) {
      if (RegExp(r'prazo:\s*\d+\s*d', caseSensitive: false).hasMatch(text) ||
          RegExp(r'\d+\s*dias', caseSensitive: false).hasMatch(text)) {
        return const LiveSystemChatParsed(
          kind: LiveSystemChatEventKind.reserveAcceptedPublic,
          visibility: LiveSystemChatVisibility.backoffice,
          tone: LiveSystemChatTone.success,
          line: '',
        );
      }
      return const LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.reserveAcceptedPublic,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.success,
        line: '',
      );
    }

    if (RegExp(r'pedido', caseSensitive: false).hasMatch(text)) {
      return LiveSystemChatParsed(
        kind: LiveSystemChatEventKind.backofficeOverStock,
        visibility: LiveSystemChatVisibility.backoffice,
        tone: LiveSystemChatTone.pending,
        line: '',
      );
    }

    return LiveSystemChatParsed(
      kind: LiveSystemChatEventKind.unknown,
      visibility: LiveSystemChatVisibility.publicSocial,
      tone: LiveSystemChatTone.neutral,
      line: _short(_clean(text, 56), 60),
      emphasis: LiveSystemChatEmphasis.normal,
    );
  }

  static LiveSystemChatParsed parseTip({
    required double amountEur,
    String? contributorName,
    required String amountLabel,
  }) {
    final name = contributorName?.trim() ?? '';
    final line = name.isNotEmpty
        ? '$name apoiou a live com $amountLabel'
        : 'Alguém apoiou a live com $amountLabel';
    return LiveSystemChatParsed(
      kind: LiveSystemChatEventKind.tip,
      visibility: LiveSystemChatVisibility.publicSocial,
      tone: LiveSystemChatTone.success,
      line: line,
      personName: name.isEmpty ? null : name,
      icon: LiveSystemChatIcons.tip,
      emphasis: LiveSystemChatEmphasis.social,
      highlightDuration: const Duration(milliseconds: 3000),
    );
  }

  static bool _isBackofficeHeuristic(String text) {
    final t = text.toLowerCase();
    return t.contains('aguarda confirmação') ||
        t.contains('aguarda confirmacao') ||
        t.contains('dias para pagar') ||
        t.contains('tem 5 dias') ||
        t.contains('prazo:') ||
        t.contains('rejeitou') ||
        t.contains('recusaste') ||
        t.contains('fila de espera') ||
        t.contains('qty_confirm') ||
        t.contains('acima do stock');
  }

  static String _short(String value, int max) {
    final t = value.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max).trim()}…';
  }

  static String _clean(String value, int max) {
    final cleaned = value
        .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}'), '')
        .replaceAll(RegExp(r'[🔒🔴✅📋🛍️💶🔥↩❌📦]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _short(cleaned, max);
  }
}
