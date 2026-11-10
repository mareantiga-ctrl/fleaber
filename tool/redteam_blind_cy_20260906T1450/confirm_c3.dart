/// C3 replay: resolve-mux unpublished live ainda activa (não ended).
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  final s2 = c.seller2Id!;
  await c.setHub(s2, false);
  final live = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: 'rtcyPbC3replay1450',
    muxLiveId: 'rtcyMuxC3replay',
    title: '$prefix c3-replay',
  );
  final rAnon = await c.edge('resolve-mux-playback', body: {'live_id': live});
  final rB1 = await c.edge(
    'resolve-mux-playback',
    jwt: c.buyerJwt,
    body: {'live_id': live},
  );
  final rOwn = await c.edge(
    'resolve-mux-playback',
    jwt: c.seller2Jwt,
    body: {'live_id': live},
  );
  await c.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  final s1 = await c.profile(c.sellerId!);
  final out = {
    'live': live,
    'anon': rAnon.brief,
    'b1': rB1.brief,
    'owner': rOwn.brief,
    's1_hub': s1?['hub_published'],
  };
  await dumpJson('${outDir()}/confirm_c3.json', out);
  stdout.writeln(out);
}
