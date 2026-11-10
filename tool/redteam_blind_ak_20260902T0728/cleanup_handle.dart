import 'dart:io';

import '_rtak.dart';

/// Fixture cleanup only — restore QA seller handle. No product fix.
void main() async {
  final c = Rtak.fromEnv(loadEnv());
  final h = await c.rest(
    'PATCH',
    'profiles?id=eq.${envRequire(c.env, 'LIVE_OPS_TEST_SELLER_ID')}',
    service: true,
    body: {
      'handle': 'fleahub-demo-ux',
      'hub_published': true,
    },
  );
  stdout.writeln('restore seller handle ${h.brief}');
  final p = await c.rest(
    'GET',
    'profiles?id=eq.${envRequire(c.env, 'LIVE_OPS_TEST_SELLER_ID')}&select=id,handle,hub_published',
    service: true,
  );
  stdout.writeln('now ${p.brief}');
}
