// ignore_for_file: avoid_print
/// Cruzamento BD ↔ regra do saco (espelha liveBagDisplayRequests + secção inBag).
///
/// Não altera a app. Uso:
///   dart run tool/maestro_verify_bag_crosscheck.dart
///   dart run tool/maestro_verify_bag_crosscheck.dart --live-id=UUID --buyer-id=UUID
///   dart run tool/maestro_verify_bag_crosscheck.dart --expect-in-bag=1 --expect-qty=1
///   dart run tool/maestro_verify_bag_crosscheck.dart --diagnose-all-buyers
///
/// Exit 0 = checks OK (ou só diagnóstico sem --expect-*).
/// Exit 1 = mismatch / dados inválidos.
library;

import 'dart:io';

import 'bag_crosscheck_logic.dart';
import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  var liveId = '';
  var buyerId = '';
  int? expectInBag;
  int? expectQty;
  var diagnoseAll = args.contains('--diagnose-all-buyers');
  var pendingOnlyFail = args.contains('--require-pending');

  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.split('=').last.trim();
    if (a.startsWith('--buyer-id=')) buyerId = a.split('=').last.trim();
    if (a.startsWith('--expect-in-bag=')) {
      expectInBag = int.tryParse(a.split('=').last.trim());
    }
    if (a.startsWith('--expect-qty=')) {
      expectQty = int.tryParse(a.split('=').last.trim());
    }
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final envPath = File('.maestro/.env');
  final env = envPath.existsSync() ? _readEnv(envPath) : <String, String>{};

  if (liveId.isEmpty) {
    liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  }
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: --live-id ou MAESTRO_LIVE_ID UUID obrigatório');
    exit(1);
  }

  if (buyerId.isEmpty && !diagnoseAll) {
    buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
    if (!isUuid(buyerId)) {
      final email = env['MAESTRO_BUYER_EMAIL'] ??
          staging['LIVE_OPS_TEST_BUYER_EMAIL'] ??
          '';
      final pass = env['MAESTRO_BUYER_PASSWORD'] ??
          staging['LIVE_OPS_TEST_BUYER_PASSWORD'] ??
          '';
      if (email.isEmpty || pass.isEmpty) {
        stderr.writeln('FAIL: buyer em falta (id ou email/password)');
        exit(1);
      }
      final token = await client.signIn(email: email, password: pass);
      buyerId = await client.userIdForAccessToken(token);
    }
  }

  final allRows = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 200,
  );

  print('live_id=$liveId');
  print('reservas_na_live=${allRows.length}');

  if (diagnoseAll) {
    final byBuyer = <String, List<Map<String, dynamic>>>{};
    for (final r in allRows) {
      final b = (r['buyer_id'] ?? '').toString();
      byBuyer.putIfAbsent(b, () => []).add(r);
    }
    for (final e in byBuyer.entries) {
      _printBuyerReport(e.key, e.value);
    }
    exit(0);
  }

  final buyerRows =
      allRows.where((r) => (r['buyer_id'] ?? '').toString() == buyerId).toList();
  _printBuyerReport(buyerId, buyerRows);

  final expected = BagCrosscheckLogic.fromRows(buyerRows);
  print('---');
  print('esperado_ui_saco (regra app):');
  print('  in_bag_rows=${expected.inBagRowCount}');
  print('  in_bag_units=${expected.inBagUnitQty}');
  print('  label="${expected.inBagRowCount} no saco"');
  print('  bag_query_rows=${expected.bagQueryRowCount} '
      '(source=fleaber_live, qualquer status)');
  print('  skipped_empty_live_item_id=${expected.skippedEmptyLiveItemId}');
  print('  skipped_wrong_source=${expected.skippedWrongSource}');
  print('  pending_any_source=${expected.pendingAnySource}');
  print('  pending_visible_in_bag=${expected.pendingVisibleInBag}');

  if (expected.diagnoses.isNotEmpty) {
    print('diagnóstico:');
    for (final d in expected.diagnoses) {
      print('  - $d');
    }
  }

  var failed = 0;
  if (pendingOnlyFail && expected.pendingAnySource < 1) {
    stderr.writeln('FAIL: --require-pending mas pending_any_source=0');
    failed++;
  }
  if (expectInBag != null && expected.inBagRowCount != expectInBag) {
    stderr.writeln(
      'FAIL: expect-in-bag=$expectInBag vs computed=${expected.inBagRowCount}',
    );
    failed++;
  }
  if (expectQty != null && expected.inBagUnitQty != expectQty) {
    stderr.writeln(
      'FAIL: expect-qty=$expectQty vs computed=${expected.inBagUnitQty}',
    );
    failed++;
  }

  // Regra dura: se há pending fleaber_live com live_item_id, inBag ≥ 1
  if (expected.pendingVisibleInBag >= 1 && expected.inBagRowCount < 1) {
    stderr.writeln(
      'FAIL CONTRATO: pending visível no filtro do saco mas in_bag_rows=0',
    );
    failed++;
  }

  // Caso clássico do relatório F5: pending BD + UI 0
  if (expected.pendingAnySource >= 1 && expected.inBagRowCount < 1) {
    stderr.writeln(
      'FAIL BUG-CANDIDATE: há pending na live para este buyer mas '
      'regra do saco prevê 0 (ver skipped_* / source / live_item_id / buyer)',
    );
    failed++;
  }

  if (failed > 0) {
    stderr.writeln('BAG CROSSCHECK FAIL ($failed)');
    exit(1);
  }
  print('BAG CROSSCHECK PASS');
}

void _printBuyerReport(String buyerId, List<Map<String, dynamic>> rows) {
  print('---');
  print('buyer_id=$buyerId rows=${rows.length}');
  for (final r in rows.take(15)) {
    final notes = (r['notes'] ?? '').toString().replaceAll('\n', ' ');
    final notesShort =
        notes.length <= 60 ? notes : '${notes.substring(0, 60)}…';
    print(
      '  id=${r['id']} status=${r['status']} qty=${r['requested_qty']} '
      'source=${r['source']} live_item_id=${r['live_item_id']} '
      'notes=$notesShort',
    );
  }
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

String envRequire(Map<String, String> m, String key) {
  final v = m[key]?.trim() ?? '';
  if (v.isEmpty) throw StateError('$key em falta');
  return v;
}
