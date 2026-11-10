import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pass1.json').readAsStringSync(),
  ) as Map;
  stdout.writeln('findings=${(j['findings'] as List).length} rpcs_oa=${j['rpcs_openapi']} tables=${j['tables_openapi']} rpc_hits=${(j['rpc_hits'] as List).length} matrix=${(j['matrix'] as List).length}');
  stdout.writeln('=== FINDINGS ===');
  for (final f in j['findings'] as List) {
    stdout.writeln(jsonEncode(f));
  }
  stdout.writeln('=== INTERESTING MATRIX ===');
  for (final m in j['matrix'] as List) {
    final r = (m['result'] ?? '').toString();
    final st = int.tryParse(r.split(' ').first) ?? 0;
    final empty = r == '$st []' || r == '$st {}' || r.trim() == '$st';
    final denied = r.toLowerCase().contains('permission denied') ||
        r.contains('42501') ||
        r.contains('PGRST301') ||
        r.contains('not_allowed') ||
        r.contains('JWT');
    final keep = (!empty && st >= 200 && st < 300) ||
        (st == 200 && !empty) ||
        (st >= 400 && st < 500 && !denied && r.length > 40);
    if (!keep) continue;
    final clip = r.length > 260 ? '${r.substring(0, 260)}…' : r;
    stdout.writeln('${m['identity']}|${m['surface']}|${m['attack']}|$clip');
  }
  stdout.writeln('=== RPC HITS 2xx or not 404 ===');
  for (final h in j['rpc_hits'] as List) {
    final st = h['status'] as int? ?? 0;
    final body = (h['body'] ?? '').toString();
    if (st == 404 || body.contains('PGRST202')) continue;
    if (st >= 200 && st < 300 || st == 403 || st == 401 || body.contains('permission denied')) {
      final clip = body.length > 180 ? '${body.substring(0, 180)}…' : body;
      stdout.writeln('${h['ident']}|${h['fn']}|$st|$clip');
    }
  }
}
