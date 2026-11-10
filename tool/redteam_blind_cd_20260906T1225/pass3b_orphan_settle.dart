/// settle GET nas 2 cs_ do overlap + CPI na linha F órfã.
import 'dart:io';

import '_rtcd.dart';

Future<void> main() async {
  final c = Rtcd.fromEnv(loadEnv());
  await c.loginActors();
  const s0 = 'cs_test_a1MsLGzGDQQ6UvGwRPKHzYALnRdYazfUYp5B8k047JCs8CF5kQQgBOgwrC';
  const s1 = 'cs_test_a1yfC9pveappSm4k1Uza1MByuqGLMQhCDPmSMEeS9dYZLrUrY2FaxlXtWV';
  final g0 = await c.settleGet(s0);
  final g1 = await c.settleGet(s1);
  c.note('P3.settle.s0', 'GET settle cs0 ABCDE', g0.brief, lens: 'CD8', well: 'CD-A');
  c.note('P3.settle.s1', 'GET settle cs1 DEF órfão', g1.brief, lens: 'CD8', well: 'CD-A');

  const f = '87628b9a-6698-4947-90f9-2bbe8559ec04';
  final rowF = await c.orderRow(f);
  c.note('P3.F.row', 'order F sid', rowF, lens: 'CD2', well: 'CD-A');
  final pid = rowF?['product_id']?.toString();
  if (pid != null) {
    final ck = await c.checkout(orderId: f, productId: pid, amount: 1);
    c.note('P3.F.cpi', 'CPI na linha F (sid era null)', {
      'ck': ck.brief,
      'sid': ck.sessionId,
      'after': (await c.orderRow(f))?['stripe_checkout_session_id'],
    }, lens: 'CD2', well: 'CD-A');
  }

  await c.dumpAll('pass3b_orphan_settle.json');
}
