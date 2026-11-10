// ignore_for_file: avoid_print
/// Reteste auditor C23 — SEC-022 / 023 / 024 com schema real.
/// Não altera código produto.
///
///   dart run tool/c23_sec_022_023_024_retest.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main() async {
  final outDir =
      Directory('tool/reports/battery_c23_sec_2026-08-20/retest_auditor');
  outDir.createSync(recursive: true);
  final logFile = File('${outDir.path}/retest_022_023_024.log');
  final sink = logFile.openWrite();
  void log(String m) {
    final line = '[${DateTime.now().toIso8601String()}] $m';
    print(line);
    sink.writeln(line);
  }

  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final service = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final buyerTok = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(buyerTok);
  final sellerId = await client.userIdForAccessToken(sellerTok);
  log('buyer=$buyerId seller=$sellerId');

  Map<String, String> anonH() => {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> userH(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> serviceH() => {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  bool isSchemaError(String body) {
    final b = body.toLowerCase();
    return b.contains('could not find') && b.contains('column');
  }

  /// Bloqueio de segurança (RLS / privilege), NÃO schema inválido.
  bool isSecurityBlock(http.Response r) {
    if (isSchemaError(r.body)) return false;
    final b = r.body.toLowerCase();
    if (r.statusCode == 401 || r.statusCode == 403) return true;
    if (b.contains('row-level security') ||
        b.contains('violates row-level security') ||
        b.contains('permission denied') ||
        b.contains('42501') ||
        b.contains('new row violates') ||
        b.contains('rls')) {
      return true;
    }
    // PostgREST: revoke INSERT → often 401/403 with permission denied
    if (r.statusCode >= 400 &&
        (b.contains('permission') ||
            b.contains('not allowed') ||
            b.contains('unauthorized') ||
            b.contains('jwt'))) {
      return true;
    }
    return false;
  }

  String? idFromRep(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) return null;
    try {
      final body = jsonDecode(r.body);
      if (body is List && body.isNotEmpty) {
        return (body.first as Map)['id']?.toString();
      }
      if (body is Map) return body['id']?.toString();
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // SEC-022
  // ═══════════════════════════════════════════════════════════
  log('--- APP-SEC-022');
  final marker022 = 'c23_sec022_${DateTime.now().millisecondsSinceEpoch}';
  final validAppLogRow = {
    'category': 'sec.probe',
    'error_message': marker022,
    'stack_trace': null,
    'device_info': {'probe': true, 'battery': 'c23_retest'},
  };

  // Controlo positivo schema: service_role (não depende de RLS cliente)
  final svcInsert022 = await http.post(
    Uri.parse('$url/rest/v1/app_logs'),
    headers: serviceH(),
    body: jsonEncode(validAppLogRow),
  );
  final svcId022 = idFromRep(svcInsert022);
  final schemaOk = svcInsert022.statusCode >= 200 &&
      svcInsert022.statusCode < 300 &&
      svcId022 != null &&
      !isSchemaError(svcInsert022.body);

  // Observação: authenticated (não é o ataque SEC-022, mas documenta staging)
  final authInsert022 = await http.post(
    Uri.parse('$url/rest/v1/app_logs'),
    headers: userH(buyerTok),
    body: jsonEncode({
      ...validAppLogRow,
      'error_message': '${marker022}_auth',
    }),
  );

  // Ataque anon — mesmo schema que service aceitou
  final anonInsert022 = await http.post(
    Uri.parse('$url/rest/v1/app_logs'),
    headers: anonH(),
    body: jsonEncode({
      ...validAppLogRow,
      'error_message': '${marker022}_anon',
    }),
  );
  final anonId022 = idFromRep(anonInsert022);
  final anonSec = isSecurityBlock(anonInsert022);
  final anonMsg = anonInsert022.body.toLowerCase();
  final anonIsPrivilege = anonMsg.contains('permission denied') ||
      anonMsg.contains('42501') ||
      anonInsert022.statusCode == 401 ||
      anonInsert022.statusCode == 403;

  if (svcId022 != null) {
    try {
      await client.deleteWhere('app_logs', 'id=eq.$svcId022');
    } catch (e) {
      log('cleanup 022 svc: $e');
    }
  }
  final authId022 = idFromRep(authInsert022);
  if (authId022 != null) {
    try {
      await client.deleteWhere('app_logs', 'id=eq.$authId022');
    } catch (_) {}
  }

  final pass022 = schemaOk &&
      anonSec &&
      anonIsPrivilege &&
      anonId022 == null &&
      !isSchemaError(anonInsert022.body);

  final result022 = {
    'id': 'APP-SEC-022',
    'status': pass022 ? 'PASS' : 'FAIL',
    'estado_inicial': {
      'note': 'Schema provado via service_role INSERT (tabela app_logs grande).',
      'marker': marker022,
    },
    'dados_cenario': {
      'valid_row_columns': validAppLogRow.keys.toList(),
      'service_schema_control': {
        'http': svcInsert022.statusCode,
        'id': svcId022,
        'body_snip': svcInsert022.body.length > 280
            ? svcInsert022.body.substring(0, 280)
            : svcInsert022.body,
        'schema_valid': schemaOk,
      },
      'auth_observation': {
        'http': authInsert022.statusCode,
        'body': authInsert022.body,
        'note':
            'Não é o ataque SEC-022. Se 403 RLS, é observação de staging '
            '(app logging); o ataque alvo é anon.',
      },
    },
    'ataque_exato': {
      'method': 'POST',
      'path': '/rest/v1/app_logs',
      'role': 'anon (apikey=anon, Authorization=Bearer anon)',
      'body': {...validAppLogRow, 'error_message': '${marker022}_anon'},
    },
    'resposta_bruta': {
      'status': anonInsert022.statusCode,
      'body': anonInsert022.body,
      'returned_id': anonId022,
      'is_schema_error': isSchemaError(anonInsert022.body),
      'is_security_block': anonSec,
      'is_privilege_revoke': anonIsPrivilege,
    },
    'estado_final': {
      'service_row_deleted': svcId022 != null,
      'anon_created_row': anonId022 != null,
    },
    'mecanismo':
        'REVOKE INSERT ON public.app_logs FROM anon '
        '(sec_low_hardening_batata.sql). Resposta: permission denied / 42501 — '
        'não é erro de coluna.',
    'assert':
        'Service INSERT com colunas reais → 2xx. Anon INSERT mesmo schema → '
        'permission denied (privilege), sem linha criada, sem schema-error.',
    'pass': pass022,
  };
  log('SEC-022 → ${result022['status']} svc=${svcInsert022.statusCode} '
      'auth_obs=${authInsert022.statusCode} anon=${anonInsert022.statusCode} '
      'schema_err=${isSchemaError(anonInsert022.body)} sec=$anonSec');

  // ═══════════════════════════════════════════════════════════
  // SEC-023
  // ═══════════════════════════════════════════════════════════
  log('--- APP-SEC-023');
  final lives = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 1,
  );
  final liveId023 = lives.isEmpty ? null : lives.first['id']?.toString();
  // request_id é uuid na BD (não text)
  final reqSeller023 = 'c2300001-0000-4000-8000-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0').substring(0, 12)}';
  final reqAttack023 = 'c2300002-0000-4000-8000-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0').substring(0, 12)}';

  Map<String, dynamic> studioRow({
    required String actor,
    required String requestId,
    required String event,
  }) =>
      {
        'live_id': liveId023,
        'seller_id': sellerId,
        'actor_id': actor,
        'live_item_id': null,
        'request_id': requestId,
        'event': event,
        'status': 'ok',
        'detail': {'probe': true, 'battery': 'c23_retest'},
        'error_message': null,
      };

  String? sellerLogId;
  String? attackLogId;

  Map<String, dynamic> result023;
  if (liveId023 == null) {
    result023 = {
      'id': 'APP-SEC-023',
      'status': 'FAIL',
      'pass': false,
      'assert': 'sem live do seller',
    };
  } else {
    final sellerBody =
        studioRow(actor: sellerId, requestId: reqSeller023, event: 'c23_ok');
    final sellerIns = await http.post(
      Uri.parse('$url/rest/v1/live_vendor_studio_logs'),
      headers: userH(sellerTok),
      body: jsonEncode(sellerBody),
    );
    sellerLogId = idFromRep(sellerIns);
    final sellerOk = sellerIns.statusCode >= 200 &&
        sellerIns.statusCode < 300 &&
        sellerLogId != null &&
        !isSchemaError(sellerIns.body);

    final attackBody =
        studioRow(actor: buyerId, requestId: reqAttack023, event: 'c23_spoof');
    final attack = await http.post(
      Uri.parse('$url/rest/v1/live_vendor_studio_logs'),
      headers: userH(buyerTok),
      body: jsonEncode(attackBody),
    );
    attackLogId = idFromRep(attack);
    final attackSec = isSecurityBlock(attack);

    // Estado final via service GET by request_id (indexed-ish / small table)
    final svcAttackRows = await http.get(
      Uri.parse(
        '$url/rest/v1/live_vendor_studio_logs?request_id=eq.$reqAttack023&select=id,seller_id,actor_id&limit=5',
      ),
      headers: serviceH(),
    );
    List svcAttackList = [];
    try {
      svcAttackList = jsonDecode(svcAttackRows.body) as List? ?? [];
    } catch (_) {}

    if (sellerLogId != null) {
      try {
        await client.deleteWhere(
          'live_vendor_studio_logs',
          'id=eq.$sellerLogId',
        );
      } catch (e) {
        log('cleanup seller log: $e');
      }
    }
    if (attackLogId != null) {
      try {
        await client.deleteWhere(
          'live_vendor_studio_logs',
          'id=eq.$attackLogId',
        );
      } catch (_) {}
    }

    final pass023 = sellerOk &&
        attackSec &&
        attackLogId == null &&
        svcAttackList.isEmpty &&
        !isSchemaError(attack.body);

    result023 = {
      'id': 'APP-SEC-023',
      'status': pass023 ? 'PASS' : 'FAIL',
      'estado_inicial': {
        'live_id': liveId023,
        'request_id_seller': reqSeller023,
        'request_id_attack': reqAttack023,
      },
      'dados_cenario': {
        'valid_row_columns': sellerBody.keys.toList(),
        'seller_control': {
          'http': sellerIns.statusCode,
          'id': sellerLogId,
          'body_snip': sellerIns.body.length > 280
              ? sellerIns.body.substring(0, 280)
              : sellerIns.body,
          'schema_valid': sellerOk,
        },
      },
      'ataque_exato': {
        'method': 'POST',
        'path': '/rest/v1/live_vendor_studio_logs',
        'role': 'buyer JWT',
        'body': attackBody,
      },
      'resposta_bruta': {
        'status': attack.statusCode,
        'body': attack.body,
        'returned_id': attackLogId,
        'is_schema_error': isSchemaError(attack.body),
        'is_security_block': attackSec,
      },
      'estado_final': {
        'service_rows_for_attack_request_id': svcAttackList.length,
        'service_body': svcAttackRows.body.length > 200
            ? svcAttackRows.body.substring(0, 200)
            : svcAttackRows.body,
      },
      'mecanismo':
          'RLS live_vendor_studio_logs_insert WITH CHECK: actor_id=auth.uid() e '
          '(seller_id null|próprio|helper aceite). Buyer com seller_id alheio → RLS.',
      'assert':
          'Seller INSERT schema-válido OK. Buyer spoof falha por RLS (não schema) '
          'e service confirma 0 linhas do ataque.',
      'pass': pass023,
    };
    log('SEC-023 → ${result023['status']} seller=${sellerIns.statusCode} '
        'attack=${attack.statusCode} schema_err=${isSchemaError(attack.body)} '
        'sec=$attackSec svc_attack_rows=${svcAttackList.length}');
  }

  // ═══════════════════════════════════════════════════════════
  // SEC-024 — viewers reais (FK auth.users): buyer + seller na mesma live
  // ═══════════════════════════════════════════════════════════
  log('--- APP-SEC-024');
  final sellerLives = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&order=created_at.desc',
    limit: 5,
  );
  final liveId024 =
      sellerLives.isEmpty ? null : sellerLives.first['id']?.toString();

  final seeded024 = <String>[];
  late final Map<String, dynamic> result024;

  if (liveId024 == null) {
    result024 = {
      'id': 'APP-SEC-024',
      'status': 'FAIL',
      'pass': false,
      'assert': 'sem live do seller',
    };
  } else {
    Future<List<Map<String, dynamic>>> svcViewers() async {
      final r = await http.get(
        Uri.parse(
          '$url/rest/v1/live_viewers?live_id=eq.$liveId024&select=user_id,last_seen_at&limit=50',
        ),
        headers: serviceH(),
      );
      if (r.statusCode >= 400) {
        throw HttpException('svc viewers ${r.statusCode}: ${r.body}');
      }
      final list = jsonDecode(r.body);
      if (list is! List) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    Future<void> ensureViewer(String uid) async {
      final r = await http.get(
        Uri.parse(
          '$url/rest/v1/live_viewers?live_id=eq.$liveId024&user_id=eq.$uid&select=user_id&limit=1',
        ),
        headers: serviceH(),
      );
      final list = jsonDecode(r.body);
      final exists = list is List && list.isNotEmpty;
      if (exists) return;
      await http.post(
        Uri.parse('$url/rest/v1/live_viewers'),
        headers: serviceH(),
        body: jsonEncode({
          'live_id': liveId024,
          'user_id': uid,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      seeded024.add(uid);
    }

    final initial = await svcViewers();
    await ensureViewer(buyerId);
    await ensureViewer(sellerId); // "outro" viewer real (FK OK)
    final afterSeed = await svcViewers();
    final serviceIds = afterSeed
        .map((e) => e['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final others =
        serviceIds.where((id) => id != buyerId).toList();

    final buyerSel = await http.get(
      Uri.parse(
        '$url/rest/v1/live_viewers?live_id=eq.$liveId024&select=*&limit=50',
      ),
      headers: userH(buyerTok),
    );
    List buyerList = [];
    try {
      buyerList = jsonDecode(buyerSel.body) as List? ?? [];
    } catch (_) {}
    final buyerSeen = buyerList
        .whereType<Map>()
        .map((e) => e['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final leaked = buyerSeen.where((id) => id != buyerId).toList();

    final pass024 = others.isNotEmpty &&
        serviceIds.contains(buyerId) &&
        serviceIds.contains(sellerId) &&
        buyerSel.statusCode >= 200 &&
        buyerSel.statusCode < 300 &&
        leaked.isEmpty &&
        buyerSeen.every((id) => id == buyerId);

    // Cleanup only seeded rows
    for (final uid in seeded024) {
      try {
        await client.deleteWhere(
          'live_viewers',
          'live_id=eq.$liveId024&user_id=eq.$uid',
        );
      } catch (e) {
        log('cleanup viewer $uid: $e');
      }
    }

    result024 = {
      'id': 'APP-SEC-024',
      'status': pass024 ? 'PASS' : 'FAIL',
      'estado_inicial': {
        'live_id': liveId024,
        'service_count': initial.length,
        'service_user_ids':
            initial.map((e) => e['user_id']?.toString()).toList(),
      },
      'dados_cenario': {
        'service_count_after_seed': afterSeed.length,
        'service_user_ids': serviceIds.toList(),
        'other_viewers_exist': others.isNotEmpty,
        'other_user_ids': others,
        'seeded': seeded024,
        'note':
            'Viewers reais buyer+seller (FK auth.users). Service prova ≥1 outro.',
      },
      'ataque_exato': {
        'method': 'GET',
        'path':
            '/rest/v1/live_viewers?live_id=eq.$liveId024&select=*&limit=50',
        'role': 'buyer JWT',
      },
      'resposta_bruta': {
        'status': buyerSel.statusCode,
        'body': buyerSel.body,
        'buyer_seen_user_ids': buyerSeen.toList(),
        'leaked_other_user_ids': leaked,
      },
      'estado_final': {
        'buyer_visible_only_self':
            leaked.isEmpty && buyerSeen.every((id) => id == buyerId),
        'others_confirmed_by_service': others,
      },
      'mecanismo':
          'RLS live_viewers_select_scoped: user_id=auth.uid() OR dono/staff da live. '
          'Buyer não-dono só vê a própria linha; seller (outro) fica invisível.',
      'assert':
          'Service mostra buyer+seller na live; buyer SELECT não lista seller '
          'nem outros user_ids.',
      'pass': pass024,
    };
    log('SEC-024 → ${result024['status']} service_others=${others.length} '
        'buyer_seen=${buyerSeen.length} leaked=${leaked.length}');
  }

  final pack = {
    'battery': 'C23_SEC_RETEST_AUDITOR_022_023_024',
    'date': DateTime.now().toIso8601String(),
    'note':
        'Desenho corrigido após auditor: colunas reais + controlo positivo + '
        'baseline service para viewers. Sem alteração código Fleaber.',
    'auditor_prior_classification': {
      '022': 'NÃO PROVADO',
      '023': 'NÃO PROVADO',
      '024': 'NÃO PROVADO',
    },
    'results': [result022, result023, result024],
  };

  final jsonOut = File('${outDir.path}/retest_022_023_024_results.json');
  jsonOut.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(pack),
  );
  log('wrote ${jsonOut.path}');
  await sink.close();

  final fails = [result022, result023, result024]
      .where((r) => r['pass'] != true)
      .length;
  exit(fails > 0 ? 2 : 0);
}
