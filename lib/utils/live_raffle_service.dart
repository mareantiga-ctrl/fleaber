import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';

/// Estado da Rifa da Live (RPC `batata_get_live_raffle_state`).
class LiveRaffleState {
  const LiveRaffleState({
    required this.hasRaffle,
    this.raffle,
    this.viewer = const LiveRaffleViewerState(),
    this.winners = const [],
    this.leaderboard = const [],
  });

  final bool hasRaffle;
  final LiveRaffleInfo? raffle;
  final LiveRaffleViewerState viewer;
  final List<LiveRaffleWinnerInfo> winners;
  final List<LiveRaffleLeaderboardEntry> leaderboard;

  factory LiveRaffleState.empty() => const LiveRaffleState(hasRaffle: false);

  factory LiveRaffleState.fromRpc(dynamic raw) {
    if (raw is! Map) return LiveRaffleState.empty();
    final m = Map<String, dynamic>.from(raw);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'raffle_state_failed');
    }
    if (m['has_raffle'] != true) {
      return LiveRaffleState.empty();
    }
    final raffleRaw = m['raffle'];
    final viewerRaw = m['viewer'];
    final winnersRaw = m['winners'];
    final leaderboardRaw = m['leaderboard'];
    return LiveRaffleState(
      hasRaffle: true,
      raffle: raffleRaw is Map
          ? LiveRaffleInfo.fromJson(Map<String, dynamic>.from(raffleRaw))
          : null,
      viewer: viewerRaw is Map
          ? LiveRaffleViewerState.fromJson(
              Map<String, dynamic>.from(viewerRaw),
            )
          : const LiveRaffleViewerState(),
      winners: winnersRaw is List
          ? winnersRaw
              .whereType<Map>()
              .map((e) => LiveRaffleWinnerInfo.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      leaderboard: leaderboardRaw is List
          ? leaderboardRaw
              .whereType<Map>()
              .map((e) => LiveRaffleLeaderboardEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
    );
  }
}

class LiveRaffleLeaderboardEntry {
  const LiveRaffleLeaderboardEntry({
    required this.rank,
    required this.userId,
    this.displayName,
    required this.ticketBalance,
  });

  final int rank;
  final String userId;
  final String? displayName;
  final int ticketBalance;

  factory LiveRaffleLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LiveRaffleLeaderboardEntry(
      rank: int.tryParse('${json['rank']}') ?? 0,
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      ticketBalance: int.tryParse('${json['ticket_balance']}') ?? 0,
    );
  }
}

class LiveRaffleInfo {
  const LiveRaffleInfo({
    required this.id,
    required this.liveId,
    required this.title,
    this.description,
    this.photoUrl,
    this.estimatedValueEur,
    required this.winnerCount,
    required this.status,
    this.startsAt,
    this.endsAt,
    required this.hasTimer,
    this.secondsLeft,
    this.showPublicLeaderboard = false,
    this.drawnAt,
  });

  final String id;
  final String liveId;
  final String title;
  final String? description;
  final String? photoUrl;
  final double? estimatedValueEur;
  final int winnerCount;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool hasTimer;
  final int? secondsLeft;
  final bool showPublicLeaderboard;
  final DateTime? drawnAt;

  bool get isActive => status == 'active';
  bool get isClosed => status == 'closed';
  bool get isDrawn => status == 'drawn';
  bool get isCancelled => status == 'cancelled';

  factory LiveRaffleInfo.fromJson(Map<String, dynamic> json) {
    double? est;
    final rawEst = json['estimated_value_eur'];
    if (rawEst is num) {
      est = rawEst.toDouble();
    } else if (rawEst != null) {
      est = double.tryParse('$rawEst'.replaceAll(',', '.'));
    }
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toUtc();
    }

    int? sec;
    final rawSec = json['seconds_left'];
    if (rawSec is int) {
      sec = rawSec;
    } else if (rawSec is num) {
      sec = rawSec.toInt();
    }

