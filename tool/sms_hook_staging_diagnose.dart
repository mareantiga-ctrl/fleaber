// ignore_for_file: avoid_print
/// Diagnóstico objectivo SMS Hook staging (B2).
///
/// Verifica deploy, secrets, Auth Hook e assinatura webhook — **sem expor valores**.
///
/// Uso:
///   dart run tool/sms_hook_staging_diagnose.dart
///
/// Opcional (comparar secrets Auth ↔ Edge Function):
///   set SEND_SMS_HOOK_SECRET=v1,whsec_...   # PowerShell: $env:SEND_SMS_HOOK_SECRET="..."
///   dart run tool/sms_hook_staging_diagnose.dart
///
/// Opcional (checks 4–5 via Management API):
///   set SUPABASE_ACCESS_TOKEN=sbp_...
///   dart run tool/sms_hook_staging_diagnose.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _projectRef = 'fxdknzrqjenzqcvnwqqq';
const _supabaseHost = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
const _functionSlug = 'send-sms-bulkgate';
const _functionUrl =
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/send-sms-bulkgate';
const _expectedHookUri = _functionUrl;

const _requiredSecrets = [
  'SEND_SMS_HOOK_SECRET',
  'BULKGATE_APPLICATION_ID',
  'BULKGATE_APPLICATION_TOKEN',
];

