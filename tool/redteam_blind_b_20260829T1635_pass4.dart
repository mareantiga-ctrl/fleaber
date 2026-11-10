library;

import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';
import 'package:http/http.dart' as http;

void main() async {
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyer = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final seller = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final names = <(String, Map<String, dynamic>)>[
    ('staging_nuke_user_data', {'p_user_id': sellerId}),
    ('staging_restore_stock_before_nuke', {'p_user_id': sellerId}),
    ('set_active_live_item', {
      'p_live_id': '5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234',
      'p_live_item_id': 'a4e89203-f0d6-4df2-a76a-e01435065b5f',
    }),
    ('batata_staging_set_fleahub_test_state', {}),
    ('batata_sync_live_item_for_order', {
      'p_order_id': '59f1272e-6e50-430c-b574-6698a693b54f',
    }),
    ('batata_update_live_item', {
      'p_live_item_id': 'a4e89203-f0d6-4df2-a76a-e01435065b5f',
    }),
    ('batata_tick_live_raffle', {
      'p_raffle_id': '0484ddbe-dc55-44f7-b453-0a6b6f3f2513',
    }),
    ('get_seller_stats', {'p_seller_id': sellerId}),
    ('batata_ensure_draft_live', {}),
    ('batata_live_bag_update_qty', {
      'p_request_id': '4a013d5d-3110-4520-9662-f708c752cd80',
      'p_qty': 99,
    }),
  ];
  final out = <Map<String, dynamic>>[];
  for (final tok in [('buyer', buyer), ('seller', seller)]) {
    for (final n in names) {
      final r = await http.post(
        Uri.parse('${c.url}/rest/v1/rpc/${n.$1}'),
        headers: {
          'apikey': c.anonKey,
          'Authorization': 'Bearer ${tok.$2}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(n.$2),
      );
      out.add({
        'who': tok.$1,
        'rpc': n.$1,
        'status': r.statusCode,
        'body': r.body.length > 280 ? '${r.body.substring(0, 280)}…' : r.body,
      });
      stderr.writeln('${tok.$1} ${n.$1} ${r.statusCode} ${r.body.length > 120 ? r.body.substring(0, 120) : r.body}');
    }
  }
  File('tool/redteam_blind_b_20260829T1635_pass4.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
}
