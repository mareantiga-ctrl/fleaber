import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1719/out/pass1.json').readAsStringSync(),
  ) as Map;
  stdout.writeln(
    'tables=${(j['tables'] as List).length} rpcs=${(j['rpcs'] as List).length} product=${j['product_id']} hostile=${j['order_hostile_id']} stripe=${j['order_stripe_id']} ghost=${j['ghost_id']}',
  );
  stdout.writeln('--- INTERESTING ---');
  for (final raw in (j['matrix'] as List)) {
    final m = Map<String, dynamic>.from(raw as Map);
    final r = '${m['result']}';
    final impact = '${m['impact'] ?? ''}';
    final keep = impact.isNotEmpty && impact != 'null' ||
        r.startsWith('201') ||
        r.startsWith('200 {') ||
        r.startsWith('200 [') && r.length > 8 ||
        r.contains('EXECUTED') ||
        r.startsWith('204');
    if (!keep) continue;
    if (r.startsWith('EMPTY')) continue;
    if (r.startsWith('DENIED')) continue;
    var line =
        '${m['identity']} | ${m['surface']} | ${m['attack']} | $impact | $r';
    if (line.length > 280) line = '${line.substring(0, 280)}…';
    stdout.writeln(line);
  }
  stdout.writeln('--- INTERESTING RPCS ---');
  stdout.writeln((j['interesting_rpcs'] as List).join('\n'));
}
