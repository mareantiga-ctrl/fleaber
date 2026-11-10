import 'dart:convert';
import 'dart:io';

Future<void> dump(String sid) async {
  final url = 'https://checkout.stripe.com/c/pay/$sid';
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.headers.set('User-Agent', 'Mozilla/5.0');
    final rs = await rq.close();
    final text = await rs.transform(utf8.decoder).join();
    final out =
        'tool/redteam_blind_cd_20260906T1225/stripe_${sid.substring(0, 22)}.html';
    await File(out).writeAsString(text);
    final keys = [
      'session has expired',
      'This page is not available',
      'expired',
      '"status":"open"',
      '"status":"expired"',
      'payment_status',
      'Submit',
      'Pay',
      'card-number',
      'data-status',
    ];
    stdout.writeln('=== $sid status=${rs.statusCode} len=${text.length}');
    for (final k in keys) {
      final i = text.toLowerCase().indexOf(k.toLowerCase());
      stdout.writeln('  $k -> ${i >= 0 ? i : "NO"}');
    }
    final m = RegExp(r'"status"\s*:\s*"([^"]+)"').allMatches(text).take(8);
    for (final x in m) {
      stdout.writeln('  json status=${x.group(1)}');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  await dump('cs_test_a16NFwMLU4Tq6h3rrzJqbg7QQbtSV4CvXBH6h3t28T7hrYPpTXmdz0Lg5n');
  await dump('cs_test_a1f211Nn90dWmDRqRJnxXgn0EqmtmFik3GsUElohs4q7GjVrYeWDTx6wOd');
}
