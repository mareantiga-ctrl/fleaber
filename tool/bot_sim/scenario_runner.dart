import 'run_context.dart';
import 'scenarios/chat_scenario.dart';
import 'scenarios/follows_scenario.dart';
import 'scenarios/full_scenario.dart';
import 'scenarios/price_pending_scenario.dart';
import 'scenarios/raffles_scenario.dart';
import 'scenarios/reservations_scenario.dart';
import 'scenarios/viewers_scenario.dart';

Future<void> runScenarios(BotSimRunContext ctx) async {
  final s = ctx.config.scenarios;
  final isFull = s.length >= 6;

  if (isFull) {
    await runFullScenario(ctx);
    return;
  }

  final total = ctx.config.duration;
  if (s.contains('viewers')) {
    await runViewersScenario(
      ctx,
      budget: Duration(milliseconds: (total.inMilliseconds * 0.4).round()),
    );
  }
  if (s.contains('chat')) {
    await runChatScenario(
      ctx,
      budget: Duration(milliseconds: (total.inMilliseconds * 0.3).round()),
    );
  }
  if (s.contains('reservations')) {
    await runReservationsScenario(ctx);
  }
  if (s.contains('price_pending')) {
    await runPricePendingScenario(ctx);
  }
  if (s.contains('raffles')) {
    await runRafflesScenario(ctx);
  }
  if (s.contains('follows')) {
    await runFollowsScenario(ctx);
  }
}
