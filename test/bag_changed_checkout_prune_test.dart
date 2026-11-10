import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/utils/live_in_stream_checkout.dart';

/// Regression: bag_changed → Continuar must drop unavailable lines from checkout.
void main() {
  LiveBagCheckoutPayLine line({
    required String productId,
    required String liveItemId,
    required String requestId,
    String title = 'Item',
  }) {
    return LiveBagCheckoutPayLine(
      product: ProductsRow({
        'id': productId,
        'seller_id': 'seller-1',
        'price': 11.15,
        'quantity': 1,
      }),
      itemRow: LiveItemsRow({
        'id': liveItemId,
        'title': title,
        'price': 11.15,
        'product_id': productId,
      }),
      request: LiveReservationRequestsRow({
        'id': requestId,
        'live_item_id': liveItemId,
        'status': 'accepted',
        'request_kind': 'guaranteed',
        'requested_qty': 1,
      }),
      payQty: 1,
    );
  }

  test('filter keeps only available_lines (by reservation / live_item / product)',
      () {
    final keep = line(
      productId: 'prod-keep',
      liveItemId: 'li-keep',
      requestId: 'rid-keep',
      title: 'QA KEEP',
    );
    final lose = line(
      productId: 'prod-lose',
      liveItemId: 'li-lose',
      requestId: 'rid-lose',
      title: 'QA LOSE',
    );

    final filtered = filterBagPayLinesByAvailableLines(
      lines: [lose, keep],
      availableLines: [
        {
          'index': 0,
          'product_id': 'prod-keep',
          'live_item_id': 'li-keep',
          'reservation_request_id': 'rid-keep',
          'quantity': 1,
        },
      ],
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.request.id, 'rid-keep');
    expect(filtered.single.itemRow?.title, 'QA KEEP');
    expect(filtered.single.product.id, 'prod-keep');
  });

  test('filter drops all when available_lines empty', () {
    final keep = line(
      productId: 'prod-keep',
      liveItemId: 'li-keep',
      requestId: 'rid-keep',
    );
    final filtered = filterBagPayLinesByAvailableLines(
      lines: [keep],
      availableLines: const [],
    );
    expect(filtered, isEmpty);
  });

  test('filter matches by product_id when reservation id missing in available',
      () {
    final keep = line(
      productId: 'prod-keep',
      liveItemId: 'li-keep',
      requestId: 'rid-keep',
      title: 'QA KEEP',
    );
    final lose = line(
      productId: 'prod-lose',
      liveItemId: 'li-lose',
      requestId: 'rid-lose',
      title: 'QA LOSE',
    );
    final filtered = filterBagPayLinesByAvailableLines(
      lines: [lose, keep],
      availableLines: [
        {'product_id': 'prod-keep', 'quantity': 1},
      ],
    );
    expect(filtered, hasLength(1));
    expect(filtered.single.product.id, 'prod-keep');
  });
}
