// ignore_for_file: avoid_print
/// Remove objectos legados order_proofs/order_disputes do bucket público chat_media.
/// dart run tool/sec_pos_auditoria_purge_legacy_proofs.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<int> purgePrefix(String url, String service, String prefix) async {
  var removed = 0;
  while (true) {
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': prefix, 'limit': 100}),
    );
    if (res.statusCode >= 400) {
      print('list $prefix failed ${res.statusCode} ${res.body}');
      return removed;
    }
    final list = jsonDecode(res.body);
    if (list is! List || list.isEmpty) {
      print('$prefix done removed=$removed');
      return removed;
    }
    final paths = <String>[];
    for (final e in list) {
      if (e is Map && e['name'] != null && e['id'] != null) {
        paths.add('$prefix/${e['name']}');
      }
    }
    if (paths.isEmpty) return removed;
    final del = await http.delete(
      Uri.parse('$url/storage/v1/object/chat_media'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefixes': paths}),
    );
    print('remove batch=${paths.length} http=${del.statusCode} ${del.body}');
    if (del.statusCode >= 300) {
      // fallback: one-by-one via remove endpoint
      final del2 = await http.post(
        Uri.parse('$url/storage/v1/object/remove/chat_media'),
        headers: {
          'apikey': service,
          'Authorization': 'Bearer $service',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'prefixes': paths}),
      );
      print('remove2 http=${del2.statusCode} ${del2.body}');
      if (del2.statusCode >= 300) return removed;
    }
    removed += paths.length;
    if (paths.length < 100) break;
  }
  return removed;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  var total = 0;
  for (final p in ['order_proofs', 'order_disputes']) {
    total += await purgePrefix(url, service, p);
  }
  print('TOTAL_REMOVED=$total');
}
