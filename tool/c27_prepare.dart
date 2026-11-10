// ignore_for_file: avoid_print
/// C27 — preparar artigos live (A + B), fechar leftovers, .maestro/.env.
///
///   dart run tool/c27_prepare.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleA = 'C27 Produto A';
const _titleB = 'C27 Produto B';
const _priceA = 9.0;
const _priceB = 11.0;
const _qty = 3;
const _reportDir = 'tool/reports/battery_c27_2026-08-23';

Future<Map<String, dynamic>> _insertProduct(
  LiveOpsStagingClient client,
  String sellerId,
  String title,
  double price,
  String refSuffix,
) async {
  return client.insert('products', {
    'seller_id': sellerId,
    'title': title,
    'price': price,
    'quantity': _qty,
    'ref_code': 'C27$refSuffix-${DateTime.now().millisecondsSinceEpoch % 100000}',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
}

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

  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 40,
  );
  var closed = 0;
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
      closed++;
    }
  }
  print('leftover lives fechadas: $closed');

  final productA = await _insertProduct(client, sellerId, _titleA, _priceA, 'A');
  final productB = await _insertProduct(client, sellerId, _titleB, _priceB, 'B');

  _writeMaestroEnv(
    staging: staging,
    sellerId: sellerId,
    sellerEmail: sellerEmail,
    sellerPassword: sellerPassword,
    buyerEmail: buyerEmail,
    buyerPassword: buyerPassword,
    itemTitle: _titleA,
  );

  final dest = Directory(_reportDir);
  dest.createSync(recursive: true);
  Directory('${dest.path}/bd').createSync(recursive: true);
  Directory('${dest.path}/screenshots').createSync(recursive: true);
  Directory('${dest.path}/logs').createSync(recursive: true);

  final ledger = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'product_a': {
      'id': productA['id'],
      'title': _titleA,
      'price': _priceA,
      'quantity': _qty,
      'ref_code': productA['ref_code'],
    },
    'product_b': {
      'id': productB['id'],
      'title': _titleB,
      'price': _priceB,
      'quantity': _qty,
      'ref_code': productB['ref_code'],
    },
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'hub_handle': 'fleahub-demo-ux',
    'expected': {
      '253': 'reserva aceite → RPC expire → status expired + stock libertado',
      '254': '2.ª reserva → pagar MB WAY → status converted',
    },
  };
  File('${dest.path}/bd/c27_prepare.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(ledger),
  );
  print(jsonEncode(ledger));
}

void _writeMaestroEnv({
  required Map<String, String> staging,
  required String sellerId,
  required String sellerEmail,
  required String sellerPassword,
  required String buyerEmail,
  required String buyerPassword,
  required String itemTitle,
}) {
  String enc(String v) => Uri.encodeComponent(v);
  final deviceSeller = staging['MAESTRO_DEVICE_SELLER']?.trim().isNotEmpty == true
      ? staging['MAESTRO_DEVICE_SELLER']!.trim()
      : 'a698f0de';
  final deviceBuyer = staging['MAESTRO_DEVICE_BUYER']?.trim().isNotEmpty == true
      ? staging['MAESTRO_DEVICE_BUYER']!.trim()
      : 'd6pnqgz5jvnnbm9x';
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
    'MAESTRO_ITEM_TITLE=$itemTitle',
    'MAESTRO_DEVICE_SELLER=$deviceSeller',
    'MAESTRO_DEVICE_BUYER=$deviceBuyer',
    'MAESTRO_DEVICE_DEFAULT=$deviceSeller',
    'MAESTRO_DRIVER_PORT_SELLER=7010',
    'MAESTRO_DRIVER_PORT_BUYER=7011',
  ];
  existing.parent.createSync(recursive: true);
  existing.writeAsStringSync('${lines.join('\n')}\n');
}
