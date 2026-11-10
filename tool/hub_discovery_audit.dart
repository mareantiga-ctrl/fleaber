// Auditoria discovery FleaHub — staging.
// dart run tool/hub_discovery_audit.dart

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final key = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final headers = {
    'apikey': key,
    'Authorization': 'Bearer $key',
    'Content-Type': 'application/json',
  };

  Future<List<Map<String, dynamic>>> q(String path) async {
    final res = await HttpClient()
        .getUrl(Uri.parse('$url/rest/v1/$path'))
        .then((r) {
      headers.forEach(r.headers.set);
      return r.close();
    });
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('${res.statusCode}: $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void printRows(String label, List<Map<String, dynamic>> rows) {
    print('=== $label (${rows.length}) ===');
    for (final row in rows.take(12)) {
      print(jsonEncode(row));
    }
    print('');
  }

  final activeLives = await q(
    'lives?select=id,title,status,is_active,seller_id,vendedor_id,went_live_at,created_at'
    '&is_active=eq.true&order=created_at.desc&limit=15',
  );
  printRows('lives is_active=true', activeLives);

  final discoveryActive = await q(
    'hub_lives_discovery_public?select=id,title,status,is_active,seller_handle,seller_id,seller_name,went_live_at'
    '&is_active=eq.true&order=went_live_at.desc&limit=15',
  );
  printRows('hub_lives_discovery_public is_active=true', discoveryActive);

  final discoveryLive = await q(
    'hub_lives_discovery_public?select=id,title,status,is_active,seller_handle,seller_id,went_live_at'
    '&status=eq.live&order=went_live_at.desc&limit=15',
  );
  printRows('hub_lives_discovery_public status=live', discoveryLive);

  final joaoProfiles = await q(
    'profiles?select=id,handle,full_name,hub_published,is_live'
    '&or=(handle.ilike.*joao*,full_name.ilike.*joao*,handle.ilike.*joao84*)'
    '&limit=10',
  );
  printRows('profiles joao*', joaoProfiles);

  for (final p in joaoProfiles) {
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final sellerLives = await q(
      'lives?select=id,title,status,is_active,went_live_at,created_at'
      '&or=(seller_id.eq.$id,vendedor_id.eq.$id)'
      '&order=created_at.desc&limit=8',
    );
    printRows('lives seller ${p['handle'] ?? id}', sellerLives);

    final inDiscovery = await q(
      'hub_lives_discovery_public?select=id,title,status,is_active,seller_handle'
      '&seller_id=eq.$id&order=created_at.desc&limit=8',
    );
    printRows('discovery seller ${p['handle'] ?? id}', inDiscovery);
  }
}
