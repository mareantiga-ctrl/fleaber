// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final h = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
  };
  final ids = [
    '7527829b-6779-493c-aefe-30293ba5437e',
    '4e89082a-a4f0-428e-9dad-5e4889a03715',
  ];
  for (final id in ids) {
    final r = await http.get(
      Uri.parse('$url/rest/v1/chats?id=eq.$id&select=id,last_message,last_message_time'),
      headers: h,
    );
    print('CHAT $id ${r.statusCode} ${r.body}');
  }
  final m = await http.get(
    Uri.parse('$url/rest/v1/chat_messages?id=eq.1025&select=id,text'),
    headers: h,
  );
  print('MSG1025 ${m.body}');
  final m1004 = await http.get(
    Uri.parse('$url/rest/v1/chat_messages?id=eq.1004&select=id,created_at'),
    headers: h,
  );
  print('MSG1004 ${m1004.body}');
}
