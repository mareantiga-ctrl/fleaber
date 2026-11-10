// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final env = File('tool/live_ops_staging.env').readAsLinesSync();
  final service = env
      .firstWhere((l) => l.startsWith('SUPABASE_SERVICE_ROLE_KEY='))
      .split('=')[1]
      .trim();
  const url = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
  const email = 'agostinhomarina334@gmail.com';
  final bodies = [
    {
      'type': 'recovery',
      'email': email,
      'options': {'redirect_to': 'fleaber://fleaber.com/auth-callback'},
    },
    {
      'type': 'recovery',
      'email': email,
      'options': {'redirectTo': 'fleaber://fleaber.com/auth-callback'},
    },
    {
      'type': 'recovery',
      'email': email,
      'redirect_to': 'fleaber://fleaber.com/auth-callback',
    },
  ];
  for (final b in bodies) {
    final res = await http.post(
      Uri.parse('$url/auth/v1/admin/generate_link'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(b),
    );
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    print('payload=$b');
    print('  redirect_to=${m['redirect_to']}\n');
  }
}
