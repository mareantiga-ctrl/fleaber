import 'dart:convert';
import 'dart:io';

import '../../live_ops_staging_client.dart';

class DbSnapshotter {
  DbSnapshotter(this.client);

  final LiveOpsStagingClient client;

  Future<Map<String, dynamic>> capture({
    required String liveId,
  }) async {
    final live = await client.select(
      'lives',
      filter: 'id=eq.$liveId',
      limit: 1,
    );
    final viewers = await client.select(
      'live_viewers',
      filter: 'live_id=eq.$liveId',
      limit: 500,
    );
    final messageCount = await client.countRows(
      'live_messages',
      filter: 'live_id=eq.$liveId',
    );
    final messages = await client.select(
      'live_messages',
      filter: 'live_id=eq.$liveId&order=created_at.desc',
      limit: 200,
    );
    final reservations = await client.select(
      'live_reservation_requests',
      filter: 'live_id=eq.$liveId',
      limit: 500,
    );
    final items = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 200,
    );
    final raffles = await client.select(
      'live_raffles',
      filter: 'live_id=eq.$liveId',
      limit: 20,
    );
    List<Map<String, dynamic>> raffleEntries = [];
    List<Map<String, dynamic>> raffleWinners = [];
    if (raffles.isNotEmpty) {
      final raffleIds = raffles.map((r) => r['id']).whereType<String>().join(',');
      if (raffleIds.isNotEmpty) {
        raffleEntries = await client.select(
          'live_raffle_entries',
          filter: 'live_id=eq.$liveId',
          limit: 500,
        );
        raffleWinners = await client.select(
          'live_raffle_winners',
          filter: 'raffle_id=in.($raffleIds)',
          limit: 50,
        );
      }
    }
  final orders = await client.select(
      'orders',
      filter: 'live_id=eq.$liveId',
      limit: 100,
    );
    List<Map<String, dynamic>> appLogs = [];
    try {
      appLogs = await client.select(
        'app_logs',
        filter:
            'created_at=gte.${DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()}',
        limit: 100,
      );
    } catch (_) {}

    return {
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'live_id': liveId,
      'live': live,
      'viewer_count_reported': live.isEmpty ? null : live.first['viewer_count'],
      'live_viewers': viewers,
      'live_messages_count': messageCount,
      'live_messages_sample': messages.take(50).toList(),
      'live_reservation_requests': reservations,
      'live_items': items,
      'live_raffles': raffles,
      'live_raffle_entries': raffleEntries,
      'live_raffle_winners': raffleWinners,
      'orders': orders,
      'app_logs_recent': appLogs,
    };
  }

  Future<void> write(File file, Map<String, dynamic> data) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }
}
