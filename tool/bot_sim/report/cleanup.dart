import '../../live_ops_staging_client.dart';

Future<void> cleanupBotSimRun({
  required LiveOpsStagingClient client,
  required String liveId,
  required String runNotesTag,
  required List<String> botUserIds,
}) async {
  final enc = Uri.encodeComponent('%$runNotesTag%');

  await client.deleteWhere(
    'live_reservation_requests',
    'live_id=eq.$liveId&notes=ilike.$enc',
  );

  await client.deleteWhere(
    'live_messages',
    'live_id=eq.$liveId&sender_label=ilike.%25DEMO_BOT%25',
  );

  for (final uid in botUserIds) {
    await client.deleteWhere(
      'live_viewers',
      'live_id=eq.$liveId&user_id=eq.$uid',
    );
  }

  // Rifas de teste criadas nesta run
  final raffles = await client.select(
    'live_raffles',
    filter: 'live_id=eq.$liveId&title=ilike.%25STRESS_TEST%25',
    limit: 20,
  );
  for (final r in raffles) {
    final rid = r['id']?.toString();
    if (rid == null) continue;
    await client.deleteWhere('live_raffle_winners', 'raffle_id=eq.$rid');
    await client.deleteWhere('live_raffle_entries', 'raffle_id=eq.$rid');
    await client.deleteWhere('live_raffle_actions', 'raffle_id=eq.$rid');
    await client.deleteWhere('live_raffle_audit_log', 'raffle_id=eq.$rid');
    await client.deleteWhere('live_raffles', 'id=eq.$rid');
  }

  // Follows bot → seller (opcional, só bots desta run)
  for (final uid in botUserIds) {
    await client.deleteWhere('follows', 'follower_id=eq.$uid');
  }
}
