/// RED TEAM CEGO AP — pass 3. Visibilidade da mensagem falsa para 3.º viewer.
import 'dart:io';
import '_rtap.dart';

Future<void> main() async {
  final rt = Rtap.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();

  const liveS2 = 'cd7bc171-0079-425c-9266-2c7e3891e2ba';
  const liveA = '64acdcb0-805f-42d1-869a-defccef7fa7b';

  final asB2s2 = await rt.rest(
    'GET',
    'live_messages?live_id=eq.$liveS2&select=id,kind,body,user_id,channel&order=created_at.desc&limit=10',
    jwt: rt.buyer2Jwt,
  );
  final asB2a = await rt.rest(
    'GET',
    'live_messages?live_id=eq.$liveA&select=id,kind,body,user_id,channel&order=created_at.desc&limit=10',
    jwt: rt.buyer2Jwt,
  );
  final asAnon = await rt.rest(
    'GET',
    'live_messages?live_id=eq.$liveS2&select=id,kind,body&limit=5',
  );

  bool sawComprou(HttpHit h) =>
      h.ok && h.body.contains('comprou') && h.body.contains('Maestro Buyer');

  if (sawComprou(asB2s2)) {
    rt.hold(
      id: 'AP7-09b',
      lens: 'AP7',
      severity: 'P2',
      title: '3.º comprador lê «comprou» falso na live alheia',
      actor: 'buyer2 JWT',
      pre: 'mensagem plantada no pass2 na live S2',
      repro: 'GET live_messages live_id=S2',
      expected: 'system de compra só após convert pago',
      obtained: asB2s2.brief,
    );
  } else {
    rt.block('AP7-09b', 'AP7', 'buyer2 lê live S2', asB2s2);
  }

  if (sawComprou(asB2a)) {
    rt.hold(
      id: 'AP1-11d',
      lens: 'AP1',
      severity: 'P2',
      title: '3.º comprador lê «comprou» falso na live A',
      actor: 'buyer2 JWT',
      pre: 'mensagem plantada pass2',
      repro: 'GET live_messages live A',
      expected: 'não ver compra inventada',
      obtained: asB2a.brief,
    );
  } else {
    rt.block('AP1-11d', 'AP1', 'buyer2 lê live A', asB2a);
  }

  rt.note('AP7.anon.msgs', 'anon live_messages S2', asAnon.brief, lens: 'AP7');

  await rt.dumpAll('pass3.json');
  stdout.writeln(
      'DONE p3 findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
