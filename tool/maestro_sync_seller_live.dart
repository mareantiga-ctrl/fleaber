// ignore_for_file: avoid_print
/// Após o seller iniciar o directo no dispositivo A, sincroniza MAESTRO_LIVE_ID
/// e semeia catálogo (produto + live_item) na live activa.
///
/// Uso: dart run tool/maestro_sync_seller_live.dart
///      dart run tool/maestro_sync_seller_live.dart --wait-seconds=180
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _itemTitle = 'Maestro smoke item';
const _productTitle = 'Maestro smoke product';

void main(List<String> args) async {
  var waitSeconds = 180;
  for (final arg in args) {
    if (arg.startsWith('--wait-seconds=')) {
      waitSeconds = int.tryParse(arg.split('=').last) ?? waitSeconds;
    }
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final envPath = File('.maestro/.env');
  if (!envPath.existsSync()) {
    stderr.writeln('Falta .maestro/.env');
    exit(1);
  }
  final env = _readEnv(envPath);
  var sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final token = await client.signIn(
      email: envRequire(env, 'MAESTRO_SELLER_EMAIL'),
      password: envRequire(env, 'MAESTRO_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(token);
  }

  final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
  Map<String, dynamic>? live;
  while (DateTime.now().isBefore(deadline)) {
    final rows = await client.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&order=created_at.desc',
      limit: 8,
    );
    final active = rows.where((r) {
      final st = r['status']?.toString() ?? '';
      final on = r['is_active'] == true || r['is_active']?.toString() == 'true';
      return st == 'live' && on;
    }).toList();
    if (active.isNotEmpty) {
      live = active.first;
      break;
    }
    if (rows.isNotEmpty) {
      final recent = rows.first;
      final created = DateTime.tryParse(recent['created_at']?.toString() ?? '');
      if (created != null &&
          DateTime.now().toUtc().difference(created.toUtc()).inMinutes < 15) {
        live = recent;
        stdout.writeln(
          'AVISO: live sem status=live na BD; a usar mais recente (${recent['status']}).',
        );
        break;
      }
    }
    stdout.writeln('A aguardar live activa do seller…');
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  if (live == null) {
    stderr.writeln(
      'Timeout: nenhuma live status=live para seller $sellerId. '
      'Confirma «Iniciar Direto» no dispositivo seller.',
    );
    exit(1);
  }

  final liveId = live['id']!.toString();
  await _ensureCatalog(client, sellerId, liveId);

  env['MAESTRO_LIVE_ID'] = liveId;
  env['MAESTRO_SELLER_ID'] = sellerId;
  env['MAESTRO_ITEM_TITLE'] = _itemTitle;
  _writeEnv(envPath, env);

  print('maestro_sync_seller_live OK');
  print('  live_id=$liveId');
  print('  item_title=$_itemTitle');
  print('  updated ${envPath.path}');
}

Future<void> _ensureCatalog(
  LiveOpsStagingClient client,
  String sellerId,
  String liveId,
) async {
  final existing = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&title=eq.$_itemTitle',
    limit: 1,
  );
  if (existing.isNotEmpty) return;

  final ref = 'MAESTRO-${DateTime.now().millisecondsSinceEpoch % 100000}';
  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': _productTitle,
    'price': 5,
    'quantity': 5,
    'ref_code': ref,
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();

  await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': _itemTitle,
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
}

Map<String, String> _readEnv(File file) {
  final map = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return map;
}

void _writeEnv(File file, Map<String, String> env) {
  final keys = env.keys.toList()..sort();
  final buf = StringBuffer();
  for (final k in keys) {
    buf.writeln('$k=${env[k]}');
  }
  file.writeAsStringSync(buf.toString());
}

String envRequire(Map<String, String> env, String key) {
  final v = env[key]?.trim() ?? '';
  if (v.isEmpty) {
    throw StateError('$key em falta em .maestro/.env');
  }
  return v;
}
