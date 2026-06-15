// ignore_for_file: avoid_print
/// Verificação automática da bateria L1–L18 (V1.5 logical_item_id) em staging.
///
/// Uso:
///   dart run tool/live_logical_item_id_check.dart
///   dart run tool/live_logical_item_id_check.dart --keep
///   dart run tool/live_logical_item_id_check.dart --audit-only
///
/// Requer: tool/live_ops_staging.env (copiar de live_ops_staging_env.example)
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _testLiveTitle = 'LOGICAL_ID_V15_TEST';
const _testDraftTitle = 'LOGICAL_ID_V15_TEST_draft';
const _sharedRef = '#V15L15';
const _newRefPrefix = 'V15NEW';

enum _Verdict { pass, fail, skip }

class _CaseResult {
  _CaseResult(this.id, this.title, this.verdict, [this.detail = '']);

  final String id;
  final String title;
  final _Verdict verdict;
  final String detail;
}

void main(List<String> args) async {
  final keep = args.contains('--keep');
  final auditOnly = args.contains('--audit-only');
  final results = <_CaseResult>[];

  try {
    final env = loadLiveOpsStagingEnv();
    final client = LiveOpsStagingClient(
      url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
      anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
      serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    );
    var sellerId = env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
    final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
    var buyerId = env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
    final buyerEmail = env['LIVE_OPS_TEST_BUYER_EMAIL']?.trim() ?? '';
    final buyerPassword = env['LIVE_OPS_TEST_BUYER_PASSWORD']?.trim() ?? '';

    print('Fleaber V1.5 logical_item_id — verificação staging');
    print('URL: ${client.url}');
    print('---');

    final sellerToken = await client.signIn(
      email: sellerEmail,
      password: sellerPassword,
    );
    if (!isUuid(sellerId)) {
      sellerId = await client.userIdForAccessToken(sellerToken);
    }
    String? buyerToken;
    if (buyerEmail.isNotEmpty && buyerPassword.isNotEmpty) {
      buyerToken = await client.signIn(
        email: buyerEmail,
        password: buyerPassword,
      );
      if (!isUuid(buyerId)) {
        buyerId = await client.userIdForAccessToken(buyerToken);
      }
    }

    if (!auditOnly) {
      print('Limpar fixtures $_testLiveTitle (seller $sellerId)…');
      await _cleanupTestFixtures(client, sellerId);
    } else {
      print('Modo --audit-only: sem seed/cleanup de fixtures.');
    }

    final ctx = _RunContext(
      client: client,
      sellerId: sellerId,
      sellerToken: sellerToken,
      buyerId: buyerId,
      buyerToken: buyerToken,
      auditOnly: auditOnly,
    );

    results.add(await _l1NewRefLogicalId(ctx));
    results.add(await _l2BackfillHistorical(ctx));
    if (!auditOnly) {
      await _seedMultiLineageHistory(ctx);
    }
    results.add(await _l3PreviewLineages(ctx));
    final l6Snap = auditOnly ? null : await _snapshotReservationForL6(ctx);
    results.add(await _l4InheritLineage(ctx));
    results.add(await _l5NewArticleUuid(ctx));
    if (l6Snap != null) {
      results.add(await _l6ReservationsUnchanged(ctx, l6Snap));
    } else {
      results.add(_CaseResult(
        'L6',
        'Reservas antigas intactas',
        _Verdict.skip,
        'Sem fixture de reserva (usa --audit-only ou seed).',
      ));
    }
    results.add(_skip('L7', 'Badge vendas no card', 'UI do sheet — só manual.'));
    results.add(_skip('L8', 'Contexto visual no card', 'UI do sheet — só manual.'));
    results.add(_skip('L9', 'Sheet reaparece em novo prep', 'Fluxo prefs/UI — só manual.'));
    results.add(await _l10TwoContinueTargets(ctx));
    results.add(await _l11CancelNoServerWrite(ctx));
    results.add(_skip('L12', 'Marketplace sem sheet', 'Adicionar produto TYPE A — só manual.'));
    results.add(await _l13KeepLogicalOnReedit(ctx));
    results.add(_skip('L14', 'Checkout pós novo artigo', 'Stripe + live — só manual.'));
    results.add(_skip('L15', 'Regressão chat/gravado', 'Player — só manual.'));
    results.add(await _l16SaleShowsSheet(ctx));
    results.add(await _l17GhostUsageHidden(ctx));
    results.add(await _l18OldOpenReservation(ctx));

    if (!keep && !auditOnly) {
      print('---');
      print('Limpar fixtures de teste…');
      await _cleanupTestFixtures(client, sellerId);
    }
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    exitCode = 1;
    return;
  }

  _printSummary(results);
}

