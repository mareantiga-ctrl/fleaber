/// GATE confirm — todas as encomendas dos buyers A1–A4: 0 vs 1 vs 2 cs_.
import 'dart:io';

import '_rtgate.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  final buyers = {
    'A1': '0a38d638-f34b-4481-8f64-d581abb9e7b1',
    'A2': 'ccd92fc2-f66e-473a-bd01-c2ab3d768735',
    'A3': 'b8cd1d83-390e-4899-a59b-9bb42548e06b',
    'A4': '8122198d-4352-4202-a86c-74ba910c706b',
    'A5': 'fc029260-75f4-4215-b384-bef967a7abf3',
    'A6': 'ce5d080f-6abe-403a-9296-c405284aef4a',
    'B1': 'd8e27aef-f5b2-49e7-ab8c-158f0bf7870c',
    'B2': 'd8bcd105-434d-49a8-ae33-9177a112ca82',
    'B3': 'fabea3db-8ecc-4fc7-8ec1-ddaf5f1cf24c',
  };
  final out = <String, Object?>{};
  for (final e in buyers.entries) {
    final h = await c.rest(
      'GET',
      'orders?buyer_id=eq.${e.value}&select=id,status,product_id,stripe_checkout_session_id,stripe_payment_intent_id,price_total&order=created_at.asc',
      service: true,
    );
    final sids = <String>{};
    final rows = <Map<String, Object?>>[];
    for (final raw in h.list) {
      if (raw is! Map) continue;
      final cs = '${raw['stripe_checkout_session_id'] ?? ''}';
      if (cs.startsWith('cs_')) sids.add(cs);
      rows.add({
        'id': raw['id'],
        'status': raw['status'],
        'pid': raw['product_id'],
        'cs': cs,
        'pi': raw['stripe_payment_intent_id'],
      });
    }
    out[e.key] = {
      'n_orders': rows.length,
      'distinct_cs': sids.length,
      'sids': sids.toList(),
      'rows': rows,
    };
    stdout.writeln(
      '${e.key} orders=${rows.length} distinct_cs=${sids.length} $sids',
    );
  }

  final paid = await c.orderRow('f5016b00-9122-472c-b9cf-c64b635d32d6');
  final pid = '41a2e251-8896-4b91-bcad-e51fe2117146';
  final prod = await c.productRow(pid);
  final hub = await c.hubSku(pid);
  out['C1_e2e'] = {
    'status': paid?['status'],
    'cs': paid?['stripe_checkout_session_id'],
    'pi': paid?['stripe_payment_intent_id'],
    'qty': prod?['quantity'],
    'sold': prod?['is_sold'],
    'hub_n': hub.list.length,
  };
  stdout.writeln(
    'C1 e2e status=${paid?['status']} qty=${prod?['quantity']} hub=${hub.list.length} pi=${paid?['stripe_payment_intent_id']}',
  );

  await dumpJson('${outDir()}/confirm.json', out);
}
