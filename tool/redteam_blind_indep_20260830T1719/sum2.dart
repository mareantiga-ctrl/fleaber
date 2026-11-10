import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1719/out/pass2.json').readAsStringSync(),
  ) as Map;
  stdout.writeln('rpcs=${j['rpc_count']} findings=${(j['findings'] as List).length}');
  stdout.writeln(jsonEncode(j['findings']));
  stdout.writeln('\n==== MATRIX ====');
  for (final raw in (j['matrix'] as List)) {
    final m = Map<String, dynamic>.from(raw as Map);
    var line =
        '${m['identity']} | ${m['surface']} | ${m['attack']} | ${m['impact']} | ${m['result']}';
    if (line.length > 320) line = '${line.substring(0, 320)}…';
    stdout.writeln(line);
  }
}
