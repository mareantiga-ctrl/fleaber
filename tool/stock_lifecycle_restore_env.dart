// ignore_for_file: avoid_print
/// Restaura MAESTRO_LIVE_ID da sessão SL-A após SL-E/SL-G.
library;

import 'dart:io';

void main() {
  final f = File('.maestro/.env');
  if (!f.existsSync()) {
    print('sem .maestro/.env');
    return;
  }
  final lines = f.readAsLinesSync();
  String? backup;
  final out = <String>[];
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID_SLA_BACKUP=')) {
      backup = line.substring('MAESTRO_LIVE_ID_SLA_BACKUP='.length).trim();
      continue;
    }
    if (line.startsWith('MAESTRO_LIVE_ID=') && backup != null && backup.isNotEmpty) {
      out.add('MAESTRO_LIVE_ID=$backup');
      backup = null;
      continue;
    }
    if (line.startsWith('MAESTRO_EDGE_') ||
        line.startsWith('MAESTRO_CROSS_') ||
        line.startsWith('MAESTRO_ITEM_TITLE=SL Edge')) {
      continue;
    }
    out.add(line);
  }
  f.writeAsStringSync('${out.join('\n')}\n');
  print('Restored MAESTRO_LIVE_ID from SLA backup');
}
