// ignore_for_file: avoid_print
/// Após go-live no TCL: aponta C15 para a live activa e garante o artigo.
///
///   dart run tool/c15_attach_active_live.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _productTitle = 'C15 Produto A';
const _scheduledTitle = 'C15 Directo A';

void main() async {
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
    limit: 20,
  );
  Map<String, dynamic>? active;
  for (final l in lives) {
    final status = (l['status'] ?? '').toString().toLowerCase();
    if (status == 'live' && l['is_active'] != false) {
      active = l;
      break;
    }
  }
  if (active == null) {
    stderr.writeln('FAIL: nenhuma live activa');
    for (final l in lives.take(8)) {
      print('  ${l['id']} ${l['title']} status=${l['status']} active=${l['is_active']}');
    }
    exit(2);
  }

  final liveId = active['id']!.toString();
  print('live activa: $liveId title=${active['title']}');

  for (final l in lives) {
    final id = l['id']?.toString() ?? '';
    if (id.isEmpty || id == liveId) continue;
    final title = (l['title'] ?? '').toString();
    final status = (l['status'] ?? '').toString().toLowerCase();
    final leftover = title == _scheduledTitle ||
        status == 'live' ||
        l['is_active'] == true ||
        status == 'scheduled';
    if (leftover && status != 'ended') {
      await client.patch('lives', 'id=eq.$id', {'status': 'ended', 'is_active': false});
      print('  fechada leftover $id $title $status');
    }
  }

  final products = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&title=eq.${Uri.encodeQueryComponent(_productTitle)}&order=created_at.desc',
    limit: 1,
  );
  if (products.isEmpty) {
    stderr.writeln('FAIL: produto C15 Produto A em falta');
    exit(1);
  }
  final product = products.first;
  final productId = product['id']!.toString();
  final ref = product['ref_code']?.toString() ?? '';
  final price = product['price'] ?? 9.0;

  final existing = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&product_id=eq.$productId',
    limit: 1,
  );
  String liveItemId = '';
  if (existing.isNotEmpty) {
    liveItemId = existing.first['id']!.toString();
    print('artigo já no catálogo $liveItemId');
  } else {
    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': ref,
      'title': _productTitle,
      'price': price,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    liveItemId = item['id']!.toString();
    print('artigo ligado $liveItemId');
  }

  await client.patch('live_items', 'live_id=eq.$liveId', {'is_active': false});
  await client.patch('live_items', 'id=eq.$liveItemId', {'is_active': true, 'title': _productTitle, 'ref_code': ref});
  print('vitrine = C15 $liveItemId');

  _patchMaestroLiveId(liveId);

  final dest = File('tool/reports/battery_c15_2026-08-19/bd/c15_active_live.json');
  dest.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'live_id': liveId,
      'title': active['title'],
      'status': active['status'],
      'is_active': active['is_active'],
      'mux_playback_id': active['mux_playback_id'],
      'product_id': productId,
      'live_item_id': liveItemId,
    }),
  );
  print('wrote ${dest.path}');
}

void _patchMaestroLiveId(String liveId) {
  final file = File('.maestro/.env');
  final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wrote = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$liveId');
      wrote = true;
    } else {
      out.add(line);
    }
  }
  if (!wrote) out.add('MAESTRO_LIVE_ID=$liveId');
  file.writeAsStringSync('${out.join('\n')}\n');
}
