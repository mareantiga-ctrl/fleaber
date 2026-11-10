/// PASS 5 — H1 raffle INSERT · wallet helper · encerrar leftovers Mux.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureHelperChat();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 5, 'prefix': prefix};

  c.helperChatLinkId = await c.inviteHelper(
    helperUserId: c.helperChatId!,
    helperJwt: c.helperChatJwt!,
    permissions: chatOnlyPerms,
    display: '$prefix chat-only',
  );

  final wal = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance',
    jwt: c.helperChatJwt,
  );
  c.note('p5.h1.wallet', 'helper GET wallet loja', wal.brief, lens: 'H1');
  if (wal.ok && wal.list.isNotEmpty) {
    c.hold(
      id: 'RTH-H1-020',
      lens: 'H1',
      severity: 'P0',
      title: 'Helper chat-only lê saldo da loja',
      actor: 'helperChat',
      pre: 'can_view_payouts=false',
      repro: 'GET wallets?id=eq.seller',
      expected: '[]',
      obtained: wal.snippet,
    );
  }

  final live = await c.insertLive(active: true);
  if (live != null) {
    final raffleIns = await c.rest('POST', 'live_raffles', jwt: c.helperChatJwt, body: {
      'live_id': live,
      'seller_id': c.sellerId,
      'title': '$prefix helper raffle',
      'status': 'open',
    });
    c.note('p5.h1.raffle.ins', 'helper INSERT live_raffles', raffleIns.brief,
        lens: 'H1');
    if (raffleIns.ok && raffleIns.firstId != null) {
      c.hold(
        id: 'RTH-H1-021',
        lens: 'H1',
        severity: 'P1',
        title: 'Helper chat-only criou rifa na live da loja',
        actor: 'helperChat',
        pre: 'can_manage_raffles=false',
        repro: 'POST live_raffles',
        expected: '403',
        obtained: raffleIns.brief,
      );
    }

    final raffleS2 = await c.rest('POST', 'live_raffles', jwt: c.helperChatJwt, body: {
      'live_id': live,
      'seller_id': c.buyer2Id,
      'title': '$prefix cross raffle',
    });
    c.note('p5.h5.raffle.cross', 'helper raffle seller_id=B2', raffleS2.brief,
        lens: 'H5');
    if (raffleS2.ok && raffleS2.firstId != null) {
      c.hold(
        id: 'RTH-H5-020',
        lens: 'H5',
        severity: 'P1',
        title: 'Helper criou rifa com seller_id alheio',
        actor: 'helperChat',
        pre: 'seller_id=buyer2',
        repro: 'POST live_raffles seller_id=B2',
        expected: '403',
        obtained: raffleS2.brief,
      );
    }
  }

  final leftover = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeComponent('$prefix*')}&select=id,title,status,is_active,seller_id,vendedor_id&limit=30',
    service: true,
  );
  c.note('p5.leftover.lives', 'lives RTH', leftover.brief, lens: 'H5');
  for (final row in leftover.list) {
    if (row is! Map) continue;
    final id = row['id']?.toString();
    if (id == null) continue;
    if (row['is_active'] == true || row['status'] == 'live') {
      await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal');
    }
  }

  await c.endLives();
  out['notes'] = c.notes;
  out['findings'] = c.findings;
  await dumpJson('tool/redteam_blind_h_20260831T1706/pass5.json', out);
  stdout.writeln('PASS5 findings=${c.findings.length}');
}
