// ignore_for_file: avoid_print
/// GATE 1 — Comparar ID capturado pelo PS (DOM Face) com OAuth Facebook (auth.identities).
///
/// Uso:
///   dart run tool/ps_gate1_dom_vs_oauth.dart --email=... 
///   dart run tool/ps_gate1_dom_vs_oauth.dart --uid=...
///   dart run tool/ps_gate1_dom_vs_oauth.dart --email=... --probe=tool/ps_ai/runs/author_identity_YYYY-MM-DD.json
///
/// Resposta explícita no JSON de saída: dom_id_equals_oauth_provider_id: true|false|null
///
/// NÃO aplica claim. Só prova compatibilidade de identificadores.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  String? email;
  String? uid;
  String? probePath;
  String? nameHint;
  for (final a in args) {
    if (a.startsWith('--email=')) email = a.substring(8).trim();
    if (a.startsWith('--uid=')) uid = a.substring(6).trim();
    if (a.startsWith('--probe=')) probePath = a.substring(8).trim();
    if (a.startsWith('--name=')) nameHint = a.substring(7).trim();
  }

  probePath ??= _latestProbePath();
  if ((email == null || email.isEmpty) && (uid == null || uid.isEmpty)) {
    stderr.writeln(
      'Uso: dart run tool/ps_gate1_dom_vs_oauth.dart --email=USER@... [--probe=path.json]\n'
      '  ou: --uid=UUID [--probe=...] [--name=NomeFace]',
    );
    exit(2);
  }

  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final serviceRoleKey = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');

  final authUser = await _adminUser(
    url: url,
    serviceRoleKey: serviceRoleKey,
    email: email,
    uid: uid,
  );
  if (authUser == null) {
    stderr.writeln('Utilizador não encontrado (email/uid).');
    exit(3);
  }

  final identities = (authUser['identities'] as List?) ?? const [];
  final fbIdentities = identities
      .whereType<Map>()
      .where((i) => (i['provider']?.toString() ?? '') == 'facebook')
      .map((i) => Map<String, dynamic>.from(i))
      .toList();

  final oauth = <Map<String, dynamic>>[];
  for (final i in fbIdentities) {
    final data = i['identity_data'];
    final dataMap = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    oauth.add({
      'provider': i['provider'],
      'provider_id': i['provider_id']?.toString(),
      'identity_data_id': dataMap['id']?.toString(),
      'identity_data_user_id': dataMap['user_id']?.toString(),
      'identity_data_sub': dataMap['sub']?.toString(),
      'identity_data_name': dataMap['name']?.toString() ?? dataMap['full_name']?.toString(),
      'identity_data_email': dataMap['email']?.toString(),
    });
  }

  final probe = await _loadProbe(probePath);
  final domAuthors = _extractDomAuthors(probe, nameHint: nameHint);

  final oauthIds = <String>{};
  for (final o in oauth) {
    for (final k in ['provider_id', 'identity_data_id', 'identity_data_user_id', 'identity_data_sub']) {
      final v = (o[k] ?? '').toString().trim();
      if (v.isNotEmpty) oauthIds.add(v);
    }
  }

  final domNumeric = <String>{};
  final domVanity = <String>{};
  for (final a in domAuthors) {
    final id = (a['profile_id_guess'] ?? '').toString().trim();
    if (RegExp(r'^\d{5,}$').hasMatch(id)) {
      domNumeric.add(id);
    } else if (id.isNotEmpty) {
      domVanity.add(id.toLowerCase());
    }
    final href = (a['profile_href'] ?? '').toString();
    final m = RegExp(r'[?&]id=(\d{5,})').firstMatch(href);
    if (m != null) domNumeric.add(m.group(1)!);
  }

  bool? equals;
  String relation;
  if (oauthIds.isEmpty) {
    equals = null;
    relation = 'no_facebook_oauth_identity — faz Facebook Login nesta conta Fleaber primeiro';
  } else if (domNumeric.isEmpty && domVanity.isEmpty) {
    equals = null;
    relation = 'no_dom_ids — corre PS «Sondar identidade» com esta conta a comentar na Live';
  } else if (domNumeric.any(oauthIds.contains)) {
    equals = true;
    relation = 'DOM numeric id ∈ OAuth provider_id/identity_data — match directo possível';
  } else if (domVanity.isNotEmpty && oauthIds.isNotEmpty) {
    equals = false;
    relation =
        'DOM só vanity (fb:u:…) vs OAuth numérico — sem mapping seguro; NÃO claim automático por vanity';
  } else {
    equals = false;
    relation =
        'DOM numeric e OAuth ids disjuntos — NÃO assumir igualdade; mapear relação antes do claim';
  }

  final out = {
    'gate': 'GATE1_DOM_VS_OAUTH',
    'at': DateTime.now().toUtc().toIso8601String(),
    'fleaber_user': {
      'id': authUser['id'],
      'email': authUser['email'],
    },
    'oauth_facebook': oauth,
    'oauth_ids_flat': oauthIds.toList()..sort(),
    'probe_path': probePath,
    'dom_authors': domAuthors,
    'dom_numeric_ids': domNumeric.toList()..sort(),
    'dom_vanity_ids': domVanity.toList()..sort(),
    'dom_id_equals_oauth_provider_id': equals,
    'relation': relation,
    'verdict_pt': equals == true
        ? 'SIM — DOM ID numérico compatível com OAuth provider_id (nesta amostra).'
        : equals == false
            ? 'NÃO — IDs não coincidem (ou vanity≠numérico). Determinar relação antes do claim.'
            : 'INCONCLUSIVO — falta OAuth Facebook e/ou sonda DOM desta conta.',
    'next': equals == true
        ? 'Pode avançar para binding claim fb:{id}↔provider_id e teste A/B.'
        : 'Não aplicar / não considerar definitivo sec_013_claim_fb_identity até haver SIM.',
  };

  final outDir = Directory('tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas');
  outDir.createSync(recursive: true);
  final outFile = File(
    '${outDir.path}/GATE1_dom_vs_oauth_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json',
  );
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  // ponteiro estável
  File('${outDir.path}/GATE1_dom_vs_oauth_LATEST.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  print(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: ${outFile.path}');
  print('Resposta explícita: DOM ID = OAuth provider_id? ${out['verdict_pt']}');
}

