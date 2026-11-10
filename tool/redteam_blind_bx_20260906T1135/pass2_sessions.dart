import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final sids = [
    'cs_test_a15xYaiKeN7BPaybCZop10Nae7U4n8uC9JUjVy8D4pGsdrWbKdfyXjm17z',
    'cs_test_a1fbWiimvd7VgGduDJGdN0p4PGEwY9a3Jkmyw4uO2wSx8RaArqZ8bHsEpK',
    'cs_test_a1KVdYfpb7rXz8kIfDmgRfzgfchKCJmfmYLtxbgzlB5YLePK4mnTU75nEK',
    'cs_test_a1I6A34qwXfyXFYEmubyfycnt7CixOXaNQSbe2m5M2mafbct6P07CMfsaD',
    'cs_test_a1miLUudjzZ6IsLSLNjEeTy5mSZujnforpKDXUhcH43RhBgnOwdxVPja20',
    'cs_test_a1AmUzVsP09nmMSRb8YLYg5J2s0wMVyNFnVfX5PDG8HPyM7kgYEbcMjURR',
    'cs_test_a1XX9RvXIStSc9m0TN6udYllY3DcKULl0Rvpu44lNxV74tF6ON6keMH7V9',
    'cs_test_a1d1CoChNaDsnUpswD8HZzzKQaQ2Z9IA05ZdESO6pZmD9MLJBxYfNURDlt',
    'cs_test_a1Ipx7CqexnJIlSSrH2mf5zmr7rBZOXinK90VxNq5R80av4VMr60Wra6O7',
    'cs_test_a1tuG4udh9nXHAzMCkaucssjWbpsEbfPMFR6hSNLl2tuFlmfXEhQ334l0G',
    'cs_test_a1fwinMq8qn3DjxSNqx3KF4Zu9VJuxg5Xf4OBeXdUfh4PGwuliMQNyslQG',
  ];
  final out = <Map<String, Object?>>[];
  for (final s in sids) {
    final uri = Uri.parse('https://checkout.stripe.com/c/pay/$s');
    final client = HttpClient();
    try {
      final rq = await client.getUrl(uri);
      rq.followRedirects = true;
      final rs = await rq.close();
      final body = await rs.transform(utf8.decoder).join();
      final low = body.toLowerCase();
      final expired = low.contains('expired') ||
          low.contains('session has been') ||
          low.contains('no longer available') ||
          low.contains('this page isn') ||
          low.contains('checkout is not available');
      final pay = low.contains('cardnumber') ||
          low.contains('pay now') ||
          low.contains('card-element') ||
          low.contains('payment-form');
      stdout.writeln(
        '$s status=${rs.statusCode} expired=$expired payish=$pay len=${body.length}',
      );
      out.add({
        'sid': s,
        'status': rs.statusCode,
        'expired_hint': expired,
        'pay_hint': pay,
        'len': body.length,
        'snip': body.length > 500 ? body.substring(0, 500) : body,
      });
    } catch (e) {
      stdout.writeln('$s ERR $e');
      out.add({'sid': s, 'error': '$e'});
    } finally {
      client.close(force: true);
    }
  }
  await File('tool/redteam_blind_bx_20260906T1135/pass2_session_pages.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
}
