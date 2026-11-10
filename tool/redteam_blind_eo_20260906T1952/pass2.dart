/// RED TEAM CEGO EO pass2 — oráculos D3/D5 + B3 unpublish 200[].
/// Staging only. NÃO CORRIGIR.
import 'dart:io';
import '_rteo.dart';

void main() async {
  final c = Rteo.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final s1 = c.sellerId!;

  try {
    await confirmB3Unpub(c, s1);
    await confirmD3(c, s1);
    await confirmD5(c, s1);
  } finally {
    await c.restoreSeller1Published();
    await c.endLives();
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'EO pass2 findings=${c.findings.where((f) => f['count'] == true).length} '
    'probes=${c.probes.length}',
  );
}

Future<void> confirmB3Unpub(Rteo c, String s1) async {
  final before = await c.rest(
    'GET',
    'profiles?id=eq.$s1&select=id,hub_published',
    service: true,
  );
  final pub0 = before.map?['hub_published'];
  final patch = await c.rest(
    'PATCH',
    'profiles?id=eq.$s1',
    jwt: c.buyer2Jwt,
    body: {'hub_published': false},
  );
  final after = await c.rest(
    'GET',
    'profiles?id=eq.$s1&select=id,hub_published',
    service: true,
  );
  final pub1 = after.map?['hub_published'];
  final flipped = pub1 == false && pub0 != false;
  final empty = patch.list.isEmpty;
  stdout.writeln('CONFIRM B3 unpub status=${patch.status} empty=$empty pub $pub0→$pub1');
  c.probe(
    id: 'B3-confirm',
    lens: 'EO7',
    edgeRpc: 'PATCH profiles hub_published JWT B2 → S1',
    payload: 'hub_published=false',
    http: patch.brief,
    stripeBd: 'pub $pub0→$pub1 empty=$empty',
    result: flipped ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: flipped,
  );
  if (flipped) {
    c.hold(
      id: 'EO-P2-B3-UNPUB',
      lens: 'EO7',
      severity: 'P2',
      title: 'comprador JWT despublicou hub do vendedor',
      actor: 'B2 JWT',
      pre: 'RLS profiles update só self',
      repro: 'PATCH profiles?id=eq.S1 hub_published=false JWT B2',
      expected: '200 [] sem flip',
      obtained: {'pub0': pub0, 'pub1': pub1, 'body': patch.brief},
    );
  } else {
    c.block('B3.unpub-confirm', 'EO7', '200 [] sem flip hub S1', {
      'status': patch.status,
      'empty': empty,
      'pub': pub1,
    });
  }
}

Future<void> confirmD3(Rteo c, String s1) async {
  const trSame = 'tr_1UClHTH7FWYUN3jhkAnpAHI3';
  const trOther = 'tr_1UClHWH7FWYUN3jhrjrRgB5T';
  final led = await c.payoutLedger(s1, limit: 16);
  final same = led.where((r) => '${r['stripe_transfer_id']}' == trSame).toList();
  final other = led.where((r) => '${r['stripe_transfer_id']}' == trOther).toList();
  final sameKey = same.isEmpty ? null : same.first['idempotency_key'];
  final otherKey = other.isEmpty ? null : other.first['idempotency_key'];
  stdout.writeln('CONFIRM D3 same=$same other=$other');
  c.note('confirm.D3', 'ledger 2 tr_ duas keys', {
    'same': same,
    'other': other,
    'same_key': sameKey,
    'other_key': otherKey,
  }, lens: 'EO8');
  final dupSame = same.length > 1;
  c.probe(
    id: 'D3-confirm',
    lens: 'EO8',
    edgeRpc: 'wallet_payout_ledger tr_ D3',
    payload: '$trSame vs $trOther',
    http: 'same_n=${same.length} other_n=${other.length} keys=$sameKey / $otherKey',
    stripeBd: {'same': same, 'other': other},
    result: dupSame ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: dupSame,
  );
  if (dupSame) {
    c.hold(
      id: 'EO-P0-D3-DOUBLE-TR',
      lens: 'EO8',
      severity: 'P0',
      title: 'mesma payout key com 2 linhas Transfer',
      actor: 'seller JWT',
      pre: '1 key = 1 tr_',
      repro: 'ledger stripe_transfer_id',
      expected: '1 row por tr_',
      obtained: same,
    );
  } else {
    c.block('D3.ledger', 'EO8', '1 tr_ por key', {
      'same_n': same.length,
      'other_n': other.length,
    });
  }
}

Future<void> confirmD5(Rteo c, String s1) async {
  const oid0 = '10f26682-6074-431d-917f-4c550744c7cb';
  const oid50 = 'c3016c96-e63c-4d0a-be54-25b8014910c7';
  final or0 = await c.oracleWalletDispute(oid0, s1);
  final or50 = await c.oracleWalletDispute(oid50, s1);
  stdout.writeln('CONFIRM D5 0ms=$or0');
  stdout.writeln('CONFIRM D5 50ms=$or50');
  final bad = or0['both'] == true || or50['both'] == true;
  c.probe(
    id: 'D5-confirm',
    lens: 'EO7',
    edgeRpc: 'oracle release∥disputa 0ms + 50ms',
    payload: '$oid0 / $oid50',
    http: 'both0=${or0['both']} both50=${or50['both']}',
    stripeBd: {'0ms': or0, '50ms': or50},
    result: bad ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: bad,
  );
  if (bad) {
    c.hold(
      id: 'EO-P1-D5-BOTH',
      lens: 'EO7',
      severity: 'P1',
      title: 'crédito líquido + claim aberto',
      actor: 'buyer JWT',
      pre: 'both=false',
      repro: 'oracle D5',
      expected: 'net≤0 ou open_n=0',
      obtained: {'0ms': or0, '50ms': or50},
    );
  } else {
    c.block('D5.oracle', 'EO7', 'both=false 0ms+50ms', {
      'net0': or0['net'],
      'open0': or0['open_n'],
      'net50': or50['net'],
      'open50': or50['open_n'],
      'venda50': or50['venda'],
    });
  }
}
