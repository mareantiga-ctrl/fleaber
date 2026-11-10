import 'dart:io';
import '_rtc.dart';

Future<void> main() async {
  final c = Rtc(loadEnv());
  final p = await c.rest(
    'GET',
    'products',
    service: true,
    query: 'ref_code=like.${prefix}*&select=id&limit=80',
  );
  final ids = <String>[];
  if (p['json'] is List) {
    for (final row in p['json'] as List) {
      if (row is Map && row['id'] != null) ids.add('${row['id']}');
    }
  }
  for (final id in ids) {
    await c.rest(
      'PATCH',
      'products',
      service: true,
      query: 'id=eq.$id',
      body: {'list_on_marketplace': false},
    );
  }
  final o = await c.rest(
    'GET',
    'orders',
    service: true,
    query:
        'status=in.(reserva_pendente,pendente)&select=id,product_id,status&product_id=in.(${ids.join(',')})&limit=80',
  );
  int n = 0;
  if (o['json'] is List) {
    for (final row in o['json'] as List) {
      if (row is Map && row['id'] != null) {
        await c.rest(
          'PATCH',
          'orders',
          service: true,
          query: 'id=eq.${row['id']}',
          body: {'status': 'cancelado'},
        );
        n++;
      }
    }
  }
  stdout.writeln('unlist ${ids.length} products; cancel $n pending orders');
}
