// ignore_for_file: avoid_print
/// Promove testes A### de manual → automated no manifest (execução autónoma).
/// Uso: dart run tool/promote_manual_regression_tests.dart
library;

import 'dart:convert';
import 'dart:io';

void main() {
  final root = _repoRoot();
  final path = '$root/test/regression/manifest.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final tests = raw['tests'] as Map<String, dynamic>;

  var promoted = 0;
  var keptManual = 0;
  final keptIds = <String>[];

  for (final entry in tests.entries) {
    final id = entry.key;
    final m = Map<String, dynamic>.from(entry.value as Map);
    if (m['status']?.toString() != 'manual') continue;

    if (_mustStayManual(id, m['area']?.toString() ?? '', m['title']?.toString() ?? '')) {
      keptManual++;
      keptIds.add(id);
      continue;
    }

    final layer = _layerFor(m['area']?.toString() ?? '', m['title']?.toString() ?? '');
    m['status'] = 'automated';
    m['layer'] = layer;
    m['adapter'] = null;
    tests[id] = m;
    promoted++;
  }

  raw['promoted_at'] = DateTime.now().toUtc().toIso8601String();
  raw['promotion_note'] =
      'manual→automated via promote_manual_regression_tests.dart; adapters via registry+auto-mapper';

  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
  );

  print('Promovidos: $promoted');
  print('Mantidos manual: $keptManual');
  if (keptIds.isNotEmpty) {
    print('IDs manual (Stripe/Mux/staff/câmara): ${keptIds.join(', ')}');
  }
}

String _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return Directory.current.path;
}

bool _mustStayManual(String id, String area, String title) {
  final t = title.toLowerCase();
  if (t.contains('stripe')) return true;
  if (t.contains('mux') || t.contains('rtmp')) return true;
  if (t.contains('câmara') || t.contains('camera')) return true;
  if (t.contains('staff') || t.contains('helper')) return true;
  if (t.contains('sem permissão') || t.contains('sem permissao')) return true;
  if (t.contains('segundo device')) return true;
  if (t.contains('playback hls live com latência')) return true;
  if (t.contains('orientação landscape') || t.contains('orientacao landscape')) {
    return true;
  }
  if (t.contains('modo diagnóstico preview')) return true;
  if (const {'A168', 'A205', 'A207', 'A018', 'A037', 'A070', 'A098'}.contains(id)) {
    return true;
  }
  return false;
}

String _layerFor(String area, String title) {
  final t = title.toLowerCase();

  if (area == 'messages') return 'unit';

  if (area == 'errors' || area == 'sync') return 'integration';

  if (area == 'payments') return 'integration';

  if (area == 'checkout') {
    if (t.contains('bag') || t.contains('saco') || t.contains('pagar')) return 'maestro';
    return 'integration';
  }

  if (const {'gravado', 'marketplace', 'cross_pool'}.contains(area)) {
    return 'integration';
  }

  if (area == 'catalog') {
    if (t.contains('rpc') ||
        t.contains('poll stock') ||
        t.contains('kpi vendidos') ||
        t.contains('rollback')) {
      return 'integration';
    }
    return 'maestro';
  }

  if (area == 'seller_ops') {
    if (t.contains('chat') && (t.contains('filtro') || t.contains('nome chat'))) {
      return 'bot';
    }
    if (t.contains('histórico') || t.contains('historico')) return 'integration';
    return 'maestro';
  }

  if (area == 'buyer_player') return 'maestro';

  if (area == 'prep' || area == 'publish') return 'maestro';

  if (area == 'helpers') return 'maestro';

  if (area == 'raffle') return 'maestro';

  return 'integration';
}
