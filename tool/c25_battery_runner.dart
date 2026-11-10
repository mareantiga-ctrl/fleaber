// ignore_for_file: avoid_print
/// C25 battery runner — logs + snapshots BD entre passos.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final step = args.isEmpty ? 'snapshot' : args.first;
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final outDir = Directory('tool/reports/battery_c25_2026-08-22');
  final bdDir = Directory('${outDir.path}/bd');
  final logFile = File('${outDir.path}/c25_battery.log');
  await bdDir.create(recursive: true);

  void log(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    print(line);
    logFile.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  const orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  const chatId = '5350ea04-b246-4904-8fb7-7d4d53e15187';

  Future<Map<String, dynamic>> snap(String label) async {
    final order = (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
    final disputes = await sb.select('order_disputes', filter: 'order_id=eq.$orderId', limit: 5);
    final msgs = await sb.select(
      'chat_messages',
      filter: 'chat_id=eq.$chatId&order=created_at.desc',
      limit: 8,
    );
    final data = {
      'label': label,
      'at': DateTime.now().toIso8601String(),
      'order_status': order['status'],
      'order_id': orderId,
      'chat_id': chatId,
      'disputes_count': disputes.length,
      'recent_chat': msgs
          .map((m) => {
                'created_at': m['created_at'],
                'text': (m['text'] ?? '').toString().length > 160
                    ? '${(m['text'] ?? '').toString().substring(0, 160)}…'
                    : m['text'],
              })
          .toList(),
    };
    final f = File('${bdDir.path}/c25_${label}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    log('SNAP $label status=${order['status']} disputes=${disputes.length}');
    return data;
  }

  if (step == 'snapshot' || step.startsWith('snap_')) {
    final label = step == 'snapshot' ? 'manual' : step.substring(5);
    await snap(label);
    return;
  }

  log('unknown step=$step');
}
