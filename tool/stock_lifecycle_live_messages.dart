// ignore_for_file: avoid_print
/// Audita mensagens reais da live Maestro (pós-UX): humanização, duplicados, backoffice leak.
///
/// Uso: dart run tool/stock_lifecycle_live_messages.dart [--live-id UUID]
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

/// Padrões crus que não devem aparecer na UI pública (só BD ok).
final _technicalInBody = RegExp(
  r'(batata_|live_item_id|FLEABER_JSON_V1|null\b|RPC\b)',
  caseSensitive: false,
);

/// Emojis de sistema — se repetidos idênticos em <2min = redundância.
final _socialPrefix = RegExp(r'^[🛍️🔒✅💳↩❌📋💶🔥🔴🎟️]');

Future<void> main(List<String> args) async {
  var liveId = '';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--live-id' && i + 1 < args.length) liveId = args[++i];
  }

  Map<String, String> env;
  try {
    env = loadLiveOpsStagingEnv();
  } catch (e) {
    print('SKIP_CONFIG: $e');
    exit(3);
  }

  final guard = RegressionStagingGuard.check(env);
  if (!guard.ok) {
    print('SKIP_CONFIG: ${guard.reason}');
    exit(3);
  }

  if (liveId.isEmpty) liveId = _readMaestroEnvKey('MAESTRO_LIVE_ID') ?? '';
  if (!isUuid(liveId)) {
    print('FAIL: MAESTRO_LIVE_ID em falta');
    exit(1);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final rows = await client.select(
    'live_messages',
    filter: 'live_id=eq.$liveId',
    limit: 80,
  );

  print('=== LIVE MESSAGES AUDIT live=$liveId count=${rows.length} ===');
  var fail = 0;
  var warn = 0;

  final seenBodies = <String, int>{};
  for (final row in rows) {
    final body = row['body']?.toString() ?? '';
    final kind = row['kind']?.toString() ?? '';
    if (body.isEmpty) continue;

    if (_technicalInBody.hasMatch(body)) {
      print('  FAIL técnico no body: [$kind] $body');
      fail++;
    }

    if (_socialPrefix.hasMatch(body)) {
      seenBodies[body] = (seenBodies[body] ?? 0) + 1;
    }

    // Backoffice over-stock não deve ir para chat público como linha social duplicada
    if (body.contains('só 1 disponível') && body.contains('Pedido de')) {
      print('  WARN backoffice over-stock armazenado (ok BD, verificar UI): $body');
      warn++;
    }
  }

  for (final e in seenBodies.entries) {
    if (e.value > 2) {
      print('  WARN redundância: "${e.key.substring(0, e.key.length.clamp(0, 60))}" ×${e.value}');
      warn++;
    }
  }

  // Reservas na live — estados presentes
  final reqs = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId',
    limit: 30,
  );
  final statuses = <String, int>{};
  for (final r in reqs) {
    final s = r['status']?.toString() ?? '?';
    statuses[s] = (statuses[s] ?? 0) + 1;
  }
  print('  reservation statuses: $statuses');

  print('');
  print('FAIL=$fail WARN=$warn');
  exit(fail > 0 ? 1 : 0);
}

String? _readMaestroEnvKey(String key) {
  final f = File('.maestro/.env');
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('$key=')) return t.substring(key.length + 1).trim();
  }
  return null;
}