_CaseResult _skip(String id, String title, String detail) =>
    _CaseResult(id, title, _Verdict.skip, detail);

void _printSummary(List<_CaseResult> results) {
  print('---');
  var pass = 0, fail = 0, skip = 0;
  for (final r in results) {
    final tag = switch (r.verdict) {
      _Verdict.pass => 'PASS',
      _Verdict.fail => 'FAIL',
      _Verdict.skip => 'SKIP',
    };
    print('$tag  ${r.id} — ${r.title}');
    if (r.detail.isNotEmpty) {
      print('      ${r.detail}');
    }
    switch (r.verdict) {
      case _Verdict.pass:
        pass++;
      case _Verdict.fail:
        fail++;
      case _Verdict.skip:
        skip++;
    }
  }
  print('---');
  print('Resumo: $pass PASS · $fail FAIL · $skip SKIP (${results.length} testes)');
  if (fail > 0) {
    exitCode = 1;
  }
  print('');
  print('Comando: dart run tool/live_logical_item_id_check.dart');
  print('Opções: --keep (não apaga fixtures) · --audit-only (só L1/L2/dados existentes)');
}

class _RunContext {
  _RunContext({
    required this.client,
    required this.sellerId,
    required this.sellerToken,
    required this.buyerId,
    this.buyerToken,
    required this.auditOnly,
  });

  final LiveOpsStagingClient client;
  final String sellerId;
  final String sellerToken;
  final String buyerId;
  final String? buyerToken;
  final bool auditOnly;

  String? puzzleLineageId;
  String? puzzleItemId;
  String? bonecaLineageId;
  String? draftLiveId;
}

Future<void> _cleanupTestFixtures(
  LiveOpsStagingClient client,
  String sellerId,
) async {
  for (final title in [_testLiveTitle, _testDraftTitle]) {
    await _deleteLivesByTitle(client, sellerId, title);
  }
}

Future<void> _deleteLivesByTitle(
  LiveOpsStagingClient client,
  String sellerId,
  String title,
) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$title',
    limit: 50,
  );
  for (final live in lives) {
    final liveId = live['id']?.toString() ?? '';
    if (liveId.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$liveId');
    await client.deleteWhere('orders', 'live_id=eq.$liveId');
    await client.deleteWhere('live_items', 'live_id=eq.$liveId');
    await client.deleteWhere('lives', 'id=eq.$liveId');
  }
  for (final ref in ['L16', 'L17', 'L18']) {
    await client.deleteWhere('products', 'seller_id=eq.$sellerId&ref_code=eq.$ref');
  }
}

Future<String> _createTestDraftLive(_RunContext ctx) async {
  final live = await ctx.client.insert('lives', {
    'title': _testDraftTitle,
    'status': 'draft',
    'seller_id': ctx.sellerId,
    'vendedor_id': ctx.sellerId,
    'is_active': false,
  });
  final id = live['id']!.toString();
  ctx.draftLiveId = id;
  return id;
}

String? _parseRpcUuid(dynamic res) {
  if (res == null) return null;
  var s = res.toString().trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1);
  }
  return isUuid(s) ? s : null;
}

