/// Cleanup fixtures RTF-20260831T1250. Não é correcção de produto.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);

  const lives = [
    '1332ba7e-91fb-4d4d-ab78-7052649d2363',
    '4bf308fe-51e8-45d6-ac21-d539e7a94da6',
    '72115a99-967e-40d7-8268-e6fd372b56d3',
    '965a92e3-fa07-4f6b-bc06-60175f0b38bc',
  ];
  const items = [
    '38c59bba-4213-4249-a927-eae0aaa908df',
    '090868bc-fd9d-4b07-a54c-943ae0daa86c',
    '6b9accc4-755c-49ac-9b57-fc88a941e72b',
  ];
  const products = [
    'd70145a9-203a-4b2d-b05f-6439e8b369d7',
    'f3f94bbf-07af-4891-9ba8-dc5e38406f5f',
    '77aa8cab-6cf0-4654-a1f4-d8a38f016ba7',
    '9c525857-bf17-4327-8fee-b8ed5d244704',
    '0cdd87fe-aee6-4a97-a938-f6907e43e4b1',
  ];
  const orders = [
    'ef4f3318-37fd-4fab-8608-20a3e63b1792',
    'a80c3e0d-da01-4bf9-b7c3-ebe2a4585c60',
    '416f1351-fbc6-461c-a7a8-c0c68cc4b7cb',
  ];
  const resvs = [
    'd5198f20-1974-4074-bff6-a4ed93428e9f',
    '540a8260-eab8-41dd-bf28-aadc1056f4cb',
  ];

  for (final id in orders) {
    final h = await c.rest('PATCH', 'orders?id=eq.$id', service: true, body: {
      'status': 'cancelado',
    });
    stderr.writeln('order $id ${h.status}');
  }
  for (final id in resvs) {
    await c.rest('PATCH', 'live_reservation_requests?id=eq.$id', service: true, body: {
      'status': 'rejected',
    }, prefer: 'return=minimal');
  }
  for (final id in items) {
    await c.rest('PATCH', 'live_items?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'paused',
    }, prefer: 'return=minimal');
  }
  for (final id in lives) {
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': id.startsWith('1332') ? 'draft' : 'ended',
    }, prefer: 'return=minimal');
  }
  for (final id in products) {
    await c.rest('PATCH', 'products?id=eq.$id', service: true, body: {
      'list_on_marketplace': false,
    }, prefer: 'return=minimal');
  }
  await c.rest(
    'PATCH',
    'seller_helpers?id=eq.c7c1cec2-bf55-41ea-984f-76a1799b79fa',
    service: true,
    body: {'active': false, 'invitation_status': 'rejected'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'ps_pairing_sessions?live_id=in.(${lives.join(',')})',
    service: true,
    body: {
      'expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
    },
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'profiles?id=eq.980f4fa1-0004-42f9-abca-69f1a9c29588',
    service: true,
    body: {'is_live': false},
    prefer: 'return=minimal',
  );
  stderr.writeln('cleanup done');
}
