// ignore_for_file: avoid_print
/// C27 — activar Produto B na vitrine (após APP-253).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleB = 'C27 Produto B';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  var sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(liveId)) exit(1);

  final products = await client.select(
    'products',
    filter:
        'seller_id=eq.$sellerId&title=eq.${Uri.encodeQueryComponent(_titleB)}&order=created_at.desc',
    limit: 1,
  );
  if (products.isEmpty) exit(2);
  final productId = products.first['id']!.toString();

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&product_id=eq.$productId',
    limit: 1,
  );
  if (items.isEmpty) exit(3);
  final itemId = items.first['id']!.toString();

  await client.patch('live_items', 'live_id=eq.$liveId', {'is_active': false});
  await client.patch('live_items', 'id=eq.$itemId', {
    'is_active': true,
    'status': 'available',
  });

  final envFile = File('.maestro/.env');
  final lines = envFile.readAsLinesSync();
  final out = lines.map((l) {
    if (l.startsWith('MAESTRO_ITEM_TITLE=')) {
      return 'MAESTRO_ITEM_TITLE=$_titleB';
    }
    return l;
  }).toList();
  envFile.writeAsStringSync('${out.join('\n')}\n');

  print(jsonEncode({'live_item_b_active': itemId, 'title': _titleB}));
}

Map<String, String> _readEnv(File file) {
  final out = <String, String>{};
  if (!file.existsSync()) return out;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
