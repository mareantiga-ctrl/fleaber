import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

Future<void> runFollowsScenario(BotSimRunContext ctx) async {
  final sellerId = ctx.live.sellerId;
  final followers = ctx.bots.take((ctx.bots.length * 0.2).ceil().clamp(2, 10)).toList();

  for (final bot in followers) {
    final s = ctx.session(bot);
    try {
      await ctx.logger.timed(
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'follow.create',
        expected: 'follow row',
        meta: {'seller_id': sellerId},
        run: () => s.followSeller(sellerId),
        actualFrom: (row) => {'follow_id': row['id']},
      );
    } catch (e) {
      final err = e.toString().toLowerCase();
      final dup = err.contains('duplicate') ||
          err.contains('unique') ||
          err.contains('23505');
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'follow.create',
        outcome: dup ? BotEventOutcome.ok : BotEventOutcome.fail,
        expected: 'follow or already following',
        error: e.toString(),
      ));
    }
    await jitterMs(300, 1500);
  }

  // Duplicado explícito
  if (followers.isNotEmpty) {
    final bot = followers.first;
    try {
      await ctx.session(bot).followSeller(sellerId);
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'follow.duplicate',
        outcome: BotEventOutcome.fail,
        error: 'deveria falhar',
      ));
    } catch (_) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'follow.duplicate',
        outcome: BotEventOutcome.ok,
        actual: 'rejected_duplicate',
      ));
    }
  }

  // Lifetime grants (se existirem na BD)
  for (final bot in followers.take(3)) {
    final grants = await ctx.client.select(
      'live_raffle_lifetime_grants',
      filter: 'user_id=eq.${bot.userId}&seller_id=eq.$sellerId',
      limit: 5,
    );
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'follow.lifetime_grants_check',
      outcome: BotEventOutcome.ok,
      actual: {
        'grant_count': grants.length,
        'note': grants.isEmpty
            ? 'sem grants configurados (OK se feature ainda não activa)'
            : 'grants presentes',
      },
    ));
  }
}
