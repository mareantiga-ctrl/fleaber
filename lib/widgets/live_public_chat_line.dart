import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/live_system_chat_humanizer.dart';
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

/// Tom visual de eventos de sistema no chat público (legado — mapeado do humanizer).
enum LivePublicChatSystemTone { success, pending, cancel, neutral }

/// Notificação leve de sistema no chat público (A2 — frase social, não ERP).
class LivePublicChatSystemLine extends StatelessWidget {
  const LivePublicChatSystemLine({
    super.key,
    required this.parsed,
    this.animateHighlight = false,
  });

  final LiveSystemChatParsed parsed;
  final bool animateHighlight;

  factory LivePublicChatSystemLine.fromBody(
    String raw, {
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
    bool animateHighlight = false,
  }) {
    final parsed = LiveSystemChatHumanizer.parse(
      raw,
      normalizeItemLabel: normalizeItemLabel,
      resolveBuyerName: resolveBuyerName,
    );
    return LivePublicChatSystemLine(
      parsed: parsed,
      animateHighlight: animateHighlight,
    );
  }

  /// Legado — devolve tom + linha humanizada (sem formato ERP).
  static ({LivePublicChatSystemTone tone, String line}) compactFromBody(
    String raw, {
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
  }) {
    final parsed = LiveSystemChatHumanizer.parse(
      raw,
      normalizeItemLabel: normalizeItemLabel,
      resolveBuyerName: resolveBuyerName,
    );
    if (!parsed.showInPublicChat || parsed.line.isEmpty) {
      return (tone: LivePublicChatSystemTone.neutral, line: '');
    }
    return (tone: _mapTone(parsed.tone), line: parsed.line);
  }

  /// Filtra mensagens que não devem aparecer no chat público.
  static bool isVisibleInPublicChat(String raw) {
    return LiveSystemChatHumanizer.parse(raw).showInPublicChat;
  }

  /// Evita duplicar a mesma notificação social (ex. duas linhas de compra).
  static bool shouldRenderSystemMessage(
    String raw, {
    required Set<String> seenSocialKeys,
    String? Function(String labelSegment)? normalizeItemLabel,
    String? Function(String rawName)? resolveBuyerName,
  }) {
    final parsed = LiveSystemChatHumanizer.parse(
      raw,
      normalizeItemLabel: normalizeItemLabel,
      resolveBuyerName: resolveBuyerName,
    );
    if (!parsed.showInPublicChat || parsed.line.isEmpty) return false;
    final key = liveSystemChatSocialDedupKey(parsed);
    if (key == null) return true;
    if (seenSocialKeys.contains(key)) return false;
    seenSocialKeys.add(key);
    return true;
  }

  /// Compat: testes/legado que ainda usam headline + detail.
  static ({String headline, String detail}) partsFromBody(String raw) {
    final parsed = compactFromBody(raw);
    if (parsed.line.isEmpty) {
      return (headline: '', detail: '');
    }
    return (headline: parsed.line, detail: '');
  }

  static LivePublicChatSystemTone _mapTone(LiveSystemChatTone tone) {
    return switch (tone) {
      LiveSystemChatTone.success => LivePublicChatSystemTone.success,
      LiveSystemChatTone.pending => LivePublicChatSystemTone.pending,
      LiveSystemChatTone.cancel => LivePublicChatSystemTone.cancel,
      LiveSystemChatTone.neutral => LivePublicChatSystemTone.neutral,
    };
  }

  Color get _toneColor => switch (parsed.tone) {
        LiveSystemChatTone.success => const Color(0xFFB8E6C8),
        LiveSystemChatTone.pending => const Color(0xFFFFD9A8),
        LiveSystemChatTone.cancel => const Color(0xFFC5CED6),
        LiveSystemChatTone.neutral => const Color(0xCCFFFFFF),
      };

  double get _fontSize => switch (parsed.emphasis) {
        LiveSystemChatEmphasis.fomo => 13,
        LiveSystemChatEmphasis.social => 12.5,
        LiveSystemChatEmphasis.normal => 12,
      };

  FontWeight get _fontWeight => switch (parsed.emphasis) {
        LiveSystemChatEmphasis.fomo => FontWeight.w700,
        LiveSystemChatEmphasis.social => FontWeight.w600,
        LiveSystemChatEmphasis.normal => FontWeight.w500,
      };

