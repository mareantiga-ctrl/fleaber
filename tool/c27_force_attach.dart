// ignore_for_file: avoid_print
/// C27 — listar lives recentes do seller + reactivar se preciso + ligar C27.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleA = 'C27 Produto A';
const _titleB = 'C27 Produto B';
const _reportDir = 'tool/reports/battery_c27_2026-08-23';

void main(List<String> args) async {
  final forceLiveId = args
      .where((a) => a.startsWith('--live='))
      .map((a) => a.split('=').last.trim())
      .firstOrNull;

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

  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 8,
  );
  print('=== lives recentes ===');
  for (final l in lives) {
    print(
      '${l['id']} | ${l['title']} | status=${l['status']} active=${l['is_active']} | mux=${l['mux_playback_id']}',
    );
  }

  Map<String, dynamic>? pick;
  if (forceLiveId != null && isUuid(forceLiveId)) {
    pick = lives.cast<Map<String, dynamic>?>().firstWhere(
          (l) => l?['id']?.toString() == forceLiveId,
          orElse: () => null,
        );
    if (pick == null) {
      final rows =
          await client.select('lives', filter: 'id=eq.$forceLiveId', limit: 1);
      if (rows.isNotEmpty) pick = rows.first;
    }
  }
  pick ??= lives.cast<Map<String, dynamic>?>().firstWhere(
        (l) {
          final s = (l?['status'] ?? '').toString().toLowerCase();
          return s == 'live' && l?['is_active'] != false;
        },
        orElse: () => null,
      );
  // Preferir live Mux real recente (não smoke fake), mesmo se ended por engano
  pick ??= lives.cast<Map<String, dynamic>?>().firstWhere(
        (l) {
          final mux = (l?['mux_playback_id'] ?? '').toString();
          final title = (l?['title'] ?? '').toString();
          return mux.isNotEmpty &&
              !mux.contains('maestro-smoke') &&
              !title.contains('MAESTRO_SMOKE');
        },
        orElse: () => null,
      );

  if (pick == null) {
    stderr.writeln('FAIL: nenhuma live candidata');
    exit(2);
  }

  final liveId = pick['id']!.toString();
  final status = (pick['status'] ?? '').toString().toLowerCase();
  if (status != 'live' || pick['is_active'] == false) {
    print('reactivating live $liveId (was $status active=${pick['is_active']})');
    await client.patch('lives', 'id=eq.$liveId', {
      'status': 'live',
      'is_active': true,
    });
  }

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
    stderr.writeln('FAIL: produtos C27 em falta');
    exit(1);
  }

  Future<String> ensureItem(Map<String, dynamic> product, bool active) async {
    final productId = product['id']!.toString();
    final title = product['title']?.toString() ?? '';
    final ref = product['ref_code']?.toString() ?? '';
    final price = product['price'] ?? 0;
    final existing = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId&product_id=eq.$productId',
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id']!.toString();
      await client.patch('live_items', 'id=eq.$id', {
        'is_active': active,
        'status': 'available',
        'title': title,
        'ref_code': ref,
        'price': price,
      });
      return id;
    }
    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': ref,
      'title': title,
      'price': price,
      'is_active': active,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    return item['id']!.toString();
  }

  // Não desactivar todos — só garantir A activo na vitrine
  final itemA = await ensureItem(productA, true);
  final itemB = await ensureItem(productB, false);
  // A na vitrine
  await client.patch('live_items', 'id=eq.$itemA', {'is_active': true});

  // patch .env
  final file = File('.maestro/.env');
  final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wrote = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$liveId');
      wrote = true;
    } else if (line.startsWith('MAESTRO_ITEM_TITLE=')) {
      out.add('MAESTRO_ITEM_TITLE=$_titleA');
    } else {
      out.add(line);
    }
  }
  if (!wrote) out.add('MAESTRO_LIVE_ID=$liveId');
  file.writeAsStringSync('${out.join('\n')}\n');

  final result = {
    'live_id': liveId,
    'title': pick['title'],
    'reactivated': status != 'live',
    'live_item_a': itemA,
    'live_item_b': itemB,
    'product_a': productA['id'],
    'product_b': productB['id'],
  };
  Directory('$_reportDir/bd').createSync(recursive: true);
  File('$_reportDir/bd/c27_force_attach.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(result),
  );
  print(jsonEncode(result));
  print('OK: C27 Produto A ligado — no studio toca refrescar / mudar vitrine se preciso');
}
