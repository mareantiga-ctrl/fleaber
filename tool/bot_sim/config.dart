import 'util/parse_duration.dart' show parseBotSimDuration;

class BotSimConfig {
  BotSimConfig({
    required this.liveId,
    required this.botCount,
    required this.activeChatters,
    required this.duration,
    required this.scenarios,
    required this.demoMode,
    required this.cleanup,
    required this.keep,
    required this.forceStaging,
    required this.observeUi,
    required this.runId,
    required this.prefix,
  });

  final String liveId;
  final int botCount;
  final int activeChatters;
  final Duration duration;
  final Set<String> scenarios;
  final bool demoMode;
  final bool cleanup;
  final bool keep;
  final bool forceStaging;
  final bool observeUi;
  final String runId;
  final String prefix;

  static BotSimConfig parse(List<String> args) {
    String? liveId;
    var bots = 50;
    var chatters = 5;
    var durationRaw = '10m';
    var scenarioRaw = 'full';
    var demoMode = false;
    var cleanup = false;
    var keep = false;
    var force = false;
    var observeUi = false;
    var prefix = 'DEMO_BOT';

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      switch (a) {
        case '--live-id':
          liveId = next()?.trim();
        case '--bots':
          bots = int.tryParse(next() ?? '') ?? bots;
        case '--active-chatters':
          chatters = int.tryParse(next() ?? '') ?? chatters;
        case '--duration':
          durationRaw = next() ?? durationRaw;
        case '--scenario':
          scenarioRaw = next() ?? scenarioRaw;
        case '--demo-mode':
          demoMode = true;
        case '--cleanup':
          cleanup = true;
        case '--keep':
          keep = true;
        case '--i-know-this-is-staging':
          force = true;
        case '--observe-ui':
          observeUi = true;
        case '--prefix':
          prefix = next()?.trim().toUpperCase() ?? prefix;
        case '--help':
        case '-h':
          _printHelp();
          throw _HelpRequested();
      }
    }

    if (liveId == null || liveId.isEmpty) {
      throw ArgumentError('--live-id é obrigatório');
    }
    if (bots < 1) throw ArgumentError('--bots deve ser >= 1');
    if (chatters < 0) throw ArgumentError('--active-chatters inválido');
    if (chatters > bots) chatters = bots;

    final scenarios = _parseScenarios(scenarioRaw);
    final runId = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');

    return BotSimConfig(
      liveId: liveId,
      botCount: bots,
      activeChatters: chatters,
      duration: parseBotSimDuration(durationRaw),
      scenarios: scenarios,
      demoMode: demoMode,
      cleanup: cleanup && !keep,
      keep: keep,
      forceStaging: force,
      observeUi: observeUi,
      runId: runId,
      prefix: prefix,
    );
  }

  static Set<String> _parseScenarios(String raw) {
    final parts = raw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (parts.contains('full')) {
      return {
        'viewers',
        'chat',
        'reservations',
        'price_pending',
        'raffles',
        'follows',
      };
    }
    return parts;
  }

  String runNotesTag() => 'STRESS_TEST:$runId';

  static void _printHelp() {
    // ignore: avoid_print
    print('''
Fleaber Bot Simulator (staging/demo apenas)

  dart run tool/fleaber_bot_simulator.dart --live-id <uuid> [opções]

Opções:
  --bots 50                 Número de bots (viewers)
  --active-chatters 5       Bots que escrevem no chat
  --duration 10m            Duração (10m, 30s, 1h)
  --scenario full           viewers,chat,reservations,price_pending,raffles,follows,full
  --demo-mode               Nomes simpáticos + ritmo natural
  --cleanup                 Apagar dados criados (default: manter se --keep)
  --keep                    Manter dados para análise
  --prefix DEMO_BOT         Prefixo interno dos bots
  --observe-ui              Abrir browser para observar (Windows)
  --i-know-this-is-staging  Ignorar guard de project ref

Env (tool/live_ops_staging.env):
  BOT_SIM_ALLOWED_PROJECT_REFS=your_staging_ref
  BOT_SIM_EMAIL_DOMAIN=staging.fleaber.bot
  BOT_SIM_DEFAULT_PASSWORD=...
''');
  }
}

class _HelpRequested implements Exception {}

bool isHelpRequested(Object e) => e is _HelpRequested;
