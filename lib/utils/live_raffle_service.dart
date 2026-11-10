import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/utils/raffle_log.dart';

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

  String get debugSummary {
    final r = raffle;
    return 'has=$hasRaffle id=${r?.id ?? '-'} status=${r?.status ?? '-'} '
        'joined=${viewer.joined} tickets=${viewer.ticketBalance} '
        'share=${viewer.shareBonusClaimed} follow=${viewer.followBonusClaimed}';
  }

  LiveRaffleState copyWith({
    bool? hasRaffle,
    LiveRaffleInfo? raffle,
    LiveRaffleViewerState? viewer,
    List<LiveRaffleWinnerInfo>? winners,
    List<LiveRaffleLeaderboardEntry>? leaderboard,
  }) {
    return LiveRaffleState(
      hasRaffle: hasRaffle ?? this.hasRaffle,
      raffle: raffle ?? this.raffle,
      viewer: viewer ?? this.viewer,
      winners: winners ?? this.winners,
      leaderboard: leaderboard ?? this.leaderboard,
    );
  }

  /// Junta estado remoto com optimista local — nunca perde joined/tickets/share.
  LiveRaffleState mergePreferringLocalViewer(LiveRaffleState remote) {
    if (!hasRaffle || raffle == null) return remote;
    if (!remote.hasRaffle || remote.raffle == null) return this;
    if (raffle!.id != remote.raffle!.id) return remote;

    final localT = viewer.ticketBalance;
    final remoteT = remote.viewer.ticketBalance;
    return remote.copyWith(
      viewer: remote.viewer.copyWith(
        joined: viewer.joined || remote.viewer.joined,
        shareBonusClaimed:
            viewer.shareBonusClaimed || remote.viewer.shareBonusClaimed,
        followBonusClaimed:
            viewer.followBonusClaimed || remote.viewer.followBonusClaimed,
        purchaseBonusClaimed:
            viewer.purchaseBonusClaimed || remote.viewer.purchaseBonusClaimed,
        isWinner: viewer.isWinner || remote.viewer.isWinner,
        ticketBalance: localT > remoteT ? localT : remoteT,
      ),
    );
  }

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
    this.liveItemId,
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
  final String? liveItemId;
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
      liveItemId: json['live_item_id']?.toString(),
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

  LiveRaffleViewerState copyWith({
    bool? joined,
    int? ticketBalance,
    bool? isWinner,
    bool? followBonusClaimed,
    bool? shareBonusClaimed,
    bool? purchaseBonusClaimed,
  }) {
    return LiveRaffleViewerState(
      joined: joined ?? this.joined,
      ticketBalance: ticketBalance ?? this.ticketBalance,
      isWinner: isWinner ?? this.isWinner,
      followBonusClaimed: followBonusClaimed ?? this.followBonusClaimed,
      shareBonusClaimed: shareBonusClaimed ?? this.shareBonusClaimed,
      purchaseBonusClaimed:
          purchaseBonusClaimed ?? this.purchaseBonusClaimed,
    );
  }

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
    final dupRaw = m['duplicate'];
    final duplicate = dupRaw == true ||
        dupRaw == 'true' ||
        '$dupRaw'.toLowerCase() == 'true';
    final balRaw = m['ticket_balance'];
    int bal = 0;
    if (balRaw is num) {
      bal = balRaw.toInt();
    } else {
      bal = int.tryParse('$balRaw') ?? 0;
    }
    return LiveRaffleShareClaimResult(
      ok: m['ok'] == true,
      duplicate: duplicate,
      ticketBalance: bal,
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
      if (res == null) {
        RaffleLog.d('fetchState null', {'liveId': id});
        return LiveRaffleState.empty();
      }
      final state = LiveRaffleState.fromRpc(res);
      RaffleLog.d('fetchState ok', {'liveId': id, 'state': state.debugSummary});
      return state;
    } catch (e) {
      RaffleLog.e('fetchState', e, {'liveId': id});
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
    String? liveItemId,
  }) async {
    Future<String?> invoke({String? itemId}) async {
      final res = await SupaFlow.client.rpc(
        'batata_create_live_raffle',
        params: {
          'p_live_id': liveId.trim(),
          'p_title': title.trim(),
          if (description != null && description.trim().isNotEmpty)
            'p_description': description.trim(),
          if (photoUrl != null && photoUrl.trim().isNotEmpty)
            'p_photo_url': photoUrl.trim(),
          if (estimatedValueEur != null)
            'p_estimated_value_eur': estimatedValueEur,
          'p_winner_count': winnerCount < 1 ? 1 : winnerCount,
          if (endsAt != null) 'p_ends_at': endsAt.toUtc().toIso8601String(),
          'p_activate': activate,
          'p_show_public_leaderboard': showPublicLeaderboard,
          if (itemId != null && itemId.trim().isNotEmpty)
            'p_live_item_id': itemId.trim(),
        },
      );
      if (res is! Map) return null;
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] != true) {
        throw StateError(m['error']?.toString() ?? 'create_failed');
      }
      return m['raffle_id']?.toString();
    }

    final linkedId = liveItemId?.trim();
    String? raffleId;
    if (linkedId == null || linkedId.isEmpty) {
      raffleId = await invoke();
    } else {
      try {
        raffleId = await invoke(itemId: linkedId);
      } catch (e) {
        // Staging pode ainda não ter a overload com p_live_item_id (PGRST202).
        // Cria na mesma com título/foto do artigo — sem link de stock.
        final s = e.toString();
        final missingParam = s.contains('PGRST202') ||
            s.contains('p_live_item_id') ||
            s.contains('Could not find the function');
        if (!missingParam) rethrow;
        debugPrint(
          '[LiveRaffle] createRaffle: staging sem p_live_item_id — retry sem link',
        );
        raffleId = await invoke();
      }
    }

    // Marketplace / prep: descer products.quantity já na criação da rifa.
    // SQL create deve chamar sync; isto é backup idempotente.
    final rid = raffleId?.trim() ?? '';
    if (rid.isNotEmpty) {
      await syncMarketplaceQtyForRaffle(rid, release: false);
    }
    return raffleId;
  }

  /// Desce (ou repõe) `products.quantity` quando a rifa liga a um live_item.
  /// Idempotente no SQL (audit). Seguro chamar após create mesmo se o create
  /// já tiver feito sync.
  static Future<void> syncMarketplaceQtyForRaffle(
    String raffleId, {
    required bool release,
  }) async {
    final id = raffleId.trim();
    if (id.isEmpty) return;
    try {
      await SupaFlow.client.rpc(
        'batata_live_raffle_sync_product_qty',
        params: {
          'p_raffle_id': id,
          'p_release': release,
        },
      );
      RaffleLog.d('syncMarketplaceQty', {'raffleId': id, 'release': release});
    } catch (e) {
      debugPrint('[LiveRaffle] syncMarketplaceQty RPC: $e');
      // Sem RPC deployada: não mexer em quantity no client — o stock live
      // ainda pode subtrair raffle_hold e haveria dupla contagem.
    }
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
    final id = raffleId.trim();
    RaffleLog.d('claimShare start', {'raffleId': id});
    try {
      final res = await SupaFlow.client.rpc(
        'batata_claim_live_raffle_share_intent',
        params: {'p_raffle_id': id},
      );
      final parsed = LiveRaffleShareClaimResult.fromRpc(res);
      RaffleLog.d('claimShare rpc', {
        'raffleId': id,
        'ok': parsed.ok,
        'dup': parsed.duplicate,
        'tickets': parsed.ticketBalance,
        'error': parsed.error ?? '-',
        'rawType': res.runtimeType.toString(),
      });
      return parsed;
    } catch (e) {
      RaffleLog.e('claimShare throw', e, {'raffleId': id});
      rethrow;
    }
  }

  static Future<int> join(String raffleId) async {
    final id = raffleId.trim();
    RaffleLog.d('join start', {'raffleId': id});
    try {
      final res = await SupaFlow.client.rpc(
        'batata_join_live_raffle',
        params: {'p_raffle_id': id},
      );
      if (res is! Map) {
        throw StateError('join_failed');
      }
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] != true) {
        throw StateError(m['error']?.toString() ?? 'join_failed');
      }
      final raw = m['ticket_balance'];
      final tickets = raw is num ? raw.toInt() : (int.tryParse('$raw') ?? 1);
      RaffleLog.d('join ok', {'raffleId': id, 'tickets': tickets});
      return tickets;
    } catch (e) {
      final s = e.toString();
      RaffleLog.e('join', e, {'raffleId': id});
      if (s.contains('auth_required')) {
        throw StateError('auth_required');
      }
      if (s.contains('raffle_not_active')) {
        throw StateError('raffle_not_active');
      }
      if (s.contains('raffle_ended')) {
        throw StateError('raffle_ended');
      }
      rethrow;
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

  static Future<Map<String, dynamic>> draw(String raffleId) async {
    final res = await SupaFlow.client.rpc(
      'batata_draw_live_raffle_winners',
      params: {'p_raffle_id': raffleId.trim()},
    );
    if (res is! Map) {
      throw StateError('draw_failed');
    }
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'draw_failed');
    }
    final prizeOrders = m['prize_orders'];
    final hasKey = m.containsKey('prize_orders');
    final n = prizeOrders is List ? prizeOrders.length : 0;
    RaffleLog.d('draw ok', {
      'raffleId': raffleId,
      'prizeOrders': n,
      'hasPrizeOrdersKey': hasKey,
    });
    // SQL antigo (prize_stock/base) não devolve prize_orders → sem encomenda.
    if (!hasKey) {
      throw StateError('prize_order_missing');
    }
    return m;
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
    final stats = await fetchParticipationStats(raffleId);
    return stats?.participants;
  }

  /// Participantes (= entradas) + total de rifas (soma de tickets).
  static Future<({int participants, int tickets})?> fetchParticipationStats(
    String raffleId,
  ) async {
    final id = raffleId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await SupaFlow.client
          .from('live_raffle_entries')
          .select('id,ticket_balance')
          .eq('raffle_id', id);
      if (rows is! List) return null;
      var tickets = 0;
      for (final row in rows) {
        if (row is! Map) continue;
        final n = int.tryParse('${row['ticket_balance']}') ?? 0;
        if (n > 0) tickets += n;
      }
      return (participants: rows.length, tickets: tickets);
    } catch (e) {
      debugPrint('[LiveRaffle] fetchParticipationStats: $e');
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
