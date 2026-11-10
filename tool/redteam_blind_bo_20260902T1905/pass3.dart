/// BO pass 3 — storage jpeg + confirmar anon CDN sem JWT.
import 'dart:convert';
import 'dart:io';

import '_rtbo.dart';

Future<void> main() async {
  final c = Rtbo.fromEnv(loadEnv());
  try {
    await c.loginActors();
    await c.ensureSeller2Unpublished();
    await c.pickPlantedPlayback();
    final plant = c.plantedPlaybackId!;

    final liveEndedUnpub = await c.insertLive(
      seller: c.seller2Id,
      status: 'ended',
      active: false,
      title: '$prefix-p3-unpub',
      muxVodPlaybackId: plant,
      muxPlaybackId: 'play-p3-unpub',
    );

    final anon = await c.rest(
      'GET',
      'lives?id=eq.$liveEndedUnpub&select=id,status,mux_vod_playback_id',
    );
    c.note('p3.anon.lives', 'anon safe-cols ended_unpub', anon, lens: 'BO6');
    final vod = '${anon.map?['mux_vod_playback_id'] ?? ''}'.trim();
    HttpHit? cdn;
    if (vod.isNotEmpty) {
      cdn = await c.muxCdn(vod);
      c.note('p3.anon.cdn', 'anon→CDN HLS', cdn, lens: 'BO7');
    }
    if (anon.ok && vod.isNotEmpty && cdn != null && cdn.body.contains('#EXTM3U')) {
      c.hold(
        id: 'p3.anon.vod.cdn',
        lens: 'BO7',
        severity: 'P2',
        title: 'anon (sem JWT) lê VOD de live ended unpublished e a CDN Mux serve HLS',
        actor: 'anon',
        pre: 'GRANT select (mux_vod_playback_id) on lives to anon; RLS status=ended',
        repro:
            'GET /rest/v1/lives?id=eq.$liveEndedUnpub&select=id,status,mux_vod_playback_id ; GET https://stream.mux.com/{id}.m3u8',
        expected: '401/[] como Hub views',
        obtained: '${anon.brief} cdn=${cdn.status} ${clip(cdn.body, 80)}',
      );
    } else {
      c.block('p3.anon.vod.cdn', 'BO7', 'anon sem HLS', {
        'anon': anon.brief,
        'cdn': cdn?.brief,
      });
    }

    final jpeg = base64.decode(
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVhZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oADAMBAAIQAxAAAAH8D/9k=',
    );
    final up = await c.req(
      'POST',
      '/storage/v1/object/fleaber_private/$prefix-p3.jpg',
      bodyBytes: jpeg,
      extra: {'Content-Type': 'image/jpeg', 'x-upsert': 'true'},
    );
    c.note('p3.storage.jpeg', 'anon JPEG private', up, lens: 'BO6');
    await c.expectDenied(
      id: 'p3.storage.jpeg',
      lens: 'BO6',
      title: 'anon upload JPEG fleaber_private',
      hit: up,
      actor: 'anon',
      pre: 'mime jpeg permitido',
      repro: 'POST storage/v1/object/fleaber_private/*.jpg',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok,
    );

    final svcBuckets = await c.req('GET', '/storage/v1/bucket', service: true);
    c.note('p3.buckets.svc', 'service buckets', 
        svcBuckets.list.map((b) => b is Map ? '${b['id']}:${b['public']}' : b).toList(),
        lens: 'BO6');
    for (final b in svcBuckets.list.take(10)) {
      if (b is! Map) continue;
      final id = '${b['id']}';
      final listing = await c.req(
        'POST',
        '/storage/v1/object/list/$id',
        body: {'prefix': '', 'limit': 3},
      );
      c.note('p3.list.$id', 'anon list', listing, lens: 'BO6');
      if (listing.ok && listing.list.isNotEmpty && b['public'] != true) {
        c.hold(
          id: 'p3.list.private',
          lens: 'BO6',
          severity: 'P1',
          title: 'anon lista bucket privado $id',
          actor: 'anon',
          pre: 'public=${b['public']}',
          repro: 'POST storage/v1/object/list/$id',
          expected: '403',
          obtained: listing.brief,
        );
      } else {
        c.block('p3.list.$id', 'BO6', 'list $id', listing);
      }
    }
  } finally {
    await c.endAllLives();
    await c.dumpAll('pass3.json');
    stdout.writeln(
        'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length}');
  }
}
