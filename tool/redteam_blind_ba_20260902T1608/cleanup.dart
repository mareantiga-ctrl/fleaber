/// Cleanup BA — restore inbox, cancel fixtures. Não é fix de produto.
import 'dart:io';
import '_rtba.dart';

Future<void> main() async {
  final c = Rtba.fromEnv(loadEnv());
  await c.loginActors();

  const chat = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  await c.patchChat(chat, {
    'last_message': 'RTBA audit ended',
  }, service: true);

  for (final id in [
    'a6b7d377-fcb9-4704-a132-8f1e73b12500',
    'c99bf6b7-f2d3-4f28-ae20-a1ab077ddf6a',
    'acc22923-1760-4d68-b8d3-44c382c4b4e9',
    'bf3acd32-56f3-4c9d-81e5-1aad8dff25f4',
  ]) {
    await c.rest('PATCH', 'orders?id=eq.$id', service: true, body: {
      'status': 'cancelado',
    }, prefer: 'return=minimal');
  }

  final products = await c.rest(
    'GET',
    'products?title=like.$prefix*&select=id',
    service: true,
  );
  for (final row in products.list) {
    if (row is Map && row['id'] != null) {
      await c.rest(
        'PATCH',
        'products?id=eq.${row['id']}',
        service: true,
        body: {
          'is_sold': true,
          'list_on_marketplace': false,
          'quantity': 0,
        },
        prefer: 'return=minimal',
      );
    }
  }

  final inbox = await c.chatRow(chat);
  stdout.writeln('cleanup inbox=${inbox?['last_message']}');
}
