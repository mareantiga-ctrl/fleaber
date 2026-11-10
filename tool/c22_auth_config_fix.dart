// ignore_for_file: avoid_print
/// Adiciona deep link mobile + branding Fleaber nos emails de recovery (Supabase Auth).
///
/// Uso:
///   $env:SUPABASE_ACCESS_TOKEN = 'sbp_...'
///   dart run tool/c22_auth_config_fix.dart
///
/// Ou (Windows, CLI já autenticado):
///   powershell -File tool/c22_auth_config_fix.ps1
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _projectRef = 'fxdknzrqjenzqcvnwqqq';

const _mobileRecoveryRedirect =
    'fleaber://fleaber.com/auth-callback?fleaber_recovery=1';

const _webRecoveryRedirect =
    'https://fleaber.pt/fleahub/index.html?fleaber_recovery=1';

const _recoverySubject = 'Fleaber — redefine a tua palavra-passe';

const _recoveryTemplate = r'''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#f4f7f8;font-family:Inter,Arial,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f7f8;padding:32px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#ffffff;border-radius:20px;overflow:hidden;">
          <tr>
            <td style="background:#007782;padding:28px 32px;">
              <p style="margin:0;color:#ffffff;font-size:13px;letter-spacing:2px;text-transform:uppercase;">Fleaber</p>
              <h1 style="margin:8px 0 0;color:#ffffff;font-size:24px;font-weight:700;">Redefinir palavra-passe</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 32px 8px;color:#222222;font-size:16px;line-height:1.5;">
              <p style="margin:0 0 16px;">Olá,</p>
              <p style="margin:0 0 16px;">Recebeste este email da <strong>Fleaber</strong> porque pediste para redefinir a palavra-passe da tua conta.</p>
              <p style="margin:0 0 24px;">Toca no botão abaixo e escolhe <strong>Fleaber</strong> (não o Chrome) para definir a nova senha neste telemóvel.</p>
              <p style="margin:0 0 28px;text-align:center;">
                <a href="https://fleaber.pt/redefinir-senha?token_hash={{ .TokenHash }}&amp;type=recovery"
                   style="display:inline-block;background:#007782;color:#ffffff;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:16px;">
                  Definir nova palavra-passe
                </a>
              </p>
              <p style="margin:0 0 8px;color:#777777;font-size:13px;">Se o botão não funcionar, copia este endereço:</p>
              <p style="margin:0 0 24px;color:#007782;font-size:12px;word-break:break-all;">https://fleaber.pt/redefinir-senha?token_hash={{ .TokenHash }}&amp;type=recovery</p>
              <p style="margin:0;color:#777777;font-size:13px;">Se não pediste esta alteração, ignora este email. A tua conta mantém-se segura.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 28px;color:#99a3a6;font-size:12px;">
              Equipa Fleaber · fleaber.pt
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';

Future<void> main() async {
  final token = Platform.environment['SUPABASE_ACCESS_TOKEN']?.trim() ?? '';
  if (token.isEmpty) {
    stderr.writeln('SUPABASE_ACCESS_TOKEN em falta.');
    exit(2);
  }

  final headers = {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  final getRes = await http.get(
    Uri.parse('https://api.supabase.com/v1/projects/$_projectRef/config/auth'),
    headers: headers,
  );
  if (getRes.statusCode >= 400) {
    stderr.writeln('GET auth config ${getRes.statusCode}: ${getRes.body}');
    exit(1);
  }

  final current = jsonDecode(getRes.body) as Map<String, dynamic>;
  print('site_url: ${current['site_url']}');
  print('uri_allow_list (antes): ${current['uri_allow_list']}');

  final allow = _parseAllowList(current['uri_allow_list']);
  for (final needed in [
    'fleaber://fleaber.com/auth-callback',
    _mobileRecoveryRedirect,
    _webRecoveryRedirect,
    'https://fleaber.pt/fleahub/index.html',
    'https://fleaber.pt/redefinir-senha',
  ]) {
    if (!allow.contains(needed)) allow.add(needed);
  }

  final patchBody = <String, dynamic>{
    'uri_allow_list': allow.join(','),
    'mailer_subjects_recovery': _recoverySubject,
    'mailer_templates_recovery_content': _recoveryTemplate.trim(),
  };

  final patchRes = await http.patch(
    Uri.parse('https://api.supabase.com/v1/projects/$_projectRef/config/auth'),
    headers: headers,
    body: jsonEncode(patchBody),
  );
  if (patchRes.statusCode >= 400) {
    stderr.writeln('PATCH auth config ${patchRes.statusCode}: ${patchRes.body}');
    exit(1);
  }

  final updated = jsonDecode(patchRes.body) as Map<String, dynamic>;
  print('uri_allow_list (depois): ${updated['uri_allow_list']}');
  print('mailer_subjects_recovery: ${updated['mailer_subjects_recovery']}');
  print('smtp_sender_name: ${updated['smtp_sender_name']}');

  // Prova: generate_link deve aceitar deep link mobile.
  final env = await File('tool/live_ops_staging.env').readAsLines();
  String? service;
  for (final line in env) {
    if (line.startsWith('SUPABASE_SERVICE_ROLE_KEY=')) {
      service = line.substring('SUPABASE_SERVICE_ROLE_KEY='.length).trim();
    }
  }
  if (service == null || service.isEmpty) {
    print('skip generate_link probe — service role em falta');
    return;
  }

  final gen = await http.post(
    Uri.parse(
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/auth/v1/admin/generate_link',
    ),
    headers: {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'type': 'recovery',
      'email': 'agostinhomarina334@gmail.com',
      'options': {'redirect_to': _mobileRecoveryRedirect},
    }),
  );
  if (gen.statusCode >= 400) {
    print('generate_link probe FAIL ${gen.statusCode}: ${gen.body}');
    return;
  }
  final m = jsonDecode(gen.body) as Map<String, dynamic>;
  print('generate_link redirect_to: ${m['redirect_to']}');
  final link = m['action_link']?.toString() ?? '';
  if (link.isNotEmpty) {
    final uri = Uri.parse(link);
    print('action_link redirect_to param: ${uri.queryParameters['redirect_to']}');
  }
  print('OK — auth config actualizado.');
}

List<String> _parseAllowList(dynamic raw) {
  if (raw == null) return <String>[];
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return <String>[];
  return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
