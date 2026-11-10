import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/bundle_order_status_util.dart';

OrdersRow _order(String status, {String? paymentMethod}) {
  return OrdersRow({
    'status': status,
    if (paymentMethod != null) 'payment_method': paymentMethod,
  });
}

void main() {
  group('bundleGroupAggregatedStatusPhrase (APP-065 / BUG-038)', () {
    test('conjunto fechado — 3× enviado', () {
      final phrase = bundleGroupAggregatedStatusPhrase([
        _order('enviado'),
        _order('enviado'),
        _order('enviado'),
      ]);
      expect(phrase, 'Artigo Enviado');
    });

    test('status enviado no map → Artigo Enviado', () {
      final phrase = bundleGroupAggregatedStatusPhrase([
        OrdersRow({'status': 'enviado'}),
      ]);
      expect(phrase, 'Artigo Enviado');
    });

    test('mix enviado + concluido → Artigo Enviado', () {
      final phrase = bundleGroupAggregatedStatusPhrase([
        _order('enviado'),
        _order('concluido'),
      ]);
      expect(phrase, 'Artigo Enviado');
    });
  });
}
