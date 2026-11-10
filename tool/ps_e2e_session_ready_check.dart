// ignore_for_file: avoid_print
/// Snapshot prep E2E Mariana — catálogo + lives + OAuth.
/// dart run tool/ps_e2e_session_ready_check.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  const marianaId = '69104e91-6a00-40d9-a7c9-b1571422ae43';

  final facebook = await _facebookIdentity(
    url: url,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    userId: marianaId,
  );

  List<Map<String, dynamic>> products = [];
  try {
    products = await sb.select(
      'products',
      filter: 'seller_id=eq.$sellerId&order=updated_at.desc',
      limit: 40,
    );
  } catch (_) {
    try {
      products = await sb.select(
        'products',
        filter: 'user_id=eq.$sellerId&order=updated_at.desc',
        limit: 40,
      );
    } catch (e) {
      products = [
        {'error': e.toString()},
      ];
    }
  }

  List<Map<String, dynamic>> lives = [];
  try {
    lives = await sb.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&order=created_at.desc',
      limit: 10,
    );
  } catch (_) {
    lives = await sb.select(
      'lives',
      filter: 'user_id=eq.$sellerId&order=created_at.desc',
      limit: 10,
    );
  }

  final activeLives = lives.where((l) {
    final st = '${l['status']}'.toLowerCase();
    return l['is_active'] == true || st == 'live' || st == 'active';
  }).toList();

  final fxish = products.where((p) {
    final r = '${p['reference'] ?? p['ref'] ?? p['sku'] ?? ''}'.toUpperCase();
    final t = '${p['title'] ?? p['name'] ?? ''}'.toUpperCase();
    return r.contains('FX') ||
        t.contains('NIKE') ||
        r.startsWith('C27') ||
        t.contains('CAMISOLA');
  }).toList();

  // Prefer FX1/FX2 by reference
  Map<String, dynamic>? fx1;
  Map<String, dynamic>? fx2;
  for (final p in products) {
    final r = '${p['reference'] ?? p['ref'] ?? ''}'.toUpperCase().trim();
    if (r == 'FX1') fx1 = p;
    if (r == 'FX2') fx2 = p;
  }

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'ready_check': 'PS_E2E_SESSION_ONE_SHOT',
    'mariana': {
      'buyer_id': marianaId,
      'email': 'mareantiga@gmail.com',
      'facebook': facebook,
      'oauth_ok': facebook['provider_id'] != null,
      'oauth_provider_id': facebook['provider_id'],
    },
    'seller': {
      'id': sellerId,
      'handle': 'fleahub-demo-ux',
      'email': env['LIVE_OPS_TEST_SELLER_EMAIL'],
    },
    'catalog': {
      'products_count': products.length,
      'fx1': fx1 == null
          ? null
          : {
              'id': fx1['id'],
              'title': fx1['title'] ?? fx1['name'],
              'reference': fx1['reference'] ?? fx1['ref'],
              'stock': fx1['stock'] ?? fx1['quantity'],
            },
      'fx2': fx2 == null
          ? null
          : {
              'id': fx2['id'],
              'title': fx2['title'] ?? fx2['name'],
              'reference': fx2['reference'] ?? fx2['ref'],
              'stock': fx2['stock'] ?? fx2['quantity'],
            },
      'fxish_preview': fxish.take(8).map((p) {
        return {
          'id': p['id'],
          'ref': p['reference'] ?? p['ref'],
          'title': p['title'] ?? p['name'],
        };
      }).toList(),
      'sample_error': products.isNotEmpty && products.first['error'] != null
          ? products.first['error']
          : null,
    },
    'lives': {
      'active_count': activeLives.length,
      'active': activeLives
          .map((l) => {
                'id': l['id'],
                'status': l['status'],
                'is_active': l['is_active'],
                'title': l['title'],
              })
          .toList(),
      'recent': lives
          .take(5)
          .map((l) => {
                'id': l['id'],
                'status': l['status'],
                'is_active': l['is_active'],
                'title': l['title'],
                'created_at': l['created_at'],
              })
          .toList(),
    },
    'ps_extension_expected': '>=1.5.44',
    'claim_sql': 'PROVISIONAL — só após GATE1=SIM',
    'homonyms_prova_a': 'SKIP — já feita (não repetir)',
  };

  final dir = Directory(
    'tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas',
  );
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final path = '${dir.path}/E2E_SESSION_READY_LATEST.json';
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  print(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path');
}

Future<Map<String, dynamic>> _facebookIdentity({
  required String url,
  required String serviceRoleKey,
  required String userId,
}) async {
  final uri = Uri.parse('$url/auth/v1/admin/users/$userId');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set('apikey', serviceRoleKey);
    req.headers.set('Authorization', 'Bearer $serviceRoleKey');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      return {'error': 'admin_user_${res.statusCode}', 'body': body};
    }
    final map = jsonDecode(body) as Map<String, dynamic>;
    final identities = (map['identities'] as List?) ?? [];
    for (final raw in identities) {
      final i = Map<String, dynamic>.from(raw as Map);
      if ('${i['provider']}' == 'facebook') {
        return {
          'provider': 'facebook',
          'provider_id': i['provider_id'],
          'identity_data': i['identity_data'],
          'updated_at': i['updated_at'],
          'last_sign_in_at': map['last_sign_in_at'],
        };
      }
    }
    return {'provider_id': null, 'note': 'no facebook identity on user'};
  } finally {
    client.close();
  }
}
