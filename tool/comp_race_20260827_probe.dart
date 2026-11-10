// ignore_for_file: avoid_print
/// COMP_RACE_20260827 — probe JWT auxiliar.
/// A bateria de composições/races corre em tool/comp_race_20260827_races.py.
/// Este ficheiro só confirma identidades e grants JWT (não sobrescreve JSON do Python).
import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: não é staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyer = await client.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final seller = await client.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  stdout.writeln(jsonEncode({
    'probe': 'COMP_RACE_20260827',
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'buyer_jwt': buyer.isNotEmpty,
    'seller_jwt': seller.isNotEmpty,
    'note': 'Races: python tool/comp_race_20260827_races.py',
  }));
}
