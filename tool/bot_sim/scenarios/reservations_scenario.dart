import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

Future<void> runReservationsScenario(BotSimRunContext ctx) async {
  final item = ctx.live.itemWithPrice();
  if (item == null) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: 'system',
      botTag: 'SYSTEM',
      action: 'reservation.skip',
      outcome: BotEventOutcome.skip,
      error: 'Nenhum live_item com preço na live',
    ));
    return;
  }

  final itemId = item['id']?.toString() ?? '';
  final sellerId = ctx.live.sellerId;
  if (itemId.isEmpty) return;

  final reservers = ctx.bots.take((ctx.bots.length * 0.3).ceil().clamp(1, 15)).toList();

  for (final bot in reservers) {
    final s = ctx.session(bot);
    try {
      await ctx.logger.timed(
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'reservation.create',
        expected: 'pending request',
        meta: {'live_item_id': itemId},
        run: () => s.createReservation(
          liveItemId: itemId,
          sellerId: sellerId,
        ),
        actualFrom: (row) => {
          'request_id': row['id'],
          'status': row['status'],
        },
      );
    } catch (e) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'reservation.create',
        outcome: BotEventOutcome.fail,
        error: e.toString(),
      ));
    }
    await jitterMs(400, 2000);
  }

  // Duplicado: mesmo bot tenta segunda vez (deve incrementar qty ou falhar graciosamente)
  if (reservers.isNotEmpty) {
    final bot = reservers.first;
    final s = ctx.session(bot);
    try {
      await ctx.logger.timed(
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'reservation.duplicate_attempt',
        expected: 'single pending or qty bump',
        run: () => s.createReservation(
          liveItemId: itemId,
          sellerId: sellerId,
          extraNotes: 'duplicate_test',
        ),
        actualFrom: (row) => row,
      );
    } catch (e) {
      await ctx.logger.log(BotSimEvent(
        timestamp: DateTime.now(),
        botId: bot.userId,
        botTag: bot.internalTag,
        action: 'reservation.duplicate_attempt',
        outcome: BotEventOutcome.ok,
        actual: 'rejected_or_merged',
        error: e.toString(),
      ));
    }
  }

  // Stock check
  if (reservers.isNotEmpty) {
    final snap = await ctx.session(reservers.first).stockSnapshot(itemId);
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: 'system',
      botTag: 'SYSTEM',
      action: 'reservation.stock_snapshot',
      outcome: BotEventOutcome.ok,
      actual: snap,
    ));
  }
}