Future<Map<String, dynamic>?> _adminUser({
  required String url,
  required String serviceRoleKey,
  String? email,
  String? uid,
}) async {
  if (uid != null && uid.isNotEmpty) {
    final res = await http.get(
      Uri.parse('$url/auth/v1/admin/users/$uid'),
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    if (res.statusCode >= 400) return null;
    final map = jsonDecode(res.body);
    return map is Map ? Map<String, dynamic>.from(map) : null;
  }

  // Listagem por email (Admin API)
  final res = await http.get(
    Uri.parse('$url/auth/v1/admin/users?page=1&per_page=200'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
    },
  );
  if (res.statusCode >= 400) {
    stderr.writeln('admin users ${res.statusCode}: ${res.body}');
    return null;
  }
  final body = jsonDecode(res.body);
  final users = body is Map ? (body['users'] as List? ?? const []) : const [];
  final want = email!.toLowerCase();
  for (final u in users) {
    if (u is! Map) continue;
    if ((u['email']?.toString() ?? '').toLowerCase() == want) {
      return Map<String, dynamic>.from(u);
    }
  }
  return null;
}

Future<Map<String, dynamic>?> _loadProbe(String? path) async {
  if (path == null || path.isEmpty) return null;
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('Probe não encontrado: $path');
    return null;
  }
  final map = jsonDecode(await f.readAsString());
  return map is Map ? Map<String, dynamic>.from(map) : null;
}

List<Map<String, dynamic>> _extractDomAuthors(
  Map<String, dynamic>? probe, {
  String? nameHint,
}) {
  if (probe == null) return const [];
  final samples = probe['samples'];
  if (samples is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final s in samples) {
    if (s is! Map) continue;
    final m = Map<String, dynamic>.from(s);
    if (nameHint != null && nameHint.isNotEmpty) {
      final n = (m['name_hint'] ?? '').toString().toLowerCase();
      if (!n.contains(nameHint.toLowerCase())) continue;
    }
    out.add({
      'name_hint': m['name_hint'],
      'profile_href': m['profile_href'],
      'profile_id_guess': m['profile_id_guess'],
      'avatar_src': (m['avatar_src'] ?? '').toString().isNotEmpty,
    });
  }
  return out;
}

String? _latestProbePath() {
  final candidates = [
    'tool/ps_ai/runs/author_identity_${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.json',
    'tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas/author_identity_2026-08-24.json',
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) return p;
  }
  final runs = Directory('tool/ps_ai/runs');
  if (!runs.existsSync()) return null;
  final files = runs
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('author_identity') && f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files.isEmpty ? null : files.first.path;
}
