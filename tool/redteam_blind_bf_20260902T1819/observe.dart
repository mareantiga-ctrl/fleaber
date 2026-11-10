/// Snapshot orders of two-bags + dup-line. Observação só.
library;

import 'dart:convert';
import 'dart:io';

import '_rtbf.dart';

Future<void> main() async {
  final c = Rtbf.fromEnv(loadEnv());
  await c.loginActors();
  final ids = {
    'p2.oa': '15bd1139-7511-431a-a176-68a9cd28f65a',
    'p2.ob': '18aceca3-4cc8-4b2f-b3c1-62630c6c36ae',
    'p2.oc': '3af0a7a6-3463-4eee-828a-7662fcd66d66',
    'p2.dup': '3c4036de-d9b3-4e33-b819-f77446775223',
    'p1.oa': '5bae78da-92cf-4c86-99d7-434c5950fe0c',
  };
  final out = <String, Object?>{};
  for (final e in ids.entries) {
    final row = await c.orderRow(e.value);
    Map<String, dynamic>? prod;
    final pid = row?['product_id']?.toString();
    if (pid != null) prod = await c.productRow(pid);
    out[e.key] = {
      'order': row,
      'product_qty': prod?['quantity'],
      'product_sold': prod?['is_sold'],
    };
  }
  await dumpJson('${outDir()}/observe.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
