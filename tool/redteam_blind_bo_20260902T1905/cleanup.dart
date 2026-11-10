import 'dart:io';

import '_rtbo.dart';

Future<void> main() async {
  final c = Rtbo.fromEnv(loadEnv());
  final h = await c.rest(
    'GET',
    'lives?title=like.$prefix*&select=id,status,is_active,title',
    service: true,
  );
  for (final row in h.list) {
    if (row is! Map) continue;
    final id = '${row['id']}';
    await c.rest(
      'PATCH',
      'lives?id=eq.$id',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    stdout.writeln('ended $id ${row['status']} ${row['is_active']}');
  }
}
