import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pass1.json').readAsStringSync(),
  ) as Map;
  for (final m in j['matrix'] as List) {
    final a = '${m['attack']}';
    if (!a.contains('PATCH own') &&
        !a.contains('seller PATCH status') &&
        !a.contains('own after') &&
        !a.contains('row after hostile')) {
      continue;
    }
    stdout.writeln('=== ${m['identity']} | ${m['attack']}');
    stdout.writeln(m['result']);
    stdout.writeln('');
  }
}
