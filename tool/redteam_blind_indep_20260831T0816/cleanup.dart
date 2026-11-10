import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  final r = await c.rest(
    'GET',
    'products?ref_code=like.RTI4-*&select=id,title,ref_code,list_on_marketplace&limit=80',
    service: true,
  );
  var n = 0;
  for (final row in r.list.whereType<Map>()) {
    final id = row['id']?.toString();
    if (id == null) continue;
    final t = (row['title'] ?? '').toString();
    if (!t.contains('RTI4-') && !t.startsWith('RTI4-')) {
      if (!(row['ref_code'] ?? '').toString().startsWith('RTI4-') &&
          !(row['ref_code'] ?? '').toString().startsWith('RC-E2E')) {
        continue;
      }
    }
    await c.rest(
      'PATCH',
      'products?id=eq.$id',
      service: true,
      body: {'list_on_marketplace': false, 'is_sold': true},
    );
    n++;
  }
  stdout.writeln('cleanup unlisted $n products');
}
