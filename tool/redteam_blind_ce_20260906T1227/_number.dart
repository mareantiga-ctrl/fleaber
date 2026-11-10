import 'dart:convert';
import 'dart:io';

void main() {
  final p1 = jsonDecode(File('pass1.json').readAsStringSync()) as Map;
  final p2 = jsonDecode(File('pass2.json').readAsStringSync()) as Map;
  final findings = <Map<String, dynamic>>[];
  var i = 1;
  for (final f in [...(p1['findings'] as List), ...(p2['findings'] as List)]) {
    final m = Map<String, dynamic>.from(f as Map);
    m['numbered'] = 'P1-$i';
    findings.add(m);
    i++;
  }
  stdout.writeln('P1_COUNT=${i - 1}');
  File('findings_numbered.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'p0': 0,
      'p1': i - 1,
      'p2': 0,
      'p3': 0,
      'p4': 0,
      'findings': findings,
    }),
  );
}
