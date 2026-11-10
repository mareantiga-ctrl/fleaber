/// Cleanup fixtures is_live (service_role observação/cleanup). Não é correção de produto.
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();
  for (final id in [c.buyer2Id, c.seller2Id]) {
    if (id == null) continue;
    await c.rest(
      'PATCH',
      'profiles?id=eq.$id',
      service: true,
      body: {'is_live': false, 'hub_published': false},
      prefer: 'return=minimal',
    );
  }
  stdout.writeln('cleaned is_live on ${c.buyer2Id} ${c.seller2Id}');
}
