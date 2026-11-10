// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

/// Evidência bruta C9 para auditoria externa (sem passwords).
void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final helpersAsSeller = await client.select(
    'seller_helpers',
    filter: 'seller_id=eq.$seller',
    limit: 50,
  );
  final helpersAsHelper = await client.select(
    'seller_helpers',
    filter: 'helper_user_id=eq.$seller',
    limit: 50,
  );
  final follows = await client.select(
    'follows',
    filter: 'follower_id=eq.$buyer&following_id=eq.$seller',
    limit: 10,
  );
  final followCount = await client.select(
    'follows',
    filter: 'following_id=eq.$seller',
    limit: 100,
  );
  final reviews = await client.select(
    'reviews',
    filter: 'target_id=eq.$seller&order=created_at.desc',
    limit: 10,
  );
  final wallets = await client.select(
    'wallets',
    filter: 'id=eq.$seller',
    limit: 1,
  );
  final tx = await client.select(
    'wallet_transactions',
    filter: 'wallet_id=eq.$seller&order=created_at.desc',
    limit: 20,
  );
  final retainedOrders = await client.select(
    'orders',
    filter:
        'seller_id=eq.$seller&status=in.(pago,enviado,em_devolucao)&order=created_at.desc',
    limit: 80,
  );
  final profiles = await client.select(
    'profiles',
    filter: 'id=eq.$seller',
    limit: 1,
  );

  final retainedOpen = retainedOrders.where((o) {
    return o['wallet_release_processed_at'] == null;
  }).toList();
  final retainedSum = retainedOpen.fold<double>(0, (s, o) {
    final v = o['price_total'];
    if (v is num) return s + v.toDouble();
    return s + (double.tryParse('$v') ?? 0);
  });

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'seller_id': seller,
    'buyer_id': buyer,
    'app128_seller_helpers_as_owner': helpersAsSeller,
    'app128_seller_helpers_as_helper': helpersAsHelper,
    'app114_follow_buyer_to_seller': follows,
    'app114_followers_of_seller_count': followCount.length,
    'app113_reviews': reviews
        .map((r) => {
              'id': r['id'],
              'stars': r['stars'] ?? r['rating'],
              'created_at': r['created_at'],
              'buyer_id': r['buyer_id'],
              'comment_len': (r['comment']?.toString() ?? '').length,
            })
        .toList(),
    'app140_wallet': wallets,
    'app141_wallet_transactions': tx
        .map((r) => {
              'id': r['id'],
              'amount': r['amount'],
              'type': r['type'],
              'description': r['description'],
              'created_at': r['created_at'],
              'order_id': r['order_id'],
            })
        .toList(),
    'app140_retained_orders_open': retainedOpen
        .map((o) => {
              'id': o['id'],
              'status': o['status'],
              'price_total': o['price_total'],
              'wallet_release_processed_at': o['wallet_release_processed_at'],
              'product_id': o['product_id'],
            })
        .toList(),
    'app140_retained_sum': retainedSum,
    'app121_profile_shipping_present': profiles.isEmpty
        ? null
        : {
            'full_name': profiles.first['full_name'],
            'followers_count': profiles.first['followers_count'],
            'has_legal_name':
                (profiles.first['legal_full_name']?.toString() ?? '')
                    .trim()
                    .isNotEmpty,
            'has_shipping_line1':
                (profiles.first['shipping_line1']?.toString() ?? '')
                    .trim()
                    .isNotEmpty,
            'shipping_city': profiles.first['shipping_city'],
            'shipping_postal_code': profiles.first['shipping_postal_code'],
            'shipping_country': profiles.first['shipping_country'],
          },
  };

  final dir = Directory('tool/reports/battery_c8_2026-08-17/evidence');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/c9_gpt_audit_evidence.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${file.path}');
  print(const JsonEncoder.withIndent('  ').convert({
    'helpers_as_owner': helpersAsSeller.length,
    'helpers_as_helper': helpersAsHelper.length,
    'follow_rows': follows.length,
    'followers_count_query': followCount.length,
    'reviews': reviews.length,
    'wallet_balance': wallets.isEmpty ? null : wallets.first['balance'],
    'tx_count': tx.length,
    'retained_open': retainedOpen.length,
    'retained_sum': retainedSum,
  }));
}
