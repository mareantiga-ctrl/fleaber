// ignore_for_file: avoid_print
/// Seed staging Vendora Mux C — artigos com foto, quota Mux livre.
/// dart run tool/seed_staging_muxc_seller.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');

  const email = 'vendora.muxc+0921@fleaber.test';
  const password = 'testeteste';
  const fullName = 'Vendora Mux C';
  const handle = 'vendora-muxc-0921';
  final tag = Random().nextInt(1 << 28).toRadixString(16);

  final headers = {
    'apikey': service,
    'Authorization': 'Bearer $service',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  // Resolve user id (create if missing)
  String? uid;
  final listRes = await http.get(
    Uri.parse('$url/auth/v1/admin/users?page=1&per_page=200'),
    headers: headers,
  );
  if (listRes.statusCode >= 300) {
    throw HttpException('list users ${listRes.statusCode}: ${listRes.body}');
  }
  final users = (jsonDecode(listRes.body) as Map)['users'] as List? ?? [];
  for (final u in users) {
    final m = u as Map;
    if ((m['email'] as String?)?.toLowerCase() == email) {
      uid = m['id'] as String?;
      break;
    }
  }
  if (uid == null) {
    final created = await http.post(
      Uri.parse('$url/auth/v1/admin/users'),
      headers: headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
        'user_metadata': {'full_name': fullName},
      }),
    );
    if (created.statusCode >= 300) {
      throw HttpException('create ${created.statusCode}: ${created.body}');
    }
    final jm = jsonDecode(created.body) as Map;
    uid = (jm['id'] ?? (jm['user'] as Map?)?['id']) as String?;
  } else {
    await http.put(
      Uri.parse('$url/auth/v1/admin/users/$uid'),
      headers: headers,
      body: jsonEncode({'password': password, 'email_confirm': true}),
    );
  }
  if (uid == null || uid.isEmpty) {
    throw StateError('uid em falta');
  }
  print('seller_id=$uid');

  // Profile
  final patch = await http.patch(
    Uri.parse('$url/rest/v1/profiles?id=eq.$uid'),
    headers: headers,
    body: jsonEncode({
      'user_type': 'vendedor',
      'handle': handle,
      'hub_published': true,
      'hub_bio': 'Conta staging Mux C — quota livre. Artigos com foto.',
      'full_name': fullName,
      'location': 'Portugal',
      'shipping_country': 'PT',
    }),
  );
  print('profile_patch=${patch.statusCode} ${patch.body}');
  if (patch.statusCode >= 300 || patch.body == '[]' || patch.body.isEmpty) {
    final ins = await http.post(
      Uri.parse('$url/rest/v1/profiles'),
      headers: headers,
      body: jsonEncode({
        'id': uid,
        'user_type': 'vendedor',
        'handle': handle,
        'hub_published': true,
        'hub_bio': 'Conta staging Mux C — quota livre. Artigos com foto.',
        'full_name': fullName,
        'location': 'Portugal',
        'shipping_country': 'PT',
      }),
    );
    print('profile_insert=${ins.statusCode} ${ins.body}');
  }

  final prof = await http.get(
    Uri.parse(
      '$url/rest/v1/profiles?id=eq.$uid&select=id,handle,full_name,user_type,hub_published',
    ),
    headers: headers,
  );
  print('profile=${prof.body}');

  // Clear prior CCC*
  await http.delete(
    Uri.parse('$url/rest/v1/products?seller_id=eq.$uid&ref_code=like.CCC*'),
    headers: headers,
  );

  const listings = [
    ('CCC1', 'Caneca cerâmica azul', 12.0, 10),
    ('CCC2', 'Taça artesanal bege', 15.0, 8),
    ('CCC3', 'Prato raso vintage', 18.0, 6),
    ('CCC4', 'Jarro vidro âmbar', 22.0, 5),
    ('CCC5', 'Conjunto chá 2 peças', 28.0, 4),
  ];

  final inserted = <Map<String, dynamic>>[];
  for (final L in listings) {
    final res = await http.post(
      Uri.parse('$url/rest/v1/products'),
      headers: headers,
      body: jsonEncode({
        'seller_id': uid,
        'title': L.$2,
        'price': L.$3,
        'quantity': L.$4,
        'ref_code': L.$1,
        'available_for_live': true,
        'list_on_marketplace': true,
        'is_sold': false,
        'state': 'Bom',
        'category': 'Casa',
        'image_urls': [
          'https://picsum.photos/seed/fleaber-${L.$1}-$tag/600/800',
        ],
      }),
    );
    if (res.statusCode >= 300) {
      throw HttpException('product ${L.$1} ${res.statusCode}: ${res.body}');
    }
    final row = (jsonDecode(res.body) as List).first as Map<String, dynamic>;
    inserted.add(row);
    print('product ${L.$1} ok img=${(row['image_urls'] as List).first}');
  }

  // Login check
  final login = await http.post(
    Uri.parse('$url/auth/v1/token?grant_type=password'),
    headers: {
      'apikey': anon,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'email': email, 'password': password}),
  );
  if (login.statusCode >= 300) {
    throw HttpException('login ${login.statusCode}: ${login.body}');
  }
  print('login_ok');

  // Update live_ops_staging.env seller keys
  final envPath = File('tool/live_ops_staging.env');
  var text = await envPath.readAsString();
  text = text.replaceAllMapped(
    RegExp(r'^LIVE_OPS_TEST_SELLER_ID=.*$', multiLine: true),
    (_) => 'LIVE_OPS_TEST_SELLER_ID=$uid',
  );
  text = text.replaceAllMapped(
    RegExp(r'^LIVE_OPS_TEST_SELLER_EMAIL=.*$', multiLine: true),
    (_) => 'LIVE_OPS_TEST_SELLER_EMAIL=$email',
  );
  text = text.replaceAllMapped(
    RegExp(r'^LIVE_OPS_TEST_SELLER_PASSWORD=.*$', multiLine: true),
    (_) => 'LIVE_OPS_TEST_SELLER_PASSWORD=$password',
  );
  await envPath.writeAsString(text);
  print('updated tool/live_ops_staging.env');

  final maestro = File('.maestro/.env');
  if (await maestro.exists()) {
    var m = await maestro.readAsString();
    m = m.replaceAllMapped(
      RegExp(r'^MAESTRO_SELLER_EMAIL=.*$', multiLine: true),
      (_) => 'MAESTRO_SELLER_EMAIL=$email',
    );
    m = m.replaceAllMapped(
      RegExp(r'^MAESTRO_SELLER_PASSWORD=.*$', multiLine: true),
      (_) => 'MAESTRO_SELLER_PASSWORD=$password',
    );
    m = m.replaceAllMapped(
      RegExp(r'^MAESTRO_SELLER_EMAIL_URL=.*$', multiLine: true),
      (_) =>
          'MAESTRO_SELLER_EMAIL_URL=${Uri.encodeComponent(email)}',
    );
    await maestro.writeAsString(m);
    print('updated .maestro/.env');
  }

  final report = {
    'email': email,
    'password': password,
    'id': uid,
    'handle': handle,
    'full_name': fullName,
    'products': inserted
        .map(
          (p) => {
            'ref': p['ref_code'],
            'title': p['title'],
            'price': p['price'],
            'qty': p['quantity'],
            'image': (p['image_urls'] as List?)?.first,
          },
        )
        .toList(),
  };
  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/staging_muxc_seller_0921.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  print('report=tool/reports/staging_muxc_seller_0921.json');
}
