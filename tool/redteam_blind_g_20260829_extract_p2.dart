import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_g_20260829/pass2_raw.json').readAsStringSync(),
  ) as Map;
  for (final p in (j['probes'] as List).cast<Map>()) {
    print('==== ${p['id']} http=${p['http']} sev=${p['severity_hint']} pers=${p['persisted']}');
    print('attack: ${p['attack']}');
    print('before: ${p['before']}');
    print('after: ${p['after']}');
    print('impact: ${p['impact']}');
    print(p['response']);
    print('');
  }
}
