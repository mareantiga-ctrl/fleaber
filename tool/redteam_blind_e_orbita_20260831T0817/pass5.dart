/// Blind E pass5 — GET settle session stale; estado final order; último ciclo.
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  final findings = <Map<String, dynamic>>[];
  final out = <String, dynamic>{'pass': 5, 'stamp': stamp};

  void add(Map<String, dynamic> f) {
    findings.add(f);
    stdout.writeln(
      '${f['proven'] == true ? "HIT" : "try"} ${f['severity']} ${f['id']} ${f['title']}',
    );
  }

  const oid = '0da5b981-a8a1-421a-8110-563519238849';
  const pid = 'fd9dd752-ebb4-42e6-b1bb-c80fe405280b';
  const sid = 'cs_test_a1Vr38MEbjEzj9udPyZqbI4oABwyvC2rLLj3VoRNPvJiCpqf5PG2TxYWAU';

  final settle = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: '?checkout_return=success&session_id=$sid',
  );
  add(finding(
    id: 'E7-STALE-SESSION-SETTLE-GET',
    lens: 'E7',
    severity: settle.ok &&
            (settle.body.toLowerCase().contains('pago') ||
                (settle.location ?? '').contains('stripe-success'))
        ? 'P1'
        : 'info',
    title: 'GET checkout_return success em Session de produto já unlistado',
    pre: 'session created then unlist; GET settle anon',
    repro: 'GET create-payment-intent?checkout_return=success&session_id=',
    proven: false,
    evidence: {
      'http': settle.status,
      'loc': settle.location,
      'snip': clip(settle.body, 400),
    },
  ));

  final ord = await c.rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_checkout_session_id,stock_units_applied,price_total',
    service: true,
  );
  final prod = await c.rest(
    'GET',
    'products?id=eq.$pid&select=id,list_on_marketplace,is_sold,quantity',
    service: true,
  );
  out['order'] = ord.map;
  out['product'] = prod.map;
  out['settle'] = {
    'http': settle.status,
    'loc': settle.location,
    'snip': clip(settle.body, 400),
  };

  final paid = ['pago', 'enviado', 'entregue', 'concluido']
      .contains((ord.map?['status'] ?? '').toString().toLowerCase());
  add(finding(
    id: 'E10-STALE-SESSION-PAID',
    lens: 'E10',
    severity: paid && prod.map?['list_on_marketplace'] == false ? 'P1' : 'info',
    title: 'order liquidada após Session pré-unlist (produto unlistado)',
    pre: 'observe order+product',
    repro: 'GET orders+products service',
    proven: paid && prod.map?['list_on_marketplace'] == false,
    evidence: {'order': ord.map, 'product': prod.map},
  ));

  // reviews_gerais via hub — buyer names
  final rev = await c.rest(
    'GET',
    'hub_reviews_public?select=id,author_display,comment,stars,target_id&limit=8',
  );
  out['reviews'] = {'n': rev.list.length, 'snip': clip(rev.body, 300)};

  // location of published hubs
  final loc = await c.rest(
    'GET',
    'hub_profiles_public?select=id,handle,full_name,location&limit=5',
  );
  out['hub_locations'] = loc.list;

  out['findings'] = findings;
  out['proven'] = findings.where((f) => f['proven'] == true).toList();
  await dumpJson('tool/redteam_blind_e_orbita_$stamp/out/pass5.json', out);
  stdout.writeln('proven ${out['proven'].length} / ${findings.length}');
}
