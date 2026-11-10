import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_g_20260829/pass1_raw.json').readAsStringSync(),
  ) as Map;
  print(jsonEncode(j['inventory']));
  print('interesting count=${(j['interesting'] as List).length}');
  final probes = (j['probes'] as List).cast<Map>();
  print('probe_count=${probes.length}');
  // rpc names from probes
  final rpcOk = probes
      .where((p) => '${p['id']}'.startsWith('rpc.') && p['http'] == 200)
      .map((p) => p['id'])
      .toList();
  print('rpc http200: $rpcOk');
  final rlsAnon = probes.where((p) =>
      '${p['id']}'.startsWith('rls.select.') &&
      '${p['id']}'.endsWith('.anon') &&
      p['http'] == 200);
  print('anon 200 tables:');
  for (final p in rlsAnon) {
    print('  ${p['id']} ${p['impact']}');
  }
}
