// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

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
  if (!isUuid(sellerId)) sellerId = await sb.userIdForAccessToken(sellerToken);
  if (!isUuid(buyerId)) {
    final t = await sb.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await sb.userIdForAccessToken(t);
  }

  final aChats = await sb.select('chats', filter: 'user_a=eq.$sellerId&user_b=eq.$buyerId&order=last_message_time.desc', limit: 1);
  final bChats = await sb.select('chats', filter: 'user_a=eq.$buyerId&user_b=eq.$sellerId&order=last_message_time.desc', limit: 1);
  final chat = (aChats.isNotEmpty ? aChats.first : (bChats.isNotEmpty ? bChats.first : <String, dynamic>{}));
  if ((chat['id'] ?? '').toString().isEmpty) {
    throw StateError('chat not found between test buyer/seller');
  }
  final chatId = chat['id'].toString();

  final payload = {
    'kind': 'bundle_proposal_outcome',
    'outcome': 'accepted',
    'bundle_total': 26.06,
    'currency': 'EUR',
    'v': 1,
  };
  final messageText = 'FLEABER_JSON_V1:${jsonEncode(payload)}';
  final msg = await sb.insert('chat_messages', {
    'chat_id': chatId,
    'sender_id': sellerId,
    'text': messageText,
  });

  await sb.patch('chats', 'id=eq.$chatId', {
    'last_message': 'Proposta de conjunto aceite',
    'last_message_time': DateTime.now().toUtc().toIso8601String(),
  });

  final outDir = Directory('tool/reports/battery_c21_2026-08-19/bd');
  await outDir.create(recursive: true);
  final out = File('${outDir.path}/c21_app084_seed_outcome.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'chat_id': chatId,
    'message_id': msg['id'],
    'payload': payload,
  }));
  print('wrote ${out.path}');
}
