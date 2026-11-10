/// Observe-only: re-ler orders da pass3 após corrigir select (sem return_delivered_at).
import 'dart:io';
import '_rtax.dart';

Future<void> main() async {
  final c = Rtax.fromEnv(loadEnv());
  await c.loginActors();
  const ids = [
    '780e0c61-62df-4e8c-bf68-8e8d55653c3f', // seller concluido + completed_at
    'a4818f9c-6cf4-48bd-83ef-ebd07a1c128f', // shipped_at backdate
    '92e85c19-dfa1-45bd-ac7a-98d7b0f97b8f', // svc unship
    '02700afa-8bac-493c-b666-4119ff00b79e', // happy release
    'a0be355c-b855-4302-bf23-71384dfa5279', // race
    'b016c19f-e3f9-4329-8c26-1803f7a37bb6', // refund pago
    'd136607e-f69e-43b3-83ea-739a20bcf50a', // unship JWT
  ];
  final out = <String, Object?>{};
  for (final id in ids) {
    final row = await c.orderRow(id);
    out[id] = row;
    stdout.writeln(
        '$id status=${row?['status']} ship=${row?['shipped_at']} done=${row?['completed_at']} rel=${row?['wallet_release_processed_at']} rf=${row?['stripe_refund_id']}');
  }
  await dumpJson('${outDir()}/observe.json', out);
}
