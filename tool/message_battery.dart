// ignore_for_file: avoid_print
/// Fleaber Message Battery — varre TODAS as mensagens da app contra staging.
///
/// Cobre, no mesmo estilo da bateria A### (bots + logs + evidência BD):
///   - Chat público de live (todas as linhas de sistema do humanizer)
///   - Emissores reais (accept / cancel / compra via reconcile) end-to-end
///   - Sweep de todos os estados de encomenda (orders.status)
///   - Sweep de estados de pedido de reserva (live_reservation_requests.status)
///   - Mensagens de sistema em DM (FLEABER_JSON_V1: payloads do ciclo de vida)
///   - Chat humano comprador <-> vendedor (DM texto)
///   - Stripe: BYPASS por patch BD (pago) + RPC reconcile (sem checkout real)
///
/// A correção de COPY (texto humanizado) é validada por
/// test/message_battery_humanizer_test.dart (flutter test, sem device).
/// Este runner produz a EVIDÊNCIA BD (linhas reais) para auditoria.
///
/// Uso:
///   dart run tool/message_battery.dart            (corre tudo, limpa no fim)
///   dart run tool/message_battery.dart --keep     (não apaga fixtures)
///   dart run tool/message_battery.dart --area public_chat
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const String _liveTitle = 'MSG_BATTERY_LIVE';
const String _refPrefix = 'MSGBAT';
const String _jsonPrefix = 'FLEABER_JSON_V1:';

/// Todos os estados de orders.status (constraint BD + labels UI).
const List<String> kOrderStatuses = [
  'reserva_pendente',
  'reservado',
  'pendente',
  'aguarda_confirmacao',
  'pago',
  'enviado',
  'entregue',
  'concluido',
  'cancelado',
  'pedido_devolucao',
  'em_devolucao',
  'devolucao_entregue',
  'disputa_devolucao_vendedor',
  'devolvida',
];

/// Estados de live_reservation_requests.status.
const List<String> kReservationStatuses = [
  'pending',
  'accepted',
  'rejected',
  'expired',
  'converted',
];

class MsgCase {
  MsgCase({
    required this.id,
    required this.area,
    required this.title,
    this.rawBody,
    this.expectedHuman,
    this.expectedVisible,
  });

  final String id;
  final String area;
  final String title;

  /// Corpo cru da mensagem de sistema (chat público) — alimenta o teste humanizer.
  final String? rawBody;

  /// Linha humanizada esperada no chat público ('' = oculta/backoffice).
  final String? expectedHuman;

  /// Esperado visível no chat público?
  final bool? expectedVisible;

  String status = 'pending'; // pass | fail | warn | skip
  String? detail;
  Map<String, dynamic>? evidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'area': area,
        'title': title,
        'status': status,
        if (rawBody != null) 'raw_body': rawBody,
        if (expectedHuman != null) 'expected_human': expectedHuman,
        if (expectedVisible != null) 'expected_visible': expectedVisible,
        if (detail != null) 'detail': detail,
        if (evidence != null) 'evidence': evidence,
      };
}

class MessageBattery {
  MessageBattery(this.client, this.env, {this.keep = false, this.areaFilter});

  final LiveOpsStagingClient client;
  final Map<String, String> env;
  final bool keep;
  final String? areaFilter;

  final List<MsgCase> cases = [];

  late String sellerId;
  late String buyerId;
  late String sellerToken;
  late String buyerToken;

  String? _liveId;
  String? _liveItemId;
  String? _productId;
  String? _ref;
  final List<String> _createdChatIds = [];

  bool _wants(String area) => areaFilter == null || areaFilter == area;

  Future<void> run() async {
    print('=== Fleaber Message Battery ===');
    await _resolveIdentities();
    await _cleanup();
    await _createFixture();

    if (_wants('public_chat')) await _runPublicChat();
    if (_wants('emitters')) await _runRealEmitters();
    if (_wants('order_state')) await _runOrderStateSweep();
    if (_wants('reservation_state')) await _runReservationStateSweep();
    if (_wants('dm')) await _runDmPayloads();
    if (_wants('human_chat')) await _runHumanChat();
    if (_wants('stripe_bypass')) await _runStripeBypass();

    if (!keep) {
      await _cleanup();
    } else {
      print('--keep: fixtures preservados (live=$_liveId)');
    }

    await _writeReports();
    _printSummary();
  }

