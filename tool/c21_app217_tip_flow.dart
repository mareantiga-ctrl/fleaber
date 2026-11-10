// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C21_APP217_TIP';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  var buyerId = env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  if (!isUuid(sellerId)) sellerId = await sb.userIdForAccessToken(sellerToken);
  if (!isUuid(buyerId)) buyerId = await sb.userIdForAccessToken(buyerToken);

  final live = await sb.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': 'maestro-smoke-staging-playback',
  });
  final liveId = live['id']!.toString();

  final createdTip = await sb.rpc(
    'batata_create_live_tip_pending',
    {
      'p_live_id': liveId,
      'p_seller_id': sellerId,
      'p_amount': 2,
      'p_message': 'C21 tip test',
      'p_stripe_session_id': 'c21-tip-${DateTime.now().millisecondsSinceEpoch}',
    },
    accessToken: buyerToken,
  );
  final tipId = createdTip.toString();

  final settledSession = 'c21-tip-settled-${DateTime.now().millisecondsSinceEpoch}';
  final settled = await sb.rpc(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': tipId,
      'p_stripe_session_id': settledSession,
    },
  );

  final tipRows = await sb.select('live_tips', filter: 'id=eq.$tipId', limit: 1);
  final tip = tipRows.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(tipRows.first);
  final liveMsgs = await sb.select(
    'live_messages',
    filter: 'live_id=eq.$liveId&kind=eq.tip&order=created_at.desc',
    limit: 5,
  );
  final buyerWalletId = buyerId;
  final sellerWalletId = sellerId;
  final buyerTx = buyerWalletId.isEmpty
      ? <Map<String, dynamic>>[]
      : await sb.select(
          'wallet_transactions',
          filter: 'wallet_id=eq.$buyerWalletId&type=eq.gorjeta_enviada&order=created_at.desc',
          limit: 3,
        );
  final sellerTx = sellerWalletId.isEmpty
      ? <Map<String, dynamic>>[]
      : await sb.select(
          'wallet_transactions',
          filter: 'wallet_id=eq.$sellerWalletId&type=eq.gorjeta_recebida&order=created_at.desc',
          limit: 3,
        );

  final outDir = Directory('tool/reports/battery_c21_2026-08-19/bd');
  await outDir.create(recursive: true);
  final outFile = File('${outDir.path}/c21_app217_tip_flow.json');
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'live_id': liveId,
    'tip_id': tipId,
    'settled_return': settled,
    'tip_row': tip,
    'live_tip_messages_count': liveMsgs.length,
    'live_tip_messages_sample': liveMsgs,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'buyer_tip_tx': buyerTx,
    'seller_tip_tx': sellerTx,
    'pass_bd': tip['status'] == 'completed' && liveMsgs.isNotEmpty,
  }));
  print('wrote ${outFile.path}');
}
