// Message Battery — verificação exaustiva de COPY das linhas de sistema.
//
// Espelha os corpos crus que tool/message_battery.dart injecta no staging
// (M01–M19) e garante que o humanizer produz a linha pública correcta e a
// visibilidade certa. Qualquer alteração de copy/regex que parta uma mensagem
// é apanhada aqui (sem device).
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_system_chat_humanizer.dart';
import 'package:fleaber/widgets/live_public_chat_line.dart';

class _Case {
  const _Case(this.id, this.raw, this.expectedLine, this.visible, {this.kind});
  final String id;
  final String raw;
  final String expectedLine;
  final bool visible;
  final LiveSystemChatEventKind? kind;
}

void main() {
  // Casos espelhados de tool/message_battery.dart (mesmos corpos crus).
  const cases = <_Case>[
    _Case('M01', '🛍️ Marina reservou Puzzle', 'Marina reservou Puzzle', true,
        kind: LiveSystemChatEventKind.reserve),
    _Case('M02', '🛍️ Marina reservou para o saco da live',
        'Marina entrou na fila deste artigo', true,
        kind: LiveSystemChatEventKind.reserveQueue),
    _Case('M03', '🛍️ Marina adicionou Puzzle ao saco',
        'Marina adicionou Puzzle ao carrinho', true,
        kind: LiveSystemChatEventKind.bagAdd),
    _Case('M04', '✅ Marina comprou Puzzle', 'Marina comprou Puzzle', true,
        kind: LiveSystemChatEventKind.purchase),
    _Case('M05', '💳 Marina comprou Puzzle (10€)', 'Marina comprou Puzzle', true,
        kind: LiveSystemChatEventKind.purchase),
    _Case('M06', '🔒 Reserva aceite — Puzzle · Marina tem 5 dias para pagar',
        'Marina ficou com Puzzle', true,
        kind: LiveSystemChatEventKind.reserveAcceptedPublic),
    _Case('M07', '🔒 Reserva aceite — 2 un. · Puzzle · Marina tem 5 dias para pagar',
        'Marina ficou com Puzzle', true,
        kind: LiveSystemChatEventKind.reserveAcceptedPublic),
    _Case('M08', '🔒 Marina — reserva aceite · Puzzle · Prazo: 4d',
        'Marina ficou com Puzzle', true,
        kind: LiveSystemChatEventKind.reserveAcceptedPublic),
    _Case('M09', '💶 Preço definido · Puzzle · 12,00 €', 'Puzzle — 12,00 €', true,
        kind: LiveSystemChatEventKind.priceDefined),
    _Case('M10', '🔥 Ultima unidade — Puzzle', 'Última unidade de Puzzle', true,
        kind: LiveSystemChatEventKind.lastUnit),
    _Case('M11', '🔴 Puzzle esgotado', 'Puzzle esgotou', true,
        kind: LiveSystemChatEventKind.soldOut),
    _Case('M13', '↩ Reserva cancelada pelo comprador', 'Reserva cancelada', true,
        kind: LiveSystemChatEventKind.cancel),
    _Case('M14', '↩ Marina cancelou a reserva · Puzzle',
        'Marina cancelou a reserva de Puzzle', true,
        kind: LiveSystemChatEventKind.cancel),
    // Backoffice — ocultos do chat público.
    _Case('M15', '📋 Pedido de 3 un. · Puzzle — só 1 disponível; aguarda confirmação',
        '', false, kind: LiveSystemChatEventKind.backofficeOverStock),
    _Case('M16', '❌ Recusaste o pedido de 2 un. · Puzzle (acima do stock na live)',
        '', false, kind: LiveSystemChatEventKind.backofficeRejected),
    _Case('M17', '✅ Aceitaste vender 2 un. · Puzzle — comprador tem 5 dias para pagar',
        '', false, kind: LiveSystemChatEventKind.backofficeSellerAccept),
    _Case('M18', '❌ Vendedora rejeitou reserva · Ref A12', '', false,
        kind: LiveSystemChatEventKind.backofficeRejected),
  ];

  group('Message Battery — copy social pública', () {
    for (final c in cases) {
      test('${c.id} ${c.raw}', () {
        final r = LiveSystemChatHumanizer.parse(c.raw);
        expect(r.showInPublicChat, c.visible,
            reason: '${c.id}: visibilidade');
        if (c.visible) {
          expect(r.line, c.expectedLine, reason: '${c.id}: linha');
        }
        if (c.kind != null) {
          expect(r.kind, c.kind, reason: '${c.id}: kind');
        }
        // Sem ERP/ref/preço/prazo nas linhas públicas.
        if (c.visible) {
          expect(r.line, isNot(contains(' · ')), reason: '${c.id}: sem ERP');
          expect(r.line, isNot(contains('Ref ')), reason: '${c.id}: sem Ref');
          expect(r.line, isNot(contains('dias')), reason: '${c.id}: sem prazo');
        }
      });
    }
  });

  group('Message Battery — rifa, gorjeta, dedupe', () {
    test('M12 rifa social sem prefixo', () {
      final r = LiveSystemChatHumanizer.parse('🎟️ Rifa: Ana ganhou +2 rifas');
      expect(r.kind, LiveSystemChatEventKind.raffle);
      expect(r.showInPublicChat, isTrue);
      expect(r.line, contains('Ana ganhou +2 rifas'));
      expect(r.line, isNot(startsWith('🎟️')));
    });

    test('M19 gorjeta com nome', () {
      final r = LiveSystemChatHumanizer.parseTip(
        amountEur: 5,
        contributorName: 'Marina',
        amountLabel: '5,00 €',
      );
      expect(r.kind, LiveSystemChatEventKind.tip);
      expect(r.line, 'Marina apoiou a live com 5,00 €');
    });

    test('M19b gorjeta sem nome', () {
      final r = LiveSystemChatHumanizer.parseTip(amountEur: 3, amountLabel: '3,00 €');
      expect(r.line, 'Alguém apoiou a live com 3,00 €');
    });

    test('dedupe compra duplicada (✅ depois 💳)', () {
      final seen = <String>{};
      expect(
        LivePublicChatSystemLine.shouldRenderSystemMessage(
          '✅ Marina comprou Puzzle',
          seenSocialKeys: seen,
        ),
        isTrue,
      );
      expect(
        LivePublicChatSystemLine.shouldRenderSystemMessage(
          '💳 Marina comprou Puzzle (10€)',
          seenSocialKeys: seen,
        ),
        isFalse,
      );
    });

    test('backoffice over-stock dá snackbar, não chat', () {
      final r = LiveSystemChatHumanizer.parse(
        '📋 Pedido de 3 un. · Puzzle — só 1 disponível; aguarda confirmação',
      );
      expect(r.showInPublicChat, isFalse);
      expect(r.snackbarLine, 'Pediste 3 — só há 1 disponível');
    });
  });
}
