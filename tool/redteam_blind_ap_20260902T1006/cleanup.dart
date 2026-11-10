/// Encerrar leftovers RTAP (não é fix de produto).
import 'dart:io';
import '_rtap.dart';

Future<void> main() async {
  final rt = Rtap.fromEnv(loadEnv());
  final h = await rt.rest(
    'GET',
    'lives?title=like.*RTAP-20260902T1006*&select=id,status,is_active,title',
    service: true,
  );
  stdout.writeln('leftover ${h.brief}');
  for (final row in h.list) {
    if (row is! Map) continue;
    final id = row['id'];
    final st = '${row['status']}';
    final active = row['is_active'] == true;
    if (id == null) continue;
    if (st == 'ended' && !active) continue;
    final p = await rt.rest(
      'PATCH',
      'lives?id=eq.$id',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    stdout.writeln('ended $id ${p.status}');
  }
}