void main() async {
  final started = DateTime.now().toUtc();
  final steps = <Map<String, dynamic>>[];
  var failed = 0;

  void step(
    String id,
    String name,
    bool? ok, {
    String? detail,
    String? fix,
    Map<String, dynamic>? data,
  }) {
    final status = ok == null ? 'SKIP' : (ok ? 'PASS' : 'FAIL');
    steps.add({
      'id': id,
      'name': name,
      'status': status,
      'ok': ok,
      if (detail != null) 'detail': detail,
      if (fix != null) 'fix': fix,
      if (data != null) 'data': data,
    });
    print('[$status] $id — $name');
    if (detail != null) print('       $detail');
    if (ok == false && fix != null) print('       FIX: $fix');
    if (data != null && data.isNotEmpty) {
      for (final e in data.entries) {
        print('       ${e.key}: ${e.value}');
      }
    }
    print('');
    if (ok == false) failed++;
  }

  print('# SMS Hook staging diagnose');
  print('project_ref: $_projectRef');
  print('function: $_functionSlug');
  print('started: $started\n');

  // --- 0) App aponta para staging ---
  final appUrl = await _readAppSupabaseUrl();
  final appOk = appUrl.contains(_projectRef);
  step(
    '0',
    'App Flutter aponta para projecto staging',
    appOk,
    detail: appOk
        ? 'lib/backend/supabase/supabase.dart → $_projectRef'
        : 'URL na app: ${appUrl.isEmpty ? "(não lida)" : appUrl}',
    fix: appOk
        ? null
        : 'Alinha lib/backend/supabase/supabase.dart com $_supabaseHost',
  );

  // --- 1) Function deployada (HTTP probe) ---
  final probe = await _probeFunction();
  step(
    '1',
    'Edge Function $_functionSlug responde no projecto correcto',
    probe.reachable && !probe.notFound,
    detail: probe.summary,
    fix: probe.notFound
        ? 'npx supabase functions deploy $_functionSlug --no-verify-jwt --project-ref $_projectRef'
        : (probe.reachable
            ? null
            : 'Verifica rede/DNS ou project ref no deploy'),
    data: probe.data,
  );

  // --- 2–3) Secrets via CLI ---
  final cliSecrets = await _listSecretsViaCli();
  if (cliSecrets.cliAvailable) {
    for (final name in _requiredSecrets) {
      final present = cliSecrets.names.contains(name);
      step(
        '2-${name.substring(0, 3)}',
        'Secret Edge Function `$name` existe',
        present,
        detail: present
            ? 'Confirmado via `supabase secrets list` (nome apenas)'
            : 'Não listado em Edge Function secrets',
        fix: present
            ? null
            : 'npx supabase secrets set $name="VALOR" --project-ref $_projectRef',
      );
    }
  } else {
    step(
      '2',
      'Secrets Edge Function (CLI)',
      false,
      detail: cliSecrets.error ?? 'Supabase CLI indisponível ou não autenticado',
      fix: 'npx supabase login && npx supabase secrets list --project-ref $_projectRef',
    );
  }

  // --- 4–5) Auth hook via Management API ---
  final mgmtToken = Platform.environment['SUPABASE_ACCESS_TOKEN']?.trim() ?? '';
  Map<String, dynamic>? authConfig;
  if (mgmtToken.isEmpty) {
    step(
      '4',
      'Auth Hook Send SMS (Management API)',
      null,
      detail: 'SUPABASE_ACCESS_TOKEN não definido — skip automático de URI/secret Auth',
      fix: 'Dashboard → Account → Access Tokens → export SUPABASE_ACCESS_TOKEN=sbp_... && dart run tool/sms_hook_staging_diagnose.dart',
    );
    step(
      '5',
      'Hook secret Auth ↔ Edge Function',
      null,
      detail: 'Requer SUPABASE_ACCESS_TOKEN e SEND_SMS_HOOK_SECRET no ambiente local',
      fix: 'Compara manualmente: Authentication → Hooks → Send SMS secret == Edge secret SEND_SMS_HOOK_SECRET',
    );
  } else {
    authConfig = await _fetchAuthConfig(mgmtToken);
    if (authConfig == null) {
      step(
        '4',
        'Auth Hook Send SMS configurado',
        false,
        detail: 'GET /v1/projects/$_projectRef/config/auth falhou',
        fix: 'Verifica token Management API (scope auth read)',
      );
      step(
        '5',
        'Hook secret Auth ↔ Edge Function',
        false,
        detail: 'Não foi possível ler hook_send_sms_secrets',
        fix: 'Configura Send SMS hook no Dashboard',
      );
      failed++;
    } else {
      final enabled = authConfig['hook_send_sms_enabled'] == true;
      final uri = authConfig['hook_send_sms_uri']?.toString().trim() ?? '';
      final uriOk = uri == _expectedHookUri;
      step(
        '4',
        'Auth Hook Send SMS URL correcta',
        enabled && uriOk,
        detail: 'enabled=$enabled uri=${uri.isEmpty ? "(vazio)" : uri}',
        fix: !enabled
            ? 'Dashboard → Authentication → Hooks → Enable Send SMS hook'
            : (!uriOk
                ? 'Define hook URI exactamente: $_expectedHookUri'
                : null),
        data: {
          'expected_uri': _expectedHookUri,
          'hook_send_sms_enabled': enabled,
        },
      );

      final authSecret =
          authConfig['hook_send_sms_secrets']?.toString().trim() ?? '';
      final localSecret =
          Platform.environment['SEND_SMS_HOOK_SECRET']?.trim() ?? '';
      if (localSecret.isEmpty) {
        step(
          '5',
          'Hook secret Auth ↔ Edge Function (hash)',
          authSecret.isNotEmpty,
          detail: authSecret.isEmpty
              ? 'hook_send_sms_secrets vazio no Auth config'
              : 'Auth tem secret (${_fingerprint(authSecret)}). Define SEND_SMS_HOOK_SECRET localmente para comparar.',
          fix: authSecret.isEmpty
              ? 'Authentication → Hooks → Send SMS → Generate secret → copiar para Edge secret SEND_SMS_HOOK_SECRET'
              : 'set SEND_SMS_HOOK_SECRET=v1,whsec_... (local) && dart run tool/sms_hook_staging_diagnose.dart',
          data: {
            'auth_secret_fingerprint': authSecret.isEmpty
                ? '(vazio)'
                : _fingerprint(authSecret),
          },
        );
      } else {
        final match = authSecret.isNotEmpty &&
            _normalizeSecret(authSecret) == _normalizeSecret(localSecret);
        step(
          '5',
          'Hook secret Auth ↔ SEND_SMS_HOOK_SECRET local (hash)',
          match,
          detail: match
              ? 'Fingerprints coincidem (${_fingerprint(authSecret)})'
              : 'MISMATCH auth=${_fingerprint(authSecret)} local=${_fingerprint(localSecret)}',
          fix: match
              ? null
              : 'O secret do Hook (Auth) tem de ser IDÊNTICO ao SEND_SMS_HOOK_SECRET da Edge Function. Regenera no Dashboard e cola o MESMO valor nos dois sítios.',
          data: {
            'auth_secret_fingerprint': _fingerprint(authSecret),
            'local_secret_fingerprint': _fingerprint(localSecret),
          },
        );
      }
    }
  }

  // --- 6–7) Assinatura / payload directo ---
  final unsigned = await _postFunction(body: '{}', headers: {});
  final unsignedBody = _parseJson(unsigned.body);
  final unsignedMsg = _extractErrorMessage(unsignedBody) ?? unsigned.body;

  if (unsignedMsg.toLowerCase().contains('missing send_sms_hook_secret') ||
      unsignedMsg.toLowerCase().contains('bulkgate_application')) {
    step(
      '6',
      'Edge Function recebe pedidos (secrets em runtime)',
      false,
      detail: 'Resposta: ${_truncate(unsignedMsg, 200)}',
      fix: 'Secrets não visíveis na função após deploy. Corre: npx supabase secrets set ... --project-ref $_projectRef && redeploy',
      data: {'http_status': unsigned.statusCode},
    );
    step(
      '7',
      'Assinatura webhook Standard Webhooks',
      false,
      detail: 'Bloqueado — secrets em falta na Edge Function',
      fix: 'Resolve passo 6 primeiro',
    );
    failed++;
  } else if (unsignedMsg.toLowerCase().contains('missing required headers')) {
    step(
      '6',
      'Edge Function recebe pedidos (secrets em runtime)',
      true,
      detail:
          'Secrets carregados; pedido sem headers webhook (esperado neste teste)',
      data: {'http_status': unsigned.statusCode},
    );

    final localSecret =
        Platform.environment['SEND_SMS_HOOK_SECRET']?.trim() ?? '';
    if (localSecret.isEmpty) {
      step(
        '7',
        'Assinatura webhook válida',
        null,
        detail: 'Define SEND_SMS_HOOK_SECRET local para teste de assinatura',
        fix:
            'set SEND_SMS_HOOK_SECRET=<hook secret Auth> && dart run tool/sms_hook_staging_diagnose.dart',
      );
    } else {
      final signed = await _signedProbe(localSecret);
      step(
        '7a',
        'Assinatura webhook aceite pela função',
        signed.signatureOk,
        detail: signed.detail,
        fix: signed.signatureOk
            ? null
            : 'SEND_SMS_HOOK_SECRET local não coincide com o usado pelo Auth Hook',
        data: signed.data,
      );
      step(
        '7b',
        'Payload mínimo (phone+otp) até BulkGate',
        signed.payloadOk,
        detail: signed.payloadDetail,
        fix: signed.payloadFix,
        data: signed.data,
      );
      if (!signed.signatureOk) failed++;
      if (!signed.payloadOk) failed++;
    }
  } else if (unsignedMsg.toLowerCase().contains('hook secret') ||
      unsignedMsg.toLowerCase().contains('signature') ||
      unsignedMsg.toLowerCase().contains('webhook')) {
    step(
      '6',
      'Edge Function recebe pedidos (secrets em runtime)',
      true,
      detail: 'Secrets carregados; falha esperada sem assinatura: ${_truncate(unsignedMsg, 160)}',
      data: {'http_status': unsigned.statusCode},
    );

    final localSecret =
        Platform.environment['SEND_SMS_HOOK_SECRET']?.trim() ?? '';
    if (localSecret.isEmpty) {
      step(
        '7',
        'Assinatura webhook válida',
        false,
        detail: 'Define SEND_SMS_HOOK_SECRET local para teste de assinatura',
        fix: 'set SEND_SMS_HOOK_SECRET=<hook secret Auth> && dart run tool/sms_hook_staging_diagnose.dart',
      );
    } else {
      final signed = await _signedProbe(localSecret);
      step(
        '7a',
        'Assinatura webhook aceite pela função',
        signed.signatureOk,
        detail: signed.detail,
        fix: signed.signatureOk
            ? null
            : 'SEND_SMS_HOOK_SECRET local não coincide com o usado pelo Auth Hook',
        data: signed.data,
      );
      step(
        '7b',
        'Payload mínimo (phone+otp) até BulkGate',
        signed.payloadOk,
        detail: signed.payloadDetail,
        fix: signed.payloadOk
            ? null
            : signed.payloadFix,
        data: signed.data,
      );
      if (!signed.signatureOk) failed++;
      if (!signed.payloadOk) failed++;
    }
  } else {
    step(
      '6',
      'Edge Function resposta classificável',
      false,
      detail: 'HTTP ${unsigned.statusCode}: ${_truncate(unsignedMsg, 240)}',
      fix: 'Ver logs Edge Functions no Dashboard → send-sms-bulkgate',
      data: {'http_status': unsigned.statusCode},
    );
    step(
      '7',
      'Assinatura webhook',
      false,
      detail: 'Resposta inesperada — ver logs Supabase',
      fix: 'Dashboard → Edge Functions → send-sms-bulkgate → Logs',
    );
    failed++;
  }

  // --- 8) Auth end-to-end (opcional) ---
  final authProbe = await _probeAuthPhoneHook();
  step(
    '8',
    'Auth GoTrue phone change (erro real da app)',
    authProbe.ok,
    detail: authProbe.detail,
    fix: authProbe.fix,
    data: authProbe.data,
  );
  if (!authProbe.ok) failed++;

  // --- Veredicto ---
  String? rootCause;
  String? rootFix;
  const priority = ['8', '7b', '7a', '5', '4', '2-SEN', '6', '1'];
  for (final id in priority) {
    final s = steps.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e?['id'] == id && e?['ok'] != true,
          orElse: () => null,
        );
    if (s != null && s['fix'] != null) {
      rootCause = '${s['id']}: ${s['name']} — ${s['detail']}';
      rootFix = s['fix'] as String;
      break;
    }
  }
  if (rootCause == null) {
    for (final s in steps) {
      if (s['ok'] != true && s['fix'] != null) {
        rootCause = '${s['id']}: ${s['name']} — ${s['detail']}';
        rootFix = s['fix'] as String;
        break;
      }
    }
  }

  print('---');
  print('failed_checks: $failed');
  if (rootCause != null) {
    print('PRIMARY_CAUSE: $rootCause');
    print('PRIMARY_FIX: $rootFix');
  } else {
    print('PRIMARY_CAUSE: nenhuma falha detectada — se a app ainda falha, ver passo 8 (rate limit / número inválido).');
  }

  final reportDir = Directory('tool/reports');
  if (!reportDir.existsSync()) reportDir.createSync(recursive: true);
  final stamp = started.toIso8601String().replaceAll(':', '-');
  final reportPath = 'tool/reports/sms_hook_staging_diagnose_$stamp.json';
  File(reportPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'started_utc': started.toIso8601String(),
      'project_ref': _projectRef,
      'function_url': _functionUrl,
      'failed_count': failed,
      'primary_cause': rootCause,
      'primary_fix': rootFix,
      'steps': steps,
    }),
  );
  print('report: $reportPath');

  exit(failed > 0 ? 1 : 0);
}

