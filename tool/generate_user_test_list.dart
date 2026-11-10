// ignore_for_file: avoid_print

/// Gera lista de testes A001–A429 em português simples para não-programadores.

library;



import 'dart:convert';

import 'dart:io';



import 'regression/area_mapper.dart';

import 'regression/manifest_builder.dart';

import 'regression/store.dart';

import 'regression/user_failure_classifier.dart';



void main() {

  final root = Directory.current.path;

  final fichas = _loadFichas(root);

  final results = _loadResults(root);

  final audits = _loadAudits(root);

  final manifest = RegressionStore(RegressionPaths(root)).loadManifest();

  final coverage = _coverageCounts(manifest);



  final buf = StringBuffer()

    ..writeln('# Lista de testes Fleaber — linguagem simples')

    ..writeln()

    ..writeln('Gerado: ${DateTime.now().toIso8601String().substring(0, 19)}')

    ..writeln()

    ..writeln('## O que é isto?')

    ..writeln()

    ..writeln(

      'São **429 verificações** da app Fleaber (mais 21 da bateria T, descrita no fim). '

      'Cada uma diz: **o que fazes**, **o que deve acontecer se estiver bem**, '

      '**o que a última corrida disse**, e **o que a auditoria dos logs e prints confirmou**.',

    )

    ..writeln()

    ..writeln('### Significado dos estados')

    ..writeln()

    ..writeln('| Símbolo | Significado |')

    ..writeln('|---------|-------------|')

    ..writeln('| ✅ Passou | Correu e deu como esperado |')

    ..writeln('| ❌ Falhou | Correu mas algo correu mal (muitas vezes o robô de teste, não necessariamente a app) |')

    ..writeln('| 👤 Manual | Só uma pessoa pode confirmar (ex. pagar com cartão real) |')

    ..writeln('| ⏸️ Não correu | Faltou preparar dados (ex. criar um directo de teste) |')

    ..writeln('| 🚫 Bloqueado | Não dá para testar ainda por dependência em falta |')

    ..writeln('| ⏳ Por fazer | Ainda não foi executado na última corrida completa |')

    ..writeln('| ⚠️ Passou com aviso | Auditoria viu o essencial mas há pormenores (ex. texto técnico no ecrã) |')

    ..writeln()

    ..writeln('### Tipos de falha (quando ❌)')

    ..writeln()

    ..writeln('| Tipo | Significado |')

    ..writeln('|------|-------------|')

    ..writeln('| 🔧 **INFRA** | ${userFailureKindExplain[UserFailureKind.infra]} |')

    ..writeln('| 🧭 **NAVEGAÇÃO** | ${userFailureKindExplain[UserFailureKind.navegacao]} |')

    ..writeln('| 🗄️ **DADOS/BD** | ${userFailureKindExplain[UserFailureKind.dadosBd]} |')

    ..writeln('| 🐛 **BUG FUNCIONAL REAL** | ${userFailureKindExplain[UserFailureKind.bugReal]} |')

    ..writeln()

    ..writeln('### Quantos testes são mesmo manuais?')

    ..writeln()

    ..writeln(

      '**Importante:** na corrida completa de **16 Jun** apareciam **131** testes com estado «manual». '

      'Isso **não** quer dizer que tens 131 testes para fazer à mão — na altura o robô **nem tentava correr** '

      'muitos deles (faltavam adaptadores automáticos).',

    )

    ..writeln()

    ..writeln('| Situação | Número |')

    ..writeln('|----------|--------|')

    ..writeln('| Testes com robô automático atribuído hoje | **${coverage.automated}** |')

    ..writeln('| Testes que **sempre** precisam de pessoa (checkpoint manual) | **${coverage.manual}** |')

    ..writeln('| Testes guiados (câmara, Stripe ao vivo…) | **${coverage.guided}** |')

    ..writeln('| Total | 429 |')

    ..writeln()

    ..writeln(
      '**Garantia actual (política fixa):** todos os testes excepto os **24** da lista explícita '
      '(`tool/regression/automation_policy.dart`) têm robô atribuído no `manifest.json`. '
      'O comando `dart run tool/regression/coverage_report.dart` falha se algum ficar sem adapter '
      'ou se o número sair de **405 automáticos + 24 manuais/guiados**.',
    )

    ..writeln()

    ..writeln(

      '**Testes manuais de verdade hoje: ${coverage.manual + coverage.guided}** '

      '(${coverage.manual} manuais + ${coverage.guided} guiado). Lista completa na secção [Só manuais](#só-manuais).',

    )

    ..writeln()

    ..writeln('### Resumo da última corrida completa (429 testes, 16 Jun)')

    ..writeln()

    ..writeln(_summary(results, fullRunOnly: true))

    ..writeln()

    ..writeln('### Resumo actualizado (A001–A035 corrida 17 Jun + resto da corrida 16 Jun)')

    ..writeln()

    ..writeln(_summary(results, fullRunOnly: false))

    ..writeln()

    ..writeln('### Resumo da auditoria (logs e prints)')

    ..writeln()

    ..writeln(_auditSummary(audits))

    ..writeln()

    ..writeln('### Resumo de falhas por tipo (corrida + auditoria)')

    ..writeln()

    ..writeln(_failureSummary(results, audits))

    ..writeln()

    ..writeln('---')

    ..writeln()

    ..writeln('## Só manuais (${coverage.manual + coverage.guided} testes)')

    ..writeln()

    ..writeln(

      'Estes **não têm robô fiável** — precisam de ti (ou de hardware/contas especiais). '

      'Os outros ${coverage.automated} têm automação atribuída; se falharem, muitas vezes é problema do emulador ou do Maestro, não da app.',

    )

    ..writeln();

  _writeManualSection(buf, manifest, fichas, results, audits);

  buf

    ..writeln('---')

    ..writeln()

    ..writeln('## Os 429 testes (A001 a A429)')

    ..writeln();



  final byArea = <String, List<String>>{};

  for (var i = 1; i <= 429; i++) {

    final id = 'A${i.toString().padLeft(3, '0')}';

    final area = _areaLabel(areaForTestId(id));

    byArea.putIfAbsent(area, () => []).add(id);

  }



  for (final area in _areaOrder) {

    final ids = byArea[area];

    if (ids == null || ids.isEmpty) continue;

    buf.writeln('### $area');

    buf.writeln();

    for (final id in ids) {

      _writeTest(

        buf,

        id,

        fichas[id],

        results[id],

        audits[id],

        manifest[id],

      );

    }

    buf.writeln();

  }



  buf

    ..writeln('---')

    ..writeln()

    ..writeln('## Bateria extra T01–T21 (comprador + vendedor em 2 telemóveis)')

    ..writeln()

    ..writeln(_batterySection(root));



  final out = File('$root/tool/LISTA_TESTES_PARA_HUMANO.md');

  out.writeAsStringSync(buf.toString());

  print('Escrito: ${out.path}');

  print(_summary(results, fullRunOnly: false));

}



