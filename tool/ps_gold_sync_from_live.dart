// ignore_for_file: avoid_print
/// Sincroniza ps_training_gold.jsonl a partir da BD (reservas + painel PS).
/// O agente corre isto após cada bateria — sem copy/paste de logs.
///
/// Uso:
///   dart run tool/ps_gold_sync_from_live.dart --live-id UUID --battery TT
///   dart run tool/ps_gold_sync_from_live.dart --live-id UUID --battery RF --dry-run
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

const _goldPath = 'tool/ps_training_gold.jsonl';
const _statePath = 'tool/ps_ai/sync_state.json';

Future<void> main(List<String> args) async {
  String? liveId;
  var battery = '';
  var dryRun = false;
  var force = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--live-id' when i + 1 < args.length:
        liveId = args[++i];
      case '--battery' when i + 1 < args.length:
        battery = args[++i].trim().toUpperCase();
      case '--dry-run':
        dryRun = true;
      case '--force':
        force = true;
    }
  }

  if (liveId == null || liveId.trim().isEmpty) {
    print('Uso: dart run tool/ps_gold_sync_from_live.dart --live-id UUID --battery TT');
    exit(2);
  }
  liveId = liveId.trim();

  final repoRoot = Directory.current.path;
  final goldFile = File('$repoRoot/$_goldPath');
  if (!goldFile.existsSync()) {
    print('Falta $_goldPath');
    exit(2);
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

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final existing = _loadGold(goldFile);
  final dedupe = <String>{};
  for (final row in existing) {
    dedupe.add(_dedupeKey(row));
  }

  final state = _loadState('$repoRoot/$_statePath');
  if (!force && state['synced_live_ids'] is Map) {
    final synced = state['synced_live_ids'] as Map;
    if (synced[liveId] != null && battery.isEmpty) {
      battery = (synced[liveId]['battery'] ?? '').toString().toUpperCase();
    }
  }

  if (battery.isEmpty) {
    battery = _batteryFromRegistry('$repoRoot/tool/ps_batteries/registry.json', liveId);
  }
  if (battery.isEmpty) {
    battery = await _inferBatteryFromItems(client, liveId);
  }
  if (battery.isEmpty) {
    print('AVISO: --battery em falta; a usar prefixo LIVE.');
    battery = 'LIVE';
  }

  final candidates = <Map<String, dynamic>>[];

  final reqs = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.asc',
    limit: 500,
  );
  for (final r in reqs) {
    final raw = (r['ocr_raw_line'] ?? '').toString().trim();
    if (raw.isEmpty) continue;
    final intent = (r['parser_intent'] ?? 'reserve').toString().toLowerCase();
    if (intent != 'reserve' && intent != 'cancel') continue;

    final buyer = (r['external_display_name'] ?? '').toString().trim();
    final ref = (r['resolved_ref_slug'] ?? '').toString().trim().toUpperCase();
    final qty = _asInt(r['requested_qty'], fallback: 1);
    final slot = _inferPublicSlot(ref, raw);

    candidates.add({
      'comment': raw,
      'buyer': buyer.isEmpty ? null : buyer,
      'intent': intent,
      'ref_slug': ref.isEmpty ? null : ref,
      'public_slot': slot,
      'quantity': qty,
      'notes':
          'sync reserva ${(r['id'] ?? '').toString().substring(0, 8)} · ${r['status']} · live=$liveId',
      'source': 'reservation',
      'created_at': r['created_at'],
    });
  }

  try {
    final panel = await client.select(
      'ps_panel_events',
      filter: 'live_id=eq.$liveId&order=created_at.asc',
      limit: 500,
    );
    for (final e in panel) {
      final meta = e['meta'];
      Map<String, dynamic>? gc;
      if (meta is Map) {
        final rawGc = meta['gold_candidate'];
        if (rawGc is Map) {
          gc = Map<String, dynamic>.from(rawGc);
        } else if (meta['intent'] != null || meta['raw'] != null) {
          gc = {
            'comment': meta['raw'] ?? e['detail'] ?? '',
            'buyer': meta['buyer'],
            'intent': meta['intent'],
            'ref_slug': meta['ref'],
            'public_slot': meta['public_slot'],
            'quantity': meta['qty'] ?? 1,
          };
        }
      }
      if (gc == null) {
        final detail = (e['detail'] ?? '').toString().trim();
        if (detail.isEmpty) continue;
        final kind = (e['event_kind'] ?? '').toString();
        if (kind != 'warn' && kind != 'err') continue;
        gc = {
          'comment': detail,
          'intent': 'skip',
          'quantity': 1,
        };
      }

      final comment = (gc['comment'] ?? '').toString().trim();
      if (comment.isEmpty) continue;
      final intent = (gc['intent'] ?? 'skip').toString().toLowerCase();
      if (intent != 'reserve' &&
          intent != 'cancel' &&
          intent != 'skip' &&
          intent != 'noop') {
        continue;
      }

      candidates.add({
        'comment': comment,
        'buyer': gc['buyer'],
        'intent': intent == 'skip' ? 'skip' : intent,
        'ref_slug': gc['ref_slug']?.toString().toUpperCase(),
        'public_slot': gc['public_slot'],
        'quantity': _asInt(gc['quantity'], fallback: 1),
        'notes':
            'sync painel ${e['event_kind']} · ${e['message']} · live=$liveId',
        'source': 'panel',
        'created_at': e['created_at'],
      });
    }
  } catch (e) {
    print('AVISO: ps_panel_events indisponível ($e) — só reservas.');
  }

  if (candidates.isEmpty) {
    print('Sem candidatos na BD para live $liveId.');
    print('Confirma: SQL ps_panel_events deploy + ext v1.4+ com panel_log.');
    exit(1);
  }

  final added = <Map<String, dynamic>>[];
  var nextNum = _nextBatteryNumber(existing, battery);

  for (final c in candidates) {
    final row = <String, dynamic>{
      'battery': battery,
      'comment': c['comment'],
      'buyer': c['buyer'],
      'intent': c['intent'],
      'ref_slug': c['ref_slug'],
      'public_slot': c['public_slot'],
      'quantity': c['quantity'],
      'notes': c['notes'],
    };
    final key = _dedupeKey(row);
    if (dedupe.contains(key)) continue;
    dedupe.add(key);

    row['id'] = '$battery-${nextNum.toString().padLeft(2, '0')}';
    nextNum += 1;
    added.add(row);
  }

  print('Live: $liveId · bateria: $battery');
  print('Candidatos BD: ${candidates.length} · novos gold: ${added.length}');

  if (added.isEmpty) {
    print('Nada novo — gold já tinha estes pares.');
    _touchState(
      '$repoRoot/$_statePath',
      liveId: liveId,
      battery: battery,
      added: 0,
      dryRun: dryRun,
    );
    exit(0);
  }

  for (final row in added) {
    print('  + ${row['id']}: ${row['comment']} → ${row['intent']} ${row['ref_slug']}');
  }

  if (dryRun) {
    print('\n(dry-run — ficheiros não alterados)');
    exit(0);
  }

  final sink = goldFile.openWrite(mode: FileMode.append);
  for (final row in added) {
    sink.writeln(jsonEncode(row));
  }
  await sink.close();

  _touchState(
    '$repoRoot/$_statePath',
    liveId: liveId,
    battery: battery,
    added: added.length,
    ids: added.map((r) => r['id']).cast<String>().toList(),
    dryRun: false,
  );

  print('\nOK: ${added.length} linha(s) em $_goldPath');
  print('Seguinte: powershell -File tool/ps_ai/sync_training_pipeline.ps1 -SkipSync');
}

