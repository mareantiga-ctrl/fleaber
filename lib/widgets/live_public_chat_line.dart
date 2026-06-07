import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/widgets/profile_avatar.dart';

/// Linha de chat público no directo (com destaque opcional para a vendedora).
/// Usada no modo privado — manter estilo compacto existente.
class LivePublicChatLine extends StatelessWidget {
  const LivePublicChatLine({
    super.key,
    required this.label,
    required this.text,
    this.isSeller = false,
    this.compact = false,
    this.onDarkOverlay = true,
  });

  final String label;
  final String text;
  final bool isSeller;
  final bool compact;
  final bool onDarkOverlay;

  static const List<Shadow> kLegibilityShadow = [
    Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
    Shadow(color: Colors.black54, blurRadius: 3),
  ];

  @override
  Widget build(BuildContext context) {
    final nameColor = isSeller
        ? const Color(0xFFFFD54F)
        : onDarkOverlay
            ? const Color(0xFF4DD0E1)
            : const Color(0xFF007782);
    final bodyColor = isSeller
        ? const Color(0xFF69F0AE)
        : onDarkOverlay
            ? Colors.white
            : const Color(0xFF101518);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 5 : 7),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(
                color: nameColor,
                fontWeight: isSeller ? FontWeight.w900 : FontWeight.w700,
                fontSize: compact ? (isSeller ? 12 : 10.5) : (isSeller ? 13 : 11),
                shadows: onDarkOverlay ? kLegibilityShadow : null,
              ),
            ),
            TextSpan(
              text: text,
              style: GoogleFonts.inter(
                color: bodyColor,
                fontSize: compact ? (isSeller ? 13 : 11.5) : (isSeller ? 14 : 12),
                fontWeight: isSeller ? FontWeight.w800 : FontWeight.w500,
                height: 1.25,
                shadows: onDarkOverlay ? kLegibilityShadow : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mensagem humana no chat público — texto flutuante, sem balão (estilo live).
class LivePublicChatHumanRow extends StatelessWidget {
  const LivePublicChatHumanRow({
    super.key,
    required this.label,
    required this.text,
    this.userId,
    this.photoUrl,
    this.isSeller = false,
  });

  final String label;
  final String text;
  final String? userId;
  final String? photoUrl;
  final bool isSeller;

  @override
  Widget build(BuildContext context) {
    final nameColor = isSeller
        ? const Color(0xFFFFD54F)
        : const Color(0xFF80DEEA);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FleaberProfileAvatar(
            userId: userId,
            fullName: label,
            photoUrl: photoUrl,
            radius: 11,
            backgroundColor: const Color(0xFF00A3AD).withValues(alpha: 0.28),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: nameColor.withValues(alpha: 0.92),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    shadows: LivePublicChatLine.kLegibilityShadow,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    shadows: LivePublicChatLine.kLegibilityShadow,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tom visual de eventos de sistema no chat público.
enum LivePublicChatSystemTone { success, pending, cancel, neutral }

/// Notificação leve de sistema no chat público (evento compacto, sem cartão).
class LivePublicChatSystemLine extends StatelessWidget {
  const LivePublicChatSystemLine({
    super.key,
    required this.tone,
    required this.line,
  });

  final LivePublicChatSystemTone tone;
  final String line;

  factory LivePublicChatSystemLine.fromBody(
    String raw, {
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
  }) {
    final parsed = compactFromBody(
      raw,
      normalizeItemLabel: normalizeItemLabel,
      resolveBuyerName: resolveBuyerName,
    );
    return LivePublicChatSystemLine(tone: parsed.tone, line: parsed.line);
  }

  static ({LivePublicChatSystemTone tone, String line}) compactFromBody(
    String raw, {
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
  }) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      return (tone: LivePublicChatSystemTone.neutral, line: '');
    }

    String normLabel(String label) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return trimmed;
      final mapped = normalizeItemLabel?.call(trimmed);
      return (mapped != null && mapped.trim().isNotEmpty) ? mapped.trim() : trimmed;
    }

    String buyerName(String raw) {
      final trimmed = raw.trim();
      final resolved = resolveBuyerName?.call(trimmed);
      if (resolved != null && resolved.trim().isNotEmpty) {
        return resolved.trim();
      }
      return trimmed.isEmpty ? 'Utilizador' : trimmed;
    }

    final acceptBroadcast = RegExp(
      r'🔒\s*Reserva aceite\s*—\s*(?:(\d+)\s*un\.\s*·\s*)?(.+?)\s*·',
      caseSensitive: false,
    ).firstMatch(text);
    if (acceptBroadcast != null) {
      final qty = acceptBroadcast.group(1)?.trim();
      final label = _short(normLabel(acceptBroadcast.group(2) ?? ''), 22);
      if (qty != null && qty.isNotEmpty) {
        return (
          tone: LivePublicChatSystemTone.success,
          line: _line('✅ Reserva aceite', '$qty un.', label),
        );
      }
      return (
        tone: LivePublicChatSystemTone.success,
        line: _line('✅ Reserva aceite', label),
      );
    }

    final soldOut = RegExp(
      r'🔴\s*(.+?)\s+esgotado',
      caseSensitive: false,
    ).firstMatch(text);
    if (soldOut != null) {
      final label = _short(normLabel(soldOut.group(1) ?? ''), 22);
      return (
        tone: LivePublicChatSystemTone.cancel,
        line: _line('🔴 Esgotado', label),
      );
    }

    final sellerAccept = RegExp(
      r'✅\s*Aceitaste vender (\d+)\s*un\.(?:\s*·\s*(.+?))?\s*—',
      caseSensitive: false,
    ).firstMatch(text);
    if (sellerAccept != null) {
      final qty = sellerAccept.group(1) ?? '1';
      final rawLabel = (sellerAccept.group(2) ?? '').trim();
      final label =
          rawLabel.isEmpty ? null : _short(normLabel(rawLabel), 22);
      return (
        tone: LivePublicChatSystemTone.success,
        line: label == null
            ? _line('✅ Reserva aceite', '$qty un.')
            : _line('✅ Reserva aceite', '$qty un.', label),
      );
    }

    final pedidoQty = RegExp(
      r'📋\s*Pedido de (\d+)\s*un\.(?:\s*·\s*(.+?))?\s*—',
      caseSensitive: false,
    ).firstMatch(text);
    if (pedidoQty != null) {
      final qty = pedidoQty.group(1) ?? '1';
      final rawLabel = (pedidoQty.group(2) ?? '').trim();
      final label =
          rawLabel.isEmpty ? null : _short(normLabel(rawLabel), 22);
      return (
        tone: LivePublicChatSystemTone.pending,
        line: label == null
            ? _line('📦 Pedido criado', '$qty un.')
            : _line('📦 Pedido criado', '$qty un.', label),
      );
    }

    final reserve = RegExp(
      r'^(?:🛍️\s*)?(.*?)\s+reservou\s+(.*)$',
    ).firstMatch(text);
    if (reserve != null) {
      final name = _short(buyerName(reserve.group(1) ?? ''), 14);
      final label = _short(
        normLabel(
          (reserve.group(2) ?? '').replaceAll('para o saco da live', '').trim(),
        ),
        22,
      );
      return (
        tone: LivePublicChatSystemTone.pending,
        line: label.isEmpty
            ? _line('🛍️ Reserva', name)
            : _line('🛍️ Reserva', label, name),
      );
    }

    final bought = RegExp(r'^(?:✅\s*)?(.*?)\s+comprou\s+(.*)$').firstMatch(text);
    if (bought != null) {
      final name = _short(buyerName(bought.group(1) ?? ''), 14);
      final label = _short(normLabel((bought.group(2) ?? '').trim()), 22);
      return (
        tone: LivePublicChatSystemTone.success,
        line: label.isEmpty
            ? _line('✅ Compra', name)
            : _line('✅ Compra', label, name),
      );
    }

    final accept = RegExp(
      r'(?:reserva\s+)?aceite|aceitou',
      caseSensitive: false,
    ).hasMatch(text);
    if (accept) {
      return (
        tone: LivePublicChatSystemTone.success,
        line: _line('✅ Reserva aceite', _clean(text, 28)),
      );
    }

    final cancel = RegExp(
      r'cancel',
      caseSensitive: false,
    ).hasMatch(text);
    if (cancel) {
      return (
        tone: LivePublicChatSystemTone.cancel,
        line: _line('↩ Reserva cancelada', _clean(text, 28)),
      );
    }

    final order = RegExp(r'pedido', caseSensitive: false).hasMatch(text);
    if (order) {
      return (
        tone: LivePublicChatSystemTone.pending,
        line: _line('📦 Pedido criado', _clean(text, 28)),
      );
    }

    return (
      tone: LivePublicChatSystemTone.neutral,
      line: _short(_clean(text, 48), 52),
    );
  }

  /// Compat: testes/legado que ainda usam headline + detail.
  static ({String headline, String detail}) partsFromBody(String raw) {
    final parsed = compactFromBody(raw);
    if (parsed.line.isEmpty) {
      return (headline: '', detail: '');
    }
    final sep = parsed.line.indexOf(' · ');
    if (sep < 0) {
      return (headline: parsed.line, detail: '');
    }
    return (
      headline: parsed.line.substring(0, sep),
      detail: parsed.line.substring(sep + 3),
    );
  }

  static String _line(String lead, [String? a, String? b]) {
    final parts = <String>[
      lead,
      if (a != null && a.isNotEmpty) a,
      if (b != null && b.isNotEmpty) b,
    ];
    return _short(parts.join(' · '), 52);
  }

  static String _short(String value, int max) {
    final t = value.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max).trim()}…';
  }

  static String _clean(String value, int max) {
    final cleaned = value
        .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}'), '')
        .replaceAll(
          RegExp(r'(?:reserva\s+)?aceite|aceitou', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _short(cleaned, max);
  }

  Color get _toneColor => switch (tone) {
        LivePublicChatSystemTone.success => const Color(0xFF8BCB9E),
        LivePublicChatSystemTone.pending => const Color(0xFFFFCC80),
        LivePublicChatSystemTone.cancel => const Color(0xFFB0BEC5),
        LivePublicChatSystemTone.neutral => const Color(0x99FFFFFF),
      };

  @override
  Widget build(BuildContext context) {
    if (line.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 5),
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: _toneColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
          shadows: LivePublicChatLine.kLegibilityShadow,
        ),
      ),
    );
  }
}
