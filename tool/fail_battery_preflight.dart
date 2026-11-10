// ignore_for_file: avoid_print
/// Preflight Maestro APP-065 / APP-095 — IDs de encomenda/chat na staging.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

String _statusKey(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(' ', '_');

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
    filter: 'buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 250,
  );

  // APP-065 — conjunto (≥2 linhas) com enviado/concluido
  final byBundle = <String, List<Map<String, dynamic>>>{};
  for (final o in orders) {
    final bid = o['bundle_id']?.toString().trim() ?? '';
    if (bid.isEmpty) continue;
    final st = _statusKey(o['status']?.toString());
    if (st != 'enviado' && st != 'concluido') continue;
    byBundle.putIfAbsent(bid, () => []).add(o);
  }

  Map<String, dynamic>? app065;
  for (final entry in byBundle.entries) {
    if (entry.value.length < 2) continue;
    final allShipped = entry.value.every((o) {
      final st = _statusKey(o['status']?.toString());
      return st == 'enviado' || st == 'concluido';
    });
    if (!allShipped) continue;
    final first = entry.value.first;
    app065 = {
      'bundle_id': entry.key,
      'order_count': entry.value.length,
      'order_id': first['id'],
      'statuses': entry.value.map((o) => o['status']).toList(),
      'expected_phrase': 'Artigo Enviado',
    };
    break;
  }

  // APP-095 — reserva_pendente sem encomenda paga/enviada mais recente no mesmo produto
  final pendente = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=eq.reserva_pendente&order=created_at.desc',
    limit: 20,
  );

  final ordersByProduct = <String, List<Map<String, dynamic>>>{};
  for (final o in orders) {
    final pid = o['product_id']?.toString() ?? '';
    if (pid.isEmpty) continue;
    ordersByProduct.putIfAbsent(pid, () => []).add(o);
  }

  bool productChatUsableForReservaPendente(
    Map<String, dynamic> candidate,
  ) {
    final pid = candidate['product_id']?.toString() ?? '';
    final oid = candidate['id'].toString();
    final siblings = ordersByProduct[pid] ?? [];
    const blocking = {
      'pago',
      'enviado',
      'concluido',
      'concluído',
      'entregue',
      'reservado',
      'aguarda_confirmacao',
    };
    for (final s in siblings) {
      if (s['id'].toString() == oid) continue;
      final st = _statusKey(s['status']?.toString());
      if (st.contains('cancel')) continue;
      if (blocking.contains(st)) return false;
    }
    return true;
  }

  final reservado = await sb.select(
    'orders',
    filter:
        'buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=eq.reservado&order=created_at.desc',
    limit: 10,
  );

  Map<String, dynamic>? app095;
  String app095Mode = 'none';

  Future<Map<String, dynamic>?> chatForOrder(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    final productId = order['product_id']?.toString() ?? '';
    if (productId.isEmpty) return null;
    final chats = await sb.select(
      'chats',
      filter:
          'product_id=eq.$productId&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
      limit: 5,
    );
    if (chats.isEmpty) return null;
    final c = chats.first;
    return {
      'chat_id': c['id'],
      'order_id': orderId,
      'product_id': productId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
    };
  }

  Map<String, dynamic>? app095Rejected;
  for (final o in pendente) {
    if (!productChatUsableForReservaPendente(o)) {
      app095Rejected ??= {
        'order_id': o['id'],
        'product_id': o['product_id'],
        'reason':
            'mesmo produto tem encomenda paga/enviada mais recente — chat mostra Venda paga',
      };
      continue;
    }
    final chat = await chatForOrder(o);
    if (chat != null) {
      app095Mode = 'accept_then_open';
      app095 = {
        ...chat,
        'order_status': o['status'],
        'product_note': 'chat limpo — só reserva_pendente activa neste produto',
      };
      break;
    }
  }

  if (app095 == null && pendente.isNotEmpty) {
    // fallback documentado — não usar C27 com pago por cima
    app095Rejected ??= {
      'order_id': pendente.first['id'],
      'reason': 'sem chat ou produto bloqueado',
    };
  }

  if (app095 == null && reservado.isNotEmpty) {
    final now = DateTime.now().toUtc();
    for (final o in reservado) {
      // orders não tem updated_at — usar created_at como proxy de idade da reserva
      final createdRaw = o['created_at']?.toString();
      final created = createdRaw != null ? DateTime.tryParse(createdRaw)?.toUtc() : null;
      final ageOk = created == null ||
          now.difference(created) < const Duration(hours: 48);
      if (!ageOk) continue;
      final chat = await chatForOrder(o);
      if (chat == null) continue;
      app095Mode = 'open_existing_reservado';
      app095 = {
        ...chat,
        'order_status': o['status'],
        'created_at': o['created_at'],
        'age_hours': created == null
            ? null
            : now.difference(created).inMinutes / 60.0,
      };
      break;
    }
  }

  final out = {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'app065': app065,
    'app095': app095,
    'app095_mode': app095Mode,
    'bundle_candidates': byBundle.length,
    'reserva_pendente_count': pendente.length,
    'app095_rejected_sample': app095Rejected,
  };

  final reportDir = Directory('tool/reports/battery_fail_2026-08-23/bd');
  await reportDir.create(recursive: true);
  final outPath = '${reportDir.path}/preflight.json';
  await File(outPath).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode({
    'out': outPath,
    'app065_ready': app065 != null,
    'app095_ready': app095 != null,
    'app095_mode': app095Mode,
  }));

  // Emit .env lines for maestro_prepare
  final envLines = <String>[];
  if (app065 != null) {
    envLines.add('APP065_BUNDLE_ID=${app065['bundle_id']}');
    envLines.add('APP065_ORDER_ID=${app065['order_id']}');
  }
  if (app095 != null) {
    envLines.add('APP095_CHAT_ID=${app095['chat_id']}');
    envLines.add('APP095_ORDER_ID=${app095['order_id']}');
    envLines.add('APP095_MODE=$app095Mode');
  }
  if (envLines.isNotEmpty) {
    await File('tool/reports/battery_fail_2026-08-23/bd/preflight.env').writeAsString('${envLines.join('\n')}\n');
  }

  if (app065 == null && app095 == null) exit(2);
}
