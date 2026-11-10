/// Confirm CE-B stored URLs + storage GET own vs alien + decode traversal.
import 'dart:io';
import '_rtce.dart';

Future<void> main() async {
  final c = Rtce.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final pass2 = File('${outDir()}/pass2.json');
  // find last paid-like proof from notes via listing own prefix
  final listOwn = await c.storageList(
    prefix: 'order_proofs/${c.buyerId}/',
    jwt: c.buyerJwt,
  );
  c.note('ctrl.list-own', 'B1 lista o próprio prefixo', {
    'http': listOwn.status,
    'n': listOwn.list.length,
    'snip': listOwn.brief,
  }, lens: 'CE6');

  // grab a recent order_proofs object name from list
  String? ownName;
  for (final e in listOwn.list) {
    if (e is Map && '${e['name']}'.contains('rtce_a.png')) {
      ownName = e['name']?.toString();
      break;
    }
  }
  ownName ??= listOwn.list.isNotEmpty && listOwn.list.first is Map
      ? (listOwn.list.first as Map)['name']?.toString()
      : null;

  if (ownName != null) {
    final getOwn = await c.storageGet(ownName, jwt: c.buyerJwt);
    c.note('ctrl.get-own', 'B1 GET própria prova', getOwn.brief, lens: 'CE6');
    final getB2 = await c.storageGet(ownName, jwt: c.buyer2Jwt);
    if (getB2.ok) {
      c.hold(
        id: 'CEC.get-cross-2',
        lens: 'CE6',
        severity: 'P1',
        title: 'B2 GET prova B1 (controlo com nome listado)',
        actor: 'buyer2 JWT',
        pre: 'storage select RLS',
        repro: 'GET authenticated/fleaber_private/$ownName',
        expected: '403/404',
        obtained: getB2.brief,
      );
    } else {
      c.block('CEC.get-cross-2', 'CE6', 'B2 GET nome listado recusado', getB2.brief);
    }
  }

  // persisted triple-encode / two-dot / overlong4 / iis-u cards
  final msgs = await c.rest(
    'GET',
    'chat_messages?text=like.*rtce_b.png*&select=id,text,created_at&order=created_at.desc&limit=20',
    service: true,
  );
  c.note('ctrl.cards', 'cards com rtce_b.png', {
    'n': msgs.list.length,
    'ids': msgs.list.take(8).map((e) => e is Map ? e['id'] : e).toList(),
  }, lens: 'CE4');

  for (final row in msgs.list) {
    if (row is! Map) continue;
    final text = '${row['text']}';
    if (text.contains('%25252e') ||
        text.contains('\u2025') ||
        text.contains('%f0%80%80%ae') ||
        text.contains('%u002e')) {
      c.note('ctrl.stored-url', 'URL persistida id=${row['id']}', text, lens: 'CE4');
    }
  }

  await dumpJson('${outDir()}/pass2b.json', {
    'pass': '2b',
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
}
