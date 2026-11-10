// ignore_for_file: avoid_print
/// APP-143/144/145 — preparar .maestro/.env para testes de cancelamento
///   dart run tool/app143_prepare.dart
library;

import 'dart:io';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();

  final sellerEmail   = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass    = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerEmail    = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass     = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final deviceSeller  = env['MAESTRO_DEVICE_SELLER'] ?? 'a698f0de';
  final deviceBuyer   = env['MAESTRO_DEVICE_BUYER']  ?? 'd6pnqgz5jvnnbm9x';

  String enc(String v) => Uri.encodeComponent(v);

  final lines = <String>[
    'MAESTRO_APP_ID=pt.fleaber.app',
    'MAESTRO_SELLER_EMAIL=$sellerEmail',
    'MAESTRO_SELLER_PASSWORD=$sellerPass',
    'MAESTRO_SELLER_EMAIL_URL=${enc(sellerEmail)}',
    'MAESTRO_BUYER_EMAIL=$buyerEmail',
    'MAESTRO_BUYER_PASSWORD=$buyerPass',
    'MAESTRO_BUYER_EMAIL_URL=${enc(buyerEmail)}',
    'MAESTRO_DEEP_LINK_BASE=fleaber://fleaber.com',
    'MAESTRO_DEVICE_SELLER=$deviceSeller',
    'MAESTRO_DEVICE_BUYER=$deviceBuyer',
    'MAESTRO_DEVICE_DEFAULT=$deviceSeller',
    'MAESTRO_DRIVER_PORT_SELLER=7010',
    'MAESTRO_DRIVER_PORT_BUYER=7011',
  ];

  final dotEnv = File('.maestro/.env');
  dotEnv.parent.createSync(recursive: true);
  dotEnv.writeAsStringSync('${lines.join('\n')}\n');
  print('.maestro/.env escrito com ${lines.length} linhas');
}
