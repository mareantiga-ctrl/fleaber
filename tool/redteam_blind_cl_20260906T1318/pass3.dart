/// REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1 — pass3 Mux/realtime D1–D3 + sibling cols.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);

  const fakePlayback = 'RTCLPLAY1318fake0001';
  const fakeVod = 'RTCLVOD1318fake0001xxxx';
  const fakeAsset = 'RTCLASSET1318fake0001x';
  const fakeKey = 'RTCLSTREAM1318secretxx';
  const fakeRoom = 'RTCLROOM1318livekit';
  const fakePlaybackCol = 'RTCLPB1318plain0001';
  const fakeEgress = 'RTCLEGRESS1318fake001';
  const fakeMuxLive = 'RTCLMUXLIVE1318fake01';

  final liveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux unpub',
    extra: {
      'mux_playback_id': fakePlayback,
      'mux_vod_playback_id': fakeVod,
      'mux_asset_id': fakeAsset,
      'playback_id': fakePlaybackCol,
      'livekit_room_name': fakeRoom,
    },
  );
  if (liveUnpub != null) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$liveUnpub',
      service: true,
      body: {
        'mux_stream_key': fakeKey,
        'stream_key': fakeKey,
        'mux_live_id': fakeMuxLive,
        'livekit_egress_id': fakeEgress,
      },
      prefer: 'return=minimal',
    );
  }

  // Discover lives columns via OpenAPI.
  final oa = await c.req('GET', '/rest/v1/', jwt: c.buyerJwt);
  final oaText = oa.body;
  final siblingGuess = <String>[
    'playback_id',
    'mux_playback_id',
    'mux_vod_playback_id',
    'mux_asset_id',
    'mux_stream_key',
    'stream_key',
    'mux_live_id',
    'livekit_room_name',
    'livekit_egress_id',
    'livekit_url',
    'livekit_token',
    'rtmp_url',
    'srt_url',
    'hls_url',
    'ingest_url',
    'broadcast_id',
    'publish_backend',
  ];
  final oaHits = siblingGuess.where((col) => oaText.contains('"$col"')).toList();
  c.note('p3.openapi.lives.cols', 'OpenAPI sibling hits', oaHits, lens: 'CL7');

  Future<void> probeCol({
    required String id,
    required String? liveId,
    required String? jwt,
    required String actor,
    required String col,
    bool residualCdci = false,
    bool expectedReadable = false,
  }) async {
    if (liveId == null) return;
    final h = await c.rest(
      'GET',
      'lives?id=eq.$liveId&select=id,$col',
      jwt: jwt,
    );
    final val = h.map?[col]?.toString();
    final leaked = h.ok && val != null && val.isNotEmpty;
    if (leaked) {
      if (expectedReadable) {
        c.block(id, 'CL7', '$actor lê $col (coluna concedida, não contar)',
            h.brief);
        c.probe(
          id: id,
          lens: 'CL7',
          payload: 'GET lives select=$col unpublished ($actor)',
          http: h.brief,
          verdict: 'HOLD_GRANTED',
          extra: {'val': val},
        );
        return;
      }
      if (residualCdci) {
        c.hold(
          id: id,
          lens: 'CL7',
          severity: 'P2',
          title: 'REGRESSÃO CDCI: $actor lê $col',
          actor: actor,
          pre: 'CDCI revoke playback_id / livekit_room_name',
          repro: 'GET lives?select=$col unpublished',
          expected: '403 coluna / vazio',
          obtained: h.brief,
        );
        c.probe(
          id: id,
          lens: 'CL7',
          payload: 'GET lives select=$col unpublished ($actor)',
          http: h.brief,
          verdict: 'FAIL_REGRESSION',
          extra: {'val': val},
        );
      } else {
        c.hold(
          id: id,
          lens: 'CL7',
          severity: col.contains('key') || col.contains('token') ? 'P1' : 'P2',
          title: '$actor lê $col de live alheia unpublished',
          actor: actor,
          pre: 'CDCI revoke playback_id; irmãs novas?',
          repro: 'GET lives?id=eq.$liveId&select=$col',
          expected: 'vazio / 403 coluna',
          obtained: h.brief,
        );
        c.probe(
          id: id,
          lens: 'CL7',
          payload: 'GET lives select=$col unpublished ($actor)',
          http: h.brief,
          verdict: 'FAIL',
          extra: {'val': val},
        );
      }
    } else {
      c.block(id, 'CL7', '$actor não lê $col', h.brief);
      c.probe(
        id: id,
        lens: 'CL7',
        payload: 'GET lives select=$col unpublished ($actor)',
        http: h.brief,
        verdict: residualCdci ? 'HOLD' : 'HOLD',
      );
    }
  }

  // D3 — sibling columns (residual CDCI playback_id / livekit counted HOLD).
  await probeCol(
    id: 'p3.D3.buyer.playback_id',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'playback_id',
    residualCdci: true,
  );
  await probeCol(
    id: 'p3.D3.buyer.livekit_room_name',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'livekit_room_name',
    residualCdci: true,
  );

  await probeCol(
    id: 'p3.D3.buyer.mux_live_id',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_live_id',
  );
  await probeCol(
    id: 'p3.D3.buyer.livekit_egress_id',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'livekit_egress_id',
  );
  for (final col in [
    'mux_stream_key',
    'stream_key',
    'mux_playback_id',
    'mux_vod_playback_id',
    'mux_asset_id',
  ]) {
    await probeCol(
      id: 'p3.D3.buyer.$col',
      liveId: liveUnpub,
      jwt: c.buyerJwt,
      actor: 'buyer JWT',
      col: col,
      residualCdci: true,
    );
  }
  await probeCol(
    id: 'p3.D3.buyer.publish_backend',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'publish_backend',
    expectedReadable: true,
  );

  // Wildcard SELECT * — any new keys?
  final wild = await c.rest(
    'GET',
    'lives?id=eq.$liveUnpub&select=*',
    jwt: c.buyerJwt,
  );
  final wildMap = wild.map ?? {};
  final leakedKeys = wildMap.keys.where((k) {
    final v = '${wildMap[k]}';
    return v.contains('RTCL') ||
        k.toString().contains('stream_key') ||
        k.toString().contains('mux_') ||
        k.toString().contains('playback') ||
        k.toString().contains('livekit') ||
        k.toString().contains('egress');
  }).map((k) => '$k=${wildMap[k]}').toList();
  c.note('p3.D3.wildcard.keys', 'SELECT * keys', wildMap.keys.toList(),
      lens: 'CL7');
  if (leakedKeys.isNotEmpty) {
    c.hold(
      id: 'p3.D3.wildcard.leak',
      lens: 'CL7',
      severity: leakedKeys.any((s) => s.contains('key')) ? 'P1' : 'P2',
      title: 'SELECT * lives vaza playback/stream unpublished',
      actor: 'buyer JWT',
      pre: 'column revoke CDCI; wildcard irmãs?',
      repro: 'GET lives?select=*',
      expected: 'sem mux/stream/playback alheio',
      obtained: leakedKeys,
    );
    c.probe(
      id: 'p3.D3.wildcard.leak',
      lens: 'CL7',
      payload: 'GET lives select=* unpublished',
      http: wild.brief,
      verdict: 'FAIL',
      extra: leakedKeys,
    );
  } else {
    c.block('p3.D3.wildcard.leak', 'CL7', 'wildcard sem mux/stream',
        wildMap.keys.toList());
    c.probe(
      id: 'p3.D3.wildcard.leak',
      lens: 'CL7',
      payload: 'GET lives select=* unpublished',
      http: '${wild.status} keys=${wildMap.keys.length}',
      verdict: 'HOLD',
      extra: wildMap.keys.toList(),
    );
  }

  // D2 — resolve-mux unpublished (controlo).
  Future<void> resolveMux({
    required String id,
    required String? liveId,
    String? jwt,
    required String actor,
    bool expectDeny = true,
  }) async {
    if (liveId == null) return;
    final h = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveId},
      jwt: jwt,
    );
    final pb = h.map?['playback_id']?.toString() ?? '';
    final url = h.map?['playback_url']?.toString() ?? '';
    final leaked = h.ok && (pb.isNotEmpty || url.contains('mux.com'));
    if (leaked && expectDeny) {
      c.hold(
        id: id,
        lens: 'CL7',
        severity: 'P1',
        title: 'resolve-mux-playback entrega HLS a $actor',
        actor: actor,
        pre: 'live unpublished / não dono',
        repro: 'POST resolve-mux-playback live_id',
        expected: '404 live_not_public',
        obtained: h.brief,
      );
      c.probe(
        id: id,
        lens: 'CL7',
        payload: 'resolve-mux-playback unpublished ($actor)',
        http: h.brief,
        verdict: 'FAIL',
      );
    } else {
      c.block(id, 'CL7', 'resolve recusado/vazio ($actor)', h.brief);
      c.probe(
        id: id,
        lens: 'CL7',
        payload: 'resolve-mux-playback unpublished ($actor)',
        http: h.brief,
        verdict: expectDeny ? 'HOLD' : 'HOLD_OWNER',
      );
    }
  }

  await resolveMux(
    id: 'p3.D2.resolve.buyer.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
  );
  await resolveMux(
    id: 'p3.D2.resolve.anon.unpub',
    liveId: liveUnpub,
    jwt: null,
    actor: 'anon',
  );

  // D1 — realtime channel payload playback.
  Map<String, dynamic> rt = {
    'ok': false,
    'error': 'no live',
  };
  if (liveUnpub != null) {
    rt = await c.probeRealtimeLivesPlayback(
      liveId: liveUnpub,
      jwt: c.buyerJwt!,
    );
  }
  c.note('p3.D1.realtime.raw', 'realtime frames', rt, lens: 'CL7');
  final rtHits = (rt['hits'] as List?)?.cast<String>() ?? const [];
  final playbackHit = rtHits.any((h) =>
      h.contains('playback') ||
      h.contains('mux_') ||
      h.contains('livekit') ||
      h.contains('rtclpb') ||
      h.contains('rtclmux') ||
      h.contains('rtclroom'));
  final framesText = '${rt['frames']}'.toLowerCase();
  final payloadLeak = playbackHit ||
      framesText.contains('rtclpb') ||
      framesText.contains('rtclmux') ||
      framesText.contains('rtclroom') ||
      framesText.contains(fakePlaybackCol.toLowerCase()) ||
      framesText.contains(fakePlayback.toLowerCase());
  if (payloadLeak) {
    c.hold(
      id: 'p3.D1.realtime.playback',
      lens: 'CL7',
      severity: 'P2',
      title: 'Realtime postgres_changes vaza playback/mux/livekit',
      actor: 'buyer JWT websocket',
      pre: 'REST SELECT playback_id revogado CDCI; WAL/realtime irmão?',
      repro: 'ws realtime:public:lives filter id=eq.unpub + PATCH playback',
      expected: 'payload sem playback_id / mux_* / livekit_room_name',
      obtained: {
        'hits': rtHits,
        'n_frames': rt['n_frames'],
        'joinAck': rt['joinAck'],
      },
    );
    c.probe(
      id: 'p3.D1.realtime.playback',
      lens: 'CL7',
      payload: 'ws postgres_changes lives unpublished PATCH playback',
      http: 'ws frames=${rt['n_frames']} hits=$rtHits',
      verdict: 'FAIL',
      extra: rt,
    );
  } else {
    c.block('p3.D1.realtime.playback', 'CL7',
        'realtime sem playback no payload (HOLD)', {
      'ok': rt['ok'],
      'error': rt['error'],
      'n_frames': rt['n_frames'],
      'joinAck': rt['joinAck'],
      'hits': rtHits,
    });
    c.probe(
      id: 'p3.D1.realtime.playback',
      lens: 'CL7',
      payload: 'ws postgres_changes lives unpublished PATCH playback',
      http: 'ws frames=${rt['n_frames']} join=${rt['joinAck']} err=${rt['error']}',
      verdict: 'HOLD',
      extra: {
        'ok': rt['ok'],
        'n_frames': rt['n_frames'],
        'joinAck': rt['joinAck'],
      },
    );
  }

  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1',
    'prefix': prefix,
    'liveUnpub': liveUnpub,
    'openapi_hits': oaHits,
    'wildcard_keys': wildMap.keys.toList(),
    'realtime': rt,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass3 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'probes=${c.probes.length}');
}
