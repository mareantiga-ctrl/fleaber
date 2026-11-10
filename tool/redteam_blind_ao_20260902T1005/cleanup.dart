/// Fixture cleanup only — service_role. Does not patch security.
import 'dart:io';
import '_rtao.dart';

Future<void> main() async {
  final c = Rtao.fromEnv(loadEnv());
  const chatId = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  final ids = [
    ...List.generate(48, (i) => '${1200 + i}'),
  ];
  for (final id in ids) {
    await c.rest(
      'DELETE',
      'chat_messages?id=eq.$id',
      service: true,
      prefer: 'return=minimal',
    );
  }
  await c.rest(
    'PATCH',
    'chats?id=eq.$chatId',
    service: true,
    body: {'last_message': 'RTAO audit ended'},
    prefer: 'return=minimal',
  );
  stdout.writeln('cleanup done');
}
