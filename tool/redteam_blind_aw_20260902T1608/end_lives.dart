import 'dart:io';

import '_rtaw.dart';

/// Emergency: end leftover RTAW lives. No product fix.
void main() async {
  final c = Rtaw.fromEnv(loadEnv());
  const ids = [
    'e594c647-6402-4c9f-8f0d-1cacea87e3e4',
    '1b62819d-3417-4f9a-a8ac-446652b9b043',
    'fe78269a-5fa0-493f-ae7a-5427a809e4dd',
    '4f1cf745-b1c3-4a5d-b18e-bb9d50dd497d',
    '9c3d4127-cfe2-4305-a297-5fdf62e95143',
    'e12663e7-e73b-4903-aace-275151d5cce8',
    '22ec89bb-839d-40ac-90b6-fc166f5fdd66',
  ];
  for (final id in ids) {
    final h = await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=representation');
    stdout.writeln('$id ${h.status} ${clip(h.body, 120)}');
  }
  await c.restoreQaSellerHandle();
}
