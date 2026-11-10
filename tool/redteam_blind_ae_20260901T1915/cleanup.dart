/// Cleanup holds RTAE. service_role observação/cleanup. Não é exploit.
import 'dart:io';
import '_rtae.dart';

Future<void> main() async {
  final c = Rtae.fromEnv(loadEnv());
  await c.loginActors();
  final h = await c.rest(
    'GET',
    'orders?select=id,status,product_id&or=(status.eq.reserva_pendente,status.eq.reservado)&order=created_at.desc&limit=80',
    service: true,
  );
  var n = 0;
  for (final row in h.list) {
    if (row is! Map) continue;
    final id = '${row['id']}';
    final pid = '${row['product_id']}';
    final prod = await c.productRow(pid);
    if ('${prod?['title']}'.contains('RTAE-20260901T1915')) {
      await c.rest(
        'PATCH',
        'orders?id=eq.$id',
        service: true,
        body: {'status': 'cancelado'},
        prefer: 'return=minimal',
      );
      n++;
    }
  }
  stdout.writeln('cleanup cancelled=$n');
}
