// ignore_for_file: avoid_print
/// Diagnóstico read-only da corrida E2E Facebook+PS real (sem inject).
/// dart run tool/ps_e2e_real_fail_diag.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
const marianaId = '69104e91-6a00-40d9-a7c9-b1571422ae43';
const fx1ProductId = '16824f28-70a8-4ce6-8b85-c830b8cceb79';
const fx2ProductId = 'a7152202-fe7b-49ab-bb67-a1db318b832d';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  Future<List<Map<String, dynamic>>> trySelect(
    String table, {
    String? filter,
    int limit = 50,
  }) async {
    try {
      return await sb.select(table, filter: filter, limit: limit);
    } catch (e) {
      return [
        {'_error': '$table', '_detail': e.toString()},
      ];
    }
  }

  final profile = await trySelect(
    'profiles',
    filter: 'id=eq.$sellerId',
    limit: 1,
  );
  final lives = await trySelect(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 15,
  );

  final slimLives = lives.map((l) {
    if (l.containsKey('_error')) return l;
    return {
      'id': l['id'],
      'status': l['status'],
      'is_active': l['is_active'],
      'created_at': l['created_at'],
      'ended_at': l['ended_at'] ?? l['ended_at_at'],
      'title': l['title'],
      'mux_playback_id': l['mux_playback_id'] ?? l['playback_id'],
      'mux_live_stream_id': l['mux_live_stream_id'] ?? l['live_stream_id'],
      'started_at': l['started_at'],
      'vod_playback_id': l['vod_playback_id'] ?? l['mux_vod_playback_id'],
    };
  }).toList();

  final active = lives.where((l) {
    if (l.containsKey('_error')) return false;
    final st = '${l['status']}'.toLowerCase();
    return l['is_active'] == true || st == 'live' || st == 'active';
  }).toList();

  final since = DateTime.now().toUtc().subtract(const Duration(hours: 6));
  final recent = lives.where((l) {
    if (l.containsKey('_error')) return false;
    final c = DateTime.tryParse('${l['created_at']}')?.toUtc();
    return c != null && c.isAfter(since);
  }).toList();

  final liveIds = <String>{
    ...active.map((l) => '${l['id']}'),
    ...recent.map((l) => '${l['id']}'),
  };

  final itemsByLive = <String, dynamic>{};
  final resByLive = <String, dynamic>{};
  for (final id in liveIds) {
    if (id.isEmpty || id == 'null') continue;
    itemsByLive[id] = await trySelect(
      'live_items',
      filter: 'live_id=eq.$id&order=created_at.asc',
      limit: 40,
    );
    resByLive[id] = await trySelect(
      'live_reservation_requests',
      filter: 'live_id=eq.$id&order=created_at.desc',
      limit: 80,
    );
  }

  final pairing = await trySelect(
    'ps_pairing_sessions',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 20,
  );
  final pairingAlt = pairing.isNotEmpty && pairing.first.containsKey('_error')
      ? await trySelect(
          'ps_pairing',
          filter: 'order=created_at.desc',
          limit: 20,
        )
      : pairing;

  final ingest = await trySelect(
    'ps_ingest_audit',
    filter: 'order=created_at.desc',
    limit: 80,
  );

  final ingestFx = ingest.where((r) {
    if (r.containsKey('_error')) return true;
    final blob =
        '${r['ocr_raw_line']}|${r['ref_slug_in']}|${r['resolved_ref_slug']}|${r['external_display_name']}|${r['external_buyer_ref']}'
            .toUpperCase();
    return blob.contains('FX1') ||
        blob.contains('QUERO') ||
        blob.contains('MARIANA');
  }).toList();

  final panel = await trySelect(
    'ps_panel_events',
    filter: 'order=created_at.desc',
    limit: 80,
  );
  final panelAlt = panel.isNotEmpty && panel.first.containsKey('_error')
      ? await trySelect(
          'ps_panel_logs',
          filter: 'order=created_at.desc',
          limit: 80,
        )
      : panel;

  final products = await trySelect(
    'products',
    filter: 'id=in.($fx1ProductId,$fx2ProductId)',
    limit: 5,
  );

  final marianaRes = await trySelect(
    'live_reservation_requests',
    filter: 'buyer_id=eq.$marianaId&order=created_at.desc',
    limit: 20,
  );

  final events = await trySelect(
    'live_reservation_events',
    filter: 'order=created_at.desc',
    limit: 40,
  );

  final oauth = await _facebookIdentity(
    url: url,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    userId: marianaId,
  );

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'note': 'read-only; no inject; no reservation created',
    'seller_id': sellerId,
    'mariana_buyer_id': marianaId,
    'profile': profile,
    'active_live_count': active.length,
    'active_lives': active
        .map((l) => {
              'id': l['id'],
              'status': l['status'],
              'is_active': l['is_active'],
              'created_at': l['created_at'],
              'mux_playback_id': l['mux_playback_id'] ?? l['playback_id'],
            })
        .toList(),
    'recent_lives_6h': slimLives.where((l) {
      final c = DateTime.tryParse('${l['created_at']}')?.toUtc();
      return c != null && c.isAfter(since);
    }).toList(),
    'lives_head': slimLives,
    'live_items_by_live': itemsByLive,
    'reservations_by_live': {
      for (final e in resByLive.entries)
        e.key: (e.value is List)
            ? (e.value as List).map(_slimRes).toList()
            : e.value,
    },
    'mariana_reservations': marianaRes.map(_slimRes).toList(),
    'pairing': pairingAlt.map(_slimPairing).toList(),
    'ingest_fx_or_quero': ingestFx.map(_slimIngest).toList(),
    'ingest_head': ingest.take(15).map(_slimIngest).toList(),
    'panel_head': panelAlt.take(25).toList(),
    'reservation_events_head': events.take(15).toList(),
    'fx_products': products,
    'mariana_oauth': oauth,
  };

  final dir = Directory('tool/reports/ps_oppo_live_20260912')
    ..createSync(recursive: true);
  final path =
      '${dir.path}/E2E_REAL_FAIL_DIAG_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  File('${dir.path}/E2E_REAL_FAIL_DIAG_LATEST.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode({
    'written': path,
    'active_live_count': active.length,
    'active_ids': active.map((l) => l['id']).toList(),
    'recent_6h': recent.length,
    'ingest_hits': ingestFx.where((r) => !r.containsKey('_error')).length,
    'pairing_ok': pairingAlt.isEmpty || !pairingAlt.first.containsKey('_error'),
    'panel_ok': panelAlt.isEmpty || !panelAlt.first.containsKey('_error'),
    'ingest_error': ingest.isNotEmpty && ingest.first.containsKey('_error')
        ? ingest.first['_detail']
        : null,
  }));
}

