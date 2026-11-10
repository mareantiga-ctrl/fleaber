import 'dart:convert';
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = await c.profile(ids['s1'] as String);
  final s2 = await c.profile(ids['s2'] as String);
  stdout.writeln('S1 hub_published=${s1?['hub_published']} handle=${s1?['handle']} is_live=${s1?['is_live']}');
  stdout.writeln('S2 hub_published=${s2?['hub_published']} handle=${s2?['handle']} is_live=${s2?['is_live']} type=${s2?['user_type']}');
  if (s1?['hub_published'] != true) {
    await c.rest('PATCH', 'profiles?id=eq.${ids['s1']}', service: true, body: {
      'hub_published': true,
      'is_live': false,
    }, prefer: 'return=minimal');
    stdout.writeln('RESTORED S1 hub_published=true');
  }
}
