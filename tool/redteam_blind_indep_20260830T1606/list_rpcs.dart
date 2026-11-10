import 'dart:convert';
import 'dart:io';

void main() {
  final inv = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/openapi_rpcs.json').readAsStringSync(),
  ) as Map;
  final rpcs = (inv['rpcs'] as List).cast<String>()..sort();
  stdout.writeln('RPC count ${rpcs.length}');
  for (final r in rpcs) {
    stdout.writeln(r);
  }
}
