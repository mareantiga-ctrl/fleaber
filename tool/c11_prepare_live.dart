// ignore_for_file: avoid_print
/// Corrida 11 — live + artigo novos. Sem reserva pré-inserida (o comprador reserva no Chrome).
///
///   dart run tool/c11_prepare_live.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveTitle = 'C11 Directo A';
const _productTitle = 'C11 Produto A';
const _price = 7.5;
const _qty = 5;
const _fakePlaybackId = 'maestro-smoke-staging-playback';

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

  await _endLeftoverLives(client, sellerId);

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': _productTitle,
    'price': _price,
    'quantity': _qty,
    'ref_code': 'C11A-${DateTime.now().millisecondsSinceEpoch % 100000}',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();
  final ref = product['ref_code']?.toString() ?? '';

  var muxMode = 'real';
  late String liveId;
  String? muxPlaybackId;
  try {
    print('Mux real: create-mux-live…');
    final live = await _createLiveViaMux(
      client: client,
      sellerToken: sellerToken,
      title: _liveTitle,
    );
    liveId = live['id']!.toString();
    muxPlaybackId = live['mux_playback_id']?.toString();
    print('  mux_playback_id=$muxPlaybackId');
  } catch (e) {
    muxMode = 'fake';
    print('Mux real falhou ($e) — live fake só para reservas');
    final live = await client.insert('lives', {
      'title': _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
      'mux_playback_id': _fakePlaybackId,
    });
    liveId = live['id']!.toString();
    muxPlaybackId = _fakePlaybackId;
  }

  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': _productTitle,
    'price': _price,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final liveItemId = item['id']!.toString();

  _writeMaestroEnv(
    staging: staging,
    liveId: liveId,
    sellerId: sellerId,
    sellerEmail: sellerEmail,
    sellerPassword: sellerPassword,
    buyerEmail: buyerEmail,
    buyerPassword: buyerPassword,
  );

  final dest = Directory('tool/reports/battery_c11_2026-08-18');
  dest.createSync(recursive: true);
  Directory('${dest.path}/bd').createSync(recursive: true);
  Directory('${dest.path}/screenshots').createSync(recursive: true);
  Directory('${dest.path}/logs').createSync(recursive: true);
  Directory('${dest.path}/c10_chrome_shop').createSync(recursive: true);

  final evidence = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'mux_mode': muxMode,
    'live_id': liveId,
    'live_title': _liveTitle,
    'mux_playback_id': muxPlaybackId,
    'product_id': productId,
    'product_title': _productTitle,
    'price': _price,
    'quantity': _qty,
    'live_item_id': liveItemId,
    'ref_code': ref,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'hub_handle': 'fleahub-demo-ux',
    'expected_after_reserve_qty_1': {
      'reservation_status': 'pending',
      'requested_qty': 1,
      'in_bag_rows': 1,
      'in_bag_units': 1,
      'product_quantity_unchanged': _qty,
    },
  };
  File('${dest.path}/bd/c11_prepare.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );

  final next = Uri.encodeQueryComponent('/fleahub-demo-ux');
  final email = Uri.encodeQueryComponent(buyerEmail);
  final pass = Uri.encodeQueryComponent(buyerPassword);
  File('${dest.path}/.buyer_autologin_url.txt').writeAsStringSync(
    'http://127.0.0.1:8099/#/maestroAutologin?email=$email&password=$pass&next=$next\n',
  );

  print('C11 prepare OK');
  print('  live_id=$liveId');
  print('  mux=$muxMode');
  print('  product_id=$productId');
  print('  live_item_id=$liveItemId');
  print('  buyer_id=$buyerId');
}

Future<void> _endLeftoverLives(
  LiveOpsStagingClient client,
  String sellerId,
) async {
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
    if (status == 'live' || active) {
      await client.patch(
        'lives',
        'id=eq.$id',
        {'status': 'ended', 'is_active': false},
      );
      n++;
      print('  fechada leftover $id ($status active=$active)');
    }
  }
  print('leftover lives fechadas: $n');
}

Future<Map<String, dynamic>> _createLiveViaMux({
  required LiveOpsStagingClient client,
  required String sellerToken,
  required String title,
}) async {
  final res = await client.invokeEdge(
    'create-mux-live',
    {'title': title},
    accessToken: sellerToken,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException('create-mux-live ${res.statusCode}: ${res.body}');
  }
  final body = jsonDecode(res.body);
  if (body is! Map) {
    throw const HttpException('create-mux-live: resposta inválida');
  }
  final map = Map<String, dynamic>.from(body);
  final live = map['live'];
  if (live is Map) {
    return Map<String, dynamic>.from(live);
  }
  throw const HttpException('create-mux-live: live em falta');
}

void _writeMaestroEnv({
  required Map<String, String> staging,
  required String liveId,
  required String sellerId,
  required String sellerEmail,
  required String sellerPassword,
  required String buyerEmail,
  required String buyerPassword,
}) {
  String enc(String v) => Uri.encodeComponent(v);
  final deviceSeller = staging['MAESTRO_DEVICE_SELLER']?.trim() ?? 'a698f0de';
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
  final out = File('.maestro/.env');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('${lines.join('\n')}\n');
  print('  wrote ${out.path}');
}
