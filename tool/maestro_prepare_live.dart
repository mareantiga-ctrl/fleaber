// ignore_for_file: avoid_print
/// Prepara live + .maestro/.env para flows Maestro (a partir de live_ops_staging.env).
/// Uso: dart run tool/maestro_prepare_live.dart
///      dart run tool/maestro_prepare_live.dart --multi   (V1.5: só env + cleanup, sem live pré-criada)
///      dart run tool/maestro_prepare_live.dart --real-mux  (create-mux-live real; default com TCL)
///      dart run tool/maestro_prepare_live.dart --fake-mux  (playback fake; só emulador)
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveTitle = 'MAESTRO_SMOKE_LIVE';
const _refPrefix = 'MAESTRO';
const _fakePlaybackId = 'maestro-smoke-staging-playback';

String _urlEnc(String value) => Uri.encodeComponent(value);

bool _isTruthy(String? value) {
  final v = value?.trim().toLowerCase() ?? '';
  return v == '1' || v == 'true' || v == 'yes' || v == 'on';
}

bool _isPhysicalAdbDevice(String deviceId) {
  final id = deviceId.trim();
  if (id.isEmpty) return false;
  return !id.startsWith('emulator-');
}

bool _useRealMux({
  required List<String> args,
  required Map<String, String> staging,
}) {
  if (args.contains('--fake-mux')) return false;
  if (args.contains('--real-mux')) return true;
  if (_isTruthy(staging['MAESTRO_USE_REAL_MUX'])) return true;
  final seller = staging['MAESTRO_DEVICE_SELLER']?.trim() ?? '';
  return _isPhysicalAdbDevice(seller);
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
    throw HttpException(
      'create-mux-live ${res.statusCode}: ${res.body}',
    );
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
  throw const HttpException('create-mux-live: live em falta na resposta');
}

