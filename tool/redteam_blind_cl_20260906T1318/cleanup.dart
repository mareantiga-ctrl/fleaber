/// End leftover RTCL lives. No fixes.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  final h = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active&limit=120',
    service: true,
  );
  stdout.writeln('found ${h.brief}');
  for (final row in h.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.endLive(id);
      stdout.writeln('ended $id ${row['title']}');
    }
  }

  final helpers = await c.rest(
    'GET',
    'seller_helpers?display_name=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,display_name,active',
    service: true,
  );
  stdout.writeln('helpers ${helpers.brief}');
  for (final row in helpers.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.rest(
        'PATCH',
        'seller_helpers?id=eq.$id',
        service: true,
        body: {'active': false, 'invitation_status': 'rejected'},
        prefer: 'return=minimal',
      );
      stdout.writeln('helper deactivated $id ${row['display_name']}');
    }
  }
}
