/// Encerrar leftovers RTBB2 (não é fix de produto).
import 'dart:io';
import '_rtbb.dart';

Future<void> main() async {
  final rt = Rtbb.fromEnv(loadEnv());
  final h = await rt.rest(
    'GET',
    'lives?title=like.*RTBB2-20260902T1606*&select=id,status,is_active,title',
    service: true,
  );
  stdout.writeln('leftover ${h.brief}');
  var n = 0;
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
    n++;
    stdout.writeln('ended $id ${p.status}');
  }
  stdout.writeln('closed=$n');
}
