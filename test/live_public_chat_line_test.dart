import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_system_chat_humanizer.dart';
import 'package:fleaber/widgets/live_public_chat_line.dart';

void main() {
  group('LiveSystemChatHumanizer — copy social A2', () {
    test('compra mantém Nome comprou Artigo', () {
      final r = LiveSystemChatHumanizer.parse('Marina comprou Puzzle');
      expect(r.showInPublicChat, isTrue);
      expect(r.line, 'Marina comprou Puzzle');
      expect(r.line, isNot(contains('Compra ·')));
      expect(r.line, isNot(contains(' · ')));
    });

    test('reserva mantém Nome reservou Artigo', () {
      final r = LiveSystemChatHumanizer.parse(
        'Marina reservou Puzzle para o saco da live',
      );
      expect(r.showInPublicChat, isTrue);
      expect(r.line, 'Marina reservou Puzzle');
      expect(r.line, isNot(contains('Reserva ·')));
    });

    test('reserva sem artigo → fila', () {
      final r = LiveSystemChatHumanizer.parse(
        'Marina reservou para o saco da live',
      );
      expect(r.line, 'Marina entrou na fila deste artigo');
    });

    test('reserva aceite pública → Nome ficou com Artigo', () {
      final r = LiveSystemChatHumanizer.parse(
        '🔒 Reserva aceite — Puzzle · Marina tem 5 dias para pagar',
      );
      expect(r.showInPublicChat, isTrue);
      expect(r.line, 'Marina ficou com Puzzle');
      expect(r.line, isNot(contains('5 dias')));
      expect(r.line, isNot(contains('Reserva aceite ·')));
    });

    test('reserva aceite painel → Nome ficou com Artigo (sem prazo)', () {
      final r = LiveSystemChatHumanizer.parse(
        '🔒 Marina — reserva aceite · Ref 004/18 · Prazo: 4d',
        normalizeItemLabel: (label) =>
            label.contains('004') ? 'Puzzle' : label,
      );
      expect(r.showInPublicChat, isTrue);
      expect(r.line, 'Marina ficou com Puzzle');
      expect(r.line, isNot(contains('Prazo')));
      expect(r.line, isNot(contains('Ref ')));
    });

    test('adicionou ao saco → carrinho humano', () {
      final r = LiveSystemChatHumanizer.parse(
        '🛍️ Marina adicionou Ref 012/15 ao saco',
        normalizeItemLabel: (_) => 'Puxador de Porta',
      );
      expect(r.line, 'Marina adicionou Puxador de Porta ao carrinho');
      expect(r.line, isNot(contains('Ref ')));
      expect(r.line, isNot(contains('saco')));
    });

    test('compra com preço → só nome + artigo', () {
      final r = LiveSystemChatHumanizer.parse(
        '💳 Marina comprou Ref 004/18 (10€)',
        normalizeItemLabel: (_) => 'Puzzle',
      );
      expect(r.line, 'Marina comprou Puzzle');
      expect(r.line, isNot(contains('10€')));
      expect(r.line, isNot(contains('Ref ')));
    });

    test('rejeição vendedora — oculta do chat público', () {
      final r = LiveSystemChatHumanizer.parse(
        '❌ Vendedora rejeitou reserva · Ref A12',
      );
      expect(r.showInPublicChat, isFalse);
    });

    test('prazo 5 dias não aparece no chat público', () {
      final r = LiveSystemChatHumanizer.parse(
        '🔒 Reserva aceite — 2 un. · Puzzle · Marina tem 5 dias para pagar',
      );
      expect(r.line, 'Marina ficou com Puzzle');
      expect(r.line, isNot(contains('dias')));
    });

    test('overlay comprador — Ficaste com Artigo', () {
      final r = LiveSystemChatHumanizer.parse(
        '🔒 Reserva aceite — Puzzle · Marina tem 5 dias para pagar',
        forCurrentBuyerPrivate: true,
      );
      expect(r.line, 'Ficaste com Puzzle — 5 dias para pagar');
    });

    test('preço definido → Artigo — Preço', () {
      final r = LiveSystemChatHumanizer.parse(
        '💶 Preço definido · Puzzle · 12,00 €',
      );
      expect(r.showInPublicChat, isTrue);
      expect(r.line, 'Puzzle — 12,00 €');
      expect(r.line, isNot(contains('Preço definido')));
    });

    test('última unidade → Última unidade de Artigo', () {
      final r = LiveSystemChatHumanizer.parse('🔥 Ultima unidade — Ref A12');
      expect(r.line, 'Última unidade de Ref A12');
      expect(r.emphasis, LiveSystemChatEmphasis.fomo);
    });

    test('esgotado → Artigo esgotou', () {
      final r = LiveSystemChatHumanizer.parse('🔴 Puzzle esgotado');
      expect(r.line, 'Puzzle esgotou');
      expect(r.line, isNot(contains('Esgotado ·')));
    });

    test('gorjeta com nome', () {
      final r = LiveSystemChatHumanizer.parseTip(
        amountEur: 5,
        contributorName: 'Marina',
        amountLabel: '5,00 €',
      );
      expect(r.line, 'Marina apoiou a live com 5,00 €');
    });

    test('gorjeta sem nome — fallback', () {
      final r = LiveSystemChatHumanizer.parseTip(
        amountEur: 3,
        amountLabel: '3,00 €',
      );
      expect(r.line, 'Alguém apoiou a live com 3,00 €');
    });

    test('cancelamento com nome', () {
      final r = LiveSystemChatHumanizer.parse(
        'Marina cancelou a reserva de Puzzle',
      );
      expect(r.line, contains('cancelou'));
      expect(r.line, contains('Puzzle'));
    });

    test('pedido acima stock — backoffice, não chat público', () {
      final r = LiveSystemChatHumanizer.parse(
        '📋 Pedido de 3 un. · Puzzle — só 1 disponível; aguarda confirmação',
      );
      expect(r.showInPublicChat, isFalse);
      expect(r.snackbarLine, 'Pediste 3 — só há 1 disponível');
    });

    test('recusa vendedora — backoffice', () {
      final r = LiveSystemChatHumanizer.parse(
        '❌ Recusaste o pedido de 2 un. · Puzzle (acima do stock na live)',
      );
      expect(r.showInPublicChat, isFalse);
      expect(r.snackbarLine, 'Pedido recusado — stock insuficiente');
    });

    test('aceitaste vender — backoffice', () {
      final r = LiveSystemChatHumanizer.parse(
        '✅ Aceitaste vender 2 un. · Puzzle — comprador tem 5 dias para pagar',
      );
      expect(r.showInPublicChat, isFalse);
    });

    test('normalize ref → título humano', () {
      final r = LiveSystemChatHumanizer.parse(
        'Marina comprou Ref A12',
        normalizeItemLabel: (label) =>
            label == 'Ref A12' ? 'Puzzle Star Wars' : label,
      );
      expect(r.line, 'Marina comprou Puzzle Star Wars');
      expect(r.line, isNot(contains('Ref A12')));
    });

    test('resolve nome Utilizador → perfil', () {
      final r = LiveSystemChatHumanizer.parse(
        'Utilizador reservou Puzzle',
        resolveBuyerName: (raw) =>
            raw.toLowerCase() == 'utilizador' ? 'Marina' : raw,
      );
      expect(r.line, 'Marina reservou Puzzle');
    });
  });

  group('LivePublicChatSystemLine — API comum comprador/vendedor', () {
    test('compactFromBody não usa formato ERP', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Marina comprou Puzzle',
      );
      expect(r.line, 'Marina comprou Puzzle');
      expect(r.line, isNot(contains('Compra ·')));
    });

    test('isVisibleInPublicChat filtra backoffice', () {
      expect(
        LivePublicChatSystemLine.isVisibleInPublicChat(
          '📋 Pedido de 2 un. · Puzzle — só 1 disponível; aguarda confirmação',
        ),
        isFalse,
      );
      expect(
        LivePublicChatSystemLine.isVisibleInPublicChat('Marina comprou Puzzle'),
        isTrue,
      );
    });

    test('comprador e vendedor — mesma frase via humanizer', () {
      const raw = '✅ Marina comprou Puzzle';
      final buyer = LivePublicChatSystemLine.compactFromBody(raw);
      final seller = LivePublicChatSystemLine.compactFromBody(raw);
      expect(buyer.line, seller.line);
      expect(buyer.line, 'Marina comprou Puzzle');
    });

    test('rifa da live — social público sem prefixo duplicado', () {
      final r = LiveSystemChatHumanizer.parse(
        '🎟️ Rifa: Ana ganhou +2 rifas — visitante qualificado',
      );
      expect(r.kind, LiveSystemChatEventKind.raffle);
      expect(r.showInPublicChat, isTrue);
      expect(r.line, contains('Ana ganhou +2 rifas'));
      expect(r.line, isNot(startsWith('🎟️')));
      expect(
        liveSystemChatSocialDedupKey(r),
        'raffle|ana ganhou +2 rifas — visitante qualificado',
      );
    });

    test('dedupe compra duplicada — mantém primeira linha humana', () {
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
          '💳 Marina comprou Ref 004/18 (10€)',
          seenSocialKeys: seen,
          normalizeItemLabel: (_) => 'Puzzle',
        ),
        isFalse,
      );
    });
  });
}
