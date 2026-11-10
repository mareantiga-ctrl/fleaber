import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/utils/live_in_stream_checkout.dart';
import 'package:fleaber/widgets/fleaber_primary_button.dart';

/// Visual/functional regression: after bag_changed remainder, checkout shows
/// only kept lines (Artigos 1) — mirrors LiveBagCheckoutSheet rebuild.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'bag_changed Continuar rebuild shows Artigos (1) + KEEP + Pagar',
    (tester) async {
      final keep = LiveReservationRequestsRow({
        'id': 'rid-keep',
        'live_item_id': 'li-keep',
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'requested_qty': 1,
      });
      final lose = LiveReservationRequestsRow({
        'id': 'rid-lose',
        'live_item_id': 'li-lose',
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'requested_qty': 1,
      });
      final catalog = <String, LiveItemsRow>{
        'li-keep': LiveItemsRow({
          'id': 'li-keep',
          'title': 'QA KEEP',
          'price': 11.15,
          'product_id': 'prod-keep',
        }),
        'li-lose': LiveItemsRow({
          'id': 'li-lose',
          'title': 'QA LOSE',
          'price': 12.50,
          'product_id': 'prod-lose',
        }),
      };

      var rows = <LiveReservationRequestsRow>[lose, keep];
      var selected = rows.map((r) => r.id!.trim()).toSet();

      Future<void> pumpCheckout() async {
        final itemsSubtotal = selected.fold<double>(0, (sum, id) {
          final r = rows.firstWhere((e) => e.id == id);
          final item = catalog[(r.liveItemId ?? '').trim()];
          return sum + (item?.price ?? 0);
        });
        final protection = 0.65 + (itemsSubtotal * 0.05);
        final total = itemsSubtotal + protection;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: const Color(0xFF101518),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Finalizar compra',
                        style: TextStyle(color: Colors.white, fontSize: 17)),
                    const SizedBox(height: 12),
                    for (final r in rows)
                      if (selected.contains(r.id))
                        Text(
                          catalog[(r.liveItemId ?? '')]?.title ?? 'Artigo',
                          style: const TextStyle(color: Colors.white),
                        ),
                    LiveInStreamCheckout.checkoutTotalsBreakdown(
                      itemsSubtotalEur: itemsSubtotal,
                      shippingEur: 0,
                      protectionEur: protection,
                      totalEur: total,
                      lineCount: selected.length,
                    ),
                    const SizedBox(height: 10),
                    FleaberPrimaryButton(
                      label: 'Pagar',
                      onPressed: () {},
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpCheckout();
      expect(find.text('QA LOSE'), findsOneWidget);
      expect(find.text('QA KEEP'), findsOneWidget);
      expect(find.textContaining('Artigos (2)'), findsOneWidget);

      // Simulate Continuar: prune with filterBagPayLinesByAvailableLines.
      final payLines = [
        LiveBagCheckoutPayLine(
          product: ProductsRow({
            'id': 'prod-lose',
            'seller_id': 's1',
            'price': 12.5,
          }),
          itemRow: catalog['li-lose'],
          request: lose,
          payQty: 1,
        ),
        LiveBagCheckoutPayLine(
          product: ProductsRow({
            'id': 'prod-keep',
            'seller_id': 's1',
            'price': 11.15,
          }),
          itemRow: catalog['li-keep'],
          request: keep,
          payQty: 1,
        ),
      ];
      final kept = filterBagPayLinesByAvailableLines(
        lines: payLines,
        availableLines: [
          {
            'product_id': 'prod-keep',
            'live_item_id': 'li-keep',
            'reservation_request_id': 'rid-keep',
          },
        ],
      );
      rows = kept.map((l) => l.request).toList();
      selected = rows.map((r) => r.id!.trim()).toSet();
      await pumpCheckout();

      expect(find.text('QA LOSE'), findsNothing);
      expect(find.text('Artigo'), findsNothing);
      expect(find.text('QA KEEP'), findsOneWidget);
      expect(find.textContaining('Artigos (1)'), findsOneWidget);
      // PT-PT money (comma) after Phase 5.6 formatter unification.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('12,36') == true ||
                  w.data?.contains('12.36') == true),
        ),
        findsWidgets,
      );
      expect(find.text('Pagar'), findsOneWidget);
    },
  );
}