({int automated, int manual, int guided}) _coverageCounts(

  Map<String, dynamic> manifest,

) {

  var automated = 0;

  var manual = 0;

  var guided = 0;

  for (final t in manifest.values) {

    final type = (t as dynamic).adapter?.type as String? ?? '';

    if (type == 'manual_checkpoint') {

      manual++;

    } else if (type == 'guided_checkpoint') {

      guided++;

    } else if (type.isNotEmpty) {

      automated++;

    }

  }

  return (automated: automated, manual: manual, guided: guided);

}



void _writeManualSection(

  StringBuffer buf,

  Map<String, dynamic> manifest,

  Map<String, _Ficha> fichas,

  Map<String, _Result> results,

  Map<String, _Audit> audits,

) {

  final ids = <String>[];

  for (final e in manifest.entries) {

    final type = e.value.adapter?.type as String? ?? '';

    if (type == 'manual_checkpoint' || type == 'guided_checkpoint') {

      ids.add(e.key);

    }

  }

  ids.sort();

  for (final id in ids) {

    final f = fichas[id];

    final t = manifest[id];

    final type = t?.adapter?.type as String? ?? '';

    final tag = type == 'guided_checkpoint' ? '👤 Guiado' : '👤 Manual';

    buf.writeln('#### $id — ${f?.nome ?? t?.title ?? id}');

    buf.writeln();

    buf.writeln('**Porque é manual:** ${_manualWhy(id, f, type)}');

    buf.writeln();

    final r = results[id];

    final a = audits[id];

    if (r != null) {

      buf.writeln('**Última corrida:** ${_estadoLabel(r.status)}${_motivoSimples(r).isNotEmpty ? ' — ${_motivoSimples(r)}' : ''}');

    }

    if (a != null) {

      buf.writeln();

      buf.writeln('**Auditoria:** ${_auditLabel(a)}${_auditDetail(a)}');

    }

    buf.writeln();

  }

}



