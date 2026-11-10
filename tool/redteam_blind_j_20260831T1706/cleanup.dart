/// Cleanup RTJ fixtures. Staging only. No production. No feature changes.
import 'dart:io';

import '_rtj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtj.fromEnv(env);

  const chatId = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  const pendingOid = '47329115-13fb-40e1-96eb-fe7f0c921250';
  const reviewId = '5ef340a6-82d1-4ee7-8224-129c0a8f50a6';
  const favId = '7fc3e729-f48a-4312-af1d-33aeaf6a59e1';
  const followId = '81dab6c0-9e66-434d-9cc8-47f16307d39f';
  const b2 = 'f8859e23-504b-4c85-8a51-aeb04a9e95a0';

  final msgs = await c.rest(
    'DELETE',
    'chat_messages?chat_id=eq.$chatId&text=like.*RTJ-20260831T1706*',
    service: true,
  );
  c.note('del.chat_like', {'http': msgs.status, 'body': clip(msgs.body, 120)});

  for (final id in [
    858, 860, 861, 864, 866, 868, 869, 870, 871, 872, 873, 874, 875, 876
  ]) {
    final d = await c.rest('DELETE', 'chat_messages?id=eq.$id', service: true);
    c.note('del.msg.$id', d.status);
  }

  final ord = await c.rest(
    'PATCH',
    'orders?id=eq.$pendingOid',
    service: true,
    body: {'status': 'cancelado'},
  );
  c.note('cancel.pending', {'http': ord.status, 'status': ord.map?['status']});

  final rev = await c.rest('DELETE', 'reviews?id=eq.$reviewId', service: true);
  c.note('del.review', rev.status);

  final fav = await c.rest('DELETE', 'favorites?id=eq.$favId', service: true);
  c.note('del.fav', fav.status);

  final fol = await c.rest('DELETE', 'follows?id=eq.$followId', service: true);
  c.note('del.follow', fol.status);

  final up = await c.req(
    'DELETE',
    '/storage/v1/object/fleaber_private/chat_uploads/$b2/RTJ-20260831T1706-own.json',
    service: true,
  );
  c.note('del.upload', {'http': up.status, 'body': up.snippet});

  await dumpJson('${Directory.current.path}/out/cleanup.json', {
    'prefix': prefix,
    'notes': c.notes,
  });
  stdout.writeln('cleanup done ${c.notes}');
}
