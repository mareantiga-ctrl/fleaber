// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> _adminUserByEmail(
  LiveOpsStagingClient sb,
  String email,
) async {
  final res = await http.get(
    Uri.parse('${sb.url}/auth/v1/admin/users?email=${Uri.encodeComponent(email)}'),
    headers: {
      'apikey': sb.serviceRoleKey,
      'Authorization': 'Bearer ${sb.serviceRoleKey}',
    },
  );
  if (res.statusCode >= 400) {
    throw HttpException('admin users ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  List<dynamic> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map && decoded['users'] is List) {
    list = decoded['users'] as List<dynamic>;
  } else {
    list = const [];
  }
  if (list.isEmpty) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(list.first as Map);
}

Future<Map<String, dynamic>> verifyRegisto({
  required String email,
  required String password,
  required String expectedName,
}) async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final authUser = await _adminUserByEmail(sb, email);
  final userId = authUser['id']?.toString() ?? '';
  final profiles = userId.isEmpty
      ? <Map<String, dynamic>>[]
      : await sb.select('profiles', filter: 'id=eq.$userId', limit: 1);

  String? loginError;
  String? loginUserId;
  try {
    final token = await sb.signIn(email: email, password: password);
    loginUserId = await sb.userIdForAccessToken(token);
  } catch (e) {
    loginError = e.toString();
  }

  final profile = profiles.isEmpty ? <String, dynamic>{} : profiles.first;
  return {
    'test': 'APP-002',
    'email': email,
    'auth_user_found': authUser.isNotEmpty,
    'auth_user_id': userId,
    'email_confirmed_at': authUser['email_confirmed_at'],
    'created_at': authUser['created_at'],
    'profile_found': profiles.isNotEmpty,
    'profile_full_name': profile['full_name'],
    'profile_user_type': profile['user_type'],
    'expected_name': expectedName,
    'name_matches': (profile['full_name']?.toString() ?? '') == expectedName,
    'login_ok': loginError == null,
    'login_user_id': loginUserId,
    'login_error': loginError,
    'pass_e2e': authUser.isNotEmpty &&
        profiles.isNotEmpty &&
        loginError == null &&
        (profile['full_name']?.toString() ?? '') == expectedName,
  };
}

Future<Map<String, dynamic>> verifyResetRequest({
  required String email,
}) async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final authUser = await _adminUserByEmail(sb, email);
  final userId = authUser['id']?.toString() ?? '';

  // Prova técnica: utilizador existe (reset só faz sentido para email registado).
  // Recovery link gerado via admin — valida caminho Supabase, não substitui email inbox.
  Map<String, dynamic> generateLink = {};
  if (userId.isNotEmpty) {
    final res = await http.post(
      Uri.parse('${sb.url}/auth/v1/admin/generate_link'),
      headers: {
        'apikey': sb.serviceRoleKey,
        'Authorization': 'Bearer ${sb.serviceRoleKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'recovery',
        'email': email,
      }),
    );
    generateLink = {
      'status': res.statusCode,
      'body': res.statusCode >= 400
          ? res.body
          : (jsonDecode(res.body) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, k == 'action_link' ? '[redacted]' : v)),
    };
  }

  return {
    'test': 'APP-003',
    'email': email,
    'auth_user_found': authUser.isNotEmpty,
    'auth_user_id': userId,
    'generate_recovery_link': generateLink,
    'pass_app_action': userId.isNotEmpty,
    'pass_full_e2e': false,
    'note':
        'PASS E2E completo exige abrir link do email e definir nova senha na app. '
        'App action (enviar pedido) provada por Maestro; utilizador existe em auth.',
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/c22_auth_verify.dart registo <email> <password> <name>');
    print('       dart run tool/c22_auth_verify.dart reset <email>');
    exit(2);
  }

  final outDir = Directory('tool/reports/battery_c22_2026-08-19/bd');
  await outDir.create(recursive: true);

  Map<String, dynamic> result;
  if (args[0] == 'registo') {
    if (args.length < 4) {
      print('registo requires email password name');
      exit(2);
    }
    result = await verifyRegisto(
      email: args[1],
      password: args[2],
      expectedName: args.sublist(3).join(' '),
    );
    final file = File('${outDir.path}/c22_app002_verify.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      ...result,
    }));
    print('wrote ${file.path} pass_e2e=${result['pass_e2e']}');
    exit(result['pass_e2e'] == true ? 0 : 1);
  }

  if (args[0] == 'reset') {
    if (args.length < 2) {
      print('reset requires email');
      print('optional: --manual-e2e-pass  (marca pass_full_e2e=true após confirmação operador)');
      exit(2);
    }
    final email = args[1];
    final manualE2e = args.contains('--manual-e2e-pass');
    result = await verifyResetRequest(email: email);
    if (manualE2e) {
      result = {
        ...result,
        'pass_full_e2e': true,
        'evidence_kind': 'manual_e2e_confirmed',
        'note':
            'pass_full_e2e=true por flag --manual-e2e-pass (confirmação operador). '
            'Smoke Maestro parcial não basta para este campo.',
      };
    }
    final file = File('${outDir.path}/c22_app003_verify.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      ...result,
    }));
    print(
      'wrote ${file.path} pass_app_action=${result['pass_app_action']} '
      'pass_full_e2e=${result['pass_full_e2e']}',
    );
    exit(result['pass_app_action'] == true ? 0 : 1);
  }

  print('unknown mode ${args[0]}');
  exit(2);
}
