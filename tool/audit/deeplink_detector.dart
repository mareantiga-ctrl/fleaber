// Deteta uso de deep links em flows e logs (navegação real, não comentários).
import 'dart:io';

class DeeplinkDetector {
  /// Marcadores de navegação por deep link / adb URI (não nomes de rotas em comentários).
  static const deepLinkMarkers = [
    'openLink:',
    'openlink:',
    'am start -W -a android.intent.action.VIEW',
    'adb deep link',
    'run_maestro_adb_sequence',
  ];

  static bool scanText(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('#')) continue;
      final lower = t.toLowerCase();
      for (final m in deepLinkMarkers) {
        if (lower.contains(m.toLowerCase())) return true;
      }
    }
    return false;
  }

  static bool scanFiles(List<String> paths) {
    for (final p in paths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final lower = p.toLowerCase();
        if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
          if (scanYamlFlow(f.readAsStringSync())) return true;
          continue;
        }
        if (scanText(f.readAsStringSync())) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Só conta `openLink` / adb em flows Maestro activos.
  static bool scanYamlFlow(String content) {
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.startsWith('#')) continue;
      final lower = t.toLowerCase();
      if (lower.startsWith('openlink:') || lower.contains('openlink:')) {
        return true;
      }
    }
    return false;
  }

  static List<String> listDeepLinkFlows(String maestroRoot) {
    final found = <String>[];
    final root = Directory(maestroRoot);
    if (!root.existsSync()) return found;
    for (final f in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))) {
      try {
        if (scanYamlFlow(f.readAsStringSync())) {
          found.add(f.path);
        }
      } catch (_) {}
    }
    return found;
  }
}
