import '_rtbu.dart';

Future<void> main() async {
  final c = Rtbu.fromEnv(loadEnv());
  final h = await c.rest(
    'GET',
    'lives?title=ilike.*RTBU-20260906T1046*&select=id,status,is_active,title',
    service: true,
  );
  print(h.brief);
  for (final row in h.list) {
    if (row is! Map) continue;
    final id = row['id'];
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
    print('ended $id ${row['title']}');
  }
}
