// ignore_for_file: avoid_print
/// AV pass3 — AV3-02: sold real via mark_sold RPC, Hub/REST
import 'dart:io';

import '_rtav.dart';

Future<void> main() async {
  final env = loadEnv();
  final rt = Rtav.fromEnv(env);
  await rt.loginActors();

  final live = await rt.insertLive(title: '$prefix p3');
  final item = (await rt.insertItem(
    liveId: live!,
    service: true,
    kind: 'live_only',
    qty: 1,
    price: 5,
    title: '$prefix p3-sold',
  ))
      .firstId!;

  final ms = await rt.markSold(item);
  final row = await rt.itemRow(item);
  final hub = await rt.hubDiscoveryItem(item);
  final buyer = await rt.rest(
    'GET',
    'live_items?id=eq.$item&select=id,status,quantity,is_active',
    jwt: rt.buyerJwt,
  );
  final anonStock = await rt.stockRpc(item, anon: true);

  rt.judge(
    id: 'AV3-02',
    lens: 'AV3',
    title: 'Após mark_sold sem PI, item sold visível Hub/REST buyer/anon stock',
    hit: buyer,
    cracked: hub != null ||
        buyer.list.isNotEmpty ||
        (anonStock.ok && '${anonStock.body}'.contains('available_qty')),
    actor: 'anon + buyer JWT',
    pre: 'mark_sold RPC sem order paga; live_item status deve ser sold',
    repro: 'rpc mark_sold + hub discovery + live_items SELECT + stock anon',
    expected: 'Hub vazio; buyer sem row; anon not_found',
    severity: 'P2',
    evidence: {
      'ms': ms.brief,
      'item': row,
      'hub': hub,
      'buyer': buyer.brief,
      'anonStock': anonStock.brief,
    },
  );

  await rt.cleanupSoft();
  await rt.dumpAll('pass3.json');
  stdout.writeln('PASS3 findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
