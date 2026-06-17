// ignore_for_file: avoid_print
/// Verifica estado BD após automação Maestro (sem Stripe).
/// Uso: dart run tool/maestro_verify_automation.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  final expectAccepted = !args.contains('--pending-only');
  final envPath = File('.maestro/.env');
  if (!envPath.existsSync()) {
    stderr.writeln('Falta .maestro/.env — corre maestro_prepare_live primeiro.');
    exit(1);
  }
  final env = _readEnv(envPath);
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  final sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(liveId) || !isUuid(sellerId)) {
    stderr.writeln('MAESTRO_LIVE_ID / MAESTRO_SELLER_ID inválidos em .maestro/.env');
    exit(1);
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var failed = 0;

  final lives = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  if (lives.isEmpty) {
    print('FAIL live_exists');
    failed++;
  } else {
    final st = lives.first['status']?.toString() ?? '';
    if (st == 'live') {
      print('OK live_status=live');
    } else if (st == 'ended' && expectAccepted) {
      print('WARN live_status=ended (reserva aceite OK; live pode ter fechado no studio)');
    } else {
      print('FAIL live_status=$st (esperado live)');
      failed++;
    }
  }

  final raffles = await client.select(
    'live_raffles',
    filter: 'live_id=eq.$liveId&status=eq.active',
    limit: 1,
  );
  if (raffles.isEmpty) {
    print('FAIL active_raffle');
    failed++;
  } else {
    print('OK active_raffle id=${raffles.first['id']}');
  }

  final pending = await client.countRows(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&status=eq.pending',
  );
  final accepted = await client.countRows(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&status=eq.accepted',
  );
  if (expectAccepted) {
    if (accepted < 1) {
      print('FAIL reservation_accepted count=$accepted');
      failed++;
    } else {
      print('OK reservation_accepted count=$accepted');
    }
  } else if (pending < 1) {
    print('FAIL reservation_pending count=$pending');
    failed++;
  } else {
    print('OK reservation_pending count=$pending');
  }

  final buyerEmail = env['MAESTRO_BUYER_EMAIL']?.trim() ??
      envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = env['MAESTRO_BUYER_PASSWORD']?.trim() ??
      envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final buyerToken = await client.signIn(
    email: buyerEmail,
    password: buyerPassword,
  );
  final buyerId = await client.userIdForAccessToken(buyerToken);

  if (raffles.isNotEmpty) {
    final rid = raffles.first['id']?.toString() ?? '';
    final entries = await client.countRows(
      'live_raffle_entries',
      filter: 'raffle_id=eq.$rid&user_id=eq.$buyerId',
    );
    if (entries < 1) {
      print('WARN raffle_entry_buyer=0 (flow buyer rifa pode não ter corrido)');
    } else {
      print('OK raffle_entry_buyer count=$entries');
    }
  }

  if (failed > 0) {
    stderr.writeln('VERIFY FAIL ($failed checks)');
    exit(1);
  }
  print('VERIFY PASS');
}

Map<String, String> _readEnv(File file) {
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
