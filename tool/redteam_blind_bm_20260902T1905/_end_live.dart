import 'dart:io';

import '_rtbm.dart';

Future<void> main() async {
  final c = Rtbm.fromEnv(loadEnv());
  final h = await c.rest(
    'PATCH',
    'lives?id=eq.897f51cc-4da7-4455-81cd-ee6b69258850',
    service: true,
    body: {'status': 'ended', 'is_active': false},
  );
  stdout.writeln('end-live ${h.brief}');
}