Map<String, dynamic> _slimRes(dynamic r) {
  if (r is! Map) return {'_': '$r'};
  final m = Map<String, dynamic>.from(r);
  if (m.containsKey('_error')) return m;
  return {
    'id': m['id'],
    'live_id': m['live_id'],
    'live_item_id': m['live_item_id'],
    'buyer_id': m['buyer_id'],
    'status': m['status'],
    'source': m['source'],
    'requested_qty': m['requested_qty'],
    'external_display_name': m['external_display_name'],
    'external_buyer_ref': m['external_buyer_ref'],
    'ocr_raw_line': m['ocr_raw_line'],
    'resolved_ref_slug': m['resolved_ref_slug'],
    'ingest_status': m['ingest_status'],
    'created_at': m['created_at'],
  };
}

Map<String, dynamic> _slimPairing(dynamic r) {
  if (r is! Map) return {'_': '$r'};
  final m = Map<String, dynamic>.from(r);
  if (m.containsKey('_error')) return m;
  return {
    'id': m['id'],
    'live_id': m['live_id'],
    'seller_id': m['seller_id'],
    'status': m['status'] ?? m['state'],
    'device_id': m['device_id'],
    'created_at': m['created_at'],
    'claimed_at': m['claimed_at'],
    'expires_at': m['expires_at'],
    'last_seen_at': m['last_seen_at'] ?? m['heartbeat_at'],
  };
}

Map<String, dynamic> _slimIngest(dynamic r) {
  if (r is! Map) return {'_': '$r'};
  final m = Map<String, dynamic>.from(r);
  if (m.containsKey('_error')) return m;
  return {
    'created_at': m['created_at'],
    'live_id': m['live_id'],
    'ok': m['ok'],
    'action': m['action'],
    'error': m['error'],
    'ocr_raw_line': m['ocr_raw_line'],
    'external_display_name': m['external_display_name'],
    'external_buyer_ref': m['external_buyer_ref'],
    'ref_slug_in': m['ref_slug_in'],
    'resolved_ref_slug': m['resolved_ref_slug'],
    'requested_qty': m['requested_qty'],
    'reservation_id': m['reservation_id'],
    'ingest_status': m['ingest_status'],
    'device_id': m['device_id'],
  };
}

Future<Map<String, dynamic>> _facebookIdentity({
  required String url,
  required String serviceRoleKey,
  required String userId,
}) async {
  final res = await HttpClient()
      .getUrl(Uri.parse('$url/auth/v1/admin/users/$userId'))
      .then((rq) {
    rq.headers.set('apikey', serviceRoleKey);
    rq.headers.set('Authorization', 'Bearer $serviceRoleKey');
    return rq.close();
  });
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 400) {
    return {'_error': res.statusCode, '_body': body.substring(0, body.length.clamp(0, 400))};
  }
  final map = jsonDecode(body) as Map<String, dynamic>;
  final identities = (map['identities'] as List?) ?? const [];
  final fb = identities
      .whereType<Map>()
      .where((i) => '${i['provider']}' == 'facebook')
      .map((i) {
    final data = i['identity_data'];
    final dm = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return {
      'provider_id': i['provider_id'],
      'identity_data_id': dm['id'],
      'identity_data_sub': dm['sub'],
      'name': dm['name'] ?? dm['full_name'],
      'email': dm['email'] ?? map['email'],
    };
  }).toList();
  return {
    'id': map['id'],
    'email': map['email'],
    'facebook': fb,
  };
}
