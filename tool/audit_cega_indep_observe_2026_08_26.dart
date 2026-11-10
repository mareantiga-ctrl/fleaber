import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final ev = await sb.select(
    'stripe_checkout_events',
    filter: 'order=created_at.desc',
    limit: 8,
  );
  stdout.writeln('checkout_events=${ev.length}');
  for (final e in ev) {
    stdout.writeln(jsonEncode({
      'event': e['event'],
      'order_id': e['order_id'],
      'session_id': e['session_id'],
      'detail': '${e['detail']}'.length > 240
          ? '${e['detail']}'.substring(0, 240)
          : e['detail'],
      'created': e['created_at'],
    }));
  }

  final txs = await sb.select(
    'wallet_transactions',
    filter: 'order=created_at.desc',
    limit: 8,
  );
  stdout.writeln('tx_sample=${jsonEncode(txs.map((t) => {
        'id': t['id'],
        'type': t['type'],
        'amount': t['amount'],
        'desc': t['description'],
        'created': t['created_at'],
        'order_id': t['order_id'],
        'wallet_id': t['wallet_id'],
      }).toList())}');

  for (final t in txs) {
    if (t['amount'] == 12.34 ||
        t['amount'] == 12.34.toString() ||
        '${t['description']}'.contains('Reembolso parcial de 100')) {
      try {
        await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
        stdout.writeln('CLEANUP leftover mint tx ${t['id']} wallet=${t['wallet_id']}');
      } catch (e) {
        stdout.writeln('CLEANUP tx FAIL ${t['id']} $e');
      }
    }
  }
}
