// ignore_for_file: avoid_print
/// Probe Auth P08/P09 em staging (API) — sem contas de clientes, sem OAuth novo.
///
/// Cobre: signup, login, recovery link generation, returnTo allow-list vs config.
/// Confirmação de email: documenta mailer_autoconfirm do ambiente.
/// UI visual: NOT RUN aqui (design já aprovado; sem redesign).
///
///   dart run tool/auth_p08_p09_staging_probe.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final service = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final email = 'auth.p09.val+$stamp@fleaber.test';
  final password =
      'AuthVal!${stamp.toRadixString(36)}${Random.secure().nextInt(9999)}';

  final report = <String, dynamic>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'project': url,
    'checks': <String, dynamic>{},
    'notes': <String>[],
  };

  String? userId;

  try {
    // 1) Signup (anon) — staging tem mailer_autoconfirm=true (verificado via Mgmt API)
    final swReg = Stopwatch()..start();
    final reg = await http.post(
      Uri.parse('$url/auth/v1/signup'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'data': {'auth_p09_val': true},
      }),
    );
    swReg.stop();
    report['timings_ms'] = {'signup': swReg.elapsedMilliseconds};
    report['signup_status'] = reg.statusCode;
    final regBody = jsonDecode(reg.body);
    if (reg.statusCode >= 200 && reg.statusCode < 300 && regBody is Map) {
      final map = Map<String, dynamic>.from(regBody as Map);
      final nested = map['user'];
      final nestedId = nested is Map ? nested['id']?.toString() : null;
      userId = map['id']?.toString() ?? nestedId;
      final session = map['access_token'];
      report['checks']['signup_ok'] = userId != null && userId!.isNotEmpty;
      report['checks']['signup_session_immediate'] =
          session != null && session.toString().isNotEmpty;
      report['notes'].add(
        'Se signup_session_immediate=true, confirmação de email não bloqueia (autoconfirm).',
      );
    } else {
      report['checks']['signup_ok'] = false;
      report['signup_body'] = reg.body.length > 400
          ? '${reg.body.substring(0, 400)}…'
          : reg.body;
    }

    // 2) Login password
    final swLogin = Stopwatch()..start();
    final login = await http.post(
      Uri.parse('$url/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    swLogin.stop();
    (report['timings_ms'] as Map)['login'] = swLogin.elapsedMilliseconds;
    report['login_status'] = login.statusCode;
    report['checks']['login_ok'] = login.statusCode >= 200 && login.statusCode < 300;
    String? access;
    if (report['checks']['login_ok'] == true) {
      final m = jsonDecode(login.body) as Map<String, dynamic>;
      access = m['access_token']?.toString();
      userId ??= m['user']?['id']?.toString();
    }

    // 3) Recovery — generateLink (service) sem enviar a caixa real de cliente
    final swRec = Stopwatch()..start();
    final rec = await http.post(
      Uri.parse('$url/auth/v1/recover'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );
    swRec.stop();
    (report['timings_ms'] as Map)['recover'] = swRec.elapsedMilliseconds;
    report['recover_status'] = rec.statusCode;
    // Supabase often returns 200 even if email not sent visually
    report['checks']['recover_accepted'] =
        rec.statusCode >= 200 && rec.statusCode < 300;

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
      }),
    );
    report['generate_link_status'] = gen.statusCode;
    if (gen.statusCode >= 200 && gen.statusCode < 300) {
      final gm = jsonDecode(gen.body) as Map<String, dynamic>;
      final actionLink = gm['action_link']?.toString() ?? '';
      report['recovery_action_link_host'] = Uri.tryParse(actionLink)?.host;
      report['recovery_has_token'] =
          actionLink.contains('token') || actionLink.contains('type=recovery');
      report['checks']['recovery_link_generated'] = actionLink.isNotEmpty;
    } else {
      report['checks']['recovery_link_generated'] = false;
      report['generate_link_body'] = gen.body.length > 300
          ? '${gen.body.substring(0, 300)}…'
          : gen.body;
    }

    // 4) returnTo / redirect allow-list (from local dump if present)
    final cfgFile = File('tool/reports/auth_config_staging_raw.json');
    if (cfgFile.existsSync()) {
      final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
      final allow = (cfg['uri_allow_list'] ?? '').toString();
      final siteUrl = cfg['site_url']?.toString() ?? '';
      report['auth_config'] = {
        'site_url': siteUrl,
        'mailer_autoconfirm': cfg['mailer_autoconfirm'],
        'disable_signup': cfg['disable_signup'],
        'uri_allow_list': allow,
      };
      report['checks']['returnTo_fleaber_callback_allowed'] =
          allow.contains('fleaber://fleaber.com/auth-callback');
      report['checks']['returnTo_hub_allowed'] =
          allow.contains('https://fleaber.pt/fleahub/index.html');
      report['checks']['returnTo_redefinir_senha_allowed'] =
          allow.contains('https://fleaber.pt/redefinir-senha');
      report['notes'].add(
        'returnTo na UI depende do cliente Flutter/Hub passar redirectTo '
        'dentro da allow-list; API allow-list verificada aqui.',
      );
    } else {
      report['checks']['returnTo_config_dump'] = false;
      report['notes'].add('auth_config_staging_raw.json em falta');
    }

    // 5) Shared-component regression: smoke file presence (não redesenhar)
    final shared = [
      'lib/pages/login/login_responsive_shell.dart',
      'lib/widgets/fleaber_cookie_consent_banner.dart',
      'lib/pages/login/login_widget.dart',
      'lib/pages/registo/registo_widget.dart',
    ];
    final missing = shared.where((p) => !File(p).existsSync()).toList();
    report['checks']['shared_components_present'] = missing.isEmpty;
    report['shared_missing'] = missing;

    // 6) UI E2E browser
    report['checks']['ui_e2e_browser'] = 'NOT_RUN';
    report['notes'].add(
      'UI browser (scroll/cookies/layout) já aprovada visualmente em ZIPs 08/14; '
      'esta ronda não redesenha. Fluxo completo no telemóvel/browser Hub publicado '
      'em staging: NOT RUN se host de staging Hub não estiver identificado.',
    );

    // Email confirmation explicit
    final autoconfirm =
        (report['auth_config'] as Map?)?['mailer_autoconfirm'] == true;
    report['checks']['email_confirmation_flow'] = autoconfirm
        ? 'NOT_APPLICABLE_AUTOCONFIRM'
        : 'NOT_RUN';
    if (autoconfirm) {
      report['notes'].add(
        'Staging mailer_autoconfirm=true → confirmação por email não é exigida.',
      );
    }

    if (access != null) {
      final me = await http.get(
        Uri.parse('$url/auth/v1/user'),
        headers: {'apikey': anon, 'Authorization': 'Bearer $access'},
      );
      report['checks']['session_user_ok'] =
          me.statusCode >= 200 && me.statusCode < 300;
    }

    final checks = Map<String, dynamic>.from(report['checks'] as Map);
    final failed = checks.entries
        .where((e) => e.value == false)
        .map((e) => e.key)
        .toList();
    report['result'] = failed.isEmpty ? 'PASS_WITH_LIMITS' : 'FAIL';
    report['failed_checks'] = failed;
  } catch (e, st) {
    report['result'] = 'ERROR';
    report['error'] = e.toString();
    report['stack'] = st.toString().split('\n').take(10).toList();
  } finally {
    if (userId != null && userId!.isNotEmpty) {
      try {
        final del = await http.delete(
          Uri.parse('$url/auth/v1/admin/users/$userId'),
          headers: {
            'apikey': service,
            'Authorization': 'Bearer $service',
          },
        );
        report['cleanup'] = del.statusCode >= 200 && del.statusCode < 300
            ? 'ok'
            : 'status=${del.statusCode}';
      } catch (e) {
        report['cleanup'] = 'FAIL: $e';
      }
    }
  }

  final dir = Directory('tool/reports/auth_p08_p09_staging_probe');
  dir.createSync(recursive: true);
  final f = File('${dir.path}/EVIDENCE.json');
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print('RESULT=${report['result']}');
  print('wrote ${f.path}');
}
