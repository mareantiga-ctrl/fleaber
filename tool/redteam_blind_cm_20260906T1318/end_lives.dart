/// Terminar fixtures live CM (não deixar directo a correr).
import 'dart:convert';
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  final idsFile = File('${outDir()}/pass1_ids.json');
  if (!idsFile.existsSync()) {
    stderr.writeln('no pass1_ids');
    exit(1);
  }
  final ids = jsonDecode(await idsFile.readAsString()) as Map<String, dynamic>;
  for (final k in ['airPub', 'airUnpub', 'schedUnpub', 'endedUnpub']) {
    final id = ids[k]?.toString();
    if (id == null || id.isEmpty) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
    stdout.writeln('ended $k $id');
  }
  final leftover = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active',
    service: true,
  );
  for (final row in leftover.list) {
    if (row is! Map) continue;
    final id = '${row['id']}';
    if (id.isEmpty) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
    stdout.writeln('ended leftover $id ${row['title']}');
  }
  if (ids['s2'] != null) {
    await c.rest('PATCH', 'profiles?id=eq.${ids['s2']}', service: true, body: {
      'is_live': false,
      'hub_published': false,
    }, prefer: 'return=minimal');
  }
  if (ids['s1'] != null) {
    await c.rest('PATCH', 'profiles?id=eq.${ids['s1']}', service: true, body: {
      'hub_published': true,
      'is_live': false,
    }, prefer: 'return=minimal');
  }
  if (ids['raffleId'] != null) {
    await c.rest(
      'PATCH',
      'live_raffles?id=eq.${ids['raffleId']}',
      service: true,
      body: {'status': 'cancelled'},
      prefer: 'return=minimal',
    );
  }
}
