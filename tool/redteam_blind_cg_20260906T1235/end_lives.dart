/// Terminar fixtures live CG (não deixar directo a correr).
import 'dart:convert';
import 'dart:io';
import '_rtcg.dart';

Future<void> main() async {
  final c = Rtcg.fromEnv(loadEnv());
  final idsFile = File('${outDir()}/pass1_ids.json');
  if (!idsFile.existsSync()) {
    stderr.writeln('no pass1_ids');
    exit(1);
  }
  final ids = jsonDecode(await idsFile.readAsString()) as Map<String, dynamic>;
  for (final k in ['airPub', 'airUnpub', 'schedUnpub', 'endedUnpub', 'schedPub']) {
    final id = ids[k]?.toString();
    if (id == null || id.isEmpty) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
    stdout.writeln('ended $k $id');
  }
  await c.rest('PATCH', 'profiles?id=eq.${ids['s2']}', service: true, body: {
    'is_live': false,
    'hub_published': false,
  }, prefer: 'return=minimal');
}
