import 'dart:math';

import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

final _rng = Random();

/// Bots entram, fazem heartbeat, saem gradualmente.
Future<void> runViewersScenario(
  BotSimRunContext ctx, {
  required Duration budget,
}) async {
  final endAt = DateTime.now().add(budget);
  final active = <String>{};
  final pingInterval = ctx.config.demoMode
      ? const Duration(seconds: 20)
      : const Duration(seconds: 15);

  final rampMs = (budget.inMilliseconds * 0.3).round();
  final perBotMs =
      ctx.bots.isEmpty ? 0 : rampMs ~/ ctx.bots.length;

  for (final bot in ctx.bots) {
    if (DateTime.now().isAfter(endAt)) break;
    final s = ctx.session(bot);
    try {
      await ctx.logger.timed(
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'viewer.join_ping',
        expected: 'viewer_count >= 1',
        run: () => s.viewerPing(),
        actualFrom: (int c) => {'viewer_count': c},
      );
      active.add(bot.userId);
    } catch (_) {}
    if (perBotMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: perBotMs));
    } else {
      await jitterMs(50, 200);
    }
  }

  final heartbeatUntil = DateTime.now().add(
    Duration(milliseconds: (budget.inMilliseconds * 0.7).round()),
  );
  while (DateTime.now().isBefore(heartbeatUntil) && active.isNotEmpty) {
    final shuffled = active.toList()..shuffle(_rng);
    for (final uid in shuffled) {
      if (DateTime.now().isAfter(heartbeatUntil)) break;
      final bot = ctx.bots.firstWhere((b) => b.userId == uid);
      final s = ctx.session(bot);
      try {
        await ctx.logger.timed(
          botId: bot.userId,
          botTag: bot.internalTag,
          action: 'viewer.heartbeat',
          run: () => s.viewerPing(),
          actualFrom: (int c) => {'viewer_count': c},
        );
      } catch (_) {}
      await jitterMs(100, 400);
    }
    await Future<void>.delayed(pingInterval);
  }

  final leaveOrder = active.toList()..shuffle(_rng);
  for (final uid in leaveOrder) {
    if (DateTime.now().isAfter(endAt)) break;
    final bot = ctx.bots.firstWhere((b) => b.userId == uid);
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'viewer.leave',
      outcome: BotEventOutcome.ok,
      actual: 'stopped_ping_ttl_45s',
    ));
    active.remove(uid);
    await jitterMs(300, 1200);
  }
}
