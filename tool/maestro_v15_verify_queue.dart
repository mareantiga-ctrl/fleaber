// ignore_for_file: avoid_print
/// Verifica na BD se existe reserva pending do buyer de teste na live do seller.
/// Uso apos buyer reservar (Maestro ou manual):
///   dart run tool/maestro_v15_verify_queue.dart
///   dart run tool/maestro_v15_verify_queue.dart --live-id=UUID
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  var liveId = '';
  for (final a in args) {
    if (a.startsWith('--live-id=')) {
      liveId = a.split('=').last.trim();
    }
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final envPath = File('.maestro/.env');
  final env = envPath.existsSync() ? _readEnv(envPath) : <String, String>{};
  var sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final email = env['MAESTRO_SELLER_EMAIL'] ?? staging['LIVE_OPS_TEST_SELLER_EMAIL'] ?? '';
    final pass = env['MAESTRO_SELLER_PASSWORD'] ?? staging['LIVE_OPS_TEST_SELLER_PASSWORD'] ?? '';
    if (email.isEmpty || pass.isEmpty) {
      throw StateError('credenciais seller em falta');
    }
    final token = await client.signIn(email: email, password: pass);
    sellerId = await client.userIdForAccessToken(token);
  }

  if (liveId.isEmpty) {
    liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  }
  if (liveId.isEmpty) {
    final lives = await client.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&order=created_at.desc',
      limit: 5,
    );
    if (lives.isEmpty) {
      stderr.writeln('FAIL: nenhuma live para seller $sellerId');
      exit(1);
    }
    liveId = lives.first['id']!.toString();
    print('live_id (mais recente): $liveId status=${lives.first['status']}');
  }

  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyerId)) {
    final buyerEmail = env['MAESTRO_BUYER_EMAIL'] ?? staging['LIVE_OPS_TEST_BUYER_EMAIL'] ?? '';
    final buyerPass = env['MAESTRO_BUYER_PASSWORD'] ?? staging['LIVE_OPS_TEST_BUYER_PASSWORD'] ?? '';
    final bt = await client.signIn(email: buyerEmail, password: buyerPass);
    buyerId = await client.userIdForAccessToken(bt);
  }

  final pending = await client.select(
    'live_reservation_requests',
    filter:
        'live_id=eq.$liveId&buyer_id=eq.$buyerId&status=eq.pending&order=created_at.desc',
    limit: 5,
  );

  if (pending.isEmpty) {
    stderr.writeln('FAIL: sem reserva pending do buyer nesta live.');
    stderr.writeln('  live_id=$liveId buyer_id=$buyerId');
    exit(1);
  }

  print('PASS: reserva pending na fila (BD)');
  for (final r in pending) {
    print('  id=${r['id']} item=${r['live_item_id']} qty=${r['requested_qty']} '
        'source=${r['source']}');
  }

  // Cruzamento com regra do saco (mesmo buyer + live)
  final allBuyer = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&buyer_id=eq.$buyerId',
    limit: 50,
  );
  // Import local via separate script preferred; inline mirror:
  var inBag = 0;
  var units = 0;
  for (final r in allBuyer) {
    final src = (r['source'] ?? 'fleaber_live').toString();
    final st = (r['status'] ?? '').toString();
    final iid = (r['live_item_id'] ?? '').toString().trim();
    if (src != 'fleaber_live' || iid.isEmpty) continue;
    if (st == 'pending' || st == 'accepted') {
      inBag++;
      final q = (r['requested_qty'] as num?)?.toInt() ?? 1;
      units += q < 1 ? 1 : q;
    }
  }
  print('saco_esperado: "$inBag no saco" (units=$units)');
  if (inBag < 1) {
    stderr.writeln(
      'FAIL: pending na query status=pending mas regra do saco → 0 '
      '(source/live_item_id?). Corre: dart run tool/maestro_verify_bag_crosscheck.dart',
    );
    exit(1);
  }
}

Map<String, String> _readEnv(File file) {
  final map = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return map;
}

String envRequire(Map<String, String> m, String key) {
  final v = m[key]?.trim() ?? '';
  if (v.isEmpty) throw StateError('$key em falta');
  return v;
}