  @override
  Widget build(BuildContext context) {
    if (!parsed.showInPublicChat || parsed.line.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parsed.icon != null) ...[
            Icon(
              parsed.icon,
              size: parsed.emphasis == LiveSystemChatEmphasis.fomo ? 15 : 14,
              color: _toneColor.withValues(alpha: 0.92),
            ),
            const SizedBox(width: 5),
          ],
          Expanded(child: _buildLineText()),
        ],
      ),
    );

    if (!animateHighlight || parsed.highlightDuration == null) {
      return content;
    }
    return LiveSystemChatHighlight(
      duration: parsed.highlightDuration!,
      color: _toneColor,
      intensity: parsed.kind == LiveSystemChatEventKind.purchase ? 1.0 : 1.0,
      child: content,
    );
  }

  Widget _buildLineText() {
    final name = parsed.personName?.trim() ?? '';
    final item = parsed.itemLabel?.trim() ?? '';

    if (name.isNotEmpty && item.isNotEmpty) {
      final line = parsed.line;
      final nameIdx = line.indexOf(name);
      if (nameIdx >= 0) {
        final before = line.substring(0, nameIdx);
        final afterName = line.substring(nameIdx + name.length);
        final itemIdx = afterName.indexOf(item);
        if (itemIdx >= 0) {
          final mid = afterName.substring(0, itemIdx);
          final after = afterName.substring(itemIdx + item.length);
          return RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: GoogleFonts.inter(
                color: _toneColor.withValues(alpha: 0.88),
                fontSize: _fontSize,
                fontWeight: _fontWeight,
                height: 1.25,
                shadows: LivePublicChatLine.kLegibilityShadow,
              ),
              children: [
                if (before.isNotEmpty) TextSpan(text: before),
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.96),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (mid.isNotEmpty) TextSpan(text: mid),
                TextSpan(
                  text: item,
                  style: TextStyle(
                    color: _toneColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (after.isNotEmpty) TextSpan(text: after),
              ],
            ),
          );
        }
      }
    }

    if (item.isNotEmpty && parsed.line.contains(item)) {
      final idx = parsed.line.indexOf(item);
      return RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: GoogleFonts.inter(
            color: _toneColor.withValues(alpha: 0.88),
            fontSize: _fontSize,
            fontWeight: _fontWeight,
            height: 1.25,
            shadows: LivePublicChatLine.kLegibilityShadow,
          ),
          children: [
            if (idx > 0) TextSpan(text: parsed.line.substring(0, idx)),
            TextSpan(
              text: item,
              style: TextStyle(
                color: _toneColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (idx + item.length < parsed.line.length)
              TextSpan(text: parsed.line.substring(idx + item.length)),
          ],
        ),
      );
    }

    return Text(
      parsed.line,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        color: _toneColor.withValues(alpha: 0.92),
        fontSize: _fontSize,
        fontWeight: _fontWeight,
        height: 1.25,
        shadows: LivePublicChatLine.kLegibilityShadow,
      ),
    );
  }
}

/// Destaque temporário subtil para eventos sociais (compra, FOMO, gorjeta).
class LiveSystemChatHighlight extends StatefulWidget {
  const LiveSystemChatHighlight({
    super.key,
    required this.child,
    required this.duration,
    required this.color,
    this.intensity = 1.0,
  });

  final Widget child;
  final Duration duration;
  final Color color;

  /// 1.0 = compras; >1 = gorjetas (glow ligeiramente superior).
  final double intensity;

  @override
  State<LiveSystemChatHighlight> createState() => _LiveSystemChatHighlightState();
}

class _LiveSystemChatHighlightState extends State<LiveSystemChatHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _glowStrength(double t) {
    if (t < 0.14) {
      return Curves.easeIn.transform(t / 0.14);
    }
    return 1.0 - Curves.easeOut.transform((t - 0.14) / 0.86);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final fade = _glowStrength(_controller.value) * widget.intensity;
        final bgAlpha = (0.12 * fade).clamp(0.0, 0.22);
        final glowAlpha = (0.18 * fade).clamp(0.0, 0.32);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: bgAlpha),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glowAlpha),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