  Future<void> _resolveIdentities() async {
    sellerToken = await client.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    buyerToken = await client.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
    if (!isUuid(sellerId)) {
      sellerId = await client.userIdForAccessToken(sellerToken);
    }
    buyerId = env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
    if (!isUuid(buyerId)) {
      buyerId = await client.userIdForAccessToken(buyerToken);
    }
    print('seller=$sellerId buyer=$buyerId');
  }

  Future<void> _cleanup() async {
    try {
      final lives = await client.select(
        'lives',
        filter: 'seller_id=eq.$sellerId&title=eq.$_liveTitle',
        limit: 20,
      );
      for (final live in lives) {
        final liveId = live['id']?.toString() ?? '';
        if (liveId.isEmpty) continue;
        await client.deleteWhere('live_messages', 'live_id=eq.$liveId');
        await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveId');
        await client.deleteWhere('orders', 'live_id=eq.$liveId');
        await client.deleteWhere('live_items', 'live_id=eq.$liveId');
        await client.deleteWhere('lives', 'id=eq.$liveId');
      }
      // Chats antes de products (FK chats.product_id → products.id).
      for (final chatId in _createdChatIds) {
        await client.deleteWhere('chat_messages', 'chat_id=eq.$chatId');
        await client.deleteWhere('chats', 'id=eq.$chatId');
      }
      await client.deleteWhere(
        'chats',
        'user_a=eq.$sellerId&user_b=eq.$buyerId',
      );
      // Produtos órfãos do battery
      await client.deleteWhere(
        'products',
        'seller_id=eq.$sellerId&ref_code=like.$_refPrefix*',
      );
    } catch (e) {
      print('AVISO cleanup: $e');
    }
  }

