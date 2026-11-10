// ignore_for_file: avoid_print
/// Zero stock on bag product B after checkout UI already shows both lines.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final seed = jsonDecode(
    await File(
      '14-unified-commerce-phase5.4-final-visual-proof/raw/seed_bag.json',
    ).readAsString(),
  ) as Map<String, dynamic>;
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final productB = seed['product_b']!.toString();
  await client.patch(
    'products',
    'id=eq.$productB',
    {'quantity': 0, 'is_sold': true},
  );
  final buyerToken = await client.signIn(
    email: seed['buyer_email']!.toString(),
    password: seed['buyer_password']!.toString(),
  );
  Map<String, dynamic> begin;
  try {
    begin = await client.rpc(
      'batata_commerce_checkout_begin',
      {
        'p_lines': seed['lines'],
        'p_shipping_method': 'Entrega em Mão (€0.00)',
        'p_payment_rail': 'stripe',
        'p_delivery': <String, dynamic>{},
        'p_client_idempotency_key':
            'p54_bag_zero_${DateTime.now().millisecondsSinceEpoch}',
        'p_confirm_remainder': false,
        'p_guest_token': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
  } catch (e) {
    begin = {
      'ok': false,
      'error': 'rpc_exception',
      'detail': e.toString(),
    };
  }
  final out = {
    'product_b': productB,
    'zeroed': true,
    'begin_after_zero': begin,
  };
  final f = File(
    '14-unified-commerce-phase5.4-final-visual-proof/raw/bag_zero_b.json',
  );
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
