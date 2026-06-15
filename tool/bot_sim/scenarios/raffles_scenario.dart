import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

Future<void> runRafflesScenario(BotSimRunContext ctx) async {
  // Procurar rifa activa ou criar uma (seller)
  var raffles = await ctx.client.select(
    'live_raffles',
    filter: 'live_id=eq.${ctx.live.liveId}&status=eq.active',
    limit: 1,
  );

  String? raffleId;
  var ownsRaffle = false;
  if (raffles.isEmpty) {
    try {
      final created = await ctx.client.rpc(
        'batata_create_live_raffle',
        {
          'p_live_id': ctx.live.liveId,
          'p_title': 'STRESS_TEST Rifa Bot Sim',
          'p_description': ctx.runNotesTag,
          'p_winner_count': 1,
          'p_activate': true,
        },
        accessToken: ctx.sellerToken,
      );
      if (created is Map && created['ok'] == true) {
        raffleId = created['raffle_id']?.toString();
        ownsRaffle = true;
      }
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: ctx.live.sellerId,
        botTag: 'SELLER',
        action: 'raffle.create',
        outcome: raffleId != null ? BotEventOutcome.ok : BotEventOutcome.fail,
        actual: created,
      ));
    } catch (e) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: ctx.live.sellerId,
        botTag: 'SELLER',
        action: 'raffle.create',
        outcome: BotEventOutcome.fail,
        error: e.toString(),
      ));
      return;
    }
  } else {
    final row = raffles.first;
    raffleId = row['id']?.toString();
    final title = row['title']?.toString() ?? '';
    final desc = row['description']?.toString() ?? '';
    ownsRaffle =
        title.contains('STRESS_TEST') || desc.contains(ctx.runNotesTag);
    if (!ownsRaffle) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: 'system',
        botTag: 'SYSTEM',
        action: 'raffle.draw_skipped',
        outcome: BotEventOutcome.skip,
        actual:
            'Rifa activa existente não é de teste — só join, sem close/draw',
      ));
    }
  }

  if (raffleId == null || raffleId.isEmpty) return;

  final joiners = ctx.bots.take((ctx.bots.length * 0.5).ceil().clamp(3, 30)).toList();

  for (final bot in joiners) {
    final s = ctx.session(bot);
    try {
      await ctx.logger.timed(
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'raffle.join',
        expected: 'ok true',
        meta: {'raffle_id': raffleId},
        run: () => s.joinRaffle(raffleId!),
        actualFrom: (r) => r,
      );
    } catch (e) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'raffle.join',
        outcome: BotEventOutcome.fail,
        error: e.toString(),
      ));
    }
    await jitterMs(200, 900);
  }

  // Duplicado: primeiro bot tenta join outra vez
  if (joiners.isNotEmpty) {
    final bot = joiners.first;
  try {
      final dup = await ctx.session(bot).joinRaffle(raffleId);
      final isDup = dup is Map && dup['duplicate'] == true;
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'raffle.join_duplicate',
        outcome: isDup ? BotEventOutcome.ok : BotEventOutcome.fail,
        expected: 'duplicate true',
        actual: dup,
      ));
    } catch (e) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'raffle.join_duplicate',
        outcome: BotEventOutcome.ok,
        actual: 'rejected',
        error: e.toString(),
      ));
    }
  }

  // Seller fecha e sorteia — só rifas criadas pelo simulador
  if (!ownsRaffle) return;
  try {
    await ctx.client.rpc(
      'batata_close_live_raffle',
      {'p_raffle_id': raffleId},
      accessToken: ctx.sellerToken,
    );
    final draw = await ctx.client.rpc(
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': raffleId},
      accessToken: ctx.sellerToken,
    );
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: ctx.live.sellerId,
      botTag: 'SELLER',
      action: 'raffle.draw',
      outcome: BotEventOutcome.ok,
      actual: draw,
    ));
  } catch (e) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: ctx.live.sellerId,
      botTag: 'SELLER',
      action: 'raffle.draw',
      outcome: BotEventOutcome.fail,
      error: e.toString(),
    ));
  }
}
