// ignore_for_file: avoid_print
/// Probe legado público chat_media/order_proofs.
/// dart run tool/sec_pos_auditoria_probe_legacy_proofs.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final known = 'order_proofs/1778673939223_1000000036.jpg';

  final g = await http.get(
    Uri.parse('$url/storage/v1/object/public/chat_media/$known'),
  );
  print('GET_PUBLIC known http=${g.statusCode} bytes=${g.bodyBytes.length}');

  for (final prefix in <String?>[null, '', 'order_proofs', 'order_proofs/']) {
    final body = <String, dynamic>{'limit': 100};
    if (prefix != null) body['prefix'] = prefix;
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(res.body);
    final n = decoded is List ? decoded.length : -1;
    print('LIST prefix=${prefix ?? "(omit)"} http=${res.statusCode} n=$n');
    if (decoded is List && decoded.isNotEmpty) {
      for (final e in decoded.take(8)) {
        print('  $e');
      }
    }
  }

  // Delete known by exact path (Storage API: POST remove with prefixes array)
  final del = await http.post(
    Uri.parse('$url/storage/v1/object/remove/chat_media'),
    headers: {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'prefixes': [known],
    }),
  );
  print('REMOVE known http=${del.statusCode} body=${del.body}');

  final g2 = await http.get(
    Uri.parse('$url/storage/v1/object/public/chat_media/$known'),
  );
  print('GET_PUBLIC after http=${g2.statusCode} bytes=${g2.bodyBytes.length}');
}
