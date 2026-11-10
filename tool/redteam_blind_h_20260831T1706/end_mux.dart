/// End leftover Mux lives from this freeze. Staging only.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureHelperChat();
  await c.ensureBuyer2();

  final ids = [
    '9d0f249f-3b10-4aa5-ab55-0a9f0df2e390',
    '1d81f075-8f7a-4c76-8aa0-4f5a1549e8fd',
    'e03bd487-7ac1-45d5-b5cf-de16f62cd768',
  ];
  for (final id in ids) {
    final row = await c.rest(
      'GET',
      'lives?id=eq.$id&select=id,title,status,is_active,vendedor_id,mux_live_id',
      service: true,
    );
    stdout.writeln('LIVE $id ${row.brief}');
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  final more = await c.rest(
    'GET',
    'lives?or=(vendedor_id.eq.${c.helperChatId},vendedor_id.eq.${c.buyer2Id})&select=id,title,status,is_active&order=created_at.desc&limit=10',
    service: true,
  );
  stdout.writeln('HELPER/B2 LIVES ${more.brief}');
  for (final row in more.list) {
    if (row is! Map) continue;
    if (row['is_active'] == true || row['status'] == 'live') {
      final id = row['id'];
      await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
      stdout.writeln('ENDED $id');
    }
  }
}
