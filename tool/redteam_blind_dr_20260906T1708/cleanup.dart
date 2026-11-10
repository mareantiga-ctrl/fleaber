/// End leftover RTDR lives. Restore S1 hub. Cancel raffles. No fixes.
import 'dart:io';

import '_rtdr.dart';

Future<void> main() async {
  final c = Rtdr.fromEnv(loadEnv());
  await c.loginActors();
  await c.restoreSeller1Published();

  final h = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active&limit=120',
    service: true,
  );
  stdout.writeln('found ${h.list.length}');
  for (final row in h.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.endLive(id);
      stdout.writeln(
          'ended $id ${row['title']} ${row['status']} ${row['is_active']}');
    }
  }

  final raffles = await c.rest(
    'GET',
    'live_raffles?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status&limit=40',
    service: true,
  );
  stdout.writeln('raffles ${raffles.list.length}');
  for (final row in raffles.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.rest(
        'PATCH',
        'live_raffles?id=eq.$id',
        service: true,
        body: {'status': 'cancelled'},
        prefer: 'return=minimal',
      );
      stdout.writeln('raffle cancelled $id ${row['title']}');
    }
  }
}
