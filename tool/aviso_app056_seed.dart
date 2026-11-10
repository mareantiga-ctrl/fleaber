// ignore_for_file: avoid_print
/// Seed APP-056: encomenda enviada → concluido + card reservation_order_completed no chat.
/// Não toca no bundle APP-065 (b2563d6c). Preferir encomenda individual pago/enviado.
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
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  const skipBundle = 'b2563d6c-dfa3-4c0b-9878-aaefded39a2d';

  // Já concluido com card?
  final existing = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&status=in.(concluido,entregue)&order=created_at.desc',
    limit: 20,
  );
  for (final o in existing) {
    final bid = (o['bundle_id'] ?? '').toString();
    if (bid == skipBundle) continue;
    final oid = o['id'].toString();
    final msgs = await sb.select(
      'chat_messages',
      filter: 'text=like.*reservation_order_completed*&order=created_at.desc',
      limit: 50,
    );
    for (final m in msgs) {
      final t = (m['text'] ?? '').toString();
      if (!t.contains(oid)) continue;
      final out = {
        'mode': 'reuse',
        'order_id': oid,
        'chat_id': m['chat_id'],
        'status': o['status'],
        'product_id': o['product_id'],
      };
      await _write(out);
      print(jsonEncode(out));
      return;
    }
  }

  // Preferir enviado individual (não bundle 065)
  final enviado = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyer&seller_id=eq.$seller&status=eq.enviado&order=created_at.desc',
    limit: 20,
  );
  Map<String, dynamic>? pick;
  for (final o in enviado) {
    final bid = (o['bundle_id'] ?? '').toString();
    if (bid == skipBundle || bid.isNotEmpty) continue;
    pick = o;
    break;
  }
  // Fallback: qualquer pago individual
  if (pick == null) {
    final pago = await sb.select(
      'orders',
      filter:
          'buyer_id=eq.$buyer&seller_id=eq.$seller&status=eq.pago&order=created_at.desc',
      limit: 20,
    );
    for (final o in pago) {
      final bid = (o['bundle_id'] ?? '').toString();
      if (bid.isNotEmpty) continue;
      pick = o;
      break;
    }
  }
  if (pick == null) {
    final out = {'mode': 'none', 'error': 'sem encomenda individual enviada/paga'};
    await _write(out);
    print(jsonEncode(out));
    exit(2);
  }

  final oid = pick['id'].toString();
  final productId = pick['product_id']?.toString() ?? '';

  // chat_id via mensagem recente do order ou chats buyer-seller
  String? chatId;
  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.*$oid*&order=created_at.desc',
    limit: 5,
  );
  if (msgs.isNotEmpty) {
    chatId = msgs.first['chat_id']?.toString();
  }
  if (chatId == null || chatId.isEmpty) {
    final chats = await sb.select(
      'chats',
      filter:
          'or=(and(user1_id.eq.$buyer,user2_id.eq.$seller),and(user1_id.eq.$seller,user2_id.eq.$buyer))&order=created_at.desc',
      limit: 5,
    );
    if (chats.isNotEmpty) chatId = chats.first['id']?.toString();
  }
  if (chatId == null || chatId.isEmpty) {
    final out = {'mode': 'none', 'error': 'sem chat_id', 'order_id': oid};
    await _write(out);
    print(jsonEncode(out));
    exit(2);
  }

  await sb.patch('orders', 'id=eq.$oid', {'status': 'concluido'});

  final payload = {
    'kind': 'reservation_order_completed',
    'order_id': oid,
    'v': 1,
  };
  await sb.insert('chat_messages', {
    'sender_id': buyer,
    'receiver_id': seller,
    'is_read': false,
    'text': 'FLEABER_JSON_V1:${jsonEncode(payload)}',
    'chat_id': chatId,
    'is_reservation': true,
  });

  final out = {
    'mode': 'seeded',
    'order_id': oid,
    'chat_id': chatId,
    'product_id': productId,
    'status': 'concluido',
    'expected_seller_phrase':
        'O comprador confirmou a receção. Venda concluída. Podes avaliar o cliente.',
  };
  await _write(out);
  print(jsonEncode(out));
}

Future<void> _write(Map<String, dynamic> out) async {
  final dir = Directory('tool/reports/battery_aviso_2026-08-23/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/app056_seed.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(out)}\n');
}
