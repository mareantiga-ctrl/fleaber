/// PASS 1 — L1 JWT chama jobs de cron / cleanup / expire / auto-feedback.
/// Anti-atrofia: só catálogo de jobs + EXECUTE. Sem dual-session, bag, JSON, mint, hold cancel, hub, pairing, offer morto, helper.
import 'dart:io';

import '_rtl.dart';

const cronLike = <String>[
  'batata_generate_auto_feedback',
  'batata_expire_product_offers',
  'batata_invoke_livekit_egress_cleanup',
  'batata_release_seller_wallet_for_order',
  'batata_release_expired_reservations',
  'batata_claim_expired_reservations',
  'batata_expire_pending_orders',
  'batata_process_auto_feedback',
  'expire_product_offers',
  'generate_auto_feedback',
  'batata_expire_holds',
  'batata_expire_reservations',
  'batata_expire_live_reservations',
  'batata_cleanup_stale_holds',
  'batata_release_stale_reservations',
];

bool looksCron(String name) {
  final n = name.toLowerCase();
  return n.contains('cron') ||
      n.contains('expire') ||
      n.contains('feedback') ||
      n.contains('cleanup') ||
      n.contains('ttl') ||
      n.contains('stale') ||
      (n.contains('release') &&
          (n.contains('wallet') ||
              n.contains('reserv') ||
              n.contains('hold') ||
              n.contains('expired')));
}

