/// Re-oracle B1/B3/B7 cs_ with specific expired copy (not substring 'expired').
import 'dart:io';

import '_rtdz.dart';

Future<Map<String, Object?>> inspect(String sid) async {
  final url = 'https://checkout.stripe.com/c/pay/$sid';
  final page = await Rtdb.fromEnv(loadEnv()).rawGet(url);
  final b = page.body;
  final lower = b.toLowerCase();
  return {
    'sid': sid,
    'http': page.status,
    'len': b.length,
    'has_this_checkout_session_has_expired':
        lower.contains('this checkout session has expired'),
    'has_session_has_expired': lower.contains('session has expired'),
    'has_expired_exact_h1': lower.contains('>expired<') ||
        lower.contains('session-expired') ||
        lower.contains('checkoutsessionexpired'),
    'has_pay_form': lower.contains('card-number') ||
        lower.contains('payment-form') ||
        lower.contains('Pay') && lower.contains('card'),
    'has_submit': lower.contains('submit') || lower.contains('pay now'),
    'snippet': clip(b.replaceAll(RegExp(r'\s+'), ' '), 400),
  };
}

Future<void> main() async {
  final sids = [
    'cs_test_a1tb6kvvPlkXRdRUswi745JIDqJjbexzik7Dse4yuvLt8kTAJUnvs4p2Db', // B1 t0 ledger
    'cs_test_a1ma4E8xFJu4YanRQpWHDr4kIHjs7AwgEwwG26MhrReLemGg3qKMPcYMDB', // B1 t0 orphan
    'cs_test_a1c4PtL68rCTjhWymwkgOQhJG68OGbeLSEPlHXwdlVBNzQvbX2bOXvzRNs', // B1 t50 ledger
    'cs_test_a1sAVIdPxrDO0mVFuaRs2qkKLZZEhJJTnJtK3B3rQ7QWCumHrxWV6RhsoK', // B1 t50 orphan
    'cs_test_a10VhLZg3sGvJNgu3NFCZPbOuswDJlvS5C3NVqIUKVwbld97qpWH77HJKd', // B3 a
    'cs_test_a1H6w0VDPsAoYo79lcRcgk0pgm3C14UCgvmtcC9fOGFisAwq4JyQG4e5LI', // B3 b
    'cs_test_a1XcTK4paXG86lhQgIklmxFmHhmSkR1WwImSHZ97h6I7FeMpa4nLD4scGw', // B7 subset
    'cs_test_a1ZkjgmVjkLlLZBmU1fyaERJQnuj8VMjCpnq5w5grJHNYyFPUHQ8L7KkhY', // B7 super
    'cs_test_a1CML9TPsichiBarkJk5omgjdkHKfvszO1j2hz1FlUiabm5qTB02kTDoym', // B5 a
    'cs_test_a15dxA4gM3yyjsZaJWImJCfU9N4SwvYKZ3VO0VV2jJovK3tm6Y2px3FFv7', // B5 b
    'cs_test_a1b7cqHmdwEyHRyVhvfGdCtLAiXMJpd99df2v5onRGEaG1vn00Ws9Yg2kl', // B6 a
    'cs_test_a17VS2sbIngK9rwQP3VWySGQHCj8SNTxWAfLF1v4JJtbN700JxhMYuokuE', // B6 b
  ];
  final out = <Map<String, Object?>>[];
  // reuse one client via helper
  for (final sid in sids) {
    final url = 'https://checkout.stripe.com/c/pay/$sid';
    final c = Rtdb.fromEnv(loadEnv());
    final page = await c.rawGet(url);
    final b = page.body;
    final lower = b.toLowerCase();
    final row = {
      'sid': sid,
      'http': page.status,
      'len': b.length,
      'this_checkout_session_has_expired':
          lower.contains('this checkout session has expired'),
      'session_has_expired': lower.contains('session has expired'),
      'session_expired_token': lower.contains('session-expired') ||
          lower.contains('checkoutsessionexpired') ||
          lower.contains('cs_expired'),
      'generic_expired_count': 'expired'.allMatches(lower).length,
      'has_card': lower.contains('cardnumber') ||
          lower.contains('card-number') ||
          lower.contains('data-tid="cardNumber"'),
      'snippet': clip(b.replaceAll(RegExp(r'\s+'), ' '), 280),
    };
    out.add(row);
    stdout.writeln(
      '${sid.substring(0, 28)} http=${page.status} '
      'expiredPhrase=${row['this_checkout_session_has_expired']} '
      'generic=${row['generic_expired_count']} card=${row['has_card']} len=${page.body.length}',
    );
  }
  await dumpJson('${outDir()}/oracle_recheck.json', out);
}
