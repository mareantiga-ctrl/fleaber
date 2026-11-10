/// Retry CPI on C3-SUFFIX order already planted.
import 'dart:io';

import '_rtdh.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  const oid = 'd778c692-c4ae-4ae9-a649-f144949a68ac';
  final row = await c.orderRow(oid);
  final pid = '${row?['product_id']}';
  final hit = await c.checkout(orderId: oid, productId: pid, amount: 1);
  stdout.writeln('retry suffix ${hit.brief}');
  stdout.writeln('stored ${row?['payment_method']} sid=${hit.sessionId}');
  await dumpJson('${outDir()}/confirm_c3_retry.json', {
    'cpi': hit.brief,
    'opened': hit.ok && (hit.sessionId ?? '').startsWith('cs_'),
    'stored_pm': row?['payment_method'],
    'sid': hit.sessionId,
    'status': hit.status,
  });
}