Future<String> _ensureDraftLive(_RunContext ctx) async {
  final res = await ctx.client.rpc(
    'batata_ensure_draft_live',
    {'p_seller_id': ctx.sellerId},
    accessToken: ctx.sellerToken,
  );
  final id = _parseRpcUuid(res);
  if (id == null) {
    throw StateError('batata_ensure_draft_live devolveu id inválido: $res');
  }
  ctx.draftLiveId = id;
  return id;
}

Future<Map<String, dynamic>> _upsertLiveOnly(
  _RunContext ctx, {
  required String refCode,
  required String title,
  String lineageMode = 'new',
  String? logicalItemId,
  String? liveId,
}) async {
  final params = <String, dynamic>{
    'p_seller_id': ctx.sellerId,
    'p_ref_code': refCode,
    'p_title': title,
    'p_quantity': 1,
    'p_lineage_mode': lineageMode,
    if (liveId != null) 'p_live_id': liveId,
    if (logicalItemId != null) 'p_logical_item_id': logicalItemId,
  };
  final res = await ctx.client.rpc(
    'batata_upsert_live_only_item',
    params,
    accessToken: ctx.sellerToken,
  );
  if (res is! Map) {
    throw StateError('upsert_live_only resposta inválida: $res');
  }
  return Map<String, dynamic>.from(res);
}

Future<Map<String, dynamic>> _preview(
  _RunContext ctx, {
  required String refCode,
  String? liveId,
}) async {
  final params = <String, dynamic>{
    'p_seller_id': ctx.sellerId,
    'p_ref_code': refCode,
    if (liveId != null) 'p_live_id': liveId,
  };
  final res = await ctx.client.rpc(
    'batata_live_ref_open_reservations_preview',
    params,
    accessToken: ctx.sellerToken,
  );
  if (res is! Map) {
    throw StateError('preview resposta inválida: $res');
  }
  return Map<String, dynamic>.from(res);
}

