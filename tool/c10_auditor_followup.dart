// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

/// C10 follow-up auditor: imagens, duplicados, leitura anónima.
void main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final service = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  Future<List<Map<String, dynamic>>> rest({
    required String table,
    required Map<String, String> headers,
    required String query,
  }) async {
    final res = await http.get(
      Uri.parse('$url/rest/v1/$table?$query'),
      headers: headers,
    );
    if (res.statusCode >= 400) {
      throw HttpException('$table ${res.statusCode}: ${res.body}');
    }
    final list = jsonDecode(res.body);
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  final anonHeaders = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };

  final products = await client.select(
    'products',
    filter:
        'seller_id=eq.$seller&list_on_marketplace=eq.true&is_sold=eq.false&order=created_at.desc',
    limit: 40,
  );

  final hubAnon = await rest(
    table: 'hub_products_public',
    headers: anonHeaders,
    query:
        'seller_id=eq.$seller&is_sold=eq.false&order=created_at.desc&select=id,title,price,image_urls,created_at&limit=40',
  );

  final profileAnon = await rest(
    table: 'hub_profiles_public',
    headers: anonHeaders,
    query: 'id=eq.$seller&select=id,full_name,handle',
  );

  final reviewsAnon = await rest(
    table: 'hub_reviews_public',
    headers: anonHeaders,
    query: 'target_id=eq.$seller&select=id,stars&limit=10',
  );

  Map<String, dynamic> slim(Map<String, dynamic> p) {
    final urls = p['image_urls'];
    final list = urls is List ? urls.map((e) => e.toString()).toList() : <String>[];
    return {
      'id': p['id'],
      'title': p['title'] ?? p['name'],
      'price': p['price'],
      'created_at': p['created_at'],
      'image_count': list.length,
      'image_urls': list,
    };
  }

  final listed = products.map(slim).toList();
  final byTitle = <String, List<String>>{};
  for (final p in listed) {
    final t = '${p['title']}';
    byTitle.putIfAbsent(t, () => []).add('${p['id']}');
  }
  final dupes = {
    for (final e in byTitle.entries)
      if (e.value.length > 1) e.key: e.value,
  };

  final imgDir = Directory(
    'tool/reports/battery_c10_2026-08-18/evidence/product_images',
  );
  imgDir.createSync(recursive: true);
  final imageMeta = <Map<String, dynamic>>[];
  for (final p in listed) {
    final title = '${p['title']}';
    final id = '${p['id']}'.substring(0, 8);
    final urls = (p['image_urls'] as List).cast<String>();
    if (urls.isEmpty) {
      imageMeta.add({
        'id': p['id'],
        'title': title,
        'has_image': false,
      });
      continue;
    }
    final u = urls.first;
    try {
      final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
      final safeName = title
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .trim();
      final file = File('${imgDir.path}/${id}_$safeName.jpg');
      file.writeAsBytesSync(res.bodyBytes);
      imageMeta.add({
        'id': p['id'],
        'title': title,
        'has_image': true,
        'http_status': res.statusCode,
        'bytes': res.bodyBytes.length,
        'content_type': res.headers['content-type'],
        'file': file.path,
        'url_host': Uri.parse(u).host,
      });
    } catch (e) {
      imageMeta.add({
        'id': p['id'],
        'title': title,
        'has_image': true,
        'error': e.toString(),
      });
    }
  }

  final hubIds = hubAnon.map((e) => e['id']).toSet();
  final productIds = listed.map((e) => e['id']).toSet();

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'anon_no_user_jwt': {
      'profile_ok': profileAnon.isNotEmpty,
      'profile': profileAnon.isEmpty ? null : profileAnon.first,
      'hub_products_count': hubAnon.length,
      'reviews_count': reviewsAnon.length,
    },
    'listed_products_service': listed,
    'duplicates_by_title': dupes,
    'id_match_hub_anon_vs_products': {
      'only_in_products': productIds.difference(hubIds).toList(),
      'only_in_hub': hubIds.difference(productIds).toList(),
      'same_count': productIds.length == hubIds.length,
    },
    'images': imageMeta,
  };

  final file = File(
    'tool/reports/battery_c10_2026-08-18/evidence/c10_auditor_followup.json',
  );
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${file.path}');
  print(jsonEncode({
    'listed': listed.length,
    'dupes': dupes.map((k, v) => MapEntry(k, v.length)),
    'anon_products': hubAnon.length,
    'anon_profile': profileAnon.isNotEmpty,
    'images': imageMeta.length,
  }));
}