List<Map<String, dynamic>> _loadGold(File file) {
  final out = <Map<String, dynamic>>[];
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty) continue;
    out.add(jsonDecode(t) as Map<String, dynamic>);
  }
  return out;
}

Map<String, dynamic> _loadState(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  try {
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

void _touchState(
  String path, {
  required String liveId,
  required String battery,
  required int added,
  List<String>? ids,
  required bool dryRun,
}) {
  if (dryRun) return;
  final state = _loadState(path);
  final synced = Map<String, dynamic>.from(
    (state['synced_live_ids'] as Map?)?.cast<String, dynamic>() ?? {},
  );
  synced[liveId] = {
    'battery': battery,
    'synced_at': DateTime.now().toUtc().toIso8601String(),
    'added': added,
    if (ids != null) 'ids': ids,
  };
  state['synced_live_ids'] = synced;
  state['last_sync_at'] = DateTime.now().toUtc().toIso8601String();
  state['last_live_id'] = liveId;
  state['last_battery'] = battery;
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(state));
}

String _dedupeKey(Map<String, dynamic> row) {
  final comment = (row['comment'] ?? '').toString().trim().toLowerCase();
  final buyer = (row['buyer'] ?? '').toString().trim().toLowerCase();
  final intent = (row['intent'] ?? '').toString().toLowerCase();
  final ref = (row['ref_slug'] ?? '').toString().trim().toUpperCase();
  final qty = _asInt(row['quantity'], fallback: 1);
  return '$comment|$buyer|$intent|$ref|$qty';
}

int _nextBatteryNumber(List<Map<String, dynamic>> existing, String battery) {
  var max = 0;
  final prefix = '$battery-';
  for (final row in existing) {
    final id = (row['id'] ?? '').toString();
    if (!id.startsWith(prefix)) continue;
    final tail = id.substring(prefix.length);
    final n = int.tryParse(tail.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n != null && n > max) max = n;
  }
  return max + 1;
}

int _asInt(dynamic v, {required int fallback}) {
  if (v == null) return fallback;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? fallback;
}

int? _inferPublicSlot(String ref, String raw) {
  if (RegExp(r'^\d+$').hasMatch(ref)) {
    return int.tryParse(ref);
  }
  final m = RegExp(r'\b(?:o|slot)\s*(\d)\b', caseSensitive: false).firstMatch(raw);
  if (m != null) return int.tryParse(m.group(1)!);
  return null;
}

String _batteryFromRegistry(String path, String liveId) {
  final f = File(path);
  if (!f.existsSync()) return '';
  try {
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final direct = map[liveId];
    if (direct is Map && direct['battery'] != null) {
      return direct['battery'].toString().toUpperCase();
    }
    final pending = map['pending'];
    if (pending is Map) {
      for (final entry in pending.values) {
        if (entry is Map && entry['live_id']?.toString() == liveId) {
          return (entry['battery'] ?? '').toString().toUpperCase();
        }
      }
    }
  } catch (_) {}
  return '';
}

Future<String> _inferBatteryFromItems(
  LiveOpsStagingClient client,
  String liveId,
) async {
  try {
    final items = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId&order=created_at.asc',
      limit: 10,
    );
    for (final i in items) {
      final ref = (i['ref_code'] ?? '').toString().trim().toUpperCase();
      final m = RegExp(r'^([A-Z]+)\d').firstMatch(ref);
      if (m != null) return m.group(1)!;
    }
  } catch (_) {}
  return '';
}
