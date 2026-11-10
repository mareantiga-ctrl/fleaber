/// Lista prefixo A2 `order_disputes/{B1}/../` — loot B2?
import 'dart:convert';
import 'dart:io';
import '_rteq.dart';

void main() async {
  final c = Rteq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final names = <String, Object?>{};
  for (final prefix in [
    'order_disputes/$b1/../',
    'order_disputes/$b1/..',
    'order_disputes/$b2/',
    'order_disputes/',
  ]) {
    final h = await c.storageList(prefix: prefix, jwt: c.buyerJwt, limit: 50);
    names[prefix] = {
      'status': h.status,
      'n': h.list.length,
      'items': h.list
          .take(20)
          .map((e) => e is Map
              ? {'name': e['name'], 'id': e['id'], 'keys': e.keys.take(6).toList()}
              : e)
          .toList(),
    };
  }
  await dumpJson('${outDir()}/confirm_a2_list.json', names);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(names));
}
