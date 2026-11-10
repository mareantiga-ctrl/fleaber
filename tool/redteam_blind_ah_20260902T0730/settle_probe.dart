import 'dart:io';

import '_rtah.dart';

Future<void> main() async {
  final c = Rtah.fromEnv(loadEnv());
  const s1 =
      'cs_test_a1mMqkh3eWr0dNRkNq7aDeqtQ7jT7pRIAdlG1olC8yu1rjmv2a85wJ56T7';
  const sRace1 =
      'cs_test_a1lpfOLQBeyrf8SiGGooIUEig9en38YwceR5pAmX4d7AGNok3xL4HY8tmH';
  final a = await c.settleGet(s1);
  final b = await c.settleGet(sRace1);
  stdout.writeln('SETTLE_ORPHAN_S1 ${a.status} ${clip(a.body, 220)}');
  stdout.writeln('SETTLE_RACE_S1 ${b.status} ${clip(b.body, 220)}');
  await dumpJson('${outDir()}/pass3_settle.json', {
    'orphan_s1': a.brief,
    'race_s1': b.brief,
  });
}
