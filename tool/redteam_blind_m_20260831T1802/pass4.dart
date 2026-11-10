import 'dart:io';

import '_rtm.dart';

/// Pass 4 — classify M2-005 (log vs Stripe metadata) + Hub vs resolve without live.
void main() async {
  final c = Rtm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  final s2 = c.seller2Id!;
  final out = <String, Object?>{'pass': 4};

  final prof = await c.rest(
    'GET',
    'profiles?id=eq.$s2&select=id,handle,full_name,hub_published,is_live',
    service: true,
  );
  final handle = prof.map?['handle']?.toString();
  final name = prof.map?['full_name']?.toString() ?? '';
  final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  await c.rest(
    'PATCH',
    'lives?seller_id=eq.$s2',
    service: true,
    body: {'is_active': false, 'status': 'ended'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'profiles?id=eq.$s2',
    service: true,
    body: {'is_live': false, 'hub_published': false},
    prefer: 'return=minimal',
  );

  final disc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,hub_published,is_live',
  );
  final hub = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.$s2&select=id,handle',
  );
  final rhHandle = handle == null || handle.isEmpty
      ? null
      : await c.rpc('batata_resolve_handle', {'p_handle': handle});
  final rhSlug =
      await c.rpc('batata_resolve_handle', {'p_handle': slug});

  c.note('p4.m1.offline', 'unpublished + not live', {
    'handle': handle,
    'slug': slug,
    'disc': disc.snippet,
    'hub': hub.snippet,
    'rhHandle': rhHandle?.snippet,
    'rhSlug': rhSlug.snippet,
  }, lens: 'M1');
  out['offline'] = {
    'handle': handle,
    'full_name': name,
    'slug': slug,
    'hub_published': prof.map?['hub_published'],
    'disc_n': disc.list.length,
    'hub_n': hub.list.length,
    'rhHandle': rhHandle?.map,
    'rhSlug': rhSlug.map,
  };

  if (disc.list.isEmpty &&
      hub.list.isEmpty &&
      rhSlug.map?['found'] == true &&
      rhSlug.map?['profile_id']?.toString() == s2) {
    c.hold(
      id: 'RTM-M1-015',
      lens: 'M1',
      severity: 'P1',
      title: 'resolve_handle enumera UUID com vitrine OFF e sem directo (só slug do nome)',
      actor: 'anon',
      pre: 'hub_published=false is_live=false discovery vazia',
      repro: 'POST rpc/batata_resolve_handle p_handle=$slug',
      expected: '404 — perfil invisível em todas as superfícies Hub',
      obtained: rhSlug.snippet,
    );
  }

  // M2-005 class: session_created detail keys vs request
  final ev = await c.rest(
    'GET',
    'stripe_checkout_events?event=eq.tip_checkout_session_created&select=event,session_id,detail&order=created_at.desc&limit=2',
    service: true,
  );
  out['session_created_has_origin'] =
      ev.body.contains('web_return_origin') || ev.body.contains('attacker');
  c.note('p4.m2.session_created', 'created events origin?', {
    'has_origin_field': out['session_created_has_origin'],
    'snip': ev.snippet,
  }, lens: 'M2');

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('${repoRoot()}/tool/redteam_blind_m_$stamp/pass4.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
}
