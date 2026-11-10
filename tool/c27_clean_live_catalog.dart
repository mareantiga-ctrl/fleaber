// ignore_for_file: avoid_print
/// C27 — limpar catálogo da live: só C27 A (+ B inactivo). Remove o resto dos live_items.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleA = 'C27 Produto A';
const _titleB = 'C27 Produto B';
const _defaultLiveId = '4901d8c0-49db-4471-a2f8-c7154e6d5e26';

void main(List<String> args) async {
  var liveId = _defaultLiveId;
  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.split('=').last.trim();
  }
  final _liveId = liveId;
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(t);
  }

  // Garantir live activa
  await client.patch('lives', 'id=eq.$_liveId', {
    'status': 'live',
    'is_active': true,
  });

  Future<Map<String, dynamic>?> latestProduct(String title) async {
    final rows = await client.select(
      'products',
      filter:
          'seller_id=eq.$sellerId&title=eq.${Uri.encodeQueryComponent(title)}&order=created_at.desc',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  final productA = await latestProduct(_titleA);
  final productB = await latestProduct(_titleB);
  if (productA == null || productB == null) {
    stderr.writeln('FAIL: C27 products missing');
    exit(1);
  }
  final idA = productA['id']!.toString();
  final idB = productB['id']!.toString();

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$_liveId',
    limit: 500,
  );
  print('live_items antes: ${items.length}');

  String? itemA;
  String? itemB;
  var deleted = 0;
  for (final it in items) {
    final iid = it['id']?.toString() ?? '';
    final pid = it['product_id']?.toString() ?? '';
    if (pid == idA) {
      itemA = iid;
      continue;
    }
    if (pid == idB) {
      itemB = iid;
      continue;
    }
    // apagar da live (não apaga o produto marketplace)
    if (iid.isNotEmpty) {
      await client.deleteWhere('live_items', 'id=eq.$iid');
      deleted++;
    }
  }
  print('apagados do catálogo desta live: $deleted');

  Future<String> ensure(Map<String, dynamic> product, {required bool active}) async {
    final productId = product['id']!.toString();
    final existing = await client.select(
      'live_items',
      filter: 'live_id=eq.$_liveId&product_id=eq.$productId',
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final iid = existing.first['id']!.toString();
      await client.patch('live_items', 'id=eq.$iid', {
        'is_active': active,
        'status': 'available',
        'title': product['title'],
        'ref_code': product['ref_code'],
        'price': product['price'],
      });
      return iid;
    }
    final row = await client.insert('live_items', {
      'live_id': _liveId,
      'ref_code': product['ref_code'],
      'title': product['title'],
      'price': product['price'],
      'is_active': active,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    return row['id']!.toString();
  }

  itemA = await ensure(productA, active: true);
  itemB = await ensure(productB, active: false);

  final after = await client.select(
    'live_items',
    filter: 'live_id=eq.$_liveId',
    limit: 20,
  );

  // .env
  final file = File('.maestro/.env');
  final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wroteLive = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$_liveId');
      wroteLive = true;
    } else if (line.startsWith('MAESTRO_ITEM_TITLE=')) {
      out.add('MAESTRO_ITEM_TITLE=$_titleA');
    } else {
      out.add(line);
    }
  }
  if (!wroteLive) out.add('MAESTRO_LIVE_ID=$_liveId');
  file.writeAsStringSync('${out.join('\n')}\n');

  final result = {
    'live_id': _liveId,
    'deleted_junk': deleted,
    'remaining': after
        .map((e) => {
              'id': e['id'],
              'title': e['title'],
              'is_active': e['is_active'],
              'price': e['price'],
            })
        .toList(),
    'vitrine': itemA,
  };
  Directory('tool/reports/battery_c27_2026-08-23/bd').createSync(recursive: true);
  File('tool/reports/battery_c27_2026-08-23/bd/c27_catalog_clean.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  print(jsonEncode(result));
  print('OK: catálogo limpo — só C27 A (vitrine) + C27 B (lista). No TCL: fecha e reabre o catálogo / studio.');
}
