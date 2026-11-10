// ignore_for_file: avoid_print
/// Preflight bateria AVISO — IDs de encomenda/chat/bundle na staging.
///
/// Casos: APP-031, 043/083, 055, 056, 086, SEC-025.
/// Notas: SEC-008/013/019 = skip_ps; APP-218/SEC-020 = live_needed.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _reportDir = 'tool/reports/battery_aviso_2026-08-23/bd';
const _preferredBundlePrefix = 'b2563d6c';

String _statusKey(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(' ', '_');

bool _isMbWayOrDirecto(String? method) {
  final m = (method ?? '').toLowerCase();
  return m.contains('mb') ||
      m.contains('way') ||
      m.contains('direct') ||
      m.contains('transf');
}

bool _isOpenDispute(String? status) {
  final s = _statusKey(status);
  if (s.isEmpty) return true;
  const closed = {
    'closed',
    'resolved',
    'cancelled',
    'canceled',
    'rejected',
    'expired',
  };
  return !closed.contains(s);
}

bool _hasPartialRefundOffer(Map<String, dynamic> d) {
  final offer = (d['seller_offer_type'] ?? '').toString().toLowerCase();
  return offer == 'partial_refund' ||
      offer == 'return_and_partial_refund' ||
      d['seller_refund_percent'] != null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final orders = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyerId&seller_id=eq.$sellerId&order=created_at.desc',
    limit: 300,
  );

  Future<Map<String, dynamic>?> chatForOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    final productId = order['product_id']?.toString() ?? '';
    final bundleId = order['bundle_id']?.toString() ?? '';

    // Prefer chat linked via product (same pattern as fail_battery_preflight).
    if (productId.isNotEmpty) {
      final chats = await sb.select(
        'chats',
        filter:
            'product_id=eq.$productId&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
        limit: 5,
      );
      if (chats.isNotEmpty) {
        return {
          'chat_id': chats.first['id'],
          'order_id': orderId,
          'product_id': productId,
          'bundle_id': bundleId.isEmpty ? null : bundleId,
          'seller_id': sellerId,
          'buyer_id': buyerId,
        };
      }
    }

    // Fallback: any chat between buyer/seller (bundle threads often lack product_id).
    final chats = await sb.select(
      'chats',
      filter:
          'or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))&order=last_message_time.desc.nullslast',
      limit: 10,
    );
    if (chats.isEmpty) return null;
    return {
      'chat_id': chats.first['id'],
      'order_id': orderId,
      'product_id': productId.isEmpty ? null : productId,
      'bundle_id': bundleId.isEmpty ? null : bundleId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
    };
  }

  Future<Map<String, dynamic>?> pickOrder({
    required bool Function(Map<String, dynamic>) match,
    bool preferMbWay = false,
    String? preferBundleIdContains,
  }) async {
    final matched = orders.where(match).toList();
    if (preferMbWay) {
      matched.sort((a, b) {
        final am = _isMbWayOrDirecto(a['payment_method']?.toString()) ? 0 : 1;
        final bm = _isMbWayOrDirecto(b['payment_method']?.toString()) ? 0 : 1;
        return am.compareTo(bm);
      });
    }
    if (preferBundleIdContains != null && preferBundleIdContains.isNotEmpty) {
      matched.sort((a, b) {
        final ab = (a['bundle_id'] ?? '').toString();
        final bb = (b['bundle_id'] ?? '').toString();
        final ap = ab.startsWith(preferBundleIdContains) ? 0 : 1;
        final bp = bb.startsWith(preferBundleIdContains) ? 0 : 1;
        return ap.compareTo(bp);
      });
    }
    for (final o in matched) {
      final chat = await chatForOrder(o);
      if (chat == null) continue;
      return {
        ...chat,
        'order_status': o['status'],
        'payment_method': o['payment_method'],
        'created_at': o['created_at'],
        'price_total': o['price_total'],
      };
    }
    return null;
  }

  // APP-031 — aguarda_confirmacao (prefer MB WAY / directo)
  final app031 = await pickOrder(
    match: (o) => _statusKey(o['status']?.toString()) == 'aguarda_confirmacao',
    preferMbWay: true,
  );

  // APP-055 — pago shippable
  final app055 = await pickOrder(
    match: (o) => _statusKey(o['status']?.toString()) == 'pago',
  );

  // APP-056 — concluido / entregue (seller receipt eco)
  final app056 = await pickOrder(
    match: (o) {
      final st = _statusKey(o['status']?.toString());
      if (st == 'concluido' || st == 'concluído' || st == 'entregue') {
        return true;
      }
      return st.contains('conclu') || st == 'recebido';
    },
  );

  // APP-086 — enviado (prefer bundle b2563d6c)
  final app086 = await pickOrder(
    match: (o) => _statusKey(o['status']?.toString()) == 'enviado',
    preferBundleIdContains: _preferredBundlePrefix,
  );

  // APP-043 / APP-083 — bundle thread (chat via product_ids, não product_id da order)
  Map<String, dynamic>? app043;
  String app043Source = 'none';

  int bundlePriority(Map<String, dynamic> b) {
    final id = (b['id'] ?? '').toString();
    if (id.startsWith(_preferredBundlePrefix)) return 0;
    return 1;
  }

  Future<String?> chatForBundleProducts(List<dynamic>? productIds) async {
    if (productIds == null || productIds.isEmpty) return null;
    for (final raw in productIds) {
      final pid = raw.toString().trim();
      if (pid.isEmpty) continue;
      final chats = await sb.select(
        'chats',
        filter:
            'product_id=eq.$pid&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
        limit: 1,
      );
      if (chats.isNotEmpty) return chats.first['id']?.toString();
    }
    return null;
  }

  Future<String?> chatForBundleIdInMessages(String bundleId) async {
    final msgs = await sb.select(
      'chat_messages',
      filter: 'text=ilike.*$bundleId*&order=created_at.desc',
      limit: 1,
    );
    if (msgs.isEmpty) return null;
    return msgs.first['chat_id']?.toString();
  }

  Future<Map<String, dynamic>?> bundleRowToCase(
    Map<String, dynamic> b, {
    String? note,
  }) async {
    final bundleId = b['id']?.toString() ?? '';
    if (bundleId.isEmpty) return null;
    var chatId = b['chat_id']?.toString().trim() ?? '';
    if (chatId.isEmpty) {
      chatId = await chatForBundleProducts(b['product_ids'] as List?) ?? '';
    }
    if (chatId.isEmpty) {
      chatId = await chatForBundleIdInMessages(bundleId) ?? '';
    }
    if (chatId.isEmpty) return null;

    final bundleOrders = orders
        .where((o) => (o['bundle_id']?.toString() ?? '') == bundleId)
        .toList();
    bundleOrders.sort((a, b) {
      final st = _statusKey(a['status']?.toString());
      final prefer = {'enviado': 0, 'pago': 1, 'concluido': 2};
      return (prefer[st] ?? 9).compareTo(prefer[_statusKey(b['status']?.toString())] ?? 9);
    });
    final orderId =
        bundleOrders.isEmpty ? null : bundleOrders.first['id']?.toString();

    return {
      'bundle_id': bundleId,
      'chat_id': chatId,
      'order_id': orderId,
      'status': b['status'],
      'total_eur': b['total_eur'],
      'product_ids': b['product_ids'],
      'created_at': b['created_at'],
      'seller_id': sellerId,
      'buyer_id': buyerId,
      if (note != null) 'note': note,
    };
  }

  final bundlesAccepted = await sb.select(
    'product_bundles',
    filter:
        'buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=eq.accepted&order=created_at.desc',
    limit: 20,
  );
  bundlesAccepted.sort((a, b) => bundlePriority(a).compareTo(bundlePriority(b)));

  final bundlesPurchased = await sb.select(
    'product_bundles',
    filter:
        'buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=eq.purchased&order=created_at.desc',
    limit: 10,
  );
  bundlesPurchased.sort((a, b) => bundlePriority(a).compareTo(bundlePriority(b)));

  for (final b in bundlesAccepted) {
    final c = await bundleRowToCase(b);
    if (c == null) continue;
    app043 = c;
    app043Source = 'product_bundles.accepted';
    break;
  }
  if (app043 == null) {
    for (final b in bundlesPurchased) {
      final c = await bundleRowToCase(
        b,
        note: 'purchased — card aceite/totais na thread do conjunto',
      );
      if (c == null) continue;
      app043 = c;
      app043Source = 'product_bundles.purchased';
      break;
    }
  }

  // Fallback: bundle preferido por id (chat via product_ids do bundle)
  if (app043 == null) {
    final preferredRows = await sb.select(
      'product_bundles',
      filter: 'id=eq.$_preferredBundlePrefix-dfa3-4c0b-9878-aaefded39a2d',
      limit: 1,
    );
    if (preferredRows.isNotEmpty) {
      final c = await bundleRowToCase(
        preferredRows.first,
        note: 'lookup directo bundle preferido b2563d6c',
      );
      if (c != null) {
        app043 = c;
        app043Source = 'product_bundles.id';
      }
    }
  }

  // SEC-025 — open dispute with partial refund offer
  Map<String, dynamic>? sec025;
  final disputes = await sb.select(
    'order_disputes',
    filter: 'buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 80,
  );
  for (final d in disputes) {
    if (!_isOpenDispute(d['status']?.toString())) continue;
    if (!_hasPartialRefundOffer(d)) continue;
    final orderId = d['order_id']?.toString() ?? '';
    if (orderId.isEmpty) continue;
    final orderRows =
        await sb.select('orders', filter: 'id=eq.$orderId', limit: 1);
    if (orderRows.isEmpty) continue;
    final o = orderRows.first;
    if (o['seller_id']?.toString() != sellerId) continue;
    final chat = await chatForOrder(o);
    if (chat == null) continue;
    sec025 = {
      ...chat,
      'dispute_id': d['id'],
      'dispute_status': d['status'],
      'seller_offer_type': d['seller_offer_type'],
      'seller_refund_percent': d['seller_refund_percent'],
      'order_status': o['status'],
    };
    break;
  }

  final notes = {
    'sec008': {
      'id': 'SEC-008',
      'status': 'skip_ps',
      'reason': 'PS Reader real / pairing PC — fora de âmbito desta bateria',
    },
    'sec013': {
      'id': 'SEC-013',
      'status': 'skip_ps',
      'reason': 'Claim Facebook residual — lab FB fora de âmbito (BATATA)',
    },
    'sec019': {
      'id': 'SEC-019',
      'status': 'skip_ps',
      'reason': 'Extensão PS / CORS real — requer ambiente PS',
    },
    'app218': {
      'id': 'APP-218',
      'status': 'live_needed',
      'reason':
          'Mensagem Hub → TCL exige directo activo; não criar live neste script (BATATA)',
    },
    'sec020': {
      'id': 'SEC-020',
      'status': 'live_needed',
      'reason':
          'FOMO saco stock=1 exige live; não criar live neste script (BATATA)',
    },
  };

  final out = {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'app031': app031,
    'app043': app043,
    'app043_source': app043Source,
    'app055': app055,
    'app056': app056,
    'app083': app043, // same accepted/purchased bundle thread
    'app086': app086,
    'sec025': sec025,
    'notes': notes,
    'counts': {
      'orders_scanned': orders.length,
      'accepted_bundles': bundlesAccepted.length,
      'purchased_bundles': bundlesPurchased.length,
      'disputes_scanned': disputes.length,
    },
  };

  final reportDir = Directory(_reportDir);
  await reportDir.create(recursive: true);
  final outPath = '${reportDir.path}/preflight.json';
  await File(outPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));

  final envLines = <String>[];
  void addEnv(String key, dynamic value, {bool allowEmpty = false}) {
    if (value == null) {
      if (allowEmpty) envLines.add('$key=');
      return;
    }
    final s = value.toString().trim();
    if (s.isEmpty && !allowEmpty) return;
    envLines.add('$key=$s');
  }

  if (app031 != null) {
    addEnv('AVISO031_CHAT_ID', app031['chat_id']);
    addEnv('AVISO031_ORDER_ID', app031['order_id']);
  }
  if (app043 != null) {
    addEnv('AVISO083_CHAT_ID', app043['chat_id']);
    addEnv('AVISO083_BUNDLE_ID', app043['bundle_id']);
    addEnv('AVISO083_ORDER_ID', app043['order_id'], allowEmpty: true);
    addEnv('AVISO043_CHAT_ID', app043['chat_id']);
    addEnv('AVISO043_BUNDLE_ID', app043['bundle_id']);
    addEnv('AVISO043_ORDER_ID', app043['order_id'], allowEmpty: true);
  }
  if (app055 != null) {
    addEnv('AVISO055_CHAT_ID', app055['chat_id']);
    addEnv('AVISO055_ORDER_ID', app055['order_id']);
  }
  if (app056 != null) {
    addEnv('AVISO056_CHAT_ID', app056['chat_id']);
    addEnv('AVISO056_ORDER_ID', app056['order_id']);
  }
  if (app086 != null) {
    addEnv('AVISO086_CHAT_ID', app086['chat_id']);
    addEnv('AVISO086_ORDER_ID', app086['order_id']);
    addEnv('AVISO086_BUNDLE_ID', app086['bundle_id']);
  }
  if (sec025 != null) {
    addEnv('AVISO_SEC025_CHAT_ID', sec025['chat_id']);
    addEnv('AVISO_SEC025_ORDER_ID', sec025['order_id']);
    addEnv('AVISO_SEC025_DISPUTE_ID', sec025['dispute_id']);
  }

  final envPath = '${reportDir.path}/preflight.env';
  await File(envPath).writeAsString(
    envLines.isEmpty ? '# no usable cases\n' : '${envLines.join('\n')}\n',
  );

  final summary = {
    'out': outPath,
    'env': envPath,
    'app031_ready': app031 != null,
    'app043_083_ready': app043 != null,
    'app043_source': app043Source,
    'app055_ready': app055 != null,
    'app056_ready': app056 != null,
    'app086_ready': app086 != null,
    'sec025_ready': sec025 != null,
    'skip_ps': ['SEC-008', 'SEC-013', 'SEC-019'],
    'live_needed': ['APP-218', 'SEC-020'],
  };
  print(const JsonEncoder.withIndent('  ').convert(summary));

  // Soft exit: preflight always writes JSON; runner skips missing IDs.
  if (app031 == null &&
      app043 == null &&
      app055 == null &&
      app056 == null &&
      app086 == null) {
    stderr.writeln('WARN: nenhum caso Maestro principal encontrado');
    exit(2);
  }
}
