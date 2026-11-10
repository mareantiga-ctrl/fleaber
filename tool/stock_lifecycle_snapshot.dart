// ignore_for_file: avoid_print
/// Snapshot RPC stock da live Maestro (sem cleanup) — evidência BD por fase SL##.
///
/// Uso:
///   dart run tool/stock_lifecycle_snapshot.dart --label SL04
///   dart run tool/stock_lifecycle_snapshot.dart --live-id UUID --out tool/logs/sl.json
library;

import 'dart:convert';
import 'dart:io';

import 'audit/bd_stock_snapshot.dart';
import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

Future<void> main(List<String> args) async {
  var label = 'snapshot';
  var liveId = '';
  var outPath = '';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--label' && i + 1 < args.length) {
      label = args[++i];
    } else if (args[i] == '--live-id' && i + 1 < args.length) {
      liveId = args[++i];
    } else if (args[i] == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    }
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

  if (liveId.isEmpty) {
    liveId = _readMaestroEnvKey('MAESTRO_LIVE_ID') ?? '';
  }
  if (!isUuid(liveId)) {
    print('FAIL: MAESTRO_LIVE_ID em falta ou inválido');
    exit(1);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final snap = BdStockSnapshot(client);
  final payload = await snap.capture(liveId: liveId, label: label);
  payload['label'] = label;
  payload['captured_at'] = DateTime.now().toUtc().toIso8601String();

  final stockRows = (payload['stock_by_item'] as Map?)?.entries ?? const [];
  var ok = true;
  for (final e in stockRows) {
    final m = e.value;
    if (m is! Map) continue;
    final avail = (m['available_qty'] as num?)?.toInt();
    if (avail != null && avail < 0) {
      print('FAIL: available_qty negativo item=${e.key} avail=$avail');
      ok = false;
    }
    print(
      '  item=${e.key} total=${m['total_qty']} avail=${m['available_qty']} '
      'reserved=${m['reserved_qty']} sold=${m['sold'] ?? m['sold_qty']} '
      'blocked=${m['blocked_qty']} cross=${m['cross_reserved_qty']}',
    );
  }

  final file = outPath.isNotEmpty
      ? File(outPath)
      : File('tool/logs/stock_${label}_${DateTime.now().millisecondsSinceEpoch}.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  print('Wrote ${file.path}');

  exit(ok ? 0 : 1);
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