Future<String> _readAppSupabaseUrl() async {
  try {
    final f = File('lib/backend/supabase/supabase.dart');
    if (!f.existsSync()) return '';
    final text = f.readAsStringSync();
    final m = RegExp(r"_kSupabaseUrl = '([^']+)'").firstMatch(text);
    return m?.group(1) ?? '';
  } catch (_) {
    return '';
  }
}

class _ProbeResult {
  _ProbeResult({
    required this.reachable,
    required this.notFound,
    required this.summary,
    this.data = const {},
  });
  final bool reachable;
  final bool notFound;
  final String summary;
  final Map<String, dynamic> data;
}

Future<_ProbeResult> _probeFunction() async {
  try {
    final res = await http
        .get(Uri.parse(_functionUrl))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) {
      return _ProbeResult(
        reachable: false,
        notFound: true,
        summary: 'HTTP 404 — função não encontrada neste projecto',
      );
    }
    return _ProbeResult(
      reachable: true,
      notFound: false,
      summary: 'HTTP ${res.statusCode} (GET) — endpoint existe',
      data: {'get_status': res.statusCode},
    );
  } catch (e) {
    return _ProbeResult(
      reachable: false,
      notFound: false,
      summary: 'Erro rede: $e',
    );
  }
}

class _CliSecrets {
  _CliSecrets({
    required this.cliAvailable,
    required this.names,
    this.error,
  });
  final bool cliAvailable;
  final Set<String> names;
  final String? error;
}

