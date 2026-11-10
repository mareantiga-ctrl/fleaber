// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

/// Snapshot C9 restante (helpers, wallet, emails) — sem passwords.
void main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final serviceRoleKey = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: serviceRoleKey,
  );
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  Future<Map<String, dynamic>?> authUser(String id) async {
    final res = await http.get(
      Uri.parse('$url/auth/v1/admin/users/$id'),
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    if (res.statusCode >= 400) {
      return {'error': res.statusCode, 'body': res.body};
    }
    final map = jsonDecode(res.body);
    if (map is Map) {
      return {
        'id': map['id'],
        'email': map['email'],
        'email_confirmed_at': map['email_confirmed_at'],
      };
    }
    return null;
  }

  final helpers = await client.select(
    'seller_helpers',
    filter: 'seller_id=eq.$seller',
    limit: 20,
  );
  final wallets = await client.select(
    'wallets',
    filter: 'id=eq.$seller',
    limit: 1,
  );
  final tx = await client.select(
    'wallet_transactions',
    filter: 'wallet_id=eq.$seller&order=created_at.desc',
    limit: 5,
  );

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'seller': await authUser(seller),
    'buyer': await authUser(buyer),
    'seller_helpers': helpers,
    'wallet': wallets,
    'wallet_tx_head': tx
        .map((r) => {
              'id': r['id'],
              'amount': r['amount'],
              'type': r['type'],
              'description': r['description'],
              'created_at': r['created_at'],
            })
        .toList(),
  };

  final dir = Directory('tool/reports/battery_c9_2026-08-18/evidence');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/c9_remaining_snapshot.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${file.path}');
  print(const JsonEncoder.withIndent('  ').convert({
    'seller_email': (out['seller'] as Map?)?['email'],
    'buyer_email': (out['buyer'] as Map?)?['email'],
    'helpers': helpers.length,
    'helpers_status': helpers.map((h) => h['invitation_status']).toList(),
    'stripe_account_id': wallets.isEmpty ? null : wallets.first['stripe_account_id'],
    'balance': wallets.isEmpty ? null : wallets.first['balance'],
    'tx_count_head': tx.length,
  }));
}
