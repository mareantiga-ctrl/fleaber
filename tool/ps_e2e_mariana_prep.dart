// ignore_for_file: avoid_print
/// Prep E2E PS Face real — Mariana (buyer FB) + seller + catalog snapshot.
/// Não imprime passwords. Corre: dart run tool/ps_e2e_mariana_prep.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final serviceRoleKey = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final anonKey = envRequire(env, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anonKey,
    serviceRoleKey: serviceRoleKey,
  );

  final sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim();
  final sellerEmail = env['LIVE_OPS_TEST_SELLER_EMAIL']?.trim();

  // 1) Find Mariana via admin users (name / email heuristics)
  final mariana = await _findMariana(
    url: url,
    serviceRoleKey: serviceRoleKey,
  );

  // 2) Seller profile
  Map<String, dynamic>? sellerProfile;
  if (sellerId != null && sellerId.isNotEmpty) {
    final rows = await sb.select(
      'profiles',
      filter: 'id=eq.$sellerId',
      limit: 3,
    );
    if (rows.isNotEmpty) sellerProfile = rows.first;
  }

  // 3) Recent products for seller (refs)
  List<Map<String, dynamic>> products = [];
  if (sellerId != null && sellerId.isNotEmpty) {
    try {
      products = await sb.select(
        'products',
        filter: 'seller_id=eq.$sellerId&order=updated_at.desc',
        limit: 15,
      );
    } catch (_) {
      try {
        products = await sb.select(
          'products',
          filter: 'user_id=eq.$sellerId&order=updated_at.desc',
          limit: 15,
        );
      } catch (e) {
        products = [
          {'error': e.toString()},
        ];
      }
    }
  }

  // 4) Active / recent lives for seller
  List<Map<String, dynamic>> lives = [];
  if (sellerId != null && sellerId.isNotEmpty) {
    try {
      lives = await sb.select(
        'lives',
        filter: 'seller_id=eq.$sellerId&order=created_at.desc',
        limit: 8,
      );
    } catch (_) {
      try {
        lives = await sb.select(
          'lives',
          filter: 'user_id=eq.$sellerId&order=created_at.desc',
          limit: 8,
        );
      } catch (e) {
        lives = [
          {'error': e.toString()},
        ];
      }
    }
  }

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'prep': 'PS_E2E_MARIANA',
    'seller': {
      'id': sellerId,
      'email': sellerEmail,
      'profile_full_name': sellerProfile?['full_name'],
      'profile_username': sellerProfile?['username'] ?? sellerProfile?['handle'],
    },
    'mariana': mariana,
    'products_sample': products
        .take(10)
        .map(
          (p) => {
            'id': p['id'],
            'title': p['title'] ?? p['name'],
            'ref': p['ref_code'] ?? p['ref'] ?? p['public_ref'],
            'price': p['price'],
            'error': p['error'],
          },
        )
        .toList(),
    'lives_sample': lives
        .take(5)
        .map(
          (l) => {
            'id': l['id'],
            'status': l['status'],
            'is_active': l['is_active'],
            'title': l['title'],
            'created_at': l['created_at'],
            'error': l['error'],
          },
        )
        .toList(),
    'homonym_evidence_preserved': {
      'monteiro_A': '61593383837043',
      'monteiro_B': '61590785557757',
      'note':
          'Prova A já feita — não exige FB Login nas Cláudias. GATE OAuth = só Mariana.',
    },
    'gate1_status': 'PENDING — correr após login FB Mariana + comentário + sonda',
    'claim_sql': 'PROVISIONAL — não aplicar até GATE1=SIM',
  };

  final dir = Directory(
    'tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas',
  );
  dir.createSync(recursive: true);
  final file = File('${dir.path}/E2E_MARIANA_PREP_LATEST.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: ${file.path}');
}

Future<Map<String, dynamic>> _findMariana({
  required String url,
  required String serviceRoleKey,
}) async {
  // Paginate admin users looking for Mariana / Soares / facebook identity
  final matches = <Map<String, dynamic>>[];
  for (var page = 1; page <= 5; page++) {
    final res = await http.get(
      Uri.parse('$url/auth/v1/admin/users?page=$page&per_page=200'),
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    if (res.statusCode >= 400) {
      return {
        'ok': false,
        'error': 'admin_users ${res.statusCode}',
        'body': res.body.substring(0, res.body.length.clamp(0, 200)),
      };
    }
    final body = jsonDecode(res.body);
    final users = body is Map ? (body['users'] as List? ?? const []) : const [];
    if (users.isEmpty) break;
    for (final u in users) {
      if (u is! Map) continue;
      final email = (u['email'] ?? '').toString().toLowerCase();
      final meta = u['user_metadata'] is Map
          ? Map<String, dynamic>.from(u['user_metadata'] as Map)
          : <String, dynamic>{};
      final name = '${meta['full_name'] ?? meta['name'] ?? ''}'.toLowerCase();
      final identities = (u['identities'] as List?) ?? const [];
      final hasFb = identities.any(
        (i) => i is Map && (i['provider']?.toString() ?? '') == 'facebook',
      );
      final hitName =
          name.contains('mariana') ||
          name.contains('soares') ||
          email.contains('mariana') ||
          email.contains('soares');
      if (!hitName && !hasFb) continue;
      if (!hitName && hasFb) {
        // keep facebook users with soares-like identity_data
        final fb = identities.whereType<Map>().where(
          (i) => (i['provider']?.toString() ?? '') == 'facebook',
        );
        final fbName = fb
            .map((i) {
              final d = i['identity_data'];
              if (d is! Map) return '';
              return '${d['name'] ?? d['full_name'] ?? ''}'.toLowerCase();
            })
            .join(' ');
        if (!fbName.contains('mariana') && !fbName.contains('soares')) {
          continue;
        }
      }
      final fbIdentities = identities
          .whereType<Map>()
          .where((i) => (i['provider']?.toString() ?? '') == 'facebook')
          .map((i) {
            final d = i['identity_data'] is Map
                ? Map<String, dynamic>.from(i['identity_data'] as Map)
                : <String, dynamic>{};
            return {
              'provider': i['provider'],
              'provider_id': i['provider_id']?.toString(),
              'identity_data_id': d['id']?.toString(),
              'identity_data_name': d['name']?.toString() ?? d['full_name']?.toString(),
              'identity_data_email': d['email']?.toString(),
            };
          })
          .toList();
      matches.add({
        'id': u['id'],
        'email': u['email'],
        'full_name': meta['full_name'] ?? meta['name'],
        'has_facebook_identity': fbIdentities.isNotEmpty,
        'facebook': fbIdentities,
      });
    }
  }

  // Prefer exact Mariana Soares with facebook
  matches.sort((a, b) {
    final af = a['has_facebook_identity'] == true ? 0 : 1;
    final bf = b['has_facebook_identity'] == true ? 0 : 1;
    if (af != bf) return af.compareTo(bf);
    final an = '${a['full_name']}'.toLowerCase();
    final bn = '${b['full_name']}'.toLowerCase();
    final ascore = an.contains('mariana') && an.contains('soares') ? 0 : 1;
    final bscore = bn.contains('mariana') && bn.contains('soares') ? 0 : 1;
    return ascore.compareTo(bscore);
  });

  if (matches.isEmpty) {
    return {
      'ok': false,
      'error': 'mariana_not_found_in_first_1000_users',
      'hint': 'Mariana precisa de Facebook Login pelo menos uma vez na Fleaber staging',
    };
  }

  final best = matches.first;
  return {
    'ok': true,
    'selected': best,
    'candidates_count': matches.length,
    'candidates_preview': matches.take(5).toList(),
  };
}
