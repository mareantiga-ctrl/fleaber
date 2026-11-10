import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final hs = {
    'apikey': service,
    'Authorization': 'Bearer $service',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final ids = [
    'd7d6cd90-8007-45f1-a981-630d063c8849',
    '3eab3d83-2751-44a3-9489-77253f16de48',
    'f0fd22c3-ff21-40d3-93a6-e3a2910e696c',
    '039f016f-b62a-40d2-95c8-1a17cd6bbc77',
    '08b73879-6e0b-4479-8c6f-633a2312e42c',
    'a16619b5-d5ea-4f42-a6e4-351277116402',
  ];
  for (final id in ids) {
    final r = await http.patch(
      Uri.parse('$base/rest/v1/orders?id=eq.$id'),
      headers: hs,
      body: jsonEncode({'status': 'cancelado'}),
    );
    stdout.writeln('$id ${r.statusCode}');
  }
}
