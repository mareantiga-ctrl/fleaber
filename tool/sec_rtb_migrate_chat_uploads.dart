// ignore_for_file: avoid_print
/// Migra chat_uploads de chat_media (público) → fleaber_private.
/// Copia objecto a objecto; só apaga do público após cópia OK.
/// dart run tool/sec_rtb_migrate_chat_uploads.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
    exit(2);
  }
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final H = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> req(
    String method,
    String u, {
    Object? body,
    Map<String, String>? headers,
    Uint8List? rawBody,
  }) async {
    final h = {...H, ...?headers};
    late http.Response r;
    if (method == 'POST') {
      r = rawBody != null
          ? await http.post(Uri.parse(u), headers: h, body: rawBody)
          : await http.post(Uri.parse(u),
              headers: h, body: body == null ? null : jsonEncode(body));
    } else if (method == 'DELETE') {
      r = await http.delete(
        Uri.parse(u),
        headers: h,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      r = await http.get(Uri.parse(u), headers: h);
    }
    dynamic p;
    try {
      p = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      p = r.body;
    }
    return {'http': r.statusCode, 'body': p, 'bytes': r.bodyBytes, 'text': r.body};
  }

  // List all under chat_uploads (recursive via API)
  final listed = <String>[];
  Future<void> listPrefix(String prefix) async {
    final res = await req(
      'POST',
      '$url/storage/v1/object/list/chat_media',
      body: {'prefix': prefix, 'limit': 1000},
    );
    if (res['body'] is! List) {
      stderr.writeln('list fail $prefix ${res['http']} ${res['text']}');
      return;
    }
    for (final item in res['body'] as List) {
      if (item is! Map) continue;
      final name = '${item['name'] ?? ''}';
      final id = '${item['id'] ?? ''}';
      if (name.isEmpty) continue;
      final full = prefix.isEmpty ? name : '$prefix$name';
      // folders often have id null / empty
      if (id.isEmpty || id == 'null') {
        await listPrefix('$full/');
      } else {
        listed.add(full);
      }
    }
  }

  await listPrefix('chat_uploads/');
  stdout.writeln('Found ${listed.length} objects under chat_uploads/');

  String mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.txt')) return 'image/png'; // probe legado; bucket sem text/plain
    return 'image/jpeg';
  }

  final report = <Map<String, dynamic>>[];
  for (final path in listed) {
    final enc = path.split('/').map(Uri.encodeComponent).join('/');
    final dl = await req('GET', '$url/storage/v1/object/chat_media/$enc');
    if ((dl['http'] as int) >= 400) {
      report.add({'path': path, 'ok': false, 'step': 'download', 'http': dl['http']});
      stdout.writeln('FAIL download $path ${dl['http']}');
      continue;
    }
    final bytes = dl['bytes'] as Uint8List;
    final up = await req(
      'POST',
      '$url/storage/v1/object/fleaber_private/$enc',
      headers: {
        'Content-Type': mimeFor(path),
        'x-upsert': 'true',
      },
      rawBody: bytes,
    );
    if ((up['http'] as int) >= 400) {
      report.add({
        'path': path,
        'ok': false,
        'step': 'upload_private',
        'http': up['http'],
        'body': up['text'],
      });
      stdout.writeln('FAIL upload private $path ${up['http']} ${up['text']}');
      continue;
    }
    final del = await req(
      'DELETE',
      '$url/storage/v1/object/chat_media',
      body: {'prefixes': [path]},
    );
    final delOk = (del['http'] as int) < 400;
    report.add({
      'path': path,
      'ok': delOk,
      'step': delOk ? 'moved' : 'copied_delete_failed',
      'delete_http': del['http'],
      'delete_body': del['text'],
      'bytes': bytes.length,
    });
    stdout.writeln(
        '${delOk ? "MOVED" : "COPIED_NO_DELETE"} $path (${bytes.length} B) del=${del['http']} ${del['text']}');
  }

  // Verify public CDN residual
  final residual = <Map<String, dynamic>>[];
  for (final path in listed) {
    final pub =
        '$url/storage/v1/object/public/chat_media/${path.split('/').map(Uri.encodeComponent).join('/')}';
    final head = await http.head(Uri.parse(pub), headers: {
      'apikey': envRequire(e, 'SUPABASE_ANON_KEY'),
    });
    residual.add({'path': path, 'public_head': head.statusCode});
  }

  final out = {
    'at': DateTime.now().toIso8601String(),
    'moved': report.where((r) => r['ok'] == true).length,
    'failed': report.where((r) => r['ok'] != true).length,
    'report': report,
    'public_head_after': residual,
  };
  final path =
      'tool/reports/sec_rtb_migrate_chat_uploads_${DateTime.now().millisecondsSinceEpoch}.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('Wrote $path');
  exit(out['failed'] == 0 ? 0 : 1);
}
