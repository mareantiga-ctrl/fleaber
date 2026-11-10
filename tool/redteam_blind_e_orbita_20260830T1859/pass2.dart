/// Blind E órbita — Pass 2: E6 bag-unlist → Stripe TEST capture → BD.
/// Sem produção. Sem Fase 4. Sem fixes.
import 'dart:convert';
import 'dart:io';

import '_http.dart';

Map<String, dynamic> snap = {};

Future<void> main() async {
  final c = await boot();

  Future<Map<String, dynamic>?> row(String table, String id, String cols) async {
    final r = await c.select(table, service: true, select: cols, filter: 'id=eq.$id', limit: 1);
    if (r.ok && r.json is List && (r.json as List).isNotEmpty) {
      return Map<String, dynamic>.from(r.json.first as Map);
    }
    return null;
  }

  Future<String?> insertProduct({
    required String tag,
    bool listed = true,
    int qty = 2,
    double price = 11.0,
  }) async {
    final r = await c.rest('POST', '/rest/v1/products', jwt: c.sellerJwt, body: {
      'seller_id': c.sellerId,
      'title': '$prefix $tag',
      'price': price,
      'quantity': qty,
      'is_sold': false,
      'list_on_marketplace': listed,
      'description': prefix,
    });
    if (!r.ok) {
      stderr.writeln('product $tag ${r.status} ${r.snippet}');
      return null;
    }
    final d = r.json;
    if (d is List && d.isNotEmpty) return (d.first as Map)['id']?.toString();
    if (d is Map) return d['id']?.toString();
    return null;
  }

  Future<String?> insertOrder(String pid, {double price = 11.0}) async {
    final r = await c.rest('POST', '/rest/v1/orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': price,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'shipping_method': 'mao',
    });
    stderr.writeln('order ${r.status} ${r.snippet}');
    if (!r.ok) return null;
    final d = r.json;
    if (d is List && d.isNotEmpty) return (d.first as Map)['id']?.toString();
    if (d is Map) return d['id']?.toString();
    return null;
  }

  Future<Hit> bagCheckout(List<Map<String, dynamic>> lines) {
    return c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': lines.first['product_id'],
      'order_id': lines.first['order_id'],
      'quantity': 1,
      'currency': 'eur',
      'shipping_method': 'mao',
      'bag_checkout': true,
      'bag_lines': lines,
    }, jwt: c.buyerJwt);
  }

  Future<Hit> singleCheckout(String oid, String pid) {
    return c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'order_id': oid,
      'quantity': 1,
      'currency': 'eur',
      'shipping_method': 'mao',
    }, jwt: c.buyerJwt);
  }

  Map<String, dynamic> parseCheckout(Hit h) {
    final j = h.json;
    if (j is Map) {
      return {
        'http': h.status,
        'error': j['error'],
        'checkoutUrl': j['checkoutUrl'] ?? j['url'],
        'sessionId': j['checkoutSessionId'] ?? j['session_id'],
        'amount_total': j['amount_total'] ?? j['amount'],
      };
    }
    return {'http': h.status, 'raw': h.snippet};
  }

  // --- A: listed → hold → unlist → single block / bag open ---
  final pidA = await insertProduct(tag: 'P2-unlist', qty: 2, price: 11.0);
  if (pidA == null) {
    stderr.writeln('fail product A');
    return;
  }
  final oidA = await insertOrder(pidA);
  if (oidA == null) {
    stderr.writeln('fail order A');
    return;
  }

  final beforeUnlist = await row('products', pidA, 'id,quantity,is_sold,list_on_marketplace,title,price');
  final orderBefore = await row(
    'orders',
    oidA,
    'id,status,quantity,price_total,stripe_checkout_session_id,amount_paid_cents',
  );

  final ul = await c.rest('PATCH', '/rest/v1/products?id=eq.$pidA', jwt: c.sellerJwt, body: {
    'list_on_marketplace': false,
  });
  final afterUnlist = await row('products', pidA, 'id,quantity,is_sold,list_on_marketplace');

  final hubAfter = await c.select(
    'hub_products_public',
    select: 'id,title,is_sold',
    filter: 'id=eq.$pidA',
    limit: 3,
  );
  final baseAnon = await c.select(
    'products',
    select: 'id,title,list_on_marketplace,is_sold',
    filter: 'id=eq.$pidA',
    limit: 3,
  );

  final single = await singleCheckout(oidA, pidA);
  final bag = await bagCheckout([
    {'order_id': oidA, 'product_id': pidA, 'seller_id': c.sellerId, 'quantity': 1},
  ]);
  final bagParsed = parseCheckout(bag);

  snap['A'] = {
    'product_id': pidA,
    'order_id': oidA,
    'unlist_http': ul.status,
    'product_before': beforeUnlist,
    'product_after_unlist': afterUnlist,
    'order_before': orderBefore,
    'hub_public': {'http': hubAfter.status, 'n': hubAfter.ok && hubAfter.json is List ? (hubAfter.json as List).length : -1, 'snip': hubAfter.snippet},
    'anon_products': {'http': baseAnon.status, 'snip': baseAnon.snippet},
    'single': parseCheckout(single),
    'bag': bagParsed,
  };

  // --- B: two-line bag, one unlisted one listed ---
  final pidB = await insertProduct(tag: 'P2-listed-keep', qty: 2, price: 11.0);
  String? oidB;
  if (pidB != null) {
    oidB = await insertOrder(pidB);
    if (oidB != null) {
      final mixed = await bagCheckout([
        {'order_id': oidA, 'product_id': pidA, 'seller_id': c.sellerId, 'quantity': 1},
        {'order_id': oidB, 'product_id': pidB, 'seller_id': c.sellerId, 'quantity': 1},
      ]);
      snap['mixed_bag'] = parseCheckout(mixed);
    }
  }

  // wallet snapshot (no credit expected until concluido)
  final wal = await row('wallets', c.sellerId, 'id,balance,stripe_account_id');
  snap['seller_wallet'] = wal;

  await writeOut('pass2.json', {
    'notes': [
      'E6 bag-unlist: single deve 400; bag Session TEST.',
      'Pagar checkoutUrl no browser (4242).',
      'Não tocar produção.',
    ],
    'snap': snap,
  });

  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'product_a': pidA,
    'order_a': oidA,
    'single_http': single.status,
    'single_err': parseCheckout(single)['error'],
    'bag_http': bag.status,
    'bag_session': bagParsed['sessionId'],
    'bag_url_present': bagParsed['checkoutUrl'] != null,
    'mixed': snap['mixed_bag'],
  }));

  final url = bagParsed['checkoutUrl']?.toString();
  if (url != null && url.contains('checkout.stripe.com')) {
    File('$outDir/PAY_THIS_URL.txt').writeAsStringSync('$url\n');
    stdout.writeln('PAY_URL=$url');
  }
}
