import '../live_ops_staging_client.dart';
import 'provision/bot_provisioner.dart';

class BotSession {
  BotSession({
    required this.account,
    required this.client,
    required this.liveId,
    required this.runNotesTag,
  });

  final BotAccount account;
  final LiveOpsStagingClient client;
  final String liveId;
  final String runNotesTag;

  String get userId => account.userId;
  String get tag => account.internalTag;
  String get token => account.accessToken;

  Future<int> viewerPing() async {
    final raw = await client.rpc(
      'batata_live_viewer_ping',
      {'p_live_id': liveId},
      accessToken: token,
    );
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  Future<Map<String, dynamic>> sendChat(String body) async {
    await viewerPing();
    return client.insertAsUser(
      'live_messages',
      {
        'live_id': liveId,
        'user_id': userId,
        'kind': 'chat',
        'body': body,
        'sender_label': '${account.displayName} [${account.internalTag}]',
      },
      accessToken: token,
    );
  }

  Future<Map<String, dynamic>> createReservation({
    required String liveItemId,
    required String sellerId,
    int qty = 1,
    String? extraNotes,
  }) async {
    final notes = [
      runNotesTag,
      if (extraNotes != null && extraNotes.isNotEmpty) extraNotes,
    ].join(' | ');

    final existing = await client.selectAsUser(
      'live_reservation_requests',
      accessToken: token,
      filter:
          'live_id=eq.$liveId&live_item_id=eq.$liveItemId&buyer_id=eq.$userId&status=eq.pending&source=eq.fleaber_live',
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final rid = row['id']?.toString() ?? '';
      if (rid.isNotEmpty) {
        final cur = (row['requested_qty'] as num?)?.toInt() ?? 1;
        await client.patchAsUser(
          'live_reservation_requests',
          'id=eq.$rid',
          {
            'requested_qty': cur + qty,
            'notes': notes,
          },
          accessToken: token,
        );
        final refreshed = await client.selectAsUser(
          'live_reservation_requests',
          accessToken: token,
          filter: 'id=eq.$rid',
          limit: 1,
        );
        if (refreshed.isNotEmpty) return refreshed.first;
        return row;
      }
    }

    return client.insertAsUser(
      'live_reservation_requests',
      {
        'live_id': liveId,
        'live_item_id': liveItemId,
        'seller_id': sellerId,
        'buyer_id': userId,
        'requested_qty': qty,
        'source': 'fleaber_live',
        'status': 'pending',
        'notes': notes,
      },
      accessToken: token,
    );
  }

  Future<dynamic> joinRaffle(String raffleId) async {
    return client.rpc(
      'batata_join_live_raffle',
      {'p_raffle_id': raffleId},
      accessToken: token,
    );
  }

  Future<Map<String, dynamic>> followSeller(String sellerId) async {
    return client.insertAsUser(
      'follows',
      {
        'follower_id': userId,
        'following_id': sellerId,
      },
      accessToken: token,
    );
  }

  Future<dynamic> stockSnapshot(String liveItemId) async {
    return client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': liveItemId},
      accessToken: token,
    );
  }
}
