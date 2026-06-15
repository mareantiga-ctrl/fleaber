// ignore_for_file: avoid_print
import 'dart:io';

import 'live_ops_staging_client.dart';

/// Modo de seed para flows seller harness (A089/A090/A094).
enum HarnessSeedMode { pending, accepted, cancelled }

HarnessSeedMode parseHarnessSeedMode(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'accepted' => HarnessSeedMode.accepted,
    'cancelled' || 'canceled' => HarnessSeedMode.cancelled,
    _ => HarnessSeedMode.pending,
  };
}

/// Garante live activa + reserva no estado pedido para harness Maestro.
Future<void> ensureMaestroHarnessSeed({
  String? envPath,
  HarnessSeedMode mode = HarnessSeedMode.pending,
}) async {
  final envFile = envPath ?? '.maestro/.env';
  if (!File(envFile).existsSync()) {
    print('maestro_seed: sem $envFile');
    return;
  }

  final dotEnv = <String, String>{};
  for (final line in File(envFile).readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    dotEnv[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }

  final liveId = dotEnv['MAESTRO_LIVE_ID']?.trim() ?? '';
  if (!isUuid(liveId)) {
    print('maestro_seed: MAESTRO_LIVE_ID em falta — corre maestro_prepare_live.dart');
    return;
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'live',
    'is_active': true,
  });

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId',
    limit: 5,
  );
  if (items.isEmpty) {
    print('maestro_seed: live sem items — corre maestro_prepare_live.dart');
    return;
  }
  final item = items.firstWhere(
    (it) {
      final p = it['price'];
      return p is num && p > 0;
    },
    orElse: () => items.first,
  );
  final itemId = item['id']!.toString();
  final sellerId =
      (dotEnv['MAESTRO_SELLER_ID'] ?? staging['LIVE_OPS_TEST_SELLER_ID'])?.trim() ?? '';

  final buyerEmail =
      dotEnv['MAESTRO_BUYER_EMAIL'] ?? envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword =
      dotEnv['MAESTRO_BUYER_PASSWORD'] ?? envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final buyerToken = await client.signIn(email: buyerEmail, password: buyerPassword);
  final buyerId = await client.userIdForAccessToken(buyerToken);

  // Limpa seeds anteriores deste harness na mesma live.
  final old = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&notes=ilike.%25MAESTRO_HARNESS_SEED%25',
    limit: 20,
  );
  for (final row in old) {
    final id = row['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await client.deleteWhere('live_reservation_requests', 'id=eq.$id');
    }
  }

  final (status, notes) = switch (mode) {
    HarnessSeedMode.pending => ('pending', 'MAESTRO_HARNESS_SEED'),
    HarnessSeedMode.accepted => ('accepted', 'MAESTRO_HARNESS_SEED'),
    HarnessSeedMode.cancelled => ('rejected', 'MAESTRO_HARNESS_SEED bag_removed'),
  };

  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': status,
    'notes': notes,
  });
  print('maestro_seed: reserva $status criada para harness (live=$liveId mode=$mode)');
}

void main(List<String> args) async {
  var mode = HarnessSeedMode.pending;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--mode' && i + 1 < args.length) {
      mode = parseHarnessSeedMode(args[++i]);
    }
  }
  await ensureMaestroHarnessSeed(mode: mode);
}
