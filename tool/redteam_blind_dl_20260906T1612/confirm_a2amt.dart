import 'dart:io';
import '_rtdl.dart';

void main() async {
  final c = Rtdl.fromEnv(loadEnv());
  final sid = 'cs_test_a1XiyCygYjU8wqhMyi7mI2DghdC3mJaA6kU9PWyDznH6PzwIGictQZxb7P';
  final ev = await c.rest(
    'GET',
    'stripe_checkout_events?session_id=eq.$sid&select=event,detail,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  final oid = 'd5c93937-9a4f-4d39-8ffa-a024e394bed0';
  final row = await c.orderRow(oid);
  await dumpJson('${outDir()}/confirm_a2amt.json', {
    'events': ev.json,
    'order': row,
  });
  stdout.writeln('events=${ev.brief}');
  stdout.writeln('order=${row}');
}
