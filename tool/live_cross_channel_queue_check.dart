// PS — testes fila unificada cross-canal (staging).
// dart run tool/live_cross_channel_queue_check.dart

import 'dart:convert';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (sellerId.isEmpty) {
    throw StateError('LIVE_OPS_TEST_SELLER_ID em falta');
  }

  print('=== PS queue check — seller $sellerId ===');

  final lives = await client.select(
    'lives',
    filter: 'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 1,
  );
  if (lives.isEmpty) {
    throw StateError('Sem lives para seller de teste');
  }
  final liveId = lives.first['id']?.toString() ?? '';
  print('live_id=$liveId');

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&order=created_at.asc',
    limit: 3,
  );
  if (items.isEmpty) {
    throw StateError('Live sem artigos — adiciona catálogo primeiro');
  }
  final itemId = items.first['id']?.toString() ?? '';
  print('live_item_id=$itemId ref=${items.first['ref_code']}');

  Future<void> insert({
    required String source,
    String? ingestChannel,
    DateTime? effectiveAt,
    DateTime? detectedAt,
    String? idempotencyKey,
  }) async {
    await client.insert('live_reservation_requests', {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'source': source,
      'status': 'pending',
      if (ingestChannel != null) 'ingest_channel': ingestChannel,
      if (effectiveAt != null) 'effective_at': effectiveAt.toUtc().toIso8601String(),
      if (detectedAt != null) 'detected_at': detectedAt.toUtc().toIso8601String(),
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    });
  }

  final base = DateTime.now().toUtc();
  final stamp = base.millisecondsSinceEpoch;

  await insert(
    source: 'facebook_manual',
    ingestChannel: 'ocr',
    detectedAt: base.subtract(const Duration(seconds: 8)),
    idempotencyKey: 'ps:test:fb-$stamp',
  );
  await insert(
    source: 'fleaber_live',
    effectiveAt: base,
  );

  final pending = await client.select(
    'live_reservation_requests',
    filter:
        'live_item_id=eq.$itemId&status=eq.pending&order=queue_position.asc',
    limit: 20,
  );

  print('\n=== Fila pending ===');
  for (final row in pending) {
    print(jsonEncode({
      'source': row['source'],
      'queue_position': row['queue_position'],
      'effective_at': row['effective_at'],
      'ingest_channel': row['ingest_channel'],
    }));
  }

  if (pending.length >= 2) {
    final first = pending.first;
    print(
      '\nPrimeiro: ${first['source']} #${first['queue_position']} '
      '(esperado FB se effective_at mais cedo)',
    );
  } else {
    print('\nAVISO — fila < 2; confirma SQL PS aplicado em staging');
  }
}