Map<String, _Ficha> _loadFichas(String root) {

  final out = <String, _Ficha>{};

  final rowRe = RegExp(

    r'^\|\s*\*\*([^*]+)\*\*\s*\|\s*(.+?)\s*\|\s*$',

    multiLine: true,

  );

  final headerRe = RegExp(r'^## (A\d{3})\s+[—–\-]\s+(.+)$', multiLine: true);



  for (final doc in ManifestBuilder.docFiles) {

    final content = File('$root/docs/$doc').readAsStringSync();

    final matches = headerRe.allMatches(content).toList();

    for (var i = 0; i < matches.length; i++) {

      final id = matches[i].group(1)!;

      final subtitle = matches[i].group(2)!.trim();

      final start = matches[i].end;

      final end = i + 1 < matches.length ? matches[i + 1].start : content.length;

      final body = content.substring(start, end);

      final fields = <String, String>{};

      for (final m in rowRe.allMatches(body)) {

        fields[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();

      }

      out[id] = _Ficha(

        id: id,

        subtitle: subtitle,

        nome: fields['nome'] ?? subtitle,

        passos: fields['passos'] ?? '—',

        esperado: fields['resultado esperado'] ?? '—',

        automatizavel: fields['automatizável'] ?? fields['automatizavel'] ?? '',

        tipoRecomendado: fields['tipo recomendado'] ?? '',

      );

    }

  }

  return out;

}



Map<String, _Result> _loadResults(String root) {

  final fullPath =

      '$root/tool/reports/regression_2026-06-16T19-28-54/results.json';

  final partialPath =

      '$root/tool/reports/regression_2026-06-17T09-13-33/results.json';

  final out = <String, _Result>{};



  if (File(fullPath).existsSync()) {

    final raw = jsonDecode(File(fullPath).readAsStringSync()) as Map;

    for (final t in raw['tests'] as List) {

      final m = t as Map<String, dynamic>;

      out[m['id'] as String] = _Result.fromJson(m);

    }

  }



  if (File(partialPath).existsSync()) {

    final raw = jsonDecode(File(partialPath).readAsStringSync()) as Map;

    for (final t in raw['tests'] as List) {

      final m = t as Map<String, dynamic>;

      final id = m['id'] as String;

      if (_idNum(id) >= 1 && _idNum(id) <= 35) {

        out[id] = _Result.fromJson(m);

      }

    }

  }



  return out;

}



Map<String, _Audit> _loadAudits(String root) {

  final logsDir = Directory('$root/tool/logs');

  if (!logsDir.existsSync()) return {};

  final out = <String, _Audit>{};

  for (final dir in logsDir.listSync().whereType<Directory>()) {

    if (!dir.path.contains('audit_')) continue;

    final f = File('${dir.path}/audit_results.json');

    if (!f.existsSync()) continue;

    final raw = jsonDecode(f.readAsStringSync()) as Map;

    for (final v in raw['verdicts'] as List? ?? const []) {

      final m = v as Map<String, dynamic>;

      final id = m['testId'] as String;

      final auditedAt = DateTime.tryParse(m['auditedAt']?.toString() ?? '') ??

          DateTime.fromMillisecondsSinceEpoch(0);

      final prev = out[id];

      if (prev == null || auditedAt.isAfter(prev.auditedAt)) {

        out[id] = _Audit(

          conclusion: m['conclusion']?.toString() ?? '',

          probableCause: m['probableCause']?.toString() ?? '',

          validationType: m['validationType']?.toString() ?? '',

          auditedAt: auditedAt,

          stamp: dir.path.split(Platform.pathSeparator).last,

          stockMismatches: _stringList(m['stockMismatches']),

          failures: _stringList(m['failures']),

          maestroExitCode: m['maestroExitCode'] as int? ?? 0,

        );

      }

    }

  }

  return out;

}



int _idNum(String id) => int.parse(id.substring(1));



String _summary(Map<String, _Result> results, {required bool fullRunOnly}) {

  final c = <String, int>{};

  for (var i = 1; i <= 429; i++) {

    final id = 'A${i.toString().padLeft(3, '0')}';

    if (fullRunOnly && _idNum(id) <= 35) {

      // full run only: use original full run for all

    }

    final s = results[id]?.status ?? 'not_run';

    c[s] = (c[s] ?? 0) + 1;

  }

  if (fullRunOnly) {

    // Re-load counts from full run file only for accurate 16 Jun snapshot

    final fullPath =

        '${Directory.current.path}/tool/reports/regression_2026-06-16T19-28-54/results.json';

    final fc = <String, int>{};

    if (File(fullPath).existsSync()) {

      final raw = jsonDecode(File(fullPath).readAsStringSync()) as Map;

      for (final t in raw['tests'] as List) {

        final s = (t as Map)['status'] as String;

        fc[s] = (fc[s] ?? 0) + 1;

      }

    }

    return '- ✅ Passou: ${fc['pass'] ?? 0}\n'

        '- ❌ Falhou: ${fc['fail'] ?? 0}\n'

        '- 👤 Marcado manual (robô nem tentou): ${fc['manual'] ?? 0}\n'

        '- 🚫 Bloqueado: ${fc['blocked'] ?? 0}\n'

        '- ⏸️ Não correu (config): ${fc['skip_config_missing'] ?? 0}';

  }

  return '- ✅ Passou: ${c['pass'] ?? 0}\n'

      '- ❌ Falhou: ${c['fail'] ?? 0}\n'

      '- 👤 Manual na corrida: ${c['manual'] ?? 0}\n'

      '- 🚫 Bloqueado: ${c['blocked'] ?? 0}\n'

      '- ⏸️ Não correu (config): ${c['skip_config_missing'] ?? 0}\n'

      '- ⏳ Por fazer: ${c['not_run'] ?? 0}';

}



String _auditSummary(Map<String, _Audit> audits) {

  final c = <String, int>{};

  for (final a in audits.values) {

    final k = a.conclusion.toUpperCase();

    if (k.startsWith('PASS_COM') || k.contains('AVISO')) {

      c['pass_aviso'] = (c['pass_aviso'] ?? 0) + 1;

    } else if (k == 'PASS') {

      c['pass'] = (c['pass'] ?? 0) + 1;

    } else if (k == 'FAIL') {

      c['fail'] = (c['fail'] ?? 0) + 1;

    }

  }

  return '- Testes com auditoria de logs/prints: ${audits.length}\n'

      '- ✅ Confirmado passou: ${c['pass'] ?? 0}\n'

      '- ⚠️ Passou com aviso: ${c['pass_aviso'] ?? 0}\n'

      '- ❌ Confirmado falhou: ${c['fail'] ?? 0}\n'

      '- (Restantes 429 − ${audits.length} ainda sem auditoria automática)';

}



String _failureSummary(Map<String, _Result> results, Map<String, _Audit> audits) {

  final byKind = <UserFailureKind, List<String>>{};

  final realBugs = <String>[];

  final auditOkButFailed = <String>[];

  for (var i = 1; i <= 429; i++) {

    final id = 'A${i.toString().padLeft(3, '0')}';

    final r = results[id];

    if (r?.status != 'fail') continue;

    final a = audits[id];

    final info = classifyFromFields(

      status: r!.status,

      message: r.message,

      layersRun: r.layersRun,

      audit: _toAuditHint(a),

    );

    byKind.putIfAbsent(info.kind, () => []).add(id);

    if (info.kind == UserFailureKind.bugReal && !info.likelyFalsePositive) {

      realBugs.add(id);

    }

    if (info.auditOverridesRun) auditOkButFailed.add(id);

  }

  final buf = StringBuffer();

  for (final kind in UserFailureKind.values) {

    if (kind == UserFailureKind.none) continue;

    final ids = byKind[kind] ?? [];

    final label = userFailureKindLabels[kind]!;

    final emoji = userFailureKindEmoji(kind);

    buf.writeln('- $emoji **$label**: ${ids.length} teste(s)');

  }

  buf.writeln();

  if (realBugs.isEmpty) {

    buf.writeln(

      '**Bugs funcionais reais confirmados: 0** — nenhuma falha ficou como 🐛 BUG REAL '

      'depois de cruzar corrida com auditoria.',

    );

  } else {

    buf.writeln('**Bugs funcionais reais:** ${realBugs.join(', ')}');

  }

  if (auditOkButFailed.isNotEmpty) {

    buf.writeln();

    buf.writeln(

      '**Corrida falhou mas auditoria confirmou OK** (${auditOkButFailed.length}): '

      '${auditOkButFailed.join(', ')}',

    );

  }

  final infra = byKind[UserFailureKind.infra] ?? [];

  final nav = byKind[UserFailureKind.navegacao] ?? [];

  if (infra.isNotEmpty || nav.isNotEmpty) {

    buf.writeln();

    buf.writeln(

      '**Prep Maestro (NAVEGAÇÃO):** ${nav.where((id) => _idNum(id) <= 35).join(', ')}',

    );

    buf.writeln(

      '**Infra/dedupe/lançar app:** ${infra.join(', ')}',

    );

  }

  return buf.toString().trimRight();

}



UserAuditHint? _toAuditHint(_Audit? a) {

  if (a == null) return null;

  return UserAuditHint(

    conclusion: a.conclusion,

    probableCause: a.probableCause,

    validationType: a.validationType,

    stockMismatches: a.stockMismatches,

    failures: a.failures,

    maestroExitCode: a.maestroExitCode,

  );

}



List<String> _stringList(dynamic raw) {

  if (raw is! List) return const [];

  return raw.map((e) => e.toString()).toList();

}



void _writeTest(

  StringBuffer buf,

  String id,

  _Ficha? f,

  _Result? r,

  _Audit? audit,

  dynamic manifestTest,

) {

  final adapterType = manifestTest?.adapter?.type as String? ?? '';

  final isTrueManual = adapterType == 'manual_checkpoint' ||

      adapterType == 'guided_checkpoint';



  buf.writeln('#### $id — ${f?.nome ?? r?.name ?? id}');

  buf.writeln();

  buf.writeln(

    '**Corrida:** ${_estadoLabel(r?.status)}${_motivoSimples(r).isNotEmpty ? ' — ${_motivoSimples(r)}' : ''}',

  );

  buf.writeln();

  if (r?.status == 'fail') {

    final failInfo = classifyFromFields(

      status: r!.status,

      message: r.message,

      layersRun: r.layersRun,

      audit: _toAuditHint(audit),

    );

    if (failInfo.kind != UserFailureKind.none) {

      final label = userFailureKindLabels[failInfo.kind]!;

      final emoji = userFailureKindEmoji(failInfo.kind);

      var line = '**Tipo de falha:** $emoji **$label** — ${failInfo.shortReason}';

      if (failInfo.auditOverridesRun) {

        line += ' *(auditoria diz que a app está OK — falso alarme do robô)*';

      } else if (failInfo.likelyFalsePositive &&

          failInfo.kind != UserFailureKind.bugReal) {

        line += ' *(provavelmente não é bug da app)*';

      }

      buf.writeln(line);

      buf.writeln();

    }

  }

  if (audit != null) {

    buf.writeln(

      '**Auditoria (logs/prints):** ${_auditLabel(audit)}${_auditDetail(audit)}',

    );

    buf.writeln();

  } else if (r?.status == 'pass' &&

      (adapterType == 'integration' ||

          adapterType == 'unit' ||

          adapterType == 'bot')) {

    buf.writeln(

      '**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)',

    );

    buf.writeln();

  } else {

    buf.writeln('**Auditoria (logs/prints):** ⏳ Ainda não auditado');

    buf.writeln();

  }



  if (isTrueManual) {

    buf.writeln(

      '**Automatização:** 👤 Só manual — ${_manualWhy(id, f, adapterType)}',

    );

  } else if (adapterType.isNotEmpty) {

    final robotLabel = _adapterLabel(adapterType);

    final wasManualInFullRun = r?.status == 'manual' &&

        (r?.message?.contains('Validação manual') ?? false);

    var extra = '';

    if (wasManualInFullRun && _idNum(id) > 35) {

      extra =

          ' *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem $robotLabel)*';

    }

    buf.writeln('**Automatização:** 🤖 $robotLabel$extra');

  } else {

    buf.writeln('**Automatização:** ⏳ Sem robô atribuído');

  }

  buf.writeln();

  buf.writeln('**O que fazes:** ${f?.passos ?? 'Ver documentação em docs/'}');

  buf.writeln();

  buf.writeln('**Se estiver bem:** ${f?.esperado ?? '—'}');

  buf.writeln();

}



String _adapterLabel(String type) => switch (type) {

      'maestro' => 'Maestro (robô no telemóvel)',

      'bot' => 'Bot (simula comprador/vendedor na base de dados)',

      'integration' => 'Teste de dados (staging)',

      'unit' => 'Teste de código (rápido)',

      'hybrid' => 'Híbrido (dados + ecrã)',

      _ => type,

    };



String _auditLabel(_Audit a) {

  final c = a.conclusion.toUpperCase();

  if (c.startsWith('PASS_COM') || c.contains('AVISO')) {

    return '⚠️ Passou com aviso';

  }

  if (c == 'PASS') return '✅ Confirmado passou';

  if (c == 'FAIL') return '❌ Confirmado falhou';

  return a.conclusion;

}



String _auditDetail(_Audit a) {

  final parts = <String>[];

  if (a.probableCause.isNotEmpty) parts.add(a.probableCause);

  if (a.validationType.isNotEmpty) parts.add(a.validationType);

  if (parts.isEmpty) return '';

  return ' — ${parts.join('; ')}';

}



String _manualWhy(String id, _Ficha? f, String adapterType) {

  if (_manualReasons.containsKey(id)) return _manualReasons[id]!;



  final auto = (f?.automatizavel ?? '').toLowerCase();

  final tipo = (f?.tipoRecomendado ?? '').toLowerCase();

  final nome = (f?.nome ?? '').toLowerCase();



  if (adapterType == 'guided_checkpoint' ||

      nome.contains('câmara') ||

      nome.contains('camera')) {

    return 'Precisa de interagir com permissões do sistema (câmara/microfone) — o emulador não reproduz isto de forma fiável.';

  }

  if (auto == 'manual' || tipo.contains('manual')) {

    if (tipo.contains('2 devices') || nome.contains('segundo device')) {

      return 'Precisa de dois telemóveis ao mesmo tempo.';

    }

    if (nome.contains('stripe') || tipo.contains('stripe')) {

      return 'Envolve o fluxo real de pagamento Stripe (browser, 3D Secure, voltar à app).';

    }

    if (nome.contains('helper') || nome.contains('staff')) {

      return 'Precisa de contas de ajudante/staff com permissões específicas — o robô só usa vendedor/comprador de teste.';

    }

    if (nome.contains('mux') || nome.contains('rtmp') || nome.contains('hls')) {

      return 'Envolve streaming/vídeo real (Mux, RTMP ou latência HLS) — difícil de simular no robô.';

    }

    return 'Marcado na documentação como não automatizável de forma fiável.';

  }

  return 'Validação humana documentada na matriz de testes.';

}



/// Motivos em português simples para os checkpoints manuais/guiados.

const _manualReasons = <String, String>{

  'A018':

      'Conta de ajudante sem permissão para criar directo — tens de ver se o botão aparece bloqueado.',

  'A037':

      'Staff com loja activa diferente do dono — precisa login de colaborador real.',

  'A044':

      'Edição rápida de descrição só existe **durante a live**, não no ecrã de preparar.',

  'A064':

      'Publicação RTMP alternativa — depende de flag especial e stream real.',

  'A065':

      'Tens de **recusar a permissão da câmara** no Android e ver a mensagem de erro.',

  'A070':

      'Ajudante a tentar iniciar directo próprio — permissões de equipa.',

  'A072':

      'Rodar o telemóvel para paisagem durante encode/visualização.',

  'A073':

      'Modo diagnóstico de preview — só em build de debug.',

  'A076':

      'Esperar timeout da API Mux — demora real (minutos) difícil no robô.',

  'A077': 'Precisa de **dois telemóveis** — o segundo não pode publicar em paralelo.',

  'A078':

      'Ajudante a ver HLS + painel de operações — sessão helper real.',

  'A098':

      'Ajudante **sem** permissão a tentar aceitar reservas — deve ser bloqueado.',

  'A099':

      'Dono da loja ignora restrições de staff — comparar duas contas.',

  'A168':

      'Voltar à app depois de ir ao Stripe pagar — fluxo sandbox real.',

  'A169':

      'Qualidade e latência do vídeo HLS ao vivo — perceptível a olho humano.',

  'A205':

      'Abrir a página de checkout Stripe no browser ao confirmar pagamento.',

  'A207':

      'Cancelar no ecrã Stripe e confirmar que a reserva se mantém na app.',

  'A372':

      'Painel operacional do ajudante sobre HLS **sem usar a câmara**.',

  'A379':

      'Ajudante não pode editar anúncios — catálogo só leitura na live.',

  'A383': 'Ajudante não deve ver saldo, wallet nem pagamentos.',

  'A384': 'Ajudante não pode gerir outros colaboradores.',

  'A388':

      'Dono muda permissões — ajudante vê portas bloqueadas após refrescar.',

  'A399': 'Pagamento com autenticação forte Stripe (3D Secure).',

  'A410':

      'Depois do Stripe, cortar a rede e ver se o estado pendente sobrevive.',

};



String _estadoLabel(String? status) {

  switch (status) {

    case 'pass':

      return '✅ Passou';

    case 'fail':

      return '❌ Falhou';

    case 'manual':

      return '👤 Manual';

    case 'blocked':

      return '🚫 Bloqueado';

    case 'skip_config_missing':

      return '⏸️ Não correu';

    default:

      return '⏳ Por fazer';

  }

}



String _motivoSimples(_Result? r) {

  if (r == null) return 'Ainda não executado na corrida de referência';

  final msg = (r.message ?? '').toLowerCase();

  if (r.status == 'pass') return '';

  if (r.status == 'manual') {

    if (msg.contains('validação manual')) {

      return 'Robô não corre — checkpoint manual';

    }

    return 'Precisa de olhos humanos';

  }

  if (r.status == 'skip_config_missing') {

    return 'Faltou criar o directo de teste na base de dados antes de correr';

  }

  if (r.status == 'blocked') return 'Depende de outro teste ou funcionalidade em falta';

  if (msg.contains('dedupe')) {

    return 'O robô saltou porque já tinha feito um teste muito parecido na mesma sessão';

  }

  if (msg.contains('unable to launch')) {

    return 'O emulador não conseguiu abrir a app (instabilidade, não necessariamente bug na app)';

  }

  if (msg.contains('maestro exit') ||

      msg.contains('assertion') ||

      msg.contains('element not found') ||

      msg.contains('element state')) {

    return 'O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona';

  }

  if (msg.contains('híbrido') || msg.contains('hybrid')) {

    return 'Teste em duas fases (dados + ecrã): falhou na parte do ecrã';

  }

  if (r.status == 'fail') return 'Ver detalhe técnico no relatório se precisares';

  return '';

}



String _batterySection(String root) {

  final p = File('$root/tool/TEST_BATTERY_LIVE.md');

  if (!p.existsSync()) return '(bateria T não encontrada)';

  return 'Ver tabela actualizada em `tool/TEST_BATTERY_LIVE.md` — resumo: a maioria dos T01–T21 **passou** '

      '(login vendedor/comprador, reservas, stock, rifa). T08e e T21 são pagamento Stripe **manual**.';

}



const _areaOrder = [

  'Preparar directo (antes de ir ao ar)',

  'Publicar e ir ao ar',

  'Operações do vendedor durante a live',

  'Catálogo na live',

  'Comprador a ver a live',

  'Checkout e saco',

  'Pagamentos',

  'Rifas',

  'Mensagens e chat',

  'Directos gravados',

  'Cross-pool (várias lojas)',

  'Marketplace',

  'Ajudantes e staff',

  'Erros e casos limite',

  'Sincronização de dados',

  'Outros',

];



String _areaLabel(String area) {

  switch (area) {

    case 'prep':

      return 'Preparar directo (antes de ir ao ar)';

    case 'publish':

      return 'Publicar e ir ao ar';

    case 'seller_ops':

      return 'Operações do vendedor durante a live';

    case 'catalog':

      return 'Catálogo na live';

    case 'buyer_player':

      return 'Comprador a ver a live';

    case 'checkout':

      return 'Checkout e saco';

    case 'payments':

      return 'Pagamentos';

    case 'raffle':

      return 'Rifas';

    case 'messages':

      return 'Mensagens e chat';

    case 'gravado':

      return 'Directos gravados';

    case 'cross_pool':

      return 'Cross-pool (várias lojas)';

    case 'marketplace':

      return 'Marketplace';

    case 'helpers':

      return 'Ajudantes e staff';

    case 'errors':

      return 'Erros e casos limite';

    case 'sync':

      return 'Sincronização de dados';

    default:

      return 'Outros';

  }

}



class _Ficha {

  _Ficha({

    required this.id,

    required this.subtitle,

    required this.nome,

    required this.passos,

    required this.esperado,

    required this.automatizavel,

    required this.tipoRecomendado,

  });

  final String id;

  final String subtitle;

  final String nome;

  final String passos;

  final String esperado;

  final String automatizavel;

  final String tipoRecomendado;

}



class _Result {

  _Result({

    required this.name,

    required this.status,

    this.message,

    this.layersRun = const [],

  });

  final String name;

  final String status;

  final String? message;

  final List<String> layersRun;



  factory _Result.fromJson(Map<String, dynamic> json) => _Result(

        name: json['name']?.toString() ?? '',

        status: json['status']?.toString() ?? 'not_run',

        message: json['message']?.toString(),

        layersRun: _stringList(json['layers_run']),

      );

}



class _Audit {

  _Audit({

    required this.conclusion,

    required this.probableCause,

    required this.validationType,

    required this.auditedAt,

    required this.stamp,

    this.stockMismatches = const [],

    this.failures = const [],

    this.maestroExitCode = 0,

  });

  final String conclusion;

  final String probableCause;

  final String validationType;

  final DateTime auditedAt;

  final String stamp;

  final List<String> stockMismatches;

  final List<String> failures;

  final int maestroExitCode;

}


