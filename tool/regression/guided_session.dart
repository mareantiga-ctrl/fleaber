// ignore_for_file: avoid_print
import 'dart:io';

/// Prompts interactivos — só quando `--guided` e necessário.
class GuidedSession {
  GuidedSession({required this.enabled, this.reportDir});

  final bool enabled;
  final String? reportDir;

  String? _liveId;
  bool _buyerReady = false;
  bool _sellerReady = false;
  bool _liveIdAsked = false;

  String? get liveId => _liveId;

  Future<String?> ensureLiveId({String? fromEnv}) async {
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      _liveId = fromEnv.trim();
      return _liveId;
    }
    if (_liveId != null && _liveId!.isNotEmpty) return _liveId;
    if (!enabled) return null;
    if (_liveIdAsked) return null;
    _liveIdAsked = true;

    print('');
    print('┌─ GUIDED ─────────────────────────────────────────');
    print('│ Inicia uma live na app vendedora e cola o live_id');
    print('│ (ENTER vazio = saltar testes bot que precisam live)');
    print('└──────────────────────────────────────────────────');
    stdout.write('live_id> ');
    final line = stdin.readLineSync()?.trim() ?? '';
    if (line.isEmpty) return null;
    _liveId = line;
    return _liveId;
  }

  Future<bool> confirmBuyerPlayer({bool required = false}) async {
    if (_buyerReady) return true;
    if (!enabled) return !required;
    print('');
    print('┌─ GUIDED ─────────────────────────────────────────');
    print('│ Confirma que estás no player comprador');
    print('└──────────────────────────────────────────────────');
    stdout.write('ENTER=continuar | skip> ');
    final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (line == 'skip') return false;
    _buyerReady = true;
    return true;
  }

  Future<bool> confirmSellerStudio({bool required = false}) async {
    if (_sellerReady) return true;
    if (!enabled) return !required;
    print('');
    print('┌─ GUIDED ─────────────────────────────────────────');
    print('│ Confirma que estás no studio vendedor');
    print('└──────────────────────────────────────────────────');
    stdout.write('ENTER=continuar | skip> ');
    final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (line == 'skip') return false;
    _sellerReady = true;
    return true;
  }

  /// A089 harness: o Maestro não expande o painel — operador toca «Operação» no device.
  Future<bool> confirmHarnessOperacaoExpanded() async {
    return pauseForOperator(
      'A089 — expandir Operação no emulador seller',
      [
        'No emulador SELLER (5554) deves ver o painel MAESTRO (sem vídeo).',
        'Toca na tab «Operação» no TOPO para EXPANDIR o painel.',
        'Opcional: se vires «No saco (1)», toca para abrir a lista.',
        'Confirma que vês o botão «Aceitar» antes de carregar ENTER.',
      ],
    );
  }

  Future<bool> confirmHelperLinkInvalidScreen() async {
    return pauseForOperator(
      'A387 — ecrã convite inválido no emulador buyer',
      [
        'No emulador BUYER (5558) deves ver «Convite indisponível».',
        'Se ainda estás no Início, o deep link pode não ter aberto —',
        '  abre manualmente o link de convite inválido ou aguarda.',
        'Quando vires o ecrã de convite inválido, carrega ENTER.',
      ],
    );
  }

  /// Pausa — imprime instruções e espera ENTER (terminal interactivo).
  Future<bool> pauseForOperator(String title, List<String> steps) async {
    print('');
    print('┌─ PAUSA: $title ─────────────────────────────────');
    for (final s in steps) {
      print('│ $s');
    }
    if (!enabled) {
      print('│ (sem --guided: continua automaticamente após adb/Maestro)');
      print('└──────────────────────────────────────────────────');
      return true;
    }
    print('│ ENTER=continuar | skip=saltar');
    print('└──────────────────────────────────────────────────');
    stdout.write('pausa> ');
    final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (line == 'skip' || line == 's') return false;
    return true;
  }

  Future<bool> confirmStripeOrVod(String label) async {
    if (!enabled) return false;
    print('');
    print('┌─ GUIDED ─────────────────────────────────────────');
    print('│ $label');
    print('│ ENTER=pass | fail | skip> ');
    print('└──────────────────────────────────────────────────');
    stdout.write('resultado> ');
    final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    return line == 'pass' || line == 'p' || line.isEmpty;
  }
}

/// Lê chaves de ficheiro KEY=VALUE.
Map<String, String> parseEnvFile(String path) {
  final out = <String, String>{};
  final f = File(path);
  if (!f.existsSync()) return out;
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
