/// RED TEAM CEGO BI pass3 — FOMO + hub_lives_public no vendedor lab já publicado.
import 'dart:io';

import '_rtbi.dart';

Future<void> main() async {
  final c = Rtbi.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();

  final hubS1 = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.${c.sellerId}&select=id,handle',
  );
  c.note('p3.s1.hub', 'lab seller na vitrine', hubS1.map, lens: 'BI1');

  final vodId = '8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8';
  final livePb = 'Cap7U300PcqvBmbZj01cL92AT01k401ntf97eCUWynvj9Pc';

  final liveSched = await c.insertLive(
    seller: c.sellerId,
    status: 'scheduled',
    active: true,
    title: '$prefix P3 SCHED S1',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveAir = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    title: '$prefix P3 AIR S1',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveEnded = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    title: '$prefix P3 ENDED S1',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveDraft = await c.insertLive(
    seller: c.sellerId,
    status: 'draft',
    active: true,
    title: '$prefix P3 DRAFT S1',
    muxPlayback: livePb,
    muxVod: vodId,
  );

  final itemSched = liveSched == null
      ? null
      : await c.insertItem(liveId: liveSched, qty: 5);
  if (liveSched != null && itemSched != null) {
    await c.insertPendingRes(liveId: liveSched, liveItemId: itemSched);
  }
  final itemAir =
      liveAir == null ? null : await c.insertItem(liveId: liveAir, qty: 3);

  Future<HttpHit> v(String view, String? id) => c.rest(
        'GET',
        '$view?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id',
      );

  final pubSched = await v('hub_lives_public', liveSched);
  final pubAir = await v('hub_lives_public', liveAir);
  final pubEnded = await v('hub_lives_public', liveEnded);
  final pubDraft = await v('hub_lives_public', liveDraft);
  final discSched = await v('hub_lives_discovery_public', liveSched);
  final discAir = await v('hub_lives_discovery_public', liveAir);

  c.note('p3.pub.sched', 'public sched S1', pubSched.map, lens: 'BI1');
  c.note('p3.pub.air', 'public air S1', pubAir.map, lens: 'BI1');
  c.note('p3.pub.ended', 'public ended S1', pubEnded.map, lens: 'BI1');
  c.note('p3.pub.draft', 'public draft S1', pubDraft.map, lens: 'BI1');
  c.note('p3.disc.sched', 'disc sched S1', discSched.map, lens: 'BI7');
  c.note('p3.disc.air', 'disc air S1', discAir.map, lens: 'BI7');

  if (pubSched.map != null &&
      (pubSched.map?['mux_vod_playback_id'] == null ||
          '${pubSched.map?['mux_vod_playback_id']}'.isEmpty) &&
      discSched.map != null &&
      '${discSched.map?['mux_vod_playback_id']}'.isNotEmpty) {
    c.note('p3.split', 'public anula VOD; discovery não (S1 publicado)', {
      'pub': pubSched.map,
      'disc': discSched.map,
    }, lens: 'BI7');
  }

  final fomoSched =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveSched});
  final fomoAir =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveAir});
  final fomoEnded =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveEnded});
  final fomoDraft =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveDraft});
  c.note('p3.fomo.sched', 'FOMO sched S1', fomoSched.map, lens: 'BI1');
  c.note('p3.fomo.air', 'FOMO air S1', fomoAir.map, lens: 'BI1');
  c.note('p3.fomo.ended', 'FOMO ended S1', fomoEnded.map, lens: 'BI1');
  c.note('p3.fomo.draft', 'FOMO draft S1', fomoDraft.map, lens: 'BI1');

  if (fomoSched.map?['ok'] == true) {
    final items = fomoSched.map?['items'];
    var pending = 0;
    var avail = 0;
    if (items is List && items.isNotEmpty && items.first is Map) {
      final m = items.first as Map;
      pending = (m['pending_queue_count'] as num?)?.toInt() ?? 0;
      avail = (m['available_qty'] as num?)?.toInt() ?? 0;
    }
    c.hold(
      id: pending > 0 ? 'P2-BI1-fomo-scheduled-queue' : 'P3-BI1-fomo-scheduled-ok',
      lens: 'BI1',
      severity: pending > 0 ? 'P2' : 'P3',
      title: pending > 0
          ? 'FOMO scheduled publicado revela fila pending + itens'
          : 'FOMO scheduled publicado ok=true (sem fila nesta fixture)',
      actor: 'anon',
      pre: 'S1 hub_published; scheduled+active na hub_lives_public',
      repro: 'rpc batata_hub_live_fomo_snapshot',
      expected: 'live_not_public para scheduled (não no ar)',
      obtained: fomoSched.map,
    );
    c.note('p3.fomo.nums', 'pending=$pending avail=$avail', {
      'pending': pending,
      'avail': avail,
    }, lens: 'BI1');
  } else {
    c.block('p3.fomo.sched', 'BI1', 'FOMO scheduled recusado no S1 publicado',
        fomoSched);
  }

  final stockAnonSched = itemSched == null
      ? null
      : await c.rpc(
          'batata_live_item_stock', {'p_live_item_id': itemSched});
  final stockAnonAir = itemAir == null
      ? null
      : await c.rpc('batata_live_item_stock', {'p_live_item_id': itemAir});
  c.note('p3.stock.sched', 'stock anon sched', stockAnonSched, lens: 'BI1');
  c.note('p3.stock.air', 'stock anon air', stockAnonAir, lens: 'BI1');

  final itemsDiscSched = await c.rest(
    'GET',
    'hub_live_items_discovery_public?live_id=eq.$liveSched&select=id,title,price,ref_code',
  );
  final itemsPubSched = await c.rest(
    'GET',
    'hub_live_items_public?live_id=eq.$liveSched&select=id,title,price',
  );
  c.note('p3.items.disc.sched', 'items disc sched S1', itemsDiscSched,
      lens: 'BI1');
  c.note('p3.items.pub.sched', 'items pub sched S1', itemsPubSched, lens: 'BI1');

  await c.endLives();
  await c.dumpAll('pass3_findings.json');
  stdout.writeln('PASS3 findings=${c.findings.length}');
}
