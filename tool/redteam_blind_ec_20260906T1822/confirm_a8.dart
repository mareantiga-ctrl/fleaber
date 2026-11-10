/// Confirm A6/A8 oráculos DTDY — clawback + smuggle. Staging only. NÃO CORRIGIR.
import 'dart:convert';
import 'dart:io';
import '_rtec.dart';

Future<void> main() async {
  final c = Rtec.fromEnv(loadEnv());
  await c.loginActors();
  const a6oid = '55a5d7c3-bc63-4c04-889f-9880e6dd93df';
  const a6did = '4c9801fa-9733-41e3-90d4-51fd55e77213';
  const a8oid = 'e07fcff6-6e2f-408f-bd17-930942bc286b';
  const a8did = '16388d5f-d10f-4fdb-8319-1c401d55612d';
  final s1 = c.sellerId!;

  final a6 = await c.oracleWalletDispute(a6oid, s1);
  final a8 = await c.oracleWalletDispute(a8oid, s1);
  final a6d = await c.rest(
    'GET',
    'order_disputes?id=eq.$a6did&select=id,status,reason,created_at,buyer_id',
    service: true,
  );
  final a8d = await c.rest(
    'GET',
    'order_disputes?id=eq.$a8did&select=id,status,reason,created_at,buyer_id',
    service: true,
  );
  final a8tx = await c.txnsForOrder(s1, a8oid);
  final out = {
    'a6_oracle': a6,
    'a6_disp': a6d.map ?? a6d.brief,
    'a8_oracle': a8,
    'a8_disp': a8d.map ?? a8d.brief,
    'a8_txns': a8tx,
    's1_bal': await c.walletBal(s1),
  };
  await dumpJson('${outDir()}/confirm_a8.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'a6_both': a6['both'],
    'a6_net': a6['net'],
    'a6_open': a6['open_status'],
    'a6_disp': a6d.brief,
    'a8_both': a8['both'],
    'a8_net': a8['net'],
    'a8_venda': a8['venda'],
    'a8_estorno': a8['estorno'],
    'a8_open': a8['open_status'],
    'a8_release_at': a8['release_at'],
    'a8_txns': a8tx
        .map((t) => '${t['type']} ${t['amount']} ${t['id']}')
        .toList(),
  }));
}