Future<_CliSecrets> _listSecretsViaCli() async {
  try {
    final result = await Process.run(
      'npx',
      ['supabase', 'secrets', 'list', '--project-ref', _projectRef],
      runInShell: true,
    );
    final out = '${result.stdout}\n${result.stderr}';
    if (result.exitCode != 0) {
      return _CliSecrets(
        cliAvailable: false,
        names: {},
        error: _truncate(out, 300),
      );
    }
    final names = <String>{};
    try {
      final decoded = jsonDecode(out.trim());
      if (decoded is Map && decoded['secrets'] is List) {
        for (final item in decoded['secrets'] as List) {
          if (item is Map && item['name'] != null) {
            names.add(item['name'].toString());
          }
        }
      }
    } catch (_) {}
    if (names.isEmpty) {
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('NAME')) continue;
        final parts = t.split(RegExp(r'\s+'));
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          names.add(parts.first);
        }
      }
    }
    return _CliSecrets(cliAvailable: true, names: names);
  } catch (e) {
    return _CliSecrets(
      cliAvailable: false,
      names: {},
      error: e.toString(),
    );
  }
}

Future<Map<String, dynamic>?> _fetchAuthConfig(String token) async {
  try {
    final res = await http.get(
      Uri.parse('https://api.supabase.com/v1/projects/$_projectRef/config/auth'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final map = jsonDecode(res.body);
    if (map is Map<String, dynamic>) return map;
    if (map is Map) return Map<String, dynamic>.from(map);
    return null;
  } catch (_) {
    return null;
  }
}

Future<http.Response> _postFunction({
  required String body,
  required Map<String, String> headers,
}) async {
  return http
      .post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: body,
      )
      .timeout(const Duration(seconds: 20));
}

Map<String, dynamic>? _parseJson(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return null;
}

String? _extractErrorMessage(Map<String, dynamic>? json) {
  if (json == null) return null;
  final err = json['error'];
  if (err is Map) {
    return err['message']?.toString();
  }
  return json['message']?.toString();
}

String _normalizeSecret(String s) => s.trim();

String _fingerprint(String secret) {
  final digest = sha256.convert(utf8.encode(secret.trim()));
  return digest.toString().substring(0, 12);
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

Map<String, String> _signWebhook(String hookSecretV1, String body) {
  final base64Key = hookSecretV1.replaceFirst(RegExp(r'^v1,whsec_'), '');
  final keyBytes = base64Decode(base64Key);
  final msgId = 'diag_${DateTime.now().millisecondsSinceEpoch}';
  final timestamp =
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final signedContent = '$msgId.$timestamp.$body';
  final hmac = Hmac(sha256, keyBytes);
  final digest = hmac.convert(utf8.encode(signedContent));
  final sig = base64Encode(digest.bytes);
  return {
    'webhook-id': msgId,
    'webhook-timestamp': timestamp,
    'webhook-signature': 'v1,$sig',
  };
}

class _SignedProbeResult {
  _SignedProbeResult({
    required this.signatureOk,
    required this.payloadOk,
    required this.detail,
    required this.payloadDetail,
    this.payloadFix,
    this.data = const {},
  });
  final bool signatureOk;
  final bool payloadOk;
  final String detail;
  final String payloadDetail;
  final String? payloadFix;
  final Map<String, dynamic> data;
}

Future<_SignedProbeResult> _signedProbe(String hookSecret) async {
  // Payload mínimo válido (sem chamar BulkGate de verdade se OTP fake)
  final body = jsonEncode({
    'user': {'phone': '+351910000000', 'new_phone': '+351910000000'},
    'sms': {'otp': '000000', 'phone': '+351910000000'},
  });

  final headers = _signWebhook(hookSecret, body);
  final res = await _postFunction(body: body, headers: headers);
  final json = _parseJson(res.body);
  final msg = _extractErrorMessage(json) ?? res.body;

  if (msg.toLowerCase().contains('hook secret') ||
      msg.toLowerCase().contains('signature') ||
      msg.toLowerCase().contains('webhook')) {
    return _SignedProbeResult(
      signatureOk: false,
      payloadOk: false,
      detail: _truncate(msg, 200),
      payloadDetail: 'Assinatura rejeitada',
      payloadFix: 'SEND_SMS_HOOK_SECRET incorrecto vs Auth Hook secret',
      data: {'http_status': res.statusCode},
    );
  }

  if (msg.toLowerCase().contains('missing phone or otp')) {
    return _SignedProbeResult(
      signatureOk: true,
      payloadOk: false,
      detail: 'Assinatura OK; payload rejeitado (formato inesperado)',
      payloadDetail: msg,
      payloadFix: 'Actualizar extractOtpPayload na Edge Function',
      data: {'http_status': res.statusCode},
    );
  }

  if (msg.toLowerCase().contains('bulkgate')) {
    return _SignedProbeResult(
      signatureOk: true,
      payloadOk: false,
      detail: 'Assinatura OK; falha BulkGate (credenciais/remetente/saldo)',
      payloadDetail: _truncate(msg, 240),
      payloadFix:
          'Verifica BULKGATE_APPLICATION_ID/TOKEN e remetente PT no portal BulkGate',
      data: {'http_status': res.statusCode, 'stage': 'bulkgate'},
    );
  }

  // Sucesso ou resposta vazia {}
  final okBody = json == null || json.isEmpty || !json.containsKey('error');
  return _SignedProbeResult(
    signatureOk: true,
    payloadOk: okBody,
    detail: okBody
        ? 'Assinatura OK; função aceitou payload (BulkGate respondeu OK ou {})'
        : _truncate(msg, 200),
    payloadDetail: okBody ? 'OK' : msg,
    payloadFix: okBody ? null : 'Ver resposta completa nos logs Edge',
    data: {'http_status': res.statusCode},
  );
}

class _AuthProbeResult {
  _AuthProbeResult({
    required this.ok,
    required this.detail,
    this.fix,
    this.data = const {},
  });
  final bool ok;
  final String detail;
  final String? fix;
  final Map<String, dynamic> data;
}

Future<_AuthProbeResult> _probeAuthPhoneHook() async {
  final envFile = File('tool/live_ops_staging.env');
  if (!envFile.existsSync()) {
    return _AuthProbeResult(
      ok: true,
      detail: 'Skip — tool/live_ops_staging.env ausente',
    );
  }

  final env = _parseEnvFile(envFile.readAsStringSync());
  final base = (env['SUPABASE_URL'] ?? '')
      .replaceAll('/rest/v1/', '')
      .replaceAll(RegExp(r'/+$'), '');
  final anon = env['SUPABASE_ANON_KEY'] ?? '';
  final email = env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? '';
  final password = env['LIVE_OPS_TEST_SELLER_PASSWORD'] ?? '';

  if (base.isEmpty || anon.isEmpty || email.isEmpty || password.isEmpty) {
    return _AuthProbeResult(
      ok: true,
      detail: 'Skip — credenciais teste incompletas em live_ops_staging.env',
    );
  }

  try {
    final tokenRes = await http.post(
      Uri.parse('$base/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
      return _AuthProbeResult(
        ok: false,
        detail: 'Login teste falhou HTTP ${tokenRes.statusCode}',
        fix: 'Verifica LIVE_OPS_TEST_SELLER_* em tool/live_ops_staging.env',
      );
    }
    final tokenMap = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    final access = tokenMap['access_token']?.toString() ?? '';
    if (access.isEmpty) {
      return _AuthProbeResult(
        ok: false,
        detail: 'Login teste sem access_token',
      );
    }

    final userRes = await http.put(
      Uri.parse('$base/auth/v1/user'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $access',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'phone': '+351910000001'}),
    );

    final body = userRes.body;
    Map<String, dynamic>? errJson;
    try {
      errJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final msg = errJson?['msg']?.toString() ??
        errJson?['message']?.toString() ??
        errJson?['error_description']?.toString() ??
        body;

    if (userRes.statusCode >= 200 && userRes.statusCode < 300) {
      return _AuthProbeResult(
        ok: true,
        detail: 'Auth aceitou updateUser(phone) — hook não bloqueou (HTTP ${userRes.statusCode})',
        data: {'http_status': userRes.statusCode},
      );
    }

    final lower = msg.toLowerCase();
    if (lower.contains('bulkgate') &&
        (lower.contains('unknown_identity') ||
            lower.contains('unauthorized') ||
            lower.contains('empty application_id'))) {
      return _AuthProbeResult(
        ok: false,
        detail: 'Hook OK até BulkGate — ${_truncate(msg, 240)}',
        fix:
            'BulkGate rejeitou ID/token. Portal → API → app transactional → copia Application ID + Token novos → '
            'npx supabase secrets set BULKGATE_APPLICATION_ID="..." --project-ref fxdknzrqjenzqcvnwqqq && '
            'npx supabase secrets set BULKGATE_APPLICATION_TOKEN="..." --project-ref fxdknzrqjenzqcvnwqqq '
            '(sem espaços/aspas extra; não uses credenciais marketing)',
        data: {'http_status': userRes.statusCode, 'stage': 'bulkgate_auth'},
      );
    }
    if (lower.contains('bulkgate')) {
      return _AuthProbeResult(
        ok: false,
        detail: 'Hook OK — falha BulkGate: ${_truncate(msg, 240)}',
        fix:
            'Verifica app transactional activa, remetente PT (gText/Fleaber) e saldo no portal BulkGate',
        data: {'http_status': userRes.statusCode, 'stage': 'bulkgate'},
      );
    }
    if (lower.contains('missing phone or otp in hook payload')) {
      return _AuthProbeResult(
        ok: false,
        detail:
            'Hook chamado mas payload sem phone/otp reconhecível — causa: extractOtpPayload desactualizado (falta sms.phone / user.new_phone)',
        fix:
            'Redeploy send-sms-bulkgate com fix sms.phone + confirma Auth Hook secret == SEND_SMS_HOOK_SECRET',
        data: {'http_status': userRes.statusCode},
      );
    }
    if (lower.contains('hook') || lower.contains('invalid payload')) {
      return _AuthProbeResult(
        ok: false,
        detail: 'GoTrue hook error: ${_truncate(msg, 240)}',
        fix:
            'Causa típica: secret mismatch Auth↔Edge ou hook URI errado. Corre passos 4–5 com SUPABASE_ACCESS_TOKEN + SEND_SMS_HOOK_SECRET.',
        data: {'http_status': userRes.statusCode},
      );
    }

    return _AuthProbeResult(
      ok: false,
      detail: 'Auth PUT /user HTTP ${userRes.statusCode}: ${_truncate(msg, 240)}',
      fix: 'Verifica Phone provider activo em Authentication → Providers → Phone',
      data: {'http_status': userRes.statusCode},
    );
  } catch (e) {
    return _AuthProbeResult(
      ok: false,
      detail: 'Erro no probe Auth: $e',
    );
  }
}

Map<String, String> _parseEnvFile(String raw) {
  final out = <String, String>{};
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i <= 0) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
