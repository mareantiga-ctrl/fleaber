/// Dump C2 ACAO completo + confirmar lives ended + S1 published.
import 'dart:convert';
import 'dart:io';
import '_rtde.dart';

Future<void> main() async {
  final c = Rtde.fromEnv(loadEnv());
  await c.loginActors();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final airPub = ids['airPub'] as String;
  final airUnpub = ids['airUnpub'] as String;
  const muxCreated = '9fdd06e0-2cb5-4de6-a8c8-9693b7b5acaf';

  final origins = <String, String>{
    'ext': 'chrome-extension://abcdefghijklmnopqrstuvwxyz1234',
    'sub': 'https://evil.fleaber.pt',
    'null': 'null',
    'evil': 'https://evil.example',
    'file': 'file://',
    'ok': 'https://fleaber.pt',
  };
  final rows = <String, Map<String, String?>>{};
  for (final e in origins.entries) {
    final optMux = await c.edge(
      'create-mux-live',
      method: 'OPTIONS',
      extra: {
        'Origin': e.value,
        'Access-Control-Request-Method': 'POST',
      },
    );
    final optTip = await c.edge(
      'create-live-tip-checkout',
      method: 'OPTIONS',
      extra: {
        'Origin': e.value,
        'Access-Control-Request-Method': 'POST',
      },
    );
    rows[e.key] = {
      'origin': e.value,
      'opt_mux_acao': optMux.acao,
      'opt_tip_acao': optTip.acao,
      'opt_mux_status': '${optMux.status}',
    };
  }

  for (final id in [airPub, airUnpub, muxCreated]) {
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  await c.restoreSeller1Published();
  final lives = await c.rest(
    'GET',
    'lives?id=in.($airPub,$airUnpub,$muxCreated)&select=id,status,is_active,seller_id',
    service: true,
  );
  final s1p = await c.profile(s1);
  final out = {
    'cors': rows,
    'lives': lives.json,
    's1_hub': s1p?['hub_published'],
  };
  await dumpJson('${outDir()}/confirm_c2.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