void main(List<String> args) async {
  final multi = args.contains('--multi');
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

  await _cleanupOld(client, sellerId);
  await _cleanupSellerDraft(client, sellerId);

  final deviceSeller = staging['MAESTRO_DEVICE_SELLER']?.trim() ?? '';
  final deviceBuyer = staging['MAESTRO_DEVICE_BUYER']?.trim() ?? '';

  if (multi) {
    final maestroEnvMulti = <String>[
      'MAESTRO_APP_ID=pt.fleaber.app',
      'MAESTRO_SELLER_ID=$sellerId',
      'MAESTRO_BUYER_EMAIL=$buyerEmail',
      'MAESTRO_BUYER_PASSWORD=$buyerPassword',
      'MAESTRO_SELLER_EMAIL=$sellerEmail',
      'MAESTRO_SELLER_PASSWORD=$sellerPassword',
      'MAESTRO_SELLER_EMAIL_URL=${_urlEnc(sellerEmail)}',
      'MAESTRO_BUYER_EMAIL_URL=${_urlEnc(buyerEmail)}',
      'MAESTRO_DEEP_LINK_BASE=fleaber://fleaber.com',
      'MAESTRO_ITEM_TITLE=Maestro smoke item',
      if (deviceSeller.isNotEmpty) 'MAESTRO_DEVICE_SELLER=$deviceSeller',
      if (deviceBuyer.isNotEmpty) 'MAESTRO_DEVICE_BUYER=$deviceBuyer',
      if (deviceSeller.isNotEmpty) 'MAESTRO_DEVICE_DEFAULT=$deviceSeller',
      if (deviceSeller.isNotEmpty) 'MAESTRO_DRIVER_PORT_SELLER=7001',
      if (deviceBuyer.isNotEmpty) 'MAESTRO_DRIVER_PORT_BUYER=7002',
    ];
    final outMulti = File('.maestro/.env');
    outMulti.parent.createSync(recursive: true);
    outMulti.writeAsStringSync('${maestroEnvMulti.join('\n')}\n');
    print('Maestro prepare --multi OK (sem live pré-criada)');
    print('  seller_id=$sellerId');
    if (deviceSeller.isNotEmpty) print('  device_seller=$deviceSeller');
    if (deviceBuyer.isNotEmpty) print('  device_buyer=$deviceBuyer');
    print('  wrote ${outMulti.path}');
    print('');
    print('V1.5: powershell -File tool/run_maestro_v15_reserve.ps1');
    return;
  }

  final useRealMux = _useRealMux(args: args, staging: staging);
  late final String liveId;
  String? muxPlaybackId;
  if (useRealMux) {
    print('Mux real: create-mux-live (LiveKit→Mux no TCL)…');
    final live = await _createLiveViaMux(
      client: client,
      sellerToken: sellerToken,
      title: _liveTitle,
    );
    liveId = live['id']!.toString();
    muxPlaybackId = live['mux_playback_id']?.toString();
    print('  mux_playback_id=$muxPlaybackId');
  } else {
    print('Mux fake: playback_id=$_fakePlaybackId (emulador / --fake-mux)');
    final live = await client.insert('lives', {
      'title': _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
      'mux_playback_id': _fakePlaybackId,
    });
    liveId = live['id']!.toString();
  }
  final ref = '$_refPrefix-${DateTime.now().millisecondsSinceEpoch % 100000}';

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'Maestro smoke product',
    'price': 5,
    'quantity': 5,
    'ref_code': ref,
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();

  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'Maestro smoke item',
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final liveItemId = item['id']!.toString();

  final buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  var resolvedBuyerId = buyerId;
  if (!isUuid(resolvedBuyerId)) {
    final buyerToken = await client.signIn(
      email: buyerEmail,
      password: buyerPassword,
    );
    resolvedBuyerId = await client.userIdForAccessToken(buyerToken);
  }
  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'seller_id': sellerId,
    'buyer_id': resolvedBuyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': 'pending',
  });

  String? raffleId;
  try {
    final raffleRes = await client.rpc(
      'batata_create_live_raffle',
      {
        'p_live_id': liveId,
        'p_title': 'Maestro raffle prize',
        'p_activate': true,
        'p_show_public_leaderboard': true,
      },
      accessToken: sellerToken,
    );
    if (raffleRes is Map) {
      raffleId = raffleRes['raffle_id']?.toString();
    }
  } catch (e) {
    stdout.writeln('AVISO: criar rifa Maestro falhou: $e');
  }

  final maestroEnv = <String>[
    'MAESTRO_APP_ID=pt.fleaber.app',
    'MAESTRO_LIVE_ID=$liveId',
    'MAESTRO_SELLER_ID=$sellerId',
    'MAESTRO_BUYER_EMAIL=$buyerEmail',
    'MAESTRO_BUYER_PASSWORD=$buyerPassword',
    'MAESTRO_SELLER_EMAIL=$sellerEmail',
    'MAESTRO_SELLER_PASSWORD=$sellerPassword',
    'MAESTRO_SELLER_EMAIL_URL=${_urlEnc(sellerEmail)}',
    'MAESTRO_BUYER_EMAIL_URL=${_urlEnc(buyerEmail)}',
    'MAESTRO_DEEP_LINK_BASE=fleaber://fleaber.com',
    if (raffleId != null && raffleId.isNotEmpty) 'MAESTRO_RAFFLE_ID=$raffleId',
    if (deviceSeller.isNotEmpty) 'MAESTRO_DEVICE_SELLER=$deviceSeller',
    if (deviceBuyer.isNotEmpty) 'MAESTRO_DEVICE_BUYER=$deviceBuyer',
    if (deviceSeller.isNotEmpty) 'MAESTRO_DEVICE_DEFAULT=$deviceSeller',
    if (deviceSeller.isNotEmpty) 'MAESTRO_DRIVER_PORT_SELLER=7001',
    if (deviceBuyer.isNotEmpty) 'MAESTRO_DRIVER_PORT_BUYER=7002',
  ];

  final outFile = File('.maestro/.env');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync('${maestroEnv.join('\n')}\n');

  print('Maestro prepare OK');
  print('  live_id=$liveId');
  print('  mux=${useRealMux ? "real" : "fake"}');
  print('  seller_id=$sellerId');
  print('  ref=$ref');
  if (raffleId != null && raffleId.isNotEmpty) {
    print('  raffle_id=$raffleId');
  }
  print('  wrote ${outFile.path}');
  print('');
  print('Automação completa (sem Stripe):');
  print('  powershell -File tool/run_maestro_automation.ps1');
}

Future<void> _cleanupOld(LiveOpsStagingClient client, String sellerId) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_liveTitle',
    limit: 10,
  );
  for (final live in lives) {
    final liveId = live['id']?.toString() ?? '';
    if (liveId.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveId');
    await client.deleteWhere('live_raffles', 'live_id=eq.$liveId');
    await client.deleteWhere('orders', 'live_id=eq.$liveId');
    await client.deleteWhere('live_items', 'live_id=eq.$liveId');
    await client.deleteWhere('lives', 'id=eq.$liveId');
  }
}

/// Limpa items do draft para Maestro re-pedir linhagem (A008) e sync fresco (A019).
Future<void> _cleanupSellerDraft(LiveOpsStagingClient client, String sellerId) async {
  final drafts = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&status=eq.draft',
    limit: 5,
  );
  for (final live in drafts) {
    final liveId = live['id']?.toString() ?? '';
    if (liveId.isEmpty) continue;
    await client.deleteWhere('live_items', 'live_id=eq.$liveId');
  }
}
