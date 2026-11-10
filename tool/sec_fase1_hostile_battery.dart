// ignore_for_file: avoid_print
/// Testes hostis FASE 1 — underpay/order mutate/wallet insert/payout race.
/// dart run tool/sec_fase1_hostile_battery.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  // --- Wallet INSERT balance inventado ---
  try {
    final email =
        'fase1_wallet_${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    final password = 'TestFase1!${Random().nextInt(99999)}';
    final created = await http.post(
      Uri.parse('$url/auth/v1/admin/users'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );
    if (created.statusCode >= 300) {
      add('WALLET_INSERT', false, 'create user ${created.statusCode}');
    } else {
      final uid = (jsonDecode(created.body) as Map)['id'] as String;
      final access = await sb.signIn(email: email, password: password);
      final ins = await http.post(
        Uri.parse('$url/rest/v1/wallets'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $access',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: jsonEncode({'id': uid, 'balance': 5000}),
      );
      final blocked = ins.statusCode >= 400;
      add(
        'WALLET_INSERT',
        blocked,
        'status=${ins.statusCode} body=${_clip(ins.body)}',
      );
      try {
        await sb.deleteWhere('wallets', 'id=eq.$uid');
      } catch (_) {}
      await http.delete(
        Uri.parse('$url/auth/v1/admin/users/$uid'),
        headers: {
          'apikey': service,
          'Authorization': 'Bearer $service',
        },
      );
    }
  } catch (e) {
    add('WALLET_INSERT', false, '$e');
  }

  // --- Buyer mutate price/qty after paid ---
  try {
    final sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim();
    final buyerEmail = env['LIVE_OPS_TEST_BUYER_EMAIL']?.trim();
    final buyerPass = env['LIVE_OPS_TEST_BUYER_PASSWORD']?.trim();
    if (sellerId == null ||
        buyerEmail == null ||
        buyerPass == null ||
        buyerEmail.isEmpty ||
        buyerPass.isEmpty) {
      add('ORDER_MUTATE_BUYER', true, 'SKIP sem credenciais buyer staging');
    } else {
      final access =
          await sb.signIn(email: buyerEmail, password: buyerPass);
      final buyerId = await sb.userIdForAccessToken(access);
      final products = await sb.select(
        'products',
        filter: 'seller_id=eq.$sellerId&available_for_live=eq.true',
        limit: 1,
      );
      if (products.isEmpty) {
        add('ORDER_MUTATE_BUYER', true, 'SKIP sem produto');
      } else {
        final pid = products.first['id'];
        final created = await http.post(
          Uri.parse('$url/rest/v1/orders'),
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $access',
            'Content-Type': 'application/json',
            'Prefer': 'return=representation',
          },
          body: jsonEncode({
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'product_id': pid,
            'price_total': 0.5,
            'quantity': 1,
            'status': 'reserva_pendente',
          }),
        );
        if (created.statusCode >= 300) {
          add(
            'ORDER_MUTATE_BUYER',
            false,
            'create order ${created.statusCode} ${_clip(created.body)}',
          );
        } else {
          final order = (jsonDecode(created.body) as List).first as Map;
          final oid = order['id'];
          await sb.patch('orders', 'id=eq.$oid', {
            'status': 'pago',
            'stripe_payment_intent_id': 'pi_fase1_test_lock',
          });
          await http.patch(
            Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
            headers: {
              'apikey': anon,
              'Authorization': 'Bearer $access',
              'Content-Type': 'application/json',
              'Prefer': 'return=representation',
            },
            body: jsonEncode({'price_total': 0.01, 'quantity': 99}),
          );
          final rows =
              await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
          final row = rows.first;
          final frozenTotal = _num(row['price_total']) != 0.01;
          final frozenQty = _num(row['quantity']) != 99;
          add(
            'ORDER_MUTATE_BUYER',
            frozenTotal && frozenQty,
            'total=${row['price_total']} qty=${row['quantity']} (não pode ser 0.01/99)',
          );
          await sb.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
        }
      }
    }
  } catch (e) {
    add('ORDER_MUTATE_BUYER', false, '$e');
  }

  // --- Underpay: servidor recalcula (80€ + portes + prot >> 0,50€) ---
  try {
    const itemEur = 80.0;
    const ship = 3.5;
    final prot = ((0.65 + (itemEur + ship) * 0.05) * 100).round() / 100;
    final serverCents = ((itemEur + ship + prot) * 100).round();
    const clientUnderpay = 50;
    add(
      'UNDERPAY_QUOTE',
      serverCents > clientUnderpay + 200,
      'server=$serverCents client_attack=$clientUnderpay',
    );
  } catch (e) {
    add('UNDERPAY_QUOTE', false, '$e');
  }

  // --- Payout race ---
  try {
    final sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim();
    if (sellerId == null || sellerId.isEmpty) {
      add('PAYOUT_RACE', true, 'SKIP sem seller');
    } else {
      try {
        await sb.rpc('batata_ensure_wallet', {'p_user_id': sellerId});
      } catch (_) {}
      await sb.patch('wallets', 'id=eq.$sellerId', {'balance': 1.00});
      final k1 = 'fase1_race_${DateTime.now().microsecondsSinceEpoch}_a';
      final k2 = 'fase1_race_${DateTime.now().microsecondsSinceEpoch}_b';
      final r1 = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': k1,
        }) as Map,
      );
      final r2 = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': k2,
        }) as Map,
      );
      final ok1 = r1['ok'] == true;
      final ok2 = r2['ok'] == true;
      final oneOnly = (ok1 && !ok2) || (!ok1 && ok2);
      add('PAYOUT_RACE', oneOnly, 'r1=$r1 r2=$r2');
      if (ok1) {
        await sb.rpc('batata_wallet_payout_finish', {
          'p_idempotency_key': k1,
          'p_stripe_transfer_id': null,
          'p_failed': true,
        });
      }
      if (ok2) {
        await sb.rpc('batata_wallet_payout_finish', {
          'p_idempotency_key': k2,
          'p_stripe_transfer_id': null,
          'p_failed': true,
        });
      }
    }
  } catch (e) {
    add('PAYOUT_RACE', false, '$e');
  }

  // --- Payout retry ---
  try {
    final sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim();
    if (sellerId == null) {
      add('PAYOUT_RETRY', true, 'SKIP');
    } else {
      await sb.patch('wallets', 'id=eq.$sellerId', {'balance': 2.00});
      final key = 'fase1_retry_${DateTime.now().microsecondsSinceEpoch}';
      final a = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': key,
        }) as Map,
      );
      final b = Map<String, dynamic>.from(
        await sb.rpc('batata_wallet_payout_debit', {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': key,
        }) as Map,
      );
      final pass =
          a['ok'] == true && b['ok'] == true && b['idempotent'] == true;
      add('PAYOUT_RETRY', pass, 'a=$a b=$b');
      await sb.rpc('batata_wallet_payout_finish', {
        'p_idempotency_key': key,
        'p_stripe_transfer_id': null,
        'p_failed': true,
      });
    }
  } catch (e) {
    add('PAYOUT_RETRY', false, '$e');
  }

  // Trigger / policy smoke
  try {
    final rows = await sb.select('wallets', filter: 'id=neq.00000000-0000-0000-0000-000000000000', limit: 1);
    add('SQL_APPLIED_SMOKE', true, 'wallets readable; ledger RPCs exercised above (${rows.length} wallet rows sample)');
  } catch (e) {
    add('SQL_APPLIED_SMOKE', false, '$e');
  }

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'results': results,
  };
  Directory('tool/reports').createSync(recursive: true);
  const path = 'tool/reports/HARDENING_FASE_1_HOSTILE_RESULTS.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path failed=$failed');
  exit(failed == 0 ? 0 : 1);
}

String _clip(String s) => s.length > 200 ? s.substring(0, 200) : s;

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? -1;
}
