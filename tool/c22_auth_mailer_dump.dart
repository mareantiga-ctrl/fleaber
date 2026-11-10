// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final token = Platform.environment['SUPABASE_ACCESS_TOKEN']?.trim() ?? '';
  if (token.isEmpty) exit(2);
  final res = await http.get(
    Uri.parse('https://api.supabase.com/v1/projects/fxdknzrqjenzqcvnwqqq/config/auth'),
    headers: {'Authorization': 'Bearer $token'},
  );
  final auth = jsonDecode(res.body) as Map<String, dynamic>;
  for (final e in auth.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final k = e.key.toLowerCase();
    if (k.contains('mail') || k.contains('smtp') || k.contains('subject') || k.contains('sender')) {
      print('${e.key}: ${e.value}');
    }
  }
}
