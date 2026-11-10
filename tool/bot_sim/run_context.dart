import 'dart:io';

import '../live_ops_staging_client.dart';
import 'bot_session.dart';
import 'config.dart';
import 'provision/bot_provisioner.dart';
import 'report/event_logger.dart';

class LiveContext {
  LiveContext({
    required this.liveId,
    required this.sellerId,
    required this.sellerToken,
    required this.title,
    required this.items,
  });

  final String liveId;
  final String sellerId;
  final String sellerToken;
  final String title;
  final List<Map<String, dynamic>> items;

  Map<String, dynamic>? itemWithPrice() {
    for (final it in items) {
      final p = it['price'];
      if (p is num && p > 0) return it;
    }
    return items.isEmpty ? null : items.first;
  }

  Map<String, dynamic>? itemWithoutPrice() {
    for (final it in items) {
      final p = it['price'];
      if (p == null || (p is num && p <= 0)) return it;
    }
    return null;
  }
}

class BotSimRunContext {
  BotSimRunContext({
    required this.config,
    required this.env,
    required this.client,
    required this.logger,
    required this.reportDir,
    required this.bots,
    required this.live,
    required this.sellerToken,
  });

  final BotSimConfig config;
  final Map<String, String> env;
  final LiveOpsStagingClient client;
  final EventLogger logger;
  final Directory reportDir;
  final List<BotAccount> bots;
  final LiveContext live;
  final String sellerToken;

  String get runNotesTag => config.runNotesTag();

  BotSession session(BotAccount bot) => BotSession(
        account: bot,
        client: client,
        liveId: live.liveId,
        runNotesTag: runNotesTag,
      );
}
