import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final r = await http.delete(
    Uri.parse('$url/rest/v1/seller_helpers?id=eq.dbf0e8bc-730f-4220-a86a-438ad8eccb5e'),
    headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
  );
  stdout.writeln('helper cleanup ${r.statusCode}');
}