    return LiveRaffleInfo(
      id: json['id']?.toString() ?? '',
      liveId: json['live_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Rifa da Live',
      description: json['description']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      estimatedValueEur: est,
      winnerCount: int.tryParse('${json['winner_count']}') ?? 1,
      status: json['status']?.toString() ?? 'active',
      startsAt: parseDt(json['starts_at']),
      endsAt: parseDt(json['ends_at']),
      hasTimer: json['has_timer'] == true,
      secondsLeft: sec,
      showPublicLeaderboard: json['show_public_leaderboard'] == true,
      drawnAt: parseDt(json['drawn_at']),
    );
  }
}

class LiveRaffleViewerState {
  const LiveRaffleViewerState({
    this.joined = false,
    this.ticketBalance = 0,
    this.isWinner = false,
    this.followBonusClaimed = false,
    this.shareBonusClaimed = false,
    this.purchaseBonusClaimed = false,
  });

  final bool joined;
  final int ticketBalance;
  final bool isWinner;
  final bool followBonusClaimed;
  final bool shareBonusClaimed;
  final bool purchaseBonusClaimed;

  factory LiveRaffleViewerState.fromJson(Map<String, dynamic> json) {
    return LiveRaffleViewerState(
      joined: json['joined'] == true,
      ticketBalance: int.tryParse('${json['ticket_balance']}') ?? 0,
      isWinner: json['is_winner'] == true,
      followBonusClaimed: json['follow_bonus_claimed'] == true,
      shareBonusClaimed: json['share_bonus_claimed'] == true,
      purchaseBonusClaimed: json['purchase_bonus_claimed'] == true,
    );
  }
}

class LiveRaffleShareClaimResult {
  const LiveRaffleShareClaimResult({
    required this.ok,
    this.duplicate = false,
    this.ticketBalance = 0,
    this.error,
  });

  final bool ok;
  final bool duplicate;
  final int ticketBalance;
  final String? error;

  factory LiveRaffleShareClaimResult.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const LiveRaffleShareClaimResult(ok: false, error: 'invalid_response');
    }
    final m = Map<String, dynamic>.from(raw);
    return LiveRaffleShareClaimResult(
      ok: m['ok'] == true,
      duplicate: m['duplicate'] == true,
      ticketBalance: int.tryParse('${m['ticket_balance']}') ?? 0,
      error: m['error']?.toString(),
    );
  }
}

class LiveRaffleWinnerInfo {
  const LiveRaffleWinnerInfo({
    required this.rank,
    required this.userId,
    this.displayName,
    this.ticketsAtDraw = 0,
  });

  final int rank;
  final String userId;
  final String? displayName;
  final int ticketsAtDraw;

  factory LiveRaffleWinnerInfo.fromJson(Map<String, dynamic> json) {
    return LiveRaffleWinnerInfo(
      rank: int.tryParse('${json['rank']}') ?? 1,
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      ticketsAtDraw: int.tryParse('${json['tickets_at_draw']}') ?? 0,
    );
  }
}

