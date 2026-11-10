/// Cleanup fixtures RTF-20260831T0735. Não é correcção de produto.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  final ids = [
    '66ee144e-8f2a-45bf-8e3e-34349826d293',
    'f2a8b690-a5fc-479e-8dd1-60778bc8d33c',
    'f9741e1e-9572-4538-938b-f8c87d684749',
    '859c6ce4-7fc6-4b8e-9f3e-189cb2b590c2',
    'c9ab8c25-cf44-481f-b3ee-212ed7419e74',
    '481f88ab-c731-4c2c-8d97-9d6fc2acbcf9',
  ];
  for (final id in ids) {
    final h = await c.rest('PATCH', 'orders?id=eq.$id', service: true, body: {
      'status': 'cancelado',
    });
    stderr.writeln('order $id ${h.status} ${h.snippet}');
  }
  for (final live in [
    'a61fd280-edd1-4efa-b203-c79bffeb6b1b',
    'bdd782c8-f2c4-49c4-9579-d197b2d479c9',
  ]) {
    await c.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
      'is_active': false,
      'status': live.startsWith('bdd') ? 'draft' : 'ended',
    }, prefer: 'return=minimal');
  }
  await c.rest('PATCH', 'ps_pairing_sessions?live_id=eq.a61fd280-edd1-4efa-b203-c79bffeb6b1b',
      service: true, body: {
    'expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'seller_helpers?id=eq.98f192ab-1850-4bb6-9ae9-2611ca7bc780',
      service: true, body: {
    'active': false,
    'invitation_status': 'rejected',
  }, prefer: 'return=minimal');
  for (final pid in [
    'ef9217c7-5c3a-4a50-92b8-dc535216f629',
    '38a7d055-94bb-4a2d-bb80-5063c2b0ba45',
    'b86e8a60-3e3f-4939-a5a9-73c2c21d9db7',
    'dca716df-5111-439e-a872-5a36f0b7ebb0',
    '65a0bce6-0e77-4f9a-b986-b9c81c710ae0',
    'e64d77fd-82e3-4e55-bc22-6dd8935e72a2',
  ]) {
    await c.rest('PATCH', 'products?id=eq.$pid', service: true, body: {
      'list_on_marketplace': false,
    }, prefer: 'return=minimal');
  }
  stderr.writeln('cleanup done');
}
