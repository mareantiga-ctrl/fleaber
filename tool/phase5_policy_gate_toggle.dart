// ignore_for_file: avoid_print
/// Temporarily clear seller policy for gate screenshot, or restore.
/// dart run tool/phase5_policy_gate_toggle.dart clear|restore
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'clear' : args.first.trim();
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final bak = File(
    '14-unified-commerce-phase5-live-seller-studio/raw/policy_backup.json',
  );

  if (mode == 'clear') {
    final rows = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    await bak.writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
    if (rows.isNotEmpty) {
      await client.deleteWhere(
        'seller_reservation_settings',
        'seller_id=eq.$sellerId',
      );
    }
    print('CLEARED seller policy (backup ${bak.path})');
    return;
  }

  if (mode == 'restore') {
    if (!bak.existsSync()) {
      stderr.writeln('no backup');
      exit(1);
    }
    final rows = (jsonDecode(await bak.readAsString()) as List)
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    if (existing.isEmpty && rows.isNotEmpty) {
      final r = rows.first;
      await client.insert('seller_reservation_settings', {
        'seller_id': sellerId,
        'policy_mode': r['policy_mode'] ?? 'trust',
        'untrusted_mode': r['untrusted_mode'] ?? 'approval',
        'normal_ttl_seconds': r['normal_ttl_seconds'] ?? 3600,
        'trusted_ttl_seconds': r['trusted_ttl_seconds'] ?? 86400,
        'accept_fleaber_global_trust': r['accept_fleaber_global_trust'] ?? true,
        'configured_at':
            r['configured_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': sellerId,
        'policy_mode': 'trust',
        'untrusted_mode': 'approval',
        'normal_ttl_seconds': 3600,
        'trusted_ttl_seconds': 86400,
        'accept_fleaber_global_trust': true,
        'configured_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    print('RESTORED seller policy');
    return;
  }

  stderr.writeln('usage: clear|restore');
  exit(2);
}
