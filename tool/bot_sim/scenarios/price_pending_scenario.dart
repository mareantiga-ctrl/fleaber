import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

Future<void> runPricePendingScenario(BotSimRunContext ctx) async {
  var item = ctx.live.itemWithoutPrice();
  final sellerId = ctx.live.sellerId;

  // Se não houver artigo sem preço, criar um via update a null não é seguro —
  // usar primeiro item e seller define preço depois de reserva (simula price pending)
  item ??= ctx.live.items.isNotEmpty ? ctx.live.items.first : null;

  if (item == null) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: 'system',
      botTag: 'SYSTEM',
      action: 'price_pending.skip',
      outcome: BotEventOutcome.skip,
      error: 'Sem live_items na live',
    ));
    return;
  }

  final itemId = item['id']?.toString() ?? '';
  if (itemId.isEmpty) return;

  final bot = ctx.bots.first;
  final s = ctx.session(bot);

  // 1) Reserva com artigo possivelmente sem preço
  Map<String, dynamic>? requestRow;
  try {
    final row = await s.createReservation(
      liveItemId: itemId,
      sellerId: sellerId,
      extraNotes: 'price_pending_test',
    );
    requestRow = row;
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'price_pending.reserve',
      outcome: BotEventOutcome.ok,
      expected: 'pending reservation',
      actual: {'request_id': row['id']},
    ));
  } catch (e) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'price_pending.reserve',
      outcome: BotEventOutcome.fail,
      error: e.toString(),
    ));
  }

  await jitterMs(500, 1500);

  // 2) Seller define preço manualmente
  const testPrice = 19.99;
  try {
    await ctx.logger.timed(
      botId: sellerId,
      botTag: 'SELLER',
      action: 'price_pending.seller_set_price',
      expected: {'price': testPrice},
      meta: {'live_item_id': itemId},
      run: () => ctx.client.rpc(
        'batata_update_live_item',
        {
          'p_live_item_id': itemId,
          'p_price': testPrice,
        },
        accessToken: ctx.sellerToken,
      ),
      actualFrom: (r) => r,
    );
  } catch (e) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: sellerId,
      botTag: 'SELLER',
      action: 'price_pending.seller_set_price',
      outcome: BotEventOutcome.fail,
      error: e.toString(),
    ));
  }

  await jitterMs(300, 800);

  // 3) Bot verifica stock/preço pagável (sem Stripe)
  try {
    final snap = await s.stockSnapshot(itemId);
    final price = snap is Map ? snap['price'] : null;
    final payable = price is num && price > 0;
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'price_pending.check_payable',
      outcome: payable ? BotEventOutcome.ok : BotEventOutcome.fail,
      expected: 'price > 0',
      actual: price,
      meta: {
        'request_id': requestRow?['id'],
        'note': 'checkout Stripe não simulado em staging bot',
      },
    ));
  } catch (e) {
    await ctx.logger.log(BotSimEvent(
      timestamp: DateTime.now(),
      botId: bot.userId,
      botTag: bot.internalTag,
      action: 'price_pending.check_payable',
      outcome: BotEventOutcome.fail,
      error: e.toString(),
    ));
  }
}
