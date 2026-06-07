import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/live_public_chat_line.dart';

void main() {
  group('LivePublicChatSystemLine.compactFromBody', () {
    test('aceite → success, linha compacta', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Reserva aceite · Puzzle · Marina',
      );
      expect(r.tone, LivePublicChatSystemTone.success);
      expect(r.line, startsWith('✅ Reserva aceite'));
      expect(r.line.length, lessThanOrEqualTo(53));
    });

    test('cancel → cancel tone', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Reserva cancelada Puzzle',
      );
      expect(r.tone, LivePublicChatSystemTone.cancel);
      expect(r.line, startsWith('↩ Reserva cancelada'));
    });

    test('pedido → pending tone', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Pedido criado 2 un Star Wars',
      );
      expect(r.tone, LivePublicChatSystemTone.pending);
      expect(r.line, startsWith('📦 Pedido criado'));
    });

    test('reservou → pending com nome', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Marina reservou Puzzle para o saco da live',
      );
      expect(r.tone, LivePublicChatSystemTone.pending);
      expect(r.line, contains('🛍️ Reserva'));
      expect(r.line, contains('Marina'));
    });

    test('reservou — resolve nome via user_id', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        'Utilizador reservou Puzzle',
        resolveBuyerName: (raw) =>
            raw.toLowerCase() == 'utilizador' ? 'Marina' : raw,
      );
      expect(r.line, contains('Marina'));
      expect(r.line, isNot(contains('Utilizador')));
    });

    test('aceitou case insensitive (web-safe RegExp)', () {
      final r = LivePublicChatSystemLine.compactFromBody('Joao aceitou a reserva');
      expect(r.tone, LivePublicChatSystemTone.success);
    });

    test('aceite broadcast — titulo via normalize', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        '🔒 Reserva aceite — Ref A12 · Marina tem 5 dias para pagar',
        normalizeItemLabel: (label) =>
            label == 'Ref A12' ? 'Puzzle Star Wars' : label,
      );
      expect(r.tone, LivePublicChatSystemTone.success);
      expect(r.line, contains('Puzzle Star Wars'));
      expect(r.line, isNot(contains('Ref A12')));
    });

    test('aceite broadcast — qty agregada', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        '🔒 Reserva aceite — 2 un. · Puzzle · Marina tem 5 dias para pagar',
      );
      expect(r.tone, LivePublicChatSystemTone.success);
      expect(r.line, contains('2 un.'));
      expect(r.line, contains('Puzzle'));
    });

    test('esgotado — titulo via normalize', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        '🔴 Ref A12 esgotado',
        normalizeItemLabel: (label) => label == 'Ref A12' ? 'Puzzle' : label,
      );
      expect(r.tone, LivePublicChatSystemTone.cancel);
      expect(r.line, contains('Puzzle'));
      expect(r.line, isNot(contains('Ref A12')));
    });

    test('aceitaste vender — titulo via normalize', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        '✅ Aceitaste vender 2 un. · Ref A12 — comprador tem 5 dias para pagar',
        normalizeItemLabel: (label) => label == 'Ref A12' ? 'Star Wars' : label,
      );
      expect(r.tone, LivePublicChatSystemTone.success);
      expect(r.line, contains('Star Wars'));
    });

    test('pedido qty — titulo via normalize', () {
      final r = LivePublicChatSystemLine.compactFromBody(
        '📋 Pedido de 2 un. · Ref A12 — só 1 disponível; aguarda confirmação',
        normalizeItemLabel: (label) => label == 'Ref A12' ? 'Puzzle' : label,
      );
      expect(r.tone, LivePublicChatSystemTone.pending);
      expect(r.line, contains('Puzzle'));
      expect(r.line, isNot(contains('Ref A12')));
    });
  });
}
