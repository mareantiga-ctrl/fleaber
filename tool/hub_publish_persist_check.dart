// ignore_for_file: avoid_print
/// APP-308 — ciclo publicado → oculto → publicado na BD (`profiles.hub_published`).
/// Restaura sempre o estado inicial. Não deixa o FleaHub oculto.
///
///   dart run tool/hub_publish_persist_check.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

Future<bool> _published(LiveOpsStagingClient client, String sellerId) async {
  final rows = await client.select(
    'profiles',
    filter: 'id=eq.$sellerId',
    limit: 1,
  );
  if (rows.isEmpty) throw StateError('perfil $sellerId não encontrado');
  return rows.first['hub_published'] == true;
}

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }

  var fail = 0;
  void check(String name, bool ok, [String detail = '']) {
    print('${ok ? "PASS" : "FAIL"} $name ${detail.isEmpty ? "" : "— $detail"}');
    if (!ok) fail++;
  }

  final initial = await _published(client, sellerId);
  print('estado inicial hub_published=$initial');

  try {
    if (!initial) {
      final pub = await client.rpc(
        'batata_publish_hub',
        {'p_publish': true},
        accessToken: sellerToken,
      );
      check(
        'pré: publicar para começar o ciclo',
        pub is Map && pub['ok'] == true && pub['hub_published'] == true,
        '$pub',
      );
    }

    final beforeHide = await _published(client, sellerId);
    check('BD publicado antes de ocultar', beforeHide, 'hub_published=$beforeHide');

    final hide = await client.rpc(
      'batata_publish_hub',
      {'p_publish': false},
      accessToken: sellerToken,
    );
    check(
      'RPC ocultar ok',
      hide is Map && hide['ok'] == true && hide['hub_published'] == false,
      '$hide',
    );
    final hiddenBd = await _published(client, sellerId);
    check('BD oculto após Ocultar', !hiddenBd, 'hub_published=$hiddenBd');

    final show = await client.rpc(
      'batata_publish_hub',
      {'p_publish': true},
      accessToken: sellerToken,
    );
    check(
      'RPC publicar ok',
      show is Map && show['ok'] == true && show['hub_published'] == true,
      '$show',
    );
    final shownBd = await _published(client, sellerId);
    check('BD publicado após Publicar', shownBd, 'hub_published=$shownBd');
  } finally {
    await client.rpc(
      'batata_publish_hub',
      {'p_publish': true},
      accessToken: sellerToken,
    );
    final restored = await _published(client, sellerId);
    check('restauro final publicado', restored, 'hub_published=$restored');
  }

  exit(fail > 0 ? 1 : 0);
}
