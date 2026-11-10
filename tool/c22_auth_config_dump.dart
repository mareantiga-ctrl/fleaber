// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const _ref = 'fxdknzrqjenzqcvnwqqq';

Future<void> main() async {
  final token = Platform.environment['SUPABASE_ACCESS_TOKEN']?.trim() ?? '';
  if (token.isEmpty) exit(2);

  final res = await http.get(
    Uri.parse('https://api.supabase.com/v1/projects/$_ref/config/auth'),
    headers: {'Authorization': 'Bearer $token'},
  );
  final auth = jsonDecode(res.body) as Map<String, dynamic>;

  const keys = [
    'site_url',
    'uri_allow_list',
    'mailer_subjects_recovery',
    'mailer_templates_recovery_content',
    'mailer_subjects_confirmation',
    'smtp_admin_email',
    'smtp_sender_name',
    'external_email_enabled',
    'hook_send_email_enabled',
    'hook_send_email_uri',
    'mailer_autoconfirm',
  ];
  for (final k in keys) {
    final v = auth[k];
    if (v == null) continue;
    final s = v.toString();
    print('$k: ${s.length > 200 ? '${s.substring(0, 200)}...' : s}');
  }

  // recover probe with query redirect_to (como a app Flutter envia)
  final env = await File('tool/live_ops_staging.env').readAsLines();
  final anon = env.firstWhere((l) => l.startsWith('SUPABASE_ANON_KEY=')).split('=').last.trim();
  final service = env.firstWhere((l) => l.startsWith('SUPABASE_SERVICE_ROLE_KEY=')).split('=').last.trim();
  const email = 'agostinhomarina334@gmail.com';
  const rt = 'fleaber://fleaber.com/auth-callback';

  final recoverUrl = Uri.parse(
    'https://fxdknzrqjenzqcvnwqqq.supabase.co/auth/v1/recover?redirect_to=${Uri.encodeComponent(rt)}',
  );
  final recover = await http.post(
    recoverUrl,
    headers: {'apikey': anon, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': email}),
  );
  print('\nrecover query redirect_to status=${recover.statusCode} body=${recover.body}');

  final gen = await http.post(
    Uri.parse('https://fxdknzrqjenzqcvnwqqq.supabase.co/auth/v1/admin/generate_link'),
    headers: {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'type': 'recovery',
      'email': email,
      'redirect_to': rt,
    }),
  );
  if (gen.statusCode < 400) {
    final m = jsonDecode(gen.body) as Map<String, dynamic>;
    print('generate_link redirect_to=${m['redirect_to']}');
    final link = m['action_link']?.toString() ?? '';
    if (link.isNotEmpty) {
      print('action_link redirect_to=${Uri.parse(link).queryParameters['redirect_to']}');
    }
  }
}
