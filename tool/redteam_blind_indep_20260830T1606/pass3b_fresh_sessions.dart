import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) exit(2);
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final jwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': 'RTI1606 pay ${DateTime.now().millisecondsSinceEpoch}',
    'price': 7.5,
    'quantity': 1,
    'ref_code': 'PAY-${Random().nextInt(999999)}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  final order = await admin.insertAsUser('orders', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': prod['id'],
    'price_total': 7.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  }, accessToken: jwt);
  final oid = order['id'].toString();
  final req = {
    'order_id': oid,
    'buyer_id': buyerId,
    'shipping_method': 'entrega em mão',
  };
  final pair = await Future.wait([
    admin.invokeEdge('create-payment-intent', req, accessToken: jwt),
    admin.invokeEdge('create-payment-intent', req, accessToken: jwt),
  ]);
  final a = pair[0];
  final b = pair[1];
  Map<String, dynamic> pa = {};
  Map<String, dynamic> pb = {};
  try { pa = jsonDecode(a.body) as Map<String, dynamic>; } catch (_) {}
  try { pb = jsonDecode(b.body) as Map<String, dynamic>; } catch (_) {}
  final ua = pa['checkoutUrl']?.toString() ?? '';
  final ub = pb['checkoutUrl']?.toString() ?? '';
  stdout.writeln('order=$oid');
  stdout.writeln('a_status=${a.statusCode} url_len=${ua.length} session=${pa['checkoutSessionId']} amount=${pa['amount_total']} reused=${pa['reused_session']}');
  stdout.writeln('b_status=${b.statusCode} url_len=${ub.length} session=${pb['checkoutSessionId']} amount=${pb['amount_total']} reused=${pb['reused_session']}');
  stdout.writeln('same_session=${pa['checkoutSessionId'] == pb['checkoutSessionId']}');
  File('tool/redteam_blind_indep_20260830T1606/out/pay_a.url').writeAsStringSync(ua);
  File('tool/redteam_blind_indep_20260830T1606/out/pay_b.url').writeAsStringSync(ub);
  File('tool/redteam_blind_indep_20260830T1606/out/pay_meta.json').writeAsStringSync(jsonEncode({
    'order_id': oid,
    'product_id': prod['id'],
    'session_a': pa['checkoutSessionId'],
    'session_b': pb['checkoutSessionId'],
    'amount_a': pa['amount_total'],
    'amount_b': pb['amount_total'],
    'reused_a': pa['reused_session'],
    'reused_b': pb['reused_session'],
    'url_a_len': ua.length,
    'url_b_len': ub.length,
  }));
}
