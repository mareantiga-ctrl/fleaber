// ignore_for_file: avoid_print
/// Recupera PNG corrompidos por redirect PowerShell (`>` → UTF-16 LE).
///
/// Uso: dart run tool/c22_recover_utf16_pngs.dart
import 'dart:io';

void main() {
  final dir = Directory('tool/reports/battery_c22_2026-08-19/screenshots');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'));

  for (final f in files) {
    final raw = f.readAsBytesSync();
    if (raw.length < 8) continue;
    final isPng = raw[0] == 0x89 && raw[1] == 0x50 && raw[2] == 0x4E && raw[3] == 0x47;
    if (isPng) {
      print('OK   ${f.uri.pathSegments.last}');
      continue;
    }
    if (!(raw[0] == 0xFF && raw[1] == 0xFE)) {
      print('SKIP ${f.uri.pathSegments.last} (not utf16 bom)');
      continue;
    }

    // UTF-16 LE BOM + cada byte original como char U+00xx
    final out = <int>[];
    for (var i = 2; i + 1 < raw.length; i += 2) {
      final lo = raw[i];
      final hi = raw[i + 1];
      if (hi != 0) {
        // Fallback: keep low byte only (lossy)
        out.add(lo);
      } else {
        out.add(lo);
      }
    }
    // PowerShell/console por vezes muda 0x89 → 0xEB no 1º byte
    if (out.length >= 4 &&
        out[0] != 0x89 &&
        out[1] == 0x50 &&
        out[2] == 0x4E &&
        out[3] == 0x47) {
      out[0] = 0x89;
    }

    final bak = File('${f.path}.corrupt_bak');
    if (!bak.existsSync()) {
      bak.writeAsBytesSync(raw);
    }
    f.writeAsBytesSync(out);
    final ok = out.length >= 4 &&
        out[0] == 0x89 &&
        out[1] == 0x50 &&
        out[2] == 0x4E &&
        out[3] == 0x47;
    print('${ok ? "FIXED" : "BAD "} ${f.uri.pathSegments.last} -> ${out.length} bytes');
  }
}
