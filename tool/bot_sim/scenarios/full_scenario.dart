import '../run_context.dart';
import 'chat_scenario.dart';
import 'follows_scenario.dart';
import 'price_pending_scenario.dart';
import 'raffles_scenario.dart';
import 'reservations_scenario.dart';
import 'viewers_scenario.dart';

/// Orquestra todos os cenários com divisão temporal natural.
Future<void> runFullScenario(BotSimRunContext ctx) async {
  final total = ctx.config.duration;
  final viewersBudget = Duration(
    milliseconds: (total.inMilliseconds * 0.45).round(),
  );
  final chatBudget = Duration(
    milliseconds: (total.inMilliseconds * 0.35).round(),
  );

  await runViewersScenario(ctx, budget: viewersBudget);

  // Chat em paralelo conceptual — sequencial com overlap via viewers heartbeats já feitos
  await runChatScenario(ctx, budget: chatBudget);

  await runReservationsScenario(ctx);
  await runPricePendingScenario(ctx);
  await runRafflesScenario(ctx);
  await runFollowsScenario(ctx);
}
