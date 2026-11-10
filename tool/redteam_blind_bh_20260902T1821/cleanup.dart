/// End leftover RTBH lives. No fixes.
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  final lives = await c.rest(
    'GET',
    'lives?title=like.$prefix*&select=id,title,status,is_active',
    service: true,
  );
  var n = 0;
  for (final row in lives.list.whereType<Map>()) {
    final id = row['id']?.toString();
    if (id == null) continue;
    await c.rest(
      'PATCH',
      'lives?id=eq.$id',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    n++;
  }
  stdout.writeln('ended $n lives prefix=$prefix');
}
