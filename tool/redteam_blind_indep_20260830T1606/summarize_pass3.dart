import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pass3.json').readAsStringSync(),
  ) as Map;
  stdout.writeln('findings=${(j['findings'] as List).length}');
  stdout.writeln(jsonEncode(j['findings']));
  stdout.writeln('=== RACES ===');
  stdout.writeln(jsonEncode(j['races']));
  stdout.writeln('=== STRIPE ===');
  stdout.writeln(jsonEncode(j['stripe']));
  if (File('tool/redteam_blind_indep_20260830T1606/out/dual_sessions.json').existsSync()) {
    stdout.writeln('=== DUAL FILE ===');
    stdout.writeln(File('tool/redteam_blind_indep_20260830T1606/out/dual_sessions.json').readAsStringSync());
  }
  for (final m in j['matrix'] as List) {
    final r = '${m['result']}';
    final clip = r.length > 380 ? '${r.substring(0, 380)}…' : r;
    stdout.writeln('--- ${m['identity']} | ${m['surface']} | ${m['attack']}');
    stdout.writeln(clip);
  }
}
