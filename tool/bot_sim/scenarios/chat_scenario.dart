import '../fixtures/chat_phrases.dart';
import '../report/event_logger.dart';
import '../run_context.dart';
import '../util/jitter.dart';

Future<void> runChatScenario(
  BotSimRunContext ctx, {
  required Duration budget,
}) async {
  final endAt = DateTime.now().add(budget);
  final chatters = ctx.bots.take(ctx.config.activeChatters).toList();
  if (chatters.isEmpty) return;

  final minGap = ctx.config.demoMode ? 4000 : 2000;
  final maxGap = ctx.config.demoMode ? 12000 : 8000;

  while (DateTime.now().isBefore(endAt)) {
    for (final bot in chatters) {
      if (DateTime.now().isAfter(endAt)) break;
      final phrase = pickChatPhrase(demoMode: ctx.config.demoMode);
      final s = ctx.session(bot);
      try {
        await ctx.logger.timed(
          botId: bot.userId,
          botTag: bot.internalTag,
          action: 'chat.send',
          expected: 'message inserted',
          meta: {'body': phrase},
          run: () => s.sendChat(phrase),
          actualFrom: (row) => {'message_id': row['id']},
        );
      } catch (e) {
        await ctx.logger.log(BotSimEvent(
          timestamp: DateTime.now(),
          botId: bot.userId,
          botTag: bot.internalTag,
          action: 'chat.send',
          outcome: BotEventOutcome.fail,
          error: e.toString(),
        ));
      }
      await jitterMs(minGap, maxGap);
    }
  }
}
