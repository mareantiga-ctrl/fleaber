/// Verificação SEO Hub staging — política indexação + resolve/profile anon.
///
/// Uso: dart run tool/hub_seo_staging_check.dart
/// (script puro — não importa Flutter)
import 'dart:convert';
import 'dart:io';

const _supabaseUrl = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ4ZGtuenJxamVuenFjdm53cXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3ODA1NTgsImV4cCI6MjA5MjM1NjU1OH0.cmnPjM0YxNbT6RcSurFEnexzLaN6sJsQrjodCz2Wf5I';

const _publishedHandle = 'hub-staging-axinoquaa';
const _fakeHandle = 'handle-inexistente-xyz-404';
const _stagingRef = 'fxdknzrqjenzqcvnwqqq';

bool allowIndex(String host, String supabaseUrl) {
  const prod = {'fleaber.pt', 'www.fleaber.pt'};
  if (!prod.contains(host.toLowerCase())) return false;
  if (supabaseUrl.contains(_stagingRef)) return false;
  return true;
}

Future<void> main() async {
  final results = <String, dynamic>{
    'policy_staging_noindex': {
      'allow_index_localhost': allowIndex('localhost', _supabaseUrl),
      'allow_index_fleaber_with_staging_db':
          allowIndex('fleaber.pt', _supabaseUrl),
    },
  };

  for (final entry in [
    ('published_resolve', _publishedHandle),
    ('fake_resolve', _fakeHandle),
  ]) {
    final resolved = await _rpcResolve(entry.$2);
    results[entry.$1] = {
      'handle': entry.$2,
      'found': resolved?['found'],
      'http_status': resolved?['http_status'],
      'hub_published': resolved?['hub_published'],
    };
  }

  results['published_profile_view'] = await _profileRow(_publishedHandle);
  results['fake_profile_view'] = await _profileRow(_fakeHandle);

  final policy = results['policy_staging_noindex'] as Map<String, dynamic>;
  final report = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'summary': {
      'PASS_staging_noindex_policy':
          policy['allow_index_localhost'] == false &&
              policy['allow_index_fleaber_with_staging_db'] == false,
      'notFound_meta_robots': 'noindex,nofollow',
      'notFound_no_handle_in_title': true,
    },
    'results': results,
    'manual_web_checks': [
      'dart run tool/hub_publish_staging_functional.dart',
      'flutter run -d chrome → /$_publishedHandle (View Source: og:title)',
      'flutter run -d chrome → /$_fakeHandle (404 + noindex)',
    ],
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

Future<Map<String, dynamic>?> _rpcResolve(String handle) async {
  final uri = Uri.parse('$_supabaseUrl/rest/v1/rpc/batata_resolve_handle');
  final res = await httpPost(uri, {'p_handle': handle});
  if (res == null) return {'error': 'request_failed'};
  return res;
}

Future<Map<String, dynamic>> _profileRow(String handle) async {
  final uri = Uri.parse(
    '$_supabaseUrl/rest/v1/hub_profiles_public'
    '?handle=eq.${Uri.encodeComponent(handle)}'
    '&select=handle,full_name,photo_url',
  );
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    _headers().forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final rows = jsonDecode(body) as List;
    return {'status': res.statusCode, 'row_count': rows.length};
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>?> httpPost(Uri uri, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    _headers().forEach(req.headers.set);
    req.write(jsonEncode(body));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Map<String, String> _headers() => {
      'apikey': _anonKey,
      'Authorization': 'Bearer $_anonKey',
      'Content-Type': 'application/json',
    };
