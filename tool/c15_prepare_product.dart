// ignore_for_file: avoid_print
/// Corrida 15 — preparar artigo C15 Produto A (preço normal, qty 3).
/// Fecha leftovers activos, cria produto, escreve .maestro/.env.
///
///   dart run tool/c15_prepare_product.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _productTitle = 'C15 Produto A';
const _price = 9.0;
const _qty = 3;

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final sellerEmail = envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerEmail = envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerToken = await client.signIn(
    email: sellerEmail,
    password: sellerPassword,
  );
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }
  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyerId)) {
    final t = await client.signIn(email: buyerEmail, password: buyerPassword);
    buyerId = await client.userIdForAccessToken(t);
  }

  // fechar leftovers
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 40,
  );
  var n = 0;
  for (final live in lives) {
    final id = live['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final status = (live['status'] ?? '').toString().toLowerCase();
    final active = live['is_active'] == true;
    if (status == 'live' || active || status == 'scheduled') {
      await client.patch(
        'lives',
        'id=eq.$id',
        {'status': 'ended', 'is_active': false},
      );
      n++;
      print('  fechada leftover $id');
    }
  }
  print('leftover lives fechadas: $n');

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': _productTitle,
    'price': _price,
    'quantity': _qty,
    'ref_code': 'C15A-${DateTime.now().millisecondsSinceEpoch % 100000}',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();
  final ref = product['ref_code']?.toString() ?? '';

  _writeMaestroEnv(
    staging: staging,
    sellerId: sellerId,
    sellerEmail: sellerEmail,
    sellerPassword: sellerPassword,
    buyerEmail: buyerEmail,
    buyerPassword: buyerPassword,
  );

  final dest = Directory('tool/reports/battery_c15_2026-08-19');
  dest.createSync(recursive: true);
  Directory('${dest.path}/bd').createSync(recursive: true);
  Directory('${dest.path}/screenshots').createSync(recursive: true);
  Directory('${dest.path}/logs').createSync(recursive: true);

  File('${dest.path}/bd/c15_prepare.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'product_id': productId,
      'product_title': _productTitle,
      'price': _price,
      'quantity': _qty,
      'ref_code': ref,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'hub_handle': 'fleahub-demo-ux',
    }),
  );

  print('C15 prepare OK product_id=$productId ref=$ref buyer=$buyerId');
}

void _writeMaestroEnv({
  required Map<String, String> staging,
  required String sellerId,
  required String sellerEmail,
  required String sellerPassword,
  required String buyerEmail,
  required String buyerPassword,
}) {
  String enc(String v) => Uri.encodeComponent(v);
  final deviceSeller = staging['MAESTRO_DEVICE_SELLER']?.trim() ?? 'a698f0de';
  final existing = File('.maestro/.env');
  var liveId = '';
  if (existing.existsSync()) {
    for (final line in existing.readAsLinesSync()) {
      if (line.startsWith('MAESTRO_LIVE_ID=')) {
        liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
      }
    }
  }
  final lines = <String>[
    'MAESTRO_APP_ID=pt.fleaber.app',
    'MAESTRO_LIVE_ID=$liveId',
    'MAESTRO_SELLER_ID=$sellerId',
    'MAESTRO_BUYER_EMAIL=$buyerEmail',
    'MAESTRO_BUYER_PASSWORD=$buyerPassword',
    'MAESTRO_SELLER_EMAIL=$sellerEmail',
    'MAESTRO_SELLER_PASSWORD=$sellerPassword',
    'MAESTRO_SELLER_EMAIL_URL=${enc(sellerEmail)}',
    'MAESTRO_BUYER_EMAIL_URL=${enc(buyerEmail)}',
    'MAESTRO_DEEP_LINK_BASE=fleaber://fleaber.com',
    'MAESTRO_ITEM_TITLE=$_productTitle',
    'MAESTRO_DEVICE_SELLER=$deviceSeller',
    'MAESTRO_DEVICE_DEFAULT=$deviceSeller',
    'MAESTRO_DRIVER_PORT_SELLER=7010',
  ];
  existing.parent.createSync(recursive: true);
  existing.writeAsStringSync('${lines.join('\n')}\n');
}
