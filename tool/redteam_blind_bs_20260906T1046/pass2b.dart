/// GET loot check for persisted hostile proof_urls. No fixes.
import '_rtbs.dart';

Future<void> main() async {
  final c = Rtbs.fromEnv(loadEnv());
  await c.loginActors();
  const oidA = '463c3d0b-e1bf-4dbd-8137-8ee4fddef5bd';
  const oidB = 'dd7b0688-bbce-4423-ac3c-edf852130079';
  final paths = <String, String>{
    'c0ae-auth':
        '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/${c.buyerId}/$oidB/rtbs_b.png',
    'c0ae-abs':
        '$stagingHost/storage/v1/object/fleaber_private/order_proofs/${c.buyerId}/$oidA/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/${c.buyerId}/$oidB/rtbs_b.png',
    'honest-b':
        '/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.buyerId}/$oidB/rtbs_b.png',
    'msg1460': 'n/a',
  };
  final msg = await c.msgRow('1460');
  c.note('msg1460', 'stored text', msg?['text'], lens: 'BS4');
  for (final e in paths.entries) {
    if (e.key == 'msg1460') continue;
    final h = await c.req('GET', e.value, jwt: c.buyerJwt);
    c.note(e.key, 'GET', '${h.status} len=${h.body.length} ${h.snippet}',
        lens: 'BS4');
  }
  await dumpJson('${outDir()}/pass2b.json', {
    'notes': c.notes,
  });
}