/// Cliente Rifa da Live — só RPCs `batata_*` (bloco 1).
abstract final class LiveRaffleService {
  static Future<LiveRaffleState> fetchState(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return LiveRaffleState.empty();
    try {
      final res = await SupaFlow.client.rpc(
        'batata_get_live_raffle_state',
        params: {'p_live_id': id},
      );
      if (res == null) return LiveRaffleState.empty();
      return LiveRaffleState.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveRaffle] fetchState: $e');
      rethrow;
    }
  }

  static Future<String?> createRaffle({
    required String liveId,
    required String title,
    String? description,
    String? photoUrl,
    double? estimatedValueEur,
    int winnerCount = 1,
    DateTime? endsAt,
    bool activate = true,
    bool showPublicLeaderboard = true,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_create_live_raffle',
      params: {
        'p_live_id': liveId.trim(),
        'p_title': title.trim(),
        if (description != null && description.trim().isNotEmpty)
          'p_description': description.trim(),
        if (photoUrl != null && photoUrl.trim().isNotEmpty)
          'p_photo_url': photoUrl.trim(),
        if (estimatedValueEur != null) 'p_estimated_value_eur': estimatedValueEur,
        'p_winner_count': winnerCount < 1 ? 1 : winnerCount,
        if (endsAt != null) 'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_activate': activate,
        'p_show_public_leaderboard': showPublicLeaderboard,
      },
    );
    if (res is! Map) return null;
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'create_failed');
    }
    return m['raffle_id']?.toString();
  }

  /// Bloco 3 — intenção de partilha (+1, uma vez por rifa).
  static Future<String?> ensureReferralLink(String raffleId) async {
    final res = await SupaFlow.client.rpc(
      'batata_ensure_live_raffle_referral_link',
      params: {'p_raffle_id': raffleId.trim()},
    );
    if (res is! Map || res['ok'] != true) return null;
    final code = res['code']?.toString().trim() ?? '';
    return code.isEmpty ? null : code;
  }

  static Future<void> registerReferralVisit({
    required String liveId,
    required String code,
  }) async {
    await SupaFlow.client.rpc(
      'batata_register_live_raffle_referral_visit',
      params: {
        'p_live_id': liveId.trim(),
        'p_code': code.trim().toLowerCase(),
      },
    );
  }

  static Future<void> qualifyReferralVisits(String liveId) async {
    try {
      await SupaFlow.client.rpc(
        'batata_qualify_live_raffle_referral_visits',
        params: {'p_live_id': liveId.trim()},
      );
    } catch (e) {
      debugPrint('[LiveRaffle] qualifyReferral: $e');
    }
  }

  static Future<void> tryAwardPurchaseBonus(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    try {
      await SupaFlow.client.rpc(
        'batata_award_live_raffle_purchase_bonus',
        params: {'p_order_id': id},
      );
    } catch (e) {
      debugPrint('[LiveRaffle] purchaseBonus: $e');
    }
  }

  static Future<LiveRaffleShareClaimResult> claimShareIntent(
    String raffleId,
  ) async {
    final res = await SupaFlow.client.rpc(
      'batata_claim_live_raffle_share_intent',
      params: {'p_raffle_id': raffleId.trim()},
    );
    return LiveRaffleShareClaimResult.fromRpc(res);
  }

  static Future<void> join(String raffleId) async {
    final res = await SupaFlow.client.rpc(
      'batata_join_live_raffle',
      params: {'p_raffle_id': raffleId.trim()},
    );
    if (res is! Map) return;
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'join_failed');
    }
  }

  static Future<void> closeEntries(String raffleId) async {
    final res = await SupaFlow.client.rpc(
      'batata_close_live_raffle',
      params: {'p_raffle_id': raffleId.trim()},
    );
    if (res is! Map) return;
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'close_failed');
    }
  }

  static Future<void> cancel(String raffleId, {String? reason}) async {
    final res = await SupaFlow.client.rpc(
      'batata_cancel_live_raffle',
      params: {
        'p_raffle_id': raffleId.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
      },
    );
    if (res is! Map) return;
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'cancel_failed');
    }
  }

  static Future<void> draw(String raffleId) async {
    final res = await SupaFlow.client.rpc(
      'batata_draw_live_raffle_winners',
      params: {'p_raffle_id': raffleId.trim()},
    );
    if (res is! Map) return;
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'draw_failed');
    }
  }

  static Future<void> tick(String raffleId) async {
    try {
      await SupaFlow.client.rpc(
        'batata_tick_live_raffle',
        params: {'p_raffle_id': raffleId.trim()},
      );
    } catch (e) {
      debugPrint('[LiveRaffle] tick: $e');
    }
  }

  /// Contagem via RLS (vendedora vê todos; comprador pode ver só a própria entrada).
  static Future<int?> fetchParticipantCount(String raffleId) async {
    final id = raffleId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await SupaFlow.client
          .from('live_raffle_entries')
          .select('id')
          .eq('raffle_id', id);
      if (rows is! List) return null;
      return rows.length;
    } catch (e) {
      debugPrint('[LiveRaffle] participant count: $e');
      return null;
    }
  }

  static String formatCountdown(int? secondsLeft) {
    if (secondsLeft == null) return '';
    final s = secondsLeft < 0 ? 0 : secondsLeft;
    final m = s ~/ 60;
    final r = s % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final mm = m % 60;
      return '${h}h ${mm.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}
