// ignore_for_file: avoid_print
/// Lista o que a chave anónima consegue VER no REST (sem dumps).
/// Não faz PATCH/DELETE. Só GET limit=0 / OpenAPI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final headers = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Accept': 'application/openapi+json',
  };

  final specRes = await http.get(Uri.parse('$url/rest/v1/'), headers: headers);
  print('openapi_status=${specRes.statusCode}');
  final names = <String>{};
  if (specRes.statusCode == 200 && specRes.body.isNotEmpty) {
    try {
      final spec = jsonDecode(specRes.body);
      if (spec is Map && spec['paths'] is Map) {
        for (final key in (spec['paths'] as Map).keys) {
          final p = key.toString();
          if (p.startsWith('/') && !p.contains('{')) {
            names.add(p.replaceFirst('/', ''));
          }
        }
      }
    } catch (e) {
      print('openapi_parse_error=$e');
    }
  }
  final sorted = names.toList()..sort();
  print('anon_openapi_tables=${sorted.length}');
  for (final n in sorted) {
    print('table:$n');
  }

  const suspects = [
    'spatial_ref_sys',
    'geography_columns',
    'geometry_columns',
    'raster_columns',
    'raster_overviews',
  ];
  for (final t in suspects) {
    final r = await http.get(
      Uri.parse('$url/rest/v1/$t?select=*&limit=0'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Prefer': 'count=exact',
      },
    );
    final cr = r.headers['content-range'];
    print('suspect $t status=${r.statusCode} content-range=$cr');
  }
}
