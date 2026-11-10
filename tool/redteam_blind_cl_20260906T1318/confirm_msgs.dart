/// Confirm FOMO rows: service vs buyer vs seller.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  const liveId = '3b8096de-c154-4533-ad17-6b07f5100390';
  for (final who in ['svc', 'seller', 'buyer']) {
    final jwt = who == 'seller'
        ? c.sellerJwt
        : who == 'buyer'
            ? c.buyerJwt
            : null;
    final h = await c.rest(
      'GET',
      'live_messages?live_id=eq.$liveId&select=id,kind,body,sender_label,user_id&order=created_at.desc&limit=40',
      jwt: jwt,
      service: who == 'svc',
    );
    stdout.writeln('$who status=${h.status} n=${h.list.length} ${h.brief}');
  }
}
