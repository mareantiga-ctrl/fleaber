/// Fixture cleanup only — end RTAJ lives, relist RTAJ products. No security fixes.
import 'dart:io';
import '_rtaj.dart';

Future<void> main() async {
  final rt = Rtaj.fromEnv(loadEnv());
  final lives = await rt.rest(
    'GET',
    'lives?title=like.*$prefix*&select=id,status,is_active,title',
    service: true,
  );
  for (final row in lives.list.whereType<Map>()) {
    final id = row['id'];
    if (id == null) continue;
    await rt.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  final prods = await rt.rest(
    'GET',
    'products?title=like.*$prefix*&select=id,is_sold,list_on_marketplace,title',
    service: true,
  );
  var relisted = 0;
  for (final row in prods.list.whereType<Map>()) {
    final id = row['id'];
    if (id == null) continue;
    if (row['is_sold'] == true || row['list_on_marketplace'] == false) {
      await rt.rest('PATCH', 'products?id=eq.$id', service: true, body: {
        'is_sold': false,
        'list_on_marketplace': true,
      }, prefer: 'return=minimal');
      relisted++;
    }
  }
  stdout.writeln(
      'cleanup lives=${lives.list.length} products=${prods.list.length} relisted=$relisted');
}
