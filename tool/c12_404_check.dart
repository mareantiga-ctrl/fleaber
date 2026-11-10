// ignore_for_file: avoid_print
/// C12 APP-088 / APP-404 — DM + encomendas após aceite live.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const liveId = '62e189f2-9744-40f7-8a4b-166d7446c8ff';
  const buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const productId = 'a54ad25d-55ca-4e73-95cd-368f697d5869';
  const liveItemId = '1e77af96-073d-4186-9da5-d47915e08142';
  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final reservations = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 20,
  );
  final ordersByProduct = await client.select(
    'orders',
    filter: 'product_id=eq.$productId&buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 10,
  );
  final ordersByLiveItem = await client.select(
    'orders',
    filter: 'live_item_id=eq.$liveItemId&order=created_at.desc',
    limit: 10,
  );
  List<Map<String, dynamic>> chats = [];
  try {
    chats = await client.select(
      'chats',
      filter: 'or=(user_a.eq.$buyerId,user_b.eq.$buyerId)&order=created_at.desc',
      limit: 20,
    );
  } catch (e) {
    chats = [
      {'error': e.toString()},
    ];
  }
  final msgsAccepted = await client.select(
    'chat_messages',
    filter: 'text=ilike.*reservation_accepted*&order=created_at.desc',
    limit: 10,
  );
  final msgsC12 = await client.select(
    'chat_messages',
    filter: 'text=ilike.*C12 Produto A*&order=created_at.desc',
    limit: 10,
  );
  final liveMsgs = await client.select(
    'live_messages',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 30,
  );

  Map<String, dynamic> slimRes(Map<String, dynamic> r) => {
        'id': r['id'],
        'status': r['status'],
        'notes': r['notes'],
        'requested_qty': r['requested_qty'],
        'created_at': r['created_at'],
      };
  Map<String, dynamic> slimOrder(Map<String, dynamic> r) => {
        'id': r['id'],
        'status': r['status'],
        'total': r['total'] ?? r['amount'] ?? r['price'],
        'product_id': r['product_id'],
        'live_item_id': r['live_item_id'],
        'created_at': r['created_at'],
      };
  Map<String, dynamic> slimMsg(Map<String, dynamic> r) => {
        'id': r['id'],
        'kind': r['kind'],
        'text': (r['text'] ?? r['content'] ?? '').toString().substring(
              0,
              ((r['text'] ?? r['content'] ?? '').toString().length).clamp(0, 180),
            ),
        'chat_id': r['chat_id'],
        'sender_id': r['sender_id'],
        'created_at': r['created_at'],
      };

  final out = {
    'seller_id': sellerId,
    'reservations': reservations.map(slimRes).toList(),
    'orders_by_product': ordersByProduct.map(slimOrder).toList(),
    'orders_by_live_item': ordersByLiveItem.map(slimOrder).toList(),
    'chats_count': chats.length,
    'chats_sample': chats.take(5).map((c) => {
          'id': c['id'],
          'user_a': c['user_a'],
          'user_b': c['user_b'],
        }).toList(),
    'chat_messages_reservation_accepted': msgsAccepted.map(slimMsg).toList(),
    'chat_messages_c12': msgsC12.map(slimMsg).toList(),
    'live_messages': liveMsgs.take(15).map((m) => {
          'id': m['id'],
          'body': m['body'] ?? m['text'] ?? m['message'],
          'kind': m['kind'] ?? m['type'],
          'created_at': m['created_at'],
        }).toList(),
  };

  final dir = Directory('tool/reports/battery_c12_2026-08-18/bd');
  dir.createSync(recursive: true);
  File('${dir.path}/c12_088_404.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert({
    'res': reservations.map(slimRes).toList(),
    'orders_product': ordersByProduct.length,
    'orders_live_item': ordersByLiveItem.length,
    'msgs_accepted': msgsAccepted.length,
    'msgs_c12': msgsC12.length,
    'live_msgs': liveMsgs.length,
  }));
  print('wrote tool/reports/battery_c12_2026-08-18/bd/c12_088_404.json');
}
