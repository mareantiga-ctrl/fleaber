/// End leftover RTX fixture lives. Staging only.
import '_rtx.dart';

Future<void> main() async {
  final c = Rtx.fromEnv(loadEnv());
  final lives = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('*$prefix*')}&select=id,status,is_active,title&limit=50',
    service: true,
  );
  c.note('cleanup.list', 'lives prefix', lives.list.map((e) => (e as Map)['id']).toList());
  for (final row in lives.list) {
    if (row is! Map) continue;
    final id = row['id']?.toString();
    if (id == null) continue;
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
}
