/// Confirm lives RLS + hub messages for FOMO live.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  const liveId = '3b8096de-c154-4533-ad17-6b07f5100390';

  final prof = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,hub_published,handle,is_live',
    service: true,
  );
  stdout.writeln('seller profile ${prof.brief}');

  final liveSvc = await c.rest(
    'GET',
    'lives?id=eq.$liveId&select=id,status,is_active,seller_id,title',
    service: true,
  );
  stdout.writeln('live svc ${liveSvc.brief}');

  final liveB = await c.rest(
    'GET',
    'lives?id=eq.$liveId&select=id,status,is_active,seller_id,title',
    jwt: c.buyerJwt,
  );
  stdout.writeln('live buyer ${liveB.status} ${liveB.brief}');

  final liveBstar = await c.rest(
    'GET',
    'lives?id=eq.$liveId&select=id,title,status,is_active,seller_id,created_at,viewer_count',
    jwt: c.buyerJwt,
  );
  stdout.writeln('live buyer safe cols ${liveBstar.status} ${liveBstar.brief}');

  final hub = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId&select=id,kind,body,sender_label&limit=30',
    jwt: c.buyerJwt,
  );
  stdout.writeln('hub msgs buyer n=${hub.list.length} ${hub.brief}');

  final hubAnon = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId&select=id,kind,body,sender_label&limit=30',
  );
  stdout.writeln('hub msgs anon n=${hubAnon.list.length} ${hubAnon.brief}');

  final chatB = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&kind=eq.chat&select=id,kind,body&limit=5',
    jwt: c.buyerJwt,
  );
  stdout.writeln('buyer chat kind ${chatB.status} n=${chatB.list.length} ${chatB.brief}');

  final allB = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&select=id,kind,body,channel&limit=5',
    jwt: c.buyerJwt,
  );
  stdout.writeln('buyer all msgs ${allB.status} n=${allB.list.length} ${allB.brief}');
}
