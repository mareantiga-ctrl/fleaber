// ignore_for_file: avoid_print
/// Staging ONLY — termina lives zombie da Maria Demo (`fleahub-demo-ux`).
/// Não toca noutras sellers, produção, nem grants SEC-003.
///
///   dart run tool/ps_maria_end_zombies_cleanup.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
const _expectedHandle = 'fleahub-demo-ux';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: URL não é staging fxdknzrqjenzqcvnwqqq → $url');
    exit(2);
  }
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final profiles = await client.select(
    'profiles',
    filter: 'id=eq.$_sellerId',
    limit: 1,
  );
  if (profiles.isEmpty) {
    stderr.writeln('ABORT: seller $_sellerId não existe');
    exit(2);
  }
  final handle = (profiles.first['handle'] ?? '').toString();
  final name = (profiles.first['full_name'] ?? '').toString();
  if (handle != _expectedHandle) {
    stderr.writeln(
      'ABORT: handle=$handle (esperado $_expectedHandle) — não limpar',
    );
    exit(2);
  }

  // Zombies = status live + is_active true (qualquer backend / redteam).
  final beforeActive = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)&status=eq.live&is_active=eq.true&order=created_at.desc',
    limit: 200,
  );
  final beforeAllLiveStatus = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)&status=eq.live&order=created_at.desc',
    limit: 200,
  );

  final endedAt = DateTime.now().toUtc().toIso8601String();
  final endedIds = <String>[];
  for (final row in beforeActive) {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final owner = (row['seller_id'] ?? row['vendedor_id'] ?? '').toString();
    if (owner != _sellerId) {
      stderr.writeln('SKIP safety: live $id owner=$owner ≠ Maria');
      continue;
    }
    await client.patch(
      'lives',
      'id=eq.$id&or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)',
      {
        'status': 'ended',
        'is_active': false,
        'ended_at': endedAt,
      },
    );
    endedIds.add(id);
  }

  // Também status=live com is_active null/false residual (só Maria).
  for (final row in beforeAllLiveStatus) {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty || endedIds.contains(id)) continue;
    final owner = (row['seller_id'] ?? row['vendedor_id'] ?? '').toString();
    if (owner != _sellerId) continue;
    await client.patch(
      'lives',
      'id=eq.$id&or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)',
      {
        'status': 'ended',
        'is_active': false,
        'ended_at': endedAt,
      },
    );
    endedIds.add(id);
  }

  final afterActive = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)&status=eq.live&is_active=eq.true',
    limit: 50,
  );
  final afterLiveStatus = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$_sellerId,vendedor_id.eq.$_sellerId)&status=eq.live',
    limit: 50,
  );

  // FX1/FX2 — limpar histórico de teste (reservas + live_items) desta seller.
  final fxProducts = await client.select(
    'products',
    filter: 'seller_id=eq.$_sellerId&ref_code=in.(FX1,FX2)',
    limit: 10,
  );
  final fxIds = fxProducts
      .map((p) => (p['id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toList();

  var cancelledReservations = 0;
  var deactivatedLiveItems = 0;
  var deletedFxLiveItems = 0;
  if (fxIds.isNotEmpty) {
    final inList = '(${fxIds.join(',')})';

    // live_items → product_id; reservas ligam-se via live_item_id.
    final items = await client.select(
      'live_items',
      filter: 'product_id=in.$inList',
      limit: 500,
    );
    final liveItemIds = <String>[];
    for (final li in items) {
      final lid = (li['id'] ?? '').toString();
      if (lid.isEmpty) continue;
      liveItemIds.add(lid);
      try {
        await client.patch(
          'live_items',
          'id=eq.$lid',
          {'is_active': false},
        );
        deactivatedLiveItems++;
      } catch (_) {}
    }

    if (liveItemIds.isNotEmpty) {
      final liIn = '(${liveItemIds.join(',')})';
      final reqs = await client.select(
        'live_reservation_requests',
        filter: 'live_item_id=in.$liIn',
        limit: 500,
      );
      for (final r in reqs) {
        final rid = (r['id'] ?? '').toString();
        final st = (r['status'] ?? '').toString().toLowerCase();
        if (rid.isEmpty) continue;
        if (st == 'cancelled' || st == 'expired' || st == 'rejected') continue;
        try {
          await client.patch(
            'live_reservation_requests',
            'id=eq.$rid',
            {'status': 'cancelled'},
          );
          cancelledReservations++;
        } catch (_) {}
      }
      // Apagar live_items FX de lives já ended (histórico limpo para reteste).
      for (final lid in liveItemIds) {
        try {
          await client.deleteWhere('live_items', 'id=eq.$lid');
          deletedFxLiveItems++;
        } catch (_) {}
      }
    }

    // Reset stock FX1/FX2 para valores limpos de reteste.
    for (final p in fxProducts) {
      final id = (p['id'] ?? '').toString();
      if (id.isEmpty) continue;
      await client.patch(
        'products',
        'id=eq.$id&seller_id=eq.$_sellerId',
        {
          'available_for_live': true,
          'is_sold': false,
          'quantity': 5,
          'list_on_marketplace': true,
        },
      );
    }
  }

  final evidence = {
    'at': endedAt,
    'project': 'fxdknzrqjenzqcvnwqqq',
    'seller_id': _sellerId,
    'seller_handle': handle,
    'seller_name': name,
    'zombies_active_before': beforeActive.length,
    'status_live_before': beforeAllLiveStatus.length,
    'ended_live_ids': endedIds,
    'ended_count': endedIds.length,
    'zombies_active_after': afterActive.length,
    'status_live_after': afterLiveStatus.length,
    'fx_products': fxProducts
        .map((p) => {
              'id': p['id'],
              'ref_code': p['ref_code'],
              'title': p['title'],
            })
        .toList(),
    'fx_reservations_cancelled': cancelledReservations,
    'fx_live_items_deactivated': deactivatedLiveItems,
    'fx_live_items_deleted': deletedFxLiveItems,
    'active_lives_final_must_be_zero': afterActive.isEmpty,
  };

  final outDir = Directory('tool/reports/ps_oppo_live_20260912');
  outDir.createSync(recursive: true);
  final outFile = File(
    '${outDir.path}/maria_zombie_cleanup_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json',
  );
  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );

  print(const JsonEncoder.withIndent('  ').convert(evidence));
  print('EVIDENCE=$outFile');
  if (afterActive.isNotEmpty) {
    stderr.writeln('FAIL: ainda há ${afterActive.length} lives activas');
    exit(1);
  }
  print('OK: lives activas Maria = 0');
}