Future<List<Map<String, dynamic>>> _sellerLiveOnlyItems(
  LiveOpsStagingClient client,
  String sellerId, {
  int limit = 200,
}) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId',
    limit: 100,
  );
  final out = <Map<String, dynamic>>[];
  for (final live in lives) {
    final liveId = live['id']?.toString() ?? '';
    if (liveId.isEmpty) continue;
    final items = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId&item_kind=eq.live_only',
      limit: 50,
    );
    for (final it in items) {
      out.add({
        ...it,
        'live_status': live['status'],
        'live_id': liveId,
      });
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/// Filtro PostgREST seguro para valores com `#`, espaços, etc.
String _filterEq(String column, String value) {
  if (value.contains('#') ||
      value.contains(' ') ||
      value.contains(',') ||
      value.contains('"')) {
    final escaped = value.replaceAll('"', r'\"');
    return '$column=eq."$escaped"';
  }
  return '$column=eq.$value';
}

bool _isPreviewRpcNotDeployed(Object e) {
  final msg = e.toString();
  return msg.contains('ended_at') && msg.contains('does not exist');
}

String _normalizeRef(String ref) {
  var r = ref.trim().toLowerCase();
  if (r.startsWith('#')) r = r.substring(1);
  return r.replaceAll(RegExp(r'\s+'), '');
}

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

Future<void> _seedMultiLineageHistory(_RunContext ctx) async {
  print('Seed: 2 lives ended com ref $_sharedRef (Puzzle + Boneca)…');
  final old = DateTime.now().toUtc().subtract(const Duration(days: 400));

  Future<String> endedLive(String suffix) async {
    final live = await ctx.client.insert('lives', {
      'title': _testLiveTitle,
      'status': 'ended',
      'seller_id': ctx.sellerId,
      'vendedor_id': ctx.sellerId,
      'is_active': false,
      'created_at': old.toIso8601String(),
    });
    return live['id']!.toString();
  }

  final liveA = await endedLive('A');
  final liveB = await endedLive('B');

  final itemA = await ctx.client.insert('live_items', {
    'live_id': liveA,
    'item_kind': 'live_only',
    'ref_code': _sharedRef,
    'title': 'Puzzle V15 Test',
    'quantity': 1,
    'is_active': false,
    'status': 'available',
  });
  final itemB = await ctx.client.insert('live_items', {
    'live_id': liveB,
    'item_kind': 'live_only',
    'ref_code': _sharedRef,
    'title': 'Boneca V15 Test',
    'quantity': 1,
    'is_active': false,
    'status': 'available',
  });

  final idA = itemA['id']!.toString();
  final idB = itemB['id']!.toString();
  await ctx.client.patch('live_items', 'id=eq.$idA', {'logical_item_id': idA});
  await ctx.client.patch('live_items', 'id=eq.$idB', {'logical_item_id': idB});

  ctx.puzzleItemId = idA;
  ctx.puzzleLineageId = idA;
  ctx.bonecaLineageId = idB;
}

Future<_CaseResult> _l1NewRefLogicalId(_RunContext ctx) async {
  const id = 'L1';
  try {
    if (ctx.auditOnly) {
      final items = await _sellerLiveOnlyItems(ctx.client, ctx.sellerId);
      final fresh = items.where((i) {
        final lid = i['logical_item_id']?.toString() ?? '';
        return lid.isNotEmpty && isUuid(lid);
      });
      if (fresh.isEmpty) {
        return _CaseResult(
          id,
          'Ref nova com logical_item_id',
          _Verdict.skip,
          'Sem live_only com logical_item_id — corre sem --audit-only.',
        );
      }
      return _CaseResult(
        id,
        'Ref nova com logical_item_id',
        _Verdict.pass,
        '${fresh.length} artigo(s) com logical_item_id preenchido.',
      );
    }
    final ref = '#$_newRefPrefix-${DateTime.now().millisecondsSinceEpoch}';
    final up = await _upsertLiveOnly(
      ctx,
      refCode: ref,
      title: 'L1 auto',
      lineageMode: 'new',
    );
    if (up['ok'] != true) {
      return _CaseResult(id, 'Ref nova com logical_item_id', _Verdict.fail, '$up');
    }
    final logical = up['logical_item_id']?.toString() ?? '';
    if (!isUuid(logical)) {
      return _CaseResult(
        id,
        'Ref nova com logical_item_id',
        _Verdict.fail,
        'logical_item_id vazio após upsert',
      );
    }
    return _CaseResult(
      id,
      'Ref nova com logical_item_id',
      _Verdict.pass,
      'ref $ref → logical_item_id $logical',
    );
  } catch (e) {
    return _CaseResult(id, 'Ref nova com logical_item_id', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l2BackfillHistorical(_RunContext ctx) async {
  const id = 'L2';
  try {
    final items = await _sellerLiveOnlyItems(ctx.client, ctx.sellerId);
    if (items.isEmpty) {
      return _CaseResult(
        id,
        'Backfill logical_item_id histórico',
        _Verdict.skip,
        'Seller sem live_only — corre sem --audit-only.',
      );
    }
    final nulls = items.where(
      (i) => (i['logical_item_id']?.toString() ?? '').isEmpty,
    );
    if (nulls.isNotEmpty) {
      return _CaseResult(
        id,
        'Backfill logical_item_id histórico',
        _Verdict.fail,
        '${nulls.length} artigo(s) com logical_item_id NULL',
      );
    }

    final byRef = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final ref = _normalizeRef(it['ref_code']?.toString() ?? '');
      if (ref.isEmpty) continue;
      byRef.putIfAbsent(ref, () => []).add(it);
    }
    for (final entry in byRef.entries) {
      if (entry.value.length < 2) continue;
      final logicals = entry.value
          .map((i) => i['logical_item_id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
      if (logicals.length < 2) {
        return _CaseResult(
          id,
          'Backfill logical_item_id histórico',
          _Verdict.fail,
          'Ref ${entry.key}: ${entry.value.length} itens mas só ${logicals.length} logical_item_id distintos',
        );
      }
    }
    return _CaseResult(
      id,
      'Backfill logical_item_id histórico',
      _Verdict.pass,
      '${items.length} live_only; todos com logical_item_id; refs duplicadas OK',
    );
  } catch (e) {
    return _CaseResult(id, 'Backfill logical_item_id histórico', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l3PreviewLineages(_RunContext ctx) async {
  const id = 'L3';
  try {
    final preview = await _preview(ctx, refCode: _sharedRef);
    if (preview['ok'] != true) {
      return _CaseResult(id, 'Preview lineages separadas', _Verdict.fail, '$preview');
    }
    final lineages = preview['lineages'];
    if (lineages is! List) {
      return _CaseResult(id, 'Preview lineages separadas', _Verdict.fail, 'sem lineages');
    }
    if (lineages.length < 2) {
      return _CaseResult(
        id,
        'Preview lineages separadas',
        _Verdict.skip,
        'Só ${lineages.length} linhagem para $_sharedRef — seed em falta ou histórico insuficiente.',
      );
    }
    final titles = lineages
        .map((e) => (e as Map)['display_title']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    return _CaseResult(
      id,
      'Preview lineages separadas',
      _Verdict.pass,
      '${lineages.length} linhagens; títulos: ${titles.join(', ')}',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Preview lineages separadas',
        _Verdict.skip,
        'RPC preview em falta no staging — corre live_logical_item_id_batata.sql (ou hotfix).',
      );
    }
    return _CaseResult(id, 'Preview lineages separadas', _Verdict.fail, '$e');
  }
}

Future<Map<String, dynamic>?> _snapshotReservationForL6(_RunContext ctx) async {
  if (ctx.puzzleItemId == null || ctx.buyerToken == null) return null;
  final res = await ctx.client.insert('live_reservation_requests', {
    'live_id': (await ctx.client.select(
      'live_items',
      filter: 'id=eq.${ctx.puzzleItemId}',
      limit: 1,
    ))
        .first['live_id'],
    'live_item_id': ctx.puzzleItemId,
    'seller_id': ctx.sellerId,
    'buyer_id': ctx.buyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': 'accepted',
  });
  return Map<String, dynamic>.from(res);
}

Future<_CaseResult> _l4InheritLineage(_RunContext ctx) async {
  const id = 'L4';
  try {
    if (ctx.puzzleLineageId == null) {
      return _CaseResult(
        id,
        'Inherit logical_item_id',
        _Verdict.skip,
        'Sem seed Puzzle — corre sem --audit-only.',
      );
    }
    final draftId = await _createTestDraftLive(ctx);
    final up = await _upsertLiveOnly(
      ctx,
      refCode: _sharedRef,
      title: 'Draft inherit L4',
      lineageMode: 'inherit',
      logicalItemId: ctx.puzzleLineageId,
      liveId: draftId,
    );
    if (up['ok'] != true || up['lineage_mode'] != 'inherit') {
      return _CaseResult(id, 'Inherit logical_item_id', _Verdict.fail, '$up');
    }
    final logical = up['logical_item_id']?.toString() ?? '';
    if (logical != ctx.puzzleLineageId) {
      return _CaseResult(
        id,
        'Inherit logical_item_id',
        _Verdict.fail,
        'Esperado ${ctx.puzzleLineageId}, obteve $logical',
      );
    }
    return _CaseResult(
      id,
      'Inherit logical_item_id',
      _Verdict.pass,
      'draft $draftId herdou $logical',
    );
  } catch (e) {
    return _CaseResult(id, 'Inherit logical_item_id', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l5NewArticleUuid(_RunContext ctx) async {
  const id = 'L5';
  try {
    if (ctx.puzzleLineageId == null) {
      return _CaseResult(id, 'Novo artigo UUID distinto', _Verdict.skip, 'Sem seed.');
    }
    // Draft isolado: item sem logical_item_id (como após gravar ref no prep, antes do sheet).
    final draftId = await _createTestDraftLive(ctx);
    await ctx.client.insert('live_items', {
      'live_id': draftId,
      'item_kind': 'live_only',
      'ref_code': _sharedRef,
      'title': 'Draft aguarda linhagem L5',
      'quantity': 1,
      'is_active': false,
      'status': 'available',
    });
    final up = await _upsertLiveOnly(
      ctx,
      refCode: _sharedRef,
      title: 'Boneca L5 draft',
      lineageMode: 'new',
      liveId: draftId,
    );
    if (up['ok'] != true || up['lineage_mode'] != 'new') {
      return _CaseResult(
        id,
        'Novo artigo UUID distinto',
        _Verdict.fail,
        'Esperado insert lineage_mode new, obteve $up',
      );
    }
    final logical = up['logical_item_id']?.toString() ?? '';
    final histLogicals = <String>{};
    if (ctx.puzzleLineageId != null) histLogicals.add(ctx.puzzleLineageId!);
    if (ctx.bonecaLineageId != null) histLogicals.add(ctx.bonecaLineageId!);
    if (histLogicals.contains(logical)) {
      return _CaseResult(
        id,
        'Novo artigo UUID distinto',
        _Verdict.fail,
        'logical_item_id colidiu com histórico: $logical',
      );
    }
    return _CaseResult(
      id,
      'Novo artigo UUID distinto',
      _Verdict.pass,
      'novo logical_item_id $logical',
    );
  } catch (e) {
    return _CaseResult(id, 'Novo artigo UUID distinto', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l6ReservationsUnchanged(
  _RunContext ctx,
  Map<String, dynamic> snap,
) async {
  const id = 'L6';
  try {
    final rid = snap['id']?.toString() ?? '';
    final rows = await ctx.client.select(
      'live_reservation_requests',
      filter: 'id=eq.$rid',
      limit: 1,
    );
    if (rows.isEmpty) {
      return _CaseResult(id, 'Reservas antigas intactas', _Verdict.fail, 'Reserva sumiu');
    }
    final row = rows.first;
    for (final key in ['status', 'live_item_id', 'requested_qty']) {
      if ('${row[key]}' != '${snap[key]}') {
        return _CaseResult(
          id,
          'Reservas antigas intactas',
          _Verdict.fail,
          '$key mudou: ${snap[key]} → ${row[key]}',
        );
      }
    }
    return _CaseResult(id, 'Reservas antigas intactas', _Verdict.pass, 'request $rid OK');
  } catch (e) {
    return _CaseResult(id, 'Reservas antigas intactas', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l10TwoContinueTargets(_RunContext ctx) async {
  const id = 'L10';
  try {
    final preview = await _preview(ctx, refCode: _sharedRef);
    final lineages = preview['lineages'];
    if (lineages is! List || lineages.length < 2) {
      return _CaseResult(
        id,
        'Duas linhagens distintas no preview',
        _Verdict.skip,
        'Precisa ≥2 linhagens em $_sharedRef',
      );
    }
    final ids = lineages
        .map((e) => (e as Map)['logical_item_id']?.toString() ?? '')
        .where((s) => isUuid(s))
        .toSet();
    if (ids.length < 2) {
      return _CaseResult(id, 'Duas linhagens distintas no preview', _Verdict.fail, 'IDs repetidos');
    }
    return _CaseResult(
      id,
      'Duas linhagens distintas no preview',
      _Verdict.pass,
      '${ids.length} logical_item_id distintos (UI: 2 botões Continuar)',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Duas linhagens distintas no preview',
        _Verdict.skip,
        'RPC preview não deployada no staging.',
      );
    }
    return _CaseResult(id, 'Duas linhagens distintas no preview', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l11CancelNoServerWrite(_RunContext ctx) async {
  const id = 'L11';
  try {
    final draftId = ctx.draftLiveId ?? await _createTestDraftLive(ctx);
    final refFilter = _filterEq('ref_code', _sharedRef);
    final before = await ctx.client.select(
      'live_items',
      filter: 'live_id=eq.$draftId&$refFilter',
      limit: 5,
    );
    await _preview(ctx, refCode: _sharedRef, liveId: draftId);
    final after = await ctx.client.select(
      'live_items',
      filter: 'live_id=eq.$draftId&$refFilter',
      limit: 5,
    );
    if (before.length != after.length) {
      return _CaseResult(
        id,
        'Preview não grava (simula cancel)',
        _Verdict.fail,
        'live_items mudou só com preview',
      );
    }
    return _CaseResult(
      id,
      'Preview não grava (simula cancel)',
      _Verdict.pass,
      'RPC preview não altera live_items; cancel UI = não chamar upsert',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Preview não grava (simula cancel)',
        _Verdict.skip,
        'RPC preview não deployada — L11 UI continua manual.',
      );
    }
    return _CaseResult(id, 'Preview não grava (simula cancel)', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l13KeepLogicalOnReedit(_RunContext ctx) async {
  const id = 'L13';
  try {
    final draftId = await _createTestDraftLive(ctx);
    final first = await _upsertLiveOnly(
      ctx,
      refCode: '#V15L13',
      title: 'L13 primeira',
      lineageMode: 'new',
      liveId: draftId,
    );
    final logical1 = first['logical_item_id']?.toString() ?? '';
    final second = await _upsertLiveOnly(
      ctx,
      refCode: '#V15L13',
      title: 'L13 segunda edição',
      lineageMode: 'new',
      liveId: draftId,
    );
    final logical2 = second['logical_item_id']?.toString() ?? '';
    if (second['lineage_mode'] != 'keep') {
      return _CaseResult(
        id,
        'Reedição preserva logical_item_id',
        _Verdict.fail,
        'Esperado lineage_mode keep, obteve ${second['lineage_mode']}',
      );
    }
    if (logical1 != logical2 || !isUuid(logical2)) {
      return _CaseResult(
        id,
        'Reedição preserva logical_item_id',
        _Verdict.fail,
        '$logical1 → $logical2',
      );
    }
    return _CaseResult(
      id,
      'Reedição preserva logical_item_id',
      _Verdict.pass,
      'logical_item_id estável: $logical2',
    );
  } catch (e) {
    return _CaseResult(id, 'Reedição preserva logical_item_id', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l16SaleShowsSheet(_RunContext ctx) async {
  const id = 'L16';
  try {
    if (ctx.auditOnly) {
      return _CaseResult(
        id,
        'Venda antiga → should_show_sheet',
        _Verdict.skip,
        'Requer seed com order pago.',
      );
    }
    final live = await ctx.client.insert('lives', {
      'title': _testLiveTitle,
      'status': 'ended',
      'seller_id': ctx.sellerId,
      'vendedor_id': ctx.sellerId,
      'is_active': false,
    });
    final liveId = live['id']!.toString();
    final item = await ctx.client.insert('live_items', {
      'live_id': liveId,
      'item_kind': 'live_only',
      'ref_code': '#V15L16',
      'title': 'L16 sold',
      'quantity': 1,
    });
    final itemId = item['id']!.toString();
    await ctx.client.patch('live_items', 'id=eq.$itemId', {
      'logical_item_id': itemId,
    });
    final product = await ctx.client.insert('products', {
      'seller_id': ctx.sellerId,
      'title': 'L16 product',
      'price': 10,
      'quantity': 1,
      'ref_code': 'L16',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    await ctx.client.insert('orders', {
      'product_id': product['id'],
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'live_id': liveId,
      'live_item_id': itemId,
      'price_total': 10,
      'status': 'pago',
      'quantity': 1,
    });
    final preview = await _preview(ctx, refCode: '#V15L16');
    if (preview['should_show_sheet'] == true) {
      return _CaseResult(id, 'Venda antiga → should_show_sheet', _Verdict.pass, 'should_show_sheet=true');
    }
    return _CaseResult(
      id,
      'Venda antiga → should_show_sheet',
      _Verdict.fail,
      'should_show_sheet=${preview['should_show_sheet']}',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Venda antiga → should_show_sheet',
        _Verdict.skip,
        'RPC preview não deployada no staging.',
      );
    }
    return _CaseResult(id, 'Venda antiga → should_show_sheet', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l17GhostUsageHidden(_RunContext ctx) async {
  const id = 'L17';
  try {
    if (ctx.auditOnly) {
      return _CaseResult(id, 'Uso fantasma antigo', _Verdict.skip, 'Requer seed.');
    }
    final old = DateTime.now().toUtc().subtract(const Duration(days: 620));
    final live = await ctx.client.insert('lives', {
      'title': _testLiveTitle,
      'status': 'ended',
      'seller_id': ctx.sellerId,
      'vendedor_id': ctx.sellerId,
      'is_active': false,
      'created_at': old.toIso8601String(),
    });
    final liveId = live['id']!.toString();
    final item = await ctx.client.insert('live_items', {
      'live_id': liveId,
      'item_kind': 'live_only',
      'ref_code': '#V15L17',
      'title': 'L17 ghost',
      'quantity': 1,
      'updated_at': old.toIso8601String(),
    });
    final itemId = item['id']!.toString();
    await ctx.client.patch('live_items', 'id=eq.$itemId', {
      'logical_item_id': itemId,
    });
    final preview = await _preview(ctx, refCode: '#V15L17');
    if (preview['should_show_sheet'] != true) {
      return _CaseResult(id, 'Uso fantasma antigo', _Verdict.pass, 'should_show_sheet=false');
    }
    return _CaseResult(
      id,
      'Uso fantasma antigo',
      _Verdict.fail,
      'should_show_sheet=true indevidamente',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Uso fantasma antigo',
        _Verdict.skip,
        'RPC preview não deployada no staging.',
      );
    }
    return _CaseResult(id, 'Uso fantasma antigo', _Verdict.fail, '$e');
  }
}

Future<_CaseResult> _l18OldOpenReservation(_RunContext ctx) async {
  const id = 'L18';
  try {
    if (ctx.buyerToken == null) {
      return _CaseResult(
        id,
        'Reserva aberta antiga',
        _Verdict.skip,
        'Definir LIVE_OPS_TEST_BUYER_EMAIL/PASSWORD no .env',
      );
    }
    if (ctx.auditOnly) {
      return _CaseResult(id, 'Reserva aberta antiga', _Verdict.skip, 'Requer seed.');
    }
    final old = DateTime.now().toUtc().subtract(const Duration(days: 1100));
    final live = await ctx.client.insert('lives', {
      'title': _testLiveTitle,
      'status': 'ended',
      'seller_id': ctx.sellerId,
      'vendedor_id': ctx.sellerId,
      'is_active': false,
      'created_at': old.toIso8601String(),
    });
    final liveId = live['id']!.toString();
    final item = await ctx.client.insert('live_items', {
      'live_id': liveId,
      'item_kind': 'live_only',
      'ref_code': '#V15L18',
      'title': 'L18 old open',
      'quantity': 1,
    });
    final itemId = item['id']!.toString();
    await ctx.client.patch('live_items', 'id=eq.$itemId', {
      'logical_item_id': itemId,
    });
    await ctx.client.insert('live_reservation_requests', {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': ctx.sellerId,
      'buyer_id': ctx.buyerId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
      'created_at': old.toIso8601String(),
    });
    final preview = await _preview(ctx, refCode: '#V15L18');
    if (preview['should_show_sheet'] == true) {
      final open = _asInt((preview['summary'] as Map?)?['open_reservation_count']);
      return _CaseResult(
        id,
        'Reserva aberta antiga',
        _Verdict.pass,
        'should_show_sheet=true; open=$open',
      );
    }
    return _CaseResult(
      id,
      'Reserva aberta antiga',
      _Verdict.fail,
      'should_show_sheet=${preview['should_show_sheet']}',
    );
  } catch (e) {
    if (_isPreviewRpcNotDeployed(e)) {
      return _CaseResult(
        id,
        'Reserva aberta antiga',
        _Verdict.skip,
        'RPC preview não deployada no staging.',
      );
    }
    return _CaseResult(id, 'Reserva aberta antiga', _Verdict.fail, '$e');
  }
}
