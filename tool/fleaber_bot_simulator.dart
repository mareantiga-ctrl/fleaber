// ignore_for_file: avoid_print
/// Simulador interno de bots / stress test para lives Fleaber (staging apenas).
///
///   dart run tool/fleaber_bot_simulator.dart --live-id <uuid> --bots 50 --scenario full
library;

import 'dart:io';

import 'bot_sim/config.dart';
import 'bot_sim/provision/bot_provisioner.dart';
import 'bot_sim/report/cleanup.dart';
import 'bot_sim/report/db_snapshot.dart';
import 'bot_sim/report/event_logger.dart';
import 'bot_sim/report/run_report.dart';
import 'bot_sim/report/validators.dart';
import 'bot_sim/run_context.dart';
import 'bot_sim/scenario_runner.dart';
import 'bot_sim/staging_guard.dart';
import 'live_ops_staging_client.dart';

Future<void> _ensureLiveActiveForBots(
  LiveOpsStagingClient client,
  String liveId,
  Map<String, dynamic> liveRow,
) async {
  final status = liveRow['status']?.toString() ?? '';
  final active = liveRow['is_active'] == true;
  if (status != 'live' || !active) {
    await client.patch('lives', 'id=eq.$liveId', {
      'status': 'live',
      'is_active': true,
    });
    print('Live reactivada para bots (status=live, is_active=true)');
  }
}

Future<void> main(List<String> args) async {
  BotSimConfig config;
  try {
    config = BotSimConfig.parse(args);
  } catch (e) {
    if (isHelpRequested(e)) return;
    print('Argumentos: $e');
    print('Usa --help para ajuda.');
    exitCode = 1;
    return;
  }

  final startedAt = DateTime.now();
  final stamp = startedAt.toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
  final reportDir = Directory('tool/reports/bot_sim_$stamp');
  await reportDir.create(recursive: true);

  print('Fleaber Bot Simulator');
  print('Run: ${config.runId}');
  print('Relatório: ${reportDir.path}');
  print('---');

  try {
    final env = loadLiveOpsStagingEnv();
    final client = LiveOpsStagingClient(
      url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
      anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
      serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    );

    assertBotSimStagingAllowed(
      projectUrl: client.url,
      env: env,
      force: config.forceStaging,
    );

    final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
    final sellerToken = await client.signIn(
      email: sellerEmail,
      password: sellerPassword,
    );

    final liveRows = await client.select(
      'lives',
      filter: 'id=eq.${config.liveId}',
      limit: 1,
    );
    if (liveRows.isEmpty) {
      throw StateError('Live ${config.liveId} não encontrada em staging');
    }
    final liveRow = liveRows.first;
    final sellerId = (liveRow['seller_id'] ?? liveRow['vendedor_id'])?.toString() ?? '';
    if (!isUuid(sellerId)) {
      throw StateError('Live sem seller_id válido');
    }

    final items = await client.select(
      'live_items',
      filter: 'live_id=eq.${config.liveId}',
      limit: 200,
    );

    await _ensureLiveActiveForBots(client, config.liveId, liveRow);

    print('Live: ${liveRow['title'] ?? config.liveId}');
    print('Seller: $sellerId');
    print('Items: ${items.length}');
    print('A provisionar ${config.botCount} bots…');

    final bots = await BotProvisioner(
      client: client,
      env: env,
      count: config.botCount,
      prefix: config.prefix,
      demoMode: config.demoMode,
    ).provision();

    print('Bots prontos: ${bots.length}');

    final logger = EventLogger(reportDir);
    final snapshotter = DbSnapshotter(client);

    final before = await snapshotter.capture(liveId: config.liveId);
    await snapshotter.write(
      File('${reportDir.path}/db_snapshot_before.json'),
      before,
    );

    final ctx = BotSimRunContext(
      config: config,
      env: env,
      client: client,
      logger: logger,
      reportDir: reportDir,
      bots: bots,
      live: LiveContext(
        liveId: config.liveId,
        sellerId: sellerId,
        sellerToken: sellerToken,
        title: liveRow['title']?.toString() ?? '',
        items: items,
      ),
      sellerToken: sellerToken,
    );

    if (config.observeUi) {
      await _maybeOpenObserver(env, config.liveId);
    }

    print('Cenários: ${config.scenarios.join(', ')}');
    await runScenarios(ctx);

    // Aguardar TTL viewers se cenário viewers correu
    if (config.scenarios.contains('viewers') || config.scenarios.length >= 6) {
      print('Aguardar 3s pós-cenários…');
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    final after = await snapshotter.capture(liveId: config.liveId);
    await snapshotter.write(
      File('${reportDir.path}/db_snapshot_after.json'),
      after,
    );

    final expectedChat = config.scenarios.contains('chat') ||
            config.scenarios.length >= 6
        ? 1
        : 0;

    final issues = BotSimValidators.run(
      before: before,
      after: after,
      runNotesTag: config.runNotesTag(),
      expectedChatEvents: expectedChat,
      botCount: config.botCount,
    );

    await writeRunReports(
      reportDir: reportDir,
      logger: logger,
      issues: issues,
      meta: {
        'live_id': config.liveId,
        'run_id': config.runId,
        'scenarios': config.scenarios.join(', '),
        'bots': config.botCount,
        'chatters': config.activeChatters,
        'duration': config.duration.toString(),
        'demo_mode': config.demoMode,
      },
    );

    if (config.cleanup) {
      print('Cleanup…');
      await cleanupBotSimRun(
        client: client,
        liveId: config.liveId,
        runNotesTag: config.runNotesTag(),
        botUserIds: bots.map((b) => b.userId).toList(),
      );
    } else {
      print('Dados mantidos (--keep ou sem --cleanup).');
    }

    final errorCount = issues.where((i) => i.severity == 'error').length;
    final failEvents =
        logger.events.where((e) => e.outcome == BotEventOutcome.fail).length;

    print('---');
    print('Concluído em ${DateTime.now().difference(startedAt).inSeconds}s');
    print('Eventos: ${logger.events.length} (${failEvents} falhas)');
    print('Validações: $errorCount erros');
    print('Ver: ${reportDir.path}/summary.md');

    if (errorCount > 0 || failEvents > 0) {
      exitCode = 1;
    }
  } catch (e, st) {
    print('FATAL: $e');
    print(st);
    try {
      await File('${reportDir.path}/fatal.txt').writeAsString('$e\n$st');
    } catch (_) {}
    exitCode = 1;
  }
}

Future<void> _maybeOpenObserver(
  Map<String, String> env,
  String liveId,
) async {
  final template = env['FLEABER_LIVE_WEB_URL']?.trim() ?? '';
  final url = template.isEmpty
      ? 'https://fleaber.app/live/$liveId'
      : template.replaceAll('{live_id}', liveId);
  print('Observe UI: $url');
  if (!Platform.isWindows) {
    print('(Abre manualmente no browser — só auto-launch em Windows)');
    return;
  }
  try {
    await Process.run('cmd', ['/c', 'start', 'chrome', url]);
  } catch (_) {
    await Process.run('cmd', ['/c', 'start', url]);
  }
}
