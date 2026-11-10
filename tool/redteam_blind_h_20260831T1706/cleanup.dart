/// Cleanup fixtures RTH-* — service_role observação / cleanup. No production. No fixes.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();

  final products = await c.rest(
    'GET',
    'products?description=eq.$prefix&select=id',
    service: true,
  );
  final ids = products.list
      .map((e) => (e as Map)['id']?.toString())
      .whereType<String>()
      .toList();
  for (final id in ids) {
    await c.rest('DELETE', 'orders?product_id=eq.$id',
        service: true, prefer: 'return=minimal');
    await c.rest('DELETE', 'product_offers?product_id=eq.$id',
        service: true, prefer: 'return=minimal');
    await c.rest('DELETE', 'products?id=eq.$id',
        service: true, prefer: 'return=minimal');
  }

  final lives = await c.rest(
    'GET',
    'lives?title=eq.${Uri.encodeComponent('$prefix live')}&select=id',
    service: true,
  );
  for (final row in lives.list) {
    final id = (row as Map)['id']?.toString();
    if (id == null) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }

  final helpers = await c.rest(
    'GET',
    'seller_helpers?display_name=like.${Uri.encodeComponent('$prefix*')}&select=id',
    service: true,
  );
  for (final row in helpers.list) {
    final id = (row as Map)['id']?.toString();
    if (id == null) continue;
    await c.rest('PATCH', 'seller_helpers?id=eq.$id', service: true, body: {
      'active': false,
      'invitation_status': 'revoked',
    }, prefer: 'return=minimal');
  }

  stdout.writeln(
    'cleanup products=${ids.length} lives=${lives.list.length} helpers=${helpers.list.length}',
  );
}
