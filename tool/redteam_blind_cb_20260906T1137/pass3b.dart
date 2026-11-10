import '_rtcb.dart';

/// Pass 3b — grego ο/ρ isolados (prefixos únicos; mesma classe que α).
void main() async {
  final c = Rtcb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureWalletBalance(c.sellerId!, 10);

  Future<void> pair(String id, String a, String b) async {
    final ev = await c.pairPayout(id, a, b);
    final n = (ev['new_transfer_count'] as int?) ?? 0;
    if (n >= 2) {
      c.hold(
        id: id,
        lens: 'CB4',
        severity: 'P2',
        title: '$id 2 Transfers (mesma classe α — não contar extra)',
        actor: 'seller JWT',
        pre: 'strip non-ASCII ≠ confusable fold',
        repro: '$a vs $b',
        expected: '2 Transfers se substituição lookalike (classe CB-P2-GREEK)',
        obtained: ev,
        count: false,
      );
    } else {
      c.block(id, 'CB4', '$id não 2 Transfers', ev);
    }
  }

  await pair('CB-P2-GREEK-OMICRON-ISO', 'rtcbOMICo99x', 'rtcbOMIC\u03BF99x');
  await pair('CB-P2-GREEK-RHO-ISO', 'rtcbRHOp99xx', 'rtcbRHO\u03C199xx');

  await c.dumpAll('pass3b.json');
}
