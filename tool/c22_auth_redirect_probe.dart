// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  const email = 'agostinhomarina334@gmail.com';

  final redirects = [
    'fleaber://fleaber.com/auth-callback?fleaber_recovery=1',
    'fleaber://fleaber.com/auth-callback',
    'https://fleaber.pt/fleahub/index.html?fleaber_recovery=1',
  ];

  print('# recover (anon) — redirect_to probe');
  for (final rt in redirects) {
    final res = await http.post(
      Uri.parse('$url/auth/v1/recover'),
      headers: {'apikey': anon, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'redirect_to': rt}),
    );
    print('  $rt -> ${res.statusCode} ${res.body.trim()}');
  }

  print('\n# generate_link (admin) — redirect_to probe');
  for (final rt in redirects) {
    final gen = await http.post(
      Uri.parse('$url/auth/v1/admin/generate_link'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'recovery',
        'email': email,
        'options': {'redirect_to': rt},
      }),
    );
    print('requested=$rt status=${gen.statusCode}');
    if (gen.statusCode < 400) {
      final m = jsonDecode(gen.body) as Map<String, dynamic>;
      print('  redirect_to in body: ${m['redirect_to']}');
      final link = m['action_link']?.toString() ?? '';
      if (link.isNotEmpty) {
        final uri = Uri.parse(link);
        print('  action_link redirect_to param: ${uri.queryParameters['redirect_to']}');
      }
    } else {
      print('  ${gen.body}');
    }
  }

  final mgmt = Platform.environment['SUPABASE_ACCESS_TOKEN']?.trim() ?? '';
  if (mgmt.isEmpty) {
    print('\n# Management API skip — SUPABASE_ACCESS_TOKEN não definido');
    return;
  }

  print('\n# auth config (Management API)');
  const ref = 'fxdknzrqjenzqcvnwqqq';
  final cfg = await http.get(
    Uri.parse('https://api.supabase.com/v1/projects/$ref/config/auth'),
    headers: {'Authorization': 'Bearer $mgmt'},
  );
  if (cfg.statusCode >= 400) {
    print('GET auth config failed: ${cfg.statusCode} ${cfg.body}');
    return;
  }
  final auth = jsonDecode(cfg.body) as Map<String, dynamic>;
  print('site_url: ${auth['site_url']}');
  print('uri_allow_list: ${auth['uri_allow_list']}');
  print('mailer_subjects_recovery: ${auth['mailer_subjects_recovery']}');
}
