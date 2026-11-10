import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final meta = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pay_meta.json').readAsStringSync(),
  ) as Map;
  final oid = meta['order_id'].toString();
  final sa = meta['session_a'].toString();
  final sb = meta['session_b'].toString();

  Future<void> dump(String label) async {
    final orders = await admin.select('orders', filter: 'id=eq.$oid', limit: 1);
    stdout.writeln('== $label ORDER ==');
    if (orders.isEmpty) {
      stdout.writeln('missing');
      return;
    }
    final o = orders.first;
    stdout.writeln(jsonEncode({
      'status': o['status'],
      'amount_paid_cents': o['amount_paid_cents'],
      'pi': o['stripe_payment_intent_id'],
      'cs': o['stripe_checkout_session_id'],
      'refund': o['stripe_refund_id'],
      'price_total': o['price_total'],
      'qty': o['quantity'],
    }));
    final pid = o['product_id'];
    final p = await admin.select('products', filter: 'id=eq.$pid', limit: 1);
    stdout.writeln('PRODUCT ${jsonEncode(p.isEmpty ? {} : {
      'qty': p.first['quantity'],
      'sold': p.first['is_sold'],
    })}');
  }

  await dump('before_settle_get');

  final getA = await http.get(
    Uri.parse('$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sa'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  stdout.writeln('SETTLE A ${getA.statusCode} ${getA.body.length > 400 ? getA.body.substring(0, 400) : getA.body}');
  await dump('after_settle_A');

  final getB = await http.get(
    Uri.parse('$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sb'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  stdout.writeln('SETTLE B ${getB.statusCode} ${getB.body.length > 400 ? getB.body.substring(0, 400) : getB.body}');
  await dump('after_settle_B');

  final ev = await admin.select('stripe_checkout_events', filter: 'order_id=eq.$oid', limit: 30);
  stdout.writeln('EVENTS ${ev.length}');
  for (final e in ev) {
    stdout.writeln('${e['event']} sid=${e['session_id']} ${e['detail']}'.replaceAll('\n', ' '));
  }
}
