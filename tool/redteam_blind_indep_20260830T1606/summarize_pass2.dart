import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pass2.json').readAsStringSync(),
  ) as Map;
  stdout.writeln('findings=${(j['findings'] as List).length} matrix=${(j['matrix'] as List).length}');
  stdout.writeln('=== FINDINGS ===');
  stdout.writeln(jsonEncode(j['findings']));
  stdout.writeln('=== RACES ===');
  stdout.writeln(jsonEncode(j['races']));
  stdout.writeln('=== STRIPE ===');
  stdout.writeln(jsonEncode(j['stripe']));
  stdout.writeln('=== MATRIX ===');
  for (final m in j['matrix'] as List) {
    final r = '${m['result']}';
    final clip = r.length > 420 ? '${r.substring(0, 420)}…' : r;
    stdout.writeln('--- ${m['identity']} | ${m['surface']} | ${m['attack']}');
    stdout.writeln(clip);
  }
}