void main() async {
  final env = loadEnv();
  final c = Rtl.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  c.note('p1.openapi', 'openapi status', openapi.status, lens: 'L1');

  final rpcNames = <String>{};
  final paths = openapi.map?['paths'];
  if (paths is Map) {
    for (final k in paths.keys) {
      final s = k.toString();
      if (s.startsWith('/rpc/')) {
        rpcNames.add(s.substring('/rpc/'.length));
      }
    }
  }
  final cronFromSpec = rpcNames.where(looksCron).toList()..sort();
  c.note('p1.openapi.cron', 'rpc cron-like no spec', cronFromSpec, lens: 'L1');

  final toProbe = <String>{...cronLike, ...cronFromSpec};

  Future<void> tryFn(String fn, {required String actor, String? jwt, bool service = false, Object args = const {}}) async {
    final hit = await c.rpc(fn, args, jwt: jwt, service: service);
    c.note('p1.rpc.$actor.$fn', '$actor $fn', hit.brief, lens: 'L1');
    final privileged = fn.contains('auto_feedback') ||
        fn.contains('expire') ||
        fn.contains('cleanup') ||
        fn.contains('cron');
    if (!service && privileged && hit.ok) {
      c.hold(
        id: 'RTL-L1-${fn.replaceAll('batata_', '')}-$actor',
        lens: 'L1',
        severity: 'P0',
        title: 'JWT/anon executa job de cron $fn',
        actor: actor,
        pre: 'função security definer de job',
        repro: 'POST /rest/v1/rpc/$fn como $actor',
        expected: '403 / 401 / permission denied',
        obtained: hit.brief,
        evidence: {'fn': fn, 'actor': actor, 'body': hit.snippet},
      );
    }
  }

  for (final fn in toProbe) {
    await tryFn(fn, actor: 'anon');
    await tryFn(fn, actor: 'buyer', jwt: c.buyerJwt);
    await tryFn(fn, actor: 'seller', jwt: c.sellerJwt);
    await tryFn(fn, actor: 'buyer2', jwt: c.buyer2Jwt);
  }

  // L2 vector via L1: p_now futuro (disparo cedo) — JWT.
  final pNow = isoFuture(const Duration(days: 400));
  for (final actor in [
    ['anon', null],
    ['buyer', c.buyerJwt],
    ['buyer2', c.buyer2Jwt],
  ]) {
    final hit = await c.rpc(
      'batata_generate_auto_feedback',
      {'p_now': pNow},
      jwt: actor[1] as String?,
    );
    c.note('p1.p_now.${actor[0]}', 'auto_feedback p_now+400d', hit.brief,
        lens: 'L2');
    if (hit.ok) {
      c.hold(
        id: 'RTL-L2-pnow-${actor[0]}',
        lens: 'L2',
        severity: 'P0',
        title: 'JWT dispara auto-feedback com p_now futuro (salta 48h)',
        actor: actor[0] as String,
        pre: 'rpc batata_generate_auto_feedback(p_now)',
        repro: 'POST rpc/batata_generate_auto_feedback p_now=+400d',
        expected: 'EXECUTE recusado',
        obtained: hit.brief,
        evidence: {'p_now': pNow, 'result': hit.snippet},
      );
    }
  }

  // GET rpc (PostgREST GET em VOLATILE)
  final getAf = await c.req(
    'GET',
    '/rest/v1/rpc/batata_generate_auto_feedback',
    jwt: c.buyerJwt,
  );
  c.note('p1.get.auto_feedback', 'GET rpc auto_feedback JWT', getAf.brief,
      lens: 'L1');
  if (getAf.ok) {
    c.hold(
      id: 'RTL-L1-get-auto-feedback',
      lens: 'L1',
      severity: 'P0',
      title: 'GET rpc auto_feedback com JWT',
      actor: 'buyer JWT',
      pre: 'rpc VOLATILE',
      repro: 'GET /rest/v1/rpc/batata_generate_auto_feedback',
      expected: '405/403',
      obtained: getAf.brief,
    );
  }

  // Edge cron: livekit-egress-cleanup
  final cleanupJwt = await c.edge('livekit-egress-cleanup', {}, jwt: c.buyerJwt);
  c.note('p1.edge.cleanup.jwt', 'egress cleanup JWT', cleanupJwt.brief,
      lens: 'L1');
  if (cleanupJwt.ok &&
      (cleanupJwt.map?['ok'] == true ||
          cleanupJwt.body.toLowerCase().contains('stopped') ||
          cleanupJwt.body.toLowerCase().contains('deleted'))) {
    c.hold(
      id: 'RTL-L1-egress-cleanup-jwt',
      lens: 'L1',
      severity: 'P1',
      title: 'JWT dispara livekit-egress-cleanup',
      actor: 'buyer JWT',
      pre: 'edge function de cron',
      repro: 'POST /functions/v1/livekit-egress-cleanup Bearer JWT',
      expected: '401 Unauthorized',
      obtained: cleanupJwt.brief,
    );
  }

  final cleanupEmpty = await c.edge(
    'livekit-egress-cleanup',
    {},
    extra: {'x-cleanup-secret': ''},
  );
  c.note('p1.edge.cleanup.empty', 'cleanup secret vazio', cleanupEmpty.brief,
      lens: 'L1');
  final cleanupGuess = await c.edge(
    'livekit-egress-cleanup',
    {},
    extra: {'x-cleanup-secret': 'x'},
  );
  c.note('p1.edge.cleanup.guess', 'cleanup secret x', cleanupGuess.brief,
      lens: 'L1');

  // Schema cron / vault via REST (se PostgREST expor)
  for (final path in [
    'cron.job',
    'cron.job_run_details',
    'vault.decrypted_secrets',
    'vault.secrets',
  ]) {
    final hit = await c.req('GET', '/rest/v1/$path?select=*&limit=1',
        jwt: c.buyerJwt);
    c.note('p1.schema.$path', 'JWT lê $path', hit.brief, lens: 'L1');
    if (hit.ok && hit.list.isNotEmpty) {
      c.hold(
        id: 'RTL-L1-schema-$path',
        lens: 'L1',
        severity: 'P0',
        title: 'JWT lê $path',
        actor: 'buyer JWT',
        pre: 'schema interno',
        repro: 'GET /rest/v1/$path',
        expected: '404/403',
        obtained: hit.brief,
      );
    }
  }

  await dumpJson('${outDir()}/pass1.json', {
    'stamp': stamp,
    'notes': c.notes,
    'findings': c.findings,
    'cron_from_spec': cronFromSpec,
    'rpc_count': rpcNames.length,
  });
  stdout.writeln(
      'PASS1 done findings=${c.findings.length} rpc=${rpcNames.length}');
}
