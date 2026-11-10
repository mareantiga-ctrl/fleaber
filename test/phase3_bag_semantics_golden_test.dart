import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 bag semantics visual (390px). Pure Flutter — no app imports.
void main() {
  testWidgets('phase3 bag semantic chips 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget pill(String label, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF101518),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O teu saco',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seller Ana · Live + Marketplace + Facebook',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _card('Vestido (Live)', pill('Reservado até 16:30', const Color(0xFF4CAF50))),
                _card(
                  'Colar (Marketplace)',
                  pill('No saco — o pagamento garante', const Color(0xFFFFB74D)),
                ),
                _card(
                  'Mala (Pedido)',
                  pill('A aguardar confirmação · #2', const Color(0xFFFF9800)),
                ),
                _card(
                  'Anel (Facebook PS)',
                  pill('Pedido enviado', const Color(0xFFFF9800)),
                ),
                _card(
                  'Broche (stock esgotado)',
                  pill('Indisponível', const Color(0xFFE57373)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Seller B — saco separado',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                _card(
                  'Artigo Seller B',
                  pill('Pedido enviado', const Color(0xFFFF9800)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Saco vazio',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phase3_bag_semantics_390.png'),
    );
  });
}

Widget _card(String title, Widget chip) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xCC1A2226),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 8),
          chip,
        ],
      ),
    ),
  );
}
