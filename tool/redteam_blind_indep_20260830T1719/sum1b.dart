import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1719/out/pass1.json').readAsStringSync(),
  ) as Map;
  bool match(Map m, String s, String a, String i) {
    return '${m['surface']}'.contains(s) &&
        '${m['attack']}'.contains(a) &&
        (i.isEmpty || '${m['identity']}' == i);
  }

  void dump(String label, bool Function(Map) pred) {
    stdout.writeln('\n==== $label ====');
    for (final raw in (j['matrix'] as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (!pred(m)) continue;
      stdout.writeln(
        jsonEncode({
          'i': m['identity'],
          's': m['surface'],
          'a': m['attack'],
          'impact': m['impact'],
          'result': m['result'],
          'evidence': m['evidence'],
        }),
      );
    }
  }

  dump('openapi', (m) => '${m['surface']}' == 'PostgREST');
  dump('offer amount patch', (m) => match(m, 'product_offers', 'PATCH amount', ''));
  dump('connect-account', (m) => '${m['surface']}'.contains('create-connect-account'));
  dump('payment-intent', (m) => '${m['surface']}'.contains('create-payment-intent'));
  dump('refund', (m) => '${m['surface']}'.contains('refund'));
  dump('mux', (m) => '${m['surface']}'.contains('mux') || '${m['surface']}'.contains('lives'));
  dump('wallet patch', (m) => '${m['surface']}' == 'wallets');
  dump('reviews', (m) => '${m['surface']}' == 'reviews');
  dump('e2e', (m) => '${m['surface']}'.contains('e2e') || '${m['surface']}'.contains('delete-test'));
  dump('webhook', (m) => '${m['surface']}'.contains('webhook'));
  dump('storage', (m) => '${m['surface']}'.startsWith('storage'));
  dump('payout rpc', (m) => '${m['surface']}'.contains('payout') || '${m['surface']}'.contains('ensure_wallet'));
  dump('tip', (m) => '${m['surface']}'.contains('tip'));
  dump('ocr pairing sms', (m) => '${m['surface']}'.contains('ocr') || '${m['surface']}'.contains('pairing') || '${m['surface']}'.contains('sms'));
  dump('admin email', (m) => '${m['surface']}'.contains('find_user') || '${m['surface']}'.contains('is_admin'));
  dump('stripe events', (m) => '${m['surface']}'.contains('stripe_checkout'));
}
