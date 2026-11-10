/// Expire leftover BN fixtures. Staging only. Not a product fix.
import 'dart:io';

import '_rtbn.dart';

Future<void> main() async {
  final c = Rtbn.fromEnv(loadEnv());
  const reqs = [
    '954cc131-3a14-4bf1-b2c2-a33b234826f0',
    '7b54ee0f-3985-4a8a-bbad-b5d4e9bfea53',
    'e9649ffe-80c1-4e5a-b17b-35faf4aa2f21',
    'c17376c7-25cc-497d-b23b-e25c10f75379',
    '7e8fa25e-4b82-4c44-a81e-fe859c0e35c5',
  ];
  const orders = [
    'c7f0cdb5-a002-44b3-b28d-0a9ba4c46fd0',
    '3bdaf76b-276e-4131-af00-6d66d4b07812',
  ];
  for (final id in reqs) {
    await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$id',
      service: true,
      body: {'status': 'expired'},
      prefer: 'return=minimal',
    );
  }
  for (final id in orders) {
    await c.rest(
      'PATCH',
      'orders?id=eq.$id',
      service: true,
      body: {'status': 'cancelado'},
      prefer: 'return=minimal',
    );
  }
  await c.endLives();
  stdout.writeln('cleanup done');
}