  Future<void> _createFixture() async {
    final live = await client.insert('lives', {
      'title': _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    _liveId = live['id']!.toString();
    _ref = '$_refPrefix-${DateTime.now().millisecondsSinceEpoch}';
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'Message battery product',
      'price': 10,
      'quantity': 10,
      'ref_code': _ref,
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    _productId = product['id']!.toString();
    final item = await client.insert('live_items', {
      'live_id': _liveId,
      'ref_code': _ref,
      'title': 'Puzzle',
      'price': 10,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': _productId,
      'checkout_product_id': _productId,
      'logical_item_id': _productId,
    });
    _liveItemId = item['id']!.toString();
    print('fixture live=$_liveId item=$_liveItemId ref=$_ref');
  }

  // ── Grupo 1: chat público (templates do humanizer) ────────────────────────
  // Injecta o corpo cru via live_messages (kind system/tip) — mesma tabela que
  // a app usa — e confirma o armazenamento. A copy é validada no teste flutter.

  Future<void> _runPublicChat() async {
    final templates = <MsgCase>[
      MsgCase(id: 'M01', area: 'public_chat', title: 'Reserva com artigo', rawBody: '🛍️ Marina reservou Puzzle', expectedHuman: 'Marina reservou Puzzle', expectedVisible: true),
      MsgCase(id: 'M02', area: 'public_chat', title: 'Reserva sem artigo → fila', rawBody: '🛍️ Marina reservou para o saco da live', expectedHuman: 'Marina entrou na fila deste artigo', expectedVisible: true),
      MsgCase(id: 'M03', area: 'public_chat', title: 'Adicionou ao saco → carrinho', rawBody: '🛍️ Marina adicionou Puzzle ao saco', expectedHuman: 'Marina adicionou Puzzle ao carrinho', expectedVisible: true),
      MsgCase(id: 'M04', area: 'public_chat', title: 'Compra (✅)', rawBody: '✅ Marina comprou Puzzle', expectedHuman: 'Marina comprou Puzzle', expectedVisible: true),
      MsgCase(id: 'M05', area: 'public_chat', title: 'Compra com preço (💳)', rawBody: '💳 Marina comprou Puzzle (10€)', expectedHuman: 'Marina comprou Puzzle', expectedVisible: true),
      MsgCase(id: 'M06', area: 'public_chat', title: 'Reserva aceite broadcast', rawBody: '🔒 Reserva aceite — Puzzle · Marina tem 5 dias para pagar', expectedHuman: 'Marina ficou com Puzzle', expectedVisible: true),
      MsgCase(id: 'M07', area: 'public_chat', title: 'Reserva aceite c/ qty', rawBody: '🔒 Reserva aceite — 2 un. · Puzzle · Marina tem 5 dias para pagar', expectedHuman: 'Marina ficou com Puzzle', expectedVisible: true),
      MsgCase(id: 'M08', area: 'public_chat', title: 'Reserva aceite painel (Prazo)', rawBody: '🔒 Marina — reserva aceite · Puzzle · Prazo: 4d', expectedHuman: 'Marina ficou com Puzzle', expectedVisible: true),
      MsgCase(id: 'M09', area: 'public_chat', title: 'Preço definido', rawBody: '💶 Preço definido · Puzzle · 12,00 €', expectedHuman: 'Puzzle — 12,00 €', expectedVisible: true),
      MsgCase(id: 'M10', area: 'public_chat', title: 'Última unidade (FOMO)', rawBody: '🔥 Ultima unidade — Puzzle', expectedHuman: 'Última unidade de Puzzle', expectedVisible: true),
      MsgCase(id: 'M11', area: 'public_chat', title: 'Esgotado', rawBody: '🔴 Puzzle esgotado', expectedHuman: 'Puzzle esgotou', expectedVisible: true),
      MsgCase(id: 'M12', area: 'public_chat', title: 'Rifa social', rawBody: '🎟️ Rifa: Ana ganhou +2 rifas', expectedHuman: 'Ana ganhou +2 rifas', expectedVisible: true),
      MsgCase(id: 'M13', area: 'public_chat', title: 'Cancelamento comprador', rawBody: '↩ Reserva cancelada pelo comprador', expectedHuman: 'Reserva cancelada', expectedVisible: true),
      MsgCase(id: 'M14', area: 'public_chat', title: 'Cancelamento com nome', rawBody: '↩ Marina cancelou a reserva · Puzzle', expectedHuman: 'Marina cancelou a reserva de Puzzle', expectedVisible: true),
      MsgCase(id: 'M15', area: 'public_chat', title: 'Pedido acima do stock (backoffice)', rawBody: '📋 Pedido de 3 un. · Puzzle — só 1 disponível; aguarda confirmação', expectedHuman: '', expectedVisible: false),
      MsgCase(id: 'M16', area: 'public_chat', title: 'Recusa vendedora over-stock (backoffice)', rawBody: '❌ Recusaste o pedido de 2 un. · Puzzle (acima do stock na live)', expectedHuman: '', expectedVisible: false),
      MsgCase(id: 'M17', area: 'public_chat', title: 'Aceite vendedora over-stock (backoffice)', rawBody: '✅ Aceitaste vender 2 un. · Puzzle — comprador tem 5 dias para pagar', expectedHuman: '', expectedVisible: false),
      MsgCase(id: 'M18', area: 'public_chat', title: 'Rejeição vendedora (oculta)', rawBody: '❌ Vendedora rejeitou reserva · Ref A12', expectedHuman: '', expectedVisible: false),
    ];
    for (final c in templates) {
      try {
        final row = await client.insert('live_messages', {
          'live_id': _liveId,
          'kind': 'system',
          'body': c.rawBody,
          'sender_label': 'MSG_BATTERY',
        });
        final storedBody = row['body']?.toString() ?? '';
        c.evidence = {'row_id': row['id'], 'stored_body': storedBody};
        c.status = storedBody == c.rawBody ? 'pass' : 'warn';
        if (c.status == 'warn') {
          c.detail = 'corpo armazenado diferente do injectado';
        }
      } catch (e) {
        c.status = 'fail';
        c.detail = 'insert live_messages: $e';
      }
      cases.add(c);
      print('  ${c.id} ${c.status} ${c.title}');
    }

    // M19 — gorjeta (kind=tip): linha não vem do body, mas valida storage.
    final tip = MsgCase(
      id: 'M19',
      area: 'public_chat',
      title: 'Gorjeta (kind=tip)',
      expectedHuman: 'Marina apoiou a live com 5,00 € (parseTip)',
      expectedVisible: true,
    );
    try {
      final row = await client.insert('live_messages', {
        'live_id': _liveId,
        'kind': 'tip',
        'body': 'tip:5.00',
        'sender_label': 'Marina',
      });
      tip.evidence = {'row_id': row['id'], 'kind': row['kind']};
      tip.status = (row['kind'] == 'tip') ? 'pass' : 'warn';
    } catch (e) {
      tip.status = 'fail';
      tip.detail = 'insert tip: $e';
    }
    cases.add(tip);
    print('  ${tip.id} ${tip.status} ${tip.title}');
  }

  // ── Grupo 2: emissores reais (RPC) end-to-end ─────────────────────────────
  // Corre numa live DEDICADA e limpa (sem os templates injectados no grupo 1),
  // para evitar colisão com o dedup de 15 min das funções de broadcast.
  Future<void> _runRealEmitters() async {
    final fx = await _createExtraLive();
    final eLive = fx['live_id']!;
    final eItem = fx['live_item_id']!;

    // M20 — accept via process RPC: deve emitir 🔒 reserva aceite internamente.
    await _caseAcceptViaProcess(eLive, eItem);

    // M21 — bag remove: ↩ Reserva cancelada
    await _emitterCase(
      id: 'M21',
      liveId: eLive,
      title: 'RPC bag_remove → broadcast cancelada',
      expectSubstrings: ['cancel'],
      action: () async {
        final req = await client.insert('live_reservation_requests', {
          'live_id': eLive,
          'live_item_id': eItem,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        });
        await client.rpc(
          'batata_live_bag_remove_request',
          {'p_request_id': req['id']},
          accessToken: buyerToken,
        );
      },
    );

    // M22 — accept_broadcast directo (emissor explícito) → 🔒 reserva aceite
    await _emitterCase(
      id: 'M22',
      liveId: eLive,
      title: 'RPC accept_broadcast directo → reserva aceite',
      expectSubstrings: ['aceite'],
      action: () async {
        await client.rpc('batata_live_reservation_accept_broadcast', {
          'p_live_id': eLive,
          'p_buyer_id': buyerId,
          'p_live_item_id': eItem,
          'p_requested_qty': 1,
        });
      },
    );

    // M23 — purchase_broadcast directo (mesmo emissor da edge/cliente) → ✅ comprou
    await _emitterCase(
      id: 'M23',
      liveId: eLive,
      title: 'RPC purchase_broadcast directo → compra',
      expectSubstrings: ['comprou'],
      action: () async {
        await client.rpc('batata_live_purchase_broadcast', {
          'p_live_id': eLive,
          'p_buyer_id': buyerId,
          'p_live_item_id': eItem,
        });
      },
    );
  }

  /// M20 — accept pela RPC canónica, com diagnóstico (retorno + estado + linha).
  Future<void> _caseAcceptViaProcess(String liveId, String itemId) async {
    final c = MsgCase(
      id: 'M20',
      area: 'emitters',
      title: 'RPC accept (process) → deve emitir reserva aceite',
    );
    try {
      final req = await client.insert('live_reservation_requests', {
        'live_id': liveId,
        'live_item_id': itemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      });
      final reqId = req['id'].toString();
      final before = await _systemMessages(liveId);
      final rpc = await client.rpc(
        'batata_process_live_reservation_request',
        {'p_request_id': reqId, 'p_action': 'accept'},
        accessToken: sellerToken,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final after = await _systemMessages(liveId);
      final newRows = after.where((r) => !before.any((b) => b['id'] == r['id'])).toList();
      final acceptLine = newRows.where((r) =>
          (r['body']?.toString() ?? '').toLowerCase().contains('aceite')).toList();
      final reqRows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.$reqId',
        limit: 1,
      );
      final reqStatus = reqRows.isNotEmpty ? reqRows.first['status']?.toString() : null;
      c.evidence = {
        'rpc_result': rpc,
        'reservation_status_after': reqStatus,
        'new_system_lines': newRows.map((r) => r['body']).toList(),
        'accept_broadcast': acceptLine.map((r) => r['body']).toList(),
      };
      if (acceptLine.isNotEmpty) {
        c.status = 'pass';
        c.detail = acceptLine.first['body']?.toString();
      } else if (reqStatus == 'accepted') {
        c.status = 'warn';
        c.detail =
            'reserva ficou accepted mas a RPC process NÃO emitiu a linha pública '
            '«reserva aceite» (o emissor directo M22 funciona). Linha social do '
            'accept depende deste broadcast — confirmar versão da função em staging.';
      } else {
        c.status = 'warn';
        c.detail = 'accept não confirmado (status=$reqStatus, rpc=$rpc)';
      }
    } catch (e) {
      c.status = 'fail';
      c.detail = 'process accept: $e';
    }
    cases.add(c);
    print('  ${c.id} ${c.status} ${c.title}');
  }

  Future<void> _emitterCase({
    required String id,
    required String liveId,
    required String title,
    required List<String> expectSubstrings,
    required Future<void> Function() action,
  }) async {
    final c = MsgCase(id: id, area: 'emitters', title: title);
    try {
      final before = await _systemMessages(liveId);
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final after = await _systemMessages(liveId);
      final newRows = after
          .where((r) => !before.any((b) => b['id'] == r['id']))
          .toList();
      final match = newRows.where((r) {
        final body = (r['body']?.toString() ?? '').toLowerCase();
        return expectSubstrings.every((s) => body.contains(s.toLowerCase()));
      }).toList();
      c.evidence = {
        'new_rows': newRows.map((r) => r['body']).toList(),
        'matched': match.map((r) => r['body']).toList(),
      };
      if (match.isNotEmpty) {
        c.status = 'pass';
        c.detail = match.first['body']?.toString();
      } else {
        c.status = 'warn';
        c.detail =
            'RPC ok mas sem linha sistema esperada (trigger broadcast pode estar off em staging)';
      }
    } catch (e) {
      c.status = 'fail';
      c.detail = 'RPC: $e';
    }
    cases.add(c);
    print('  ${c.id} ${c.status} ${c.title}');
  }

  Future<List<Map<String, dynamic>>> _systemMessages([String? liveId]) async {
    return client.select(
      'live_messages',
      filter: 'live_id=eq.${liveId ?? _liveId}&order=created_at.desc',
      limit: 100,
    );
  }

  /// Cria uma live extra (mesmo produto) para isolar emissores de broadcast.
  Future<Map<String, String>> _createExtraLive() async {
    final live = await client.insert('lives', {
      'title': _liveTitle,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final liveId = live['id']!.toString();
    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': _ref,
      'title': 'Puzzle',
      'price': 10,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': _productId,
      'checkout_product_id': _productId,
      'logical_item_id': _productId,
    });
    return {'live_id': liveId, 'live_item_id': item['id']!.toString()};
  }

  // ── Grupo 3: sweep de estados de encomenda ────────────────────────────────
  Future<void> _runOrderStateSweep() async {
    String? orderId;
    try {
      final order = await client.insert('orders', {
        'product_id': _productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 13.5,
        'shipping_method': 'Envio Transportadora (€3.50)',
        'payment_method': 'Pagamento na App',
        'status': 'reserva_pendente',
        'quantity': 1,
        'live_id': _liveId,
        'live_item_id': _liveItemId,
      });
      orderId = order['id']!.toString();
    } catch (e) {
      cases.add(MsgCase(id: 'M30', area: 'order_state', title: 'criar order')
        ..status = 'fail'
        ..detail = 'insert order: $e');
      print('  M30 fail criar order: $e');
      return;
    }

    var idx = 30;
    for (final status in kOrderStatuses) {
      final c = MsgCase(
        id: 'M${idx++}',
        area: 'order_state',
        title: 'orders.status = $status',
      );
      try {
        await client.patch('orders', 'id=eq.$orderId', {'status': status});
        final rows = await client.select('orders', filter: 'id=eq.$orderId', limit: 1);
        final got = rows.isNotEmpty ? rows.first['status']?.toString() : null;
        c.evidence = {'requested': status, 'stored': got};
        c.status = (got == status) ? 'pass' : 'warn';
        if (c.status == 'warn') c.detail = 'BD guardou "$got" (trigger pode normalizar)';
      } catch (e) {
        c.status = 'warn';
        c.detail = 'transição rejeitada: ${_short('$e', 160)}';
      }
      cases.add(c);
      print('  ${c.id} ${c.status} ${c.title}');
    }
  }

  // ── Grupo 4: sweep de estados de pedido de reserva ────────────────────────
  Future<void> _runReservationStateSweep() async {
    var idx = 50;
    for (final status in kReservationStatuses) {
      final c = MsgCase(
        id: 'M${idx++}',
        area: 'reservation_state',
        title: 'reservation.status = $status',
      );
      try {
        final req = await client.insert('live_reservation_requests', {
          'live_id': _liveId,
          'live_item_id': _liveItemId,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': status,
        });
        c.evidence = {'row_id': req['id'], 'stored': req['status']};
        c.status = (req['status'] == status) ? 'pass' : 'warn';
      } catch (e) {
        c.status = 'warn';
        c.detail = 'estado rejeitado: ${_short('$e', 160)}';
      }
      cases.add(c);
      print('  ${c.id} ${c.status} ${c.title}');
    }
  }

  // ── Grupo 5: payloads de sistema em DM (ciclo de vida da encomenda) ────────
  Future<void> _runDmPayloads() async {
    final chatId = await _ensureChat();
    if (chatId == null) {
      cases.add(MsgCase(id: 'M60', area: 'dm', title: 'criar chat')
        ..status = 'fail'
        ..detail = 'não consegui criar chats row');
      return;
    }

    final payloads = <String, Map<String, dynamic>>{
      'reservation_request': {'kind': 'reservation_request', 'product_id': _productId, 'qty': 1},
      'reservation_request_outcome_accepted': {'kind': 'reservation_request_outcome', 'outcome': 'accepted'},
      'reservation_request_outcome_declined': {'kind': 'reservation_request_outcome', 'outcome': 'declined'},
      'reservation_accepted': {'kind': 'reservation_accepted', 'expires_at': DateTime.now().add(const Duration(days: 5)).toIso8601String()},
      'reservation_payment_submitted': {'kind': 'reservation_payment_submitted', 'method': 'app'},
      'reservation_reminder': {'kind': 'reservation_reminder'},
      'reservation_payment_check_reminder': {'kind': 'reservation_payment_check_reminder'},
      'reservation_shipping_reminder': {'kind': 'reservation_shipping_reminder'},
      'reservation_seller_confirmed_receipt': {'kind': 'reservation_seller_confirmed_receipt'},
      'reservation_order_shipped': {'kind': 'reservation_order_shipped'},
      'reservation_order_completed': {'kind': 'reservation_order_completed'},
      'reservation_cancelled_by_seller': {'kind': 'reservation_cancelled_by_seller'},
      'cancel_request': {'kind': 'cancel_request', 'reason': 'mudei de ideias'},
      'cancel_request_outcome': {'kind': 'cancel_request_outcome', 'outcome': 'accepted'},
      'order_dispute_opened': {'kind': 'order_dispute_opened'},
      'price_offer': {'kind': 'price_offer', 'amount': 9.5},
      'price_offer_outcome': {'kind': 'price_offer_outcome', 'outcome': 'accepted'},
      'bundle_proposal': {'kind': 'bundle_proposal', 'items': 2},
      'chat_image': {'kind': 'chat_image', 'url': 'https://example.com/x.jpg'},
    };

    var idx = 60;
    payloads.forEach((label, payload) {
      // closure-friendly: collected below
      _pendingDm.add(MapEntry('M${idx++}', MapEntry(label, payload)));
    });
    for (final entry in _pendingDm) {
      final c = MsgCase(id: entry.key, area: 'dm', title: 'DM ${entry.value.key}');
      try {
        final text = _jsonPrefix + jsonEncode(entry.value.value);
        final row = await client.insert('chat_messages', {
          'chat_id': chatId,
          'sender_id': sellerId,
          'receiver_id': buyerId,
          'text': text,
          'is_read': false,
          'is_reservation': true,
        });
        // round-trip: ler de volta e validar JSON
        final stored = row['text']?.toString() ?? '';
        final ok = stored.startsWith(_jsonPrefix);
        Map<String, dynamic>? parsed;
        if (ok) {
          parsed = jsonDecode(stored.substring(_jsonPrefix.length)) as Map<String, dynamic>;
        }
        c.evidence = {'row_id': row['id'], 'kind': parsed?['kind']};
        c.status = (ok && parsed?['kind'] == entry.value.value['kind']) ? 'pass' : 'warn';
      } catch (e) {
        c.status = 'fail';
        c.detail = 'insert chat_messages: $e';
      }
      cases.add(c);
      print('  ${c.id} ${c.status} ${c.title}');
    }

    // Plain-text system DM (cancelamento de pedido)
    final plain = MsgCase(id: 'M${idx++}', area: 'dm', title: 'DM texto: comprador cancelou pedido');
    try {
      final row = await client.insert('chat_messages', {
        'chat_id': chatId,
        'sender_id': buyerId,
        'receiver_id': sellerId,
        'text': 'O comprador cancelou o pedido de reserva desta encomenda.',
        'is_read': false,
        'is_reservation': true,
      });
      plain.evidence = {'row_id': row['id']};
      plain.status = 'pass';
    } catch (e) {
      plain.status = 'fail';
      plain.detail = 'insert plain DM: $e';
    }
    cases.add(plain);
    print('  ${plain.id} ${plain.status} ${plain.title}');
  }

  final List<MapEntry<String, MapEntry<String, Map<String, dynamic>>>> _pendingDm = [];

  Future<String?> _ensureChat() async {
    try {
      final existing = await client.select(
        'chats',
        filter: 'user_a=eq.$sellerId&user_b=eq.$buyerId&product_id=eq.$_productId',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id']?.toString();
        if (id != null) _createdChatIds.add(id);
        return id;
      }
      final row = await client.insert('chats', {
        'user_a': sellerId,
        'user_b': buyerId,
        'product_id': _productId,
      });
      final id = row['id']?.toString();
      if (id != null) _createdChatIds.add(id);
      return id;
    } catch (e) {
      print('AVISO ensureChat: $e');
      return null;
    }
  }

  // ── Grupo 6: chat humano comprador <-> vendedor ───────────────────────────
  Future<void> _runHumanChat() async {
    final chatId = await _ensureChat();
    final c = MsgCase(id: 'M80', area: 'human_chat', title: 'DM humano buyer↔seller + last_message');
    if (chatId == null) {
      c.status = 'fail';
      c.detail = 'sem chat';
      cases.add(c);
      return;
    }
    try {
      await client.insert('chat_messages', {
        'chat_id': chatId,
        'sender_id': buyerId,
        'receiver_id': sellerId,
        'text': 'Olá, este artigo ainda está disponível?',
        'is_read': false,
      });
      final reply = await client.insert('chat_messages', {
        'chat_id': chatId,
        'sender_id': sellerId,
        'receiver_id': buyerId,
        'text': 'Está sim! Posso reservar para si.',
        'is_read': false,
      });
      await client.patch('chats', 'id=eq.$chatId', {
        'last_message': 'Está sim! Posso reservar para si.',
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
      });
      final rows = await client.select('chat_messages', filter: 'chat_id=eq.$chatId', limit: 50);
      final chatRows = await client.select('chats', filter: 'id=eq.$chatId', limit: 1);
      final lastMsg = chatRows.isNotEmpty ? chatRows.first['last_message']?.toString() : null;
      c.evidence = {
        'messages_count': rows.length,
        'last_message': lastMsg,
        'reply_id': reply['id'],
      };
      c.status = (rows.length >= 2 && lastMsg != null && lastMsg.isNotEmpty) ? 'pass' : 'warn';
    } catch (e) {
      c.status = 'fail';
      c.detail = 'human chat: $e';
    }
    cases.add(c);
    print('  ${c.id} ${c.status} ${c.title}');
  }

  // ── Grupo 7: Stripe BYPASS (sem checkout real) ────────────────────────────
  Future<void> _runStripeBypass() async {
    final c = MsgCase(
      id: 'M90',
      area: 'stripe_bypass',
      title: 'Compra sem Stripe: patch pago + reconcile → broadcast compra',
    );
    try {
      final order = await client.insert('orders', {
        'product_id': _productId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 13.5,
        'shipping_method': 'Envio Transportadora (€3.50)',
        'payment_method': 'Pagamento na App',
        'status': 'reserva_pendente',
        'quantity': 1,
        'live_id': _liveId,
        'live_item_id': _liveItemId,
      });
      final orderId = order['id']!.toString();
      final resReq = await client.insert('live_reservation_requests', {
        'live_id': _liveId,
        'live_item_id': _liveItemId,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'accepted',
        'notes': 'stripe_checkout:$orderId',
      });
      // BYPASS Stripe: marca pago directamente na BD
      await client.patch('orders', 'id=eq.$orderId', {'status': 'pago'});
      final before = await _systemMessages();
      final rpc = await client.rpc(
        'batata_live_reconcile_stripe_order',
        {'p_order_id': orderId, 'p_reservation_request_id': resReq['id']},
        accessToken: buyerToken,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final after = await _systemMessages();
      final newRows = after.where((r) => !before.any((b) => b['id'] == r['id'])).toList();
      final purchase = newRows.where((r) =>
          (r['body']?.toString() ?? '').toLowerCase().contains('comprou')).toList();
      final reqRows = await client.select(
        'live_reservation_requests',
        filter: 'id=eq.${resReq['id']}',
        limit: 1,
      );
      final reqStatus = reqRows.isNotEmpty ? reqRows.first['status']?.toString() : null;
      c.evidence = {
        'rpc_ok': rpc is Map ? rpc['ok'] : rpc,
        'reservation_status_after': reqStatus,
        'new_system_lines': newRows.map((r) => r['body']).toList(),
        'purchase_broadcast': purchase.map((r) => r['body']).toList(),
      };
      final rpcOk = rpc is Map && rpc['ok'] == true;
      if (rpcOk && (reqStatus == 'converted' || purchase.isNotEmpty)) {
        c.status = 'pass';
      } else if (rpcOk) {
        c.status = 'warn';
        c.detail = 'reconcile ok mas sem converted/broadcast visível';
      } else {
        c.status = 'fail';
        c.detail = 'reconcile RPC falhou: $rpc';
      }
    } catch (e) {
      c.status = 'fail';
      c.detail = 'stripe bypass: $e';
    }
    cases.add(c);
    print('  ${c.id} ${c.status} ${c.title}');
  }

  // ── Relatórios ────────────────────────────────────────────────────────────
  Future<void> _writeReports() async {
    final stamp = _stamp();
    final dir = Directory('tool/reports/message_battery_$stamp');
    dir.createSync(recursive: true);

    final pass = cases.where((c) => c.status == 'pass').length;
    final warn = cases.where((c) => c.status == 'warn').length;
    final fail = cases.where((c) => c.status == 'fail').length;

    final evidence = {
      'version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'live_id': _liveId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'summary': {'pass': pass, 'warn': warn, 'fail': fail, 'total': cases.length},
      'cases': cases.map((c) => c.toJson()).toList(),
    };
    File('${dir.path}/evidence.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));

    final md = StringBuffer()
      ..writeln('# Message Battery — relatório $stamp')
      ..writeln()
      ..writeln('- live_id: `$_liveId`')
      ..writeln('- Resumo: **pass=$pass · warn=$warn · fail=$fail** (total ${cases.length})')
      ..writeln()
      ..writeln('> warn = comportamento BD diferente do esperado ou trigger/broadcast '
          'não observável em staging (auditar manualmente). fail = erro a executar.')
      ..writeln();
    for (final area in ['public_chat', 'emitters', 'order_state', 'reservation_state', 'dm', 'human_chat', 'stripe_bypass']) {
      final group = cases.where((c) => c.area == area).toList();
      if (group.isEmpty) continue;
      md
        ..writeln('## $area')
        ..writeln()
        ..writeln('| ID | Estado | Caso | Detalhe |')
        ..writeln('|----|--------|------|---------|');
      for (final c in group) {
        final det = (c.detail ?? '').replaceAll('|', '\\|').replaceAll('\n', ' ');
        md.writeln('| ${c.id} | ${c.status.toUpperCase()} | ${c.title} | ${_short(det, 80)} |');
      }
      md.writeln();
    }
    File('${dir.path}/report.md').writeAsStringSync(md.toString());

    // Registry persistente
    final registry = {
      'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'last_report': dir.path,
      'summary': {'pass': pass, 'warn': warn, 'fail': fail, 'total': cases.length},
      'cases': {
        for (final c in cases)
          c.id: {'area': c.area, 'title': c.title, 'status': c.status, if (c.detail != null) 'detail': c.detail},
      },
    };
    File('tool/message_battery_registry.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(registry));

    print('Relatório: ${dir.path}');
  }

  void _printSummary() {
    final pass = cases.where((c) => c.status == 'pass').length;
    final warn = cases.where((c) => c.status == 'warn').length;
    final fail = cases.where((c) => c.status == 'fail').length;
    print('=== Resumo: pass=$pass warn=$warn fail=$fail total=${cases.length} ===');
  }

  static String _short(String v, int max) =>
      v.length <= max ? v : '${v.substring(0, max)}…';

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}

Future<void> main(List<String> args) async {
  final keep = args.contains('--keep');
  String? area;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--area' && i + 1 < args.length) area = args[i + 1];
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final battery = MessageBattery(client, staging, keep: keep, areaFilter: area);
  await battery.run();

  final fail = battery.cases.where((c) => c.status == 'fail').length;
  if (fail > 0) exit(1);
}
