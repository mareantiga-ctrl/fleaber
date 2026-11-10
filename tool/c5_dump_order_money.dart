// ignore_for_file: avoid_print
/// Snapshot de dinheiro + estados (encomenda + reserva + stock) para auditoria C5.
///
///   dart run tool/c5_dump_order_money.dart --label=214b_accepted --out=path.json
///   dart run tool/c5_dump_order_money.dart --live-id=UUID
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleaber/utils/fee_calculator.dart';

import 'live_ops_staging_client.dart';

const _paymentDirect = 'Pagamento Direto ao Vendedor (MB WAY/Transf)';

double _shippingEur(String method) {
  final m = method.toLowerCase();
  if (m.contains('transportadora') ||
      m.contains('3.50') ||
      m.contains('3,50')) {
    return 3.5;
  }
  return 0;
}

void main(List<String> args) async {
  var liveId = '';
  var label = 'snapshot';
  var outPath = '';
  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.split('=').last.trim();
    if (a.startsWith('--label=')) label = a.split('=').last.trim();
    if (a.startsWith('--out=')) outPath = a.split('=').last.trim();
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  if (liveId.isEmpty) {
    final envFile = File('.maestro/.env');
    if (envFile.existsSync()) {
      for (final line in envFile.readAsLinesSync()) {
        if (line.startsWith('MAESTRO_LIVE_ID=')) {
          liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
        }
      }
    }
  }
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: --live-id ou MAESTRO_LIVE_ID UUID obrigatório');
    exit(1);
  }

  final orders = await client.select(
    'orders',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 50,
  );
  final reservations = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 50,
  );

  final breakdowns = <Map<String, dynamic>>[];
  var ganhosStudioEsperado = 0.0;
  for (final o in orders) {
    final qty = (o['quantity'] as num?)?.toInt() ?? 1;
    final stored = (o['price_total'] as num?)?.toDouble() ?? 0;
    final pay = (o['payment_method'] ?? '').toString();
    final shipMethod = (o['shipping_method'] ?? '').toString();
    final shipping = _shippingEur(shipMethod);
    final isDirect = pay.trim() == _paymentDirect;
    final status = (o['status'] ?? '').toString();
    final productId = (o['product_id'] ?? '').toString();
    var unit = 0.0;
    if (isUuid(productId)) {
      final products = await client.select(
        'products',
        filter: 'id=eq.$productId',
        limit: 1,
      );
      if (products.isNotEmpty) {
        unit = (products.first['price'] as num?)?.toDouble() ?? 0;
      }
    }
    final items = unit * (qty < 1 ? 1 : qty);
    final protectionIfPrepaid = calculateFleaberProtectionFee(
      items,
      shippingEur: shipping,
    );
    final sellerGanhos = liveSellerEarningsEur(
      storedPriceTotal: stored,
      isDirectPayment: isDirect,
      lineItemEur: items,
      shippingEur: shipping,
    );
    if (status.toLowerCase().trim() == 'pago') {
      ganhosStudioEsperado += sellerGanhos;
    }
    breakdowns.add({
      'order_id': o['id'],
      'status': status,
      'quantity': qty,
      'unit_price_eur': unit,
      'items_eur': items,
      'shipping_method': shipMethod,
      'shipping_eur': shipping,
      'payment_method': pay,
      'protection_eur_direct': isDirect ? 0.0 : protectionIfPrepaid,
      'protection_eur_if_prepaid': protectionIfPrepaid,
      'price_total_bd': stored,
      'formula': isDirect
          ? 'artigos + portes (sem protecção)'
          : 'artigos + portes + protecção',
      'expected_total_eur': isDirect ? items + shipping : items + shipping + protectionIfPrepaid,
      'seller_ganhos_eur': sellerGanhos,
      'wrong_studio_old_eur': items + shipping + protectionIfPrepaid,
    });
  }

  final liveItems = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId',
    limit: 50,
  );
  final stockSnaps = <Map<String, dynamic>>[];
  for (final li in liveItems) {
    final id = (li['id'] ?? '').toString();
    if (!isUuid(id)) continue;
    try {
      final stock = await client.rpc('batata_live_item_stock', {
        'p_live_item_id': id,
      });
      stockSnaps.add({
        'live_item_id': id,
        'ref_code': li['ref_code'],
        'stock': stock,
      });
    } catch (e) {
      stockSnaps.add({'live_item_id': id, 'error': e.toString()});
    }
  }

  final payload = {
    'label': label,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    'live_id': liveId,
    'ganhos_studio_esperado_eur': ganhosStudioEsperado,
    'orders': breakdowns,
    'reservations': reservations
        .map(
          (r) => {
            'id': r['id'],
            'status': r['status'],
            'requested_qty': r['requested_qty'],
            'notes': r['notes'],
            'live_item_id': r['live_item_id'],
          },
        )
        .toList(),
    'stock': stockSnaps,
  };

  final json = const JsonEncoder.withIndent('  ').convert(payload);
  print(json);
  if (outPath.isNotEmpty) {
    final f = File(outPath);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(json);
    print('wrote $outPath');
  }
}
