// ignore_for_file: avoid_print
/// Regressão controlada SEC-013 — homónimos sem contas Facebook falsas.
///
/// Pré-condição: duas reservas reais facebook_manual na mesma live com
///   external_buyer_ref distintos (fb:A e fb:B).
///
/// Este script:
/// 1) põe o mesmo external_display_name ("João Silva") em ambas;
/// 2) verifica que as refs fb: permanecem distintas;
/// 3) documenta o esperado para claims (não executa claim sem tokens A/B).
///
/// Uso:
///   dart run tool/ps_sec013_homonym_controlled_regression.dart --live-id=UUID
///
/// Só correr DEPOIS de GATE 1 = SIM e binding claim aplicado.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  String? liveId;
  var apply = false;
  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.substring(10).trim();
    if (a == '--apply') apply = true;
  }
  if (liveId == null || liveId.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/ps_sec013_homonym_controlled_regression.dart --live-id=UUID [--apply]',
    );
    exit(2);
  }

  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final rows = await sb.select(
    'live_reservation_requests',
    filter:
        'live_id=eq.$liveId&source=eq.facebook_manual&buyer_id=is.null',
    limit: 50,
  );

  final fbRows = rows
      .where((r) => (r['external_buyer_ref'] ?? '').toString().startsWith('fb:'))
      .toList();

  if (fbRows.length < 2) {
    stderr.writeln(
      'Preciso de ≥2 reservas órfãs com external_buyer_ref fb:* nesta live (tenho ${fbRows.length}).',
    );
    exit(3);
  }

  // Escolher 2 refs distintas
  final byRef = <String, Map<String, dynamic>>{};
  for (final r in fbRows) {
    final ref = r['external_buyer_ref']?.toString() ?? '';
    if (ref.isEmpty) continue;
    byRef.putIfAbsent(ref, () => r);
  }
  if (byRef.length < 2) {
    stderr.writeln('Refs fb: não são distintas o suficiente: ${byRef.keys}');
    exit(4);
  }

  final refs = byRef.keys.take(2).toList();
  final a = byRef[refs[0]]!;
  final b = byRef[refs[1]]!;
  const homonym = 'João Silva';

  final report = <String, dynamic>{
    'test': 'SEC013_HOMONYM_CONTROLLED',
    'live_id': liveId,
    'before': {
      'A': {
        'id': a['id'],
        'external_buyer_ref': a['external_buyer_ref'],
        'external_display_name': a['external_display_name'],
      },
      'B': {
        'id': b['id'],
        'external_buyer_ref': b['external_buyer_ref'],
        'external_display_name': b['external_display_name'],
      },
    },
    'apply': apply,
    'expected_after_name_rewrite': {
      'same_display_name': homonym,
      'refs_remain_distinct': true,
      'claim_must_use_fb_ref_not_name': true,
      'cross_claim_A_to_B': 0,
      'cross_claim_B_to_A': 0,
    },
  };

  if (apply) {
    await sb.patch(
      'live_reservation_requests',
      'id=eq.${a['id']}',
      {'external_display_name': homonym},
    );
    await sb.patch(
      'live_reservation_requests',
      'id=eq.${b['id']}',
      {'external_display_name': homonym},
    );
    final after = await sb.select(
      'live_reservation_requests',
      filter: 'id=in.(${a['id']},${b['id']})',
      limit: 10,
    );
    report['after'] = after;
    report['names_equal'] = after.every(
      (r) => (r['external_display_name'] ?? '') == homonym,
    );
    report['refs_still_distinct'] =
        after.map((r) => r['external_buyer_ref']).toSet().length == 2;
  } else {
    report['hint'] =
        'Reexecuta com --apply para escrever "$homonym" nos dois display_name. '
        'Depois claim manual com contas Fleaber A/B (Facebook Login) e regista cruzados=0.';
  }

  final outDir = Directory('tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas');
  outDir.createSync(recursive: true);
  final outFile = File('${outDir.path}/SEC013_homonym_controlled_LATEST.json');
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print(const JsonEncoder.withIndent('  ').convert(report));
  print('\nEscrito: ${outFile.path}');
}
