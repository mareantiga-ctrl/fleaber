import '/utils/live_row_playback_status.dart';

/// Perfil público — view `hub_profiles_public`.
class HubProfile {
  const HubProfile({
    required this.id,
    required this.handle,
    required this.fullName,
    this.photoUrl,
    this.location,
    this.isLive = false,
    this.nextLive,
    this.lastLive,
    this.totalLives = 0,
    this.vacationMode = false,
    this.phoneVerified = false,
    this.externalPaymentsEnabled = false,
    this.followerCount = 0,
    this.hubBio,
  });

  final String id;
  final String handle;
  final String fullName;
  final String? photoUrl;
  final String? location;
  final bool isLive;
  final DateTime? nextLive;
  final DateTime? lastLive;
  final int totalLives;
  final bool vacationMode;
  final bool phoneVerified;
  final bool externalPaymentsEnabled;
  final int followerCount;
  final String? hubBio;

  bool get hasAboutSection =>
      hubBio != null && hubBio!.trim().isNotEmpty;

  factory HubProfile.fromMap(Map<String, dynamic> map) {
    return HubProfile(
      id: map['id']?.toString() ?? '',
      handle: map['handle']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      photoUrl: map['photo_url']?.toString(),
      location: map['location']?.toString(),
      isLive: map['is_live'] == true,
      nextLive: _parseDate(map['next_live']),
      lastLive: _parseDate(map['last_live']),
      totalLives: (map['total_lives'] as num?)?.toInt() ?? 0,
      vacationMode: map['vacation_mode'] == true,
      phoneVerified: map['phone_verified'] == true,
      externalPaymentsEnabled: map['external_payments_enabled'] == true,
      followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
      hubBio: map['hub_bio']?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// Live pública — view `hub_lives_public`.
class HubLive {
  const HubLive({
    required this.id,
    required this.sellerId,
    required this.sellerHandle,
    this.sellerName,
    this.sellerPhotoUrl,
    this.title,
    this.status,
    this.isActive = false,
    this.muxPlaybackId,
    this.muxVodPlaybackId,
    this.viewerCount = 0,
    this.wentLiveAt,
    this.createdAt,
    this.publishBackend,
    this.coverId,
  });

  final String id;
  final String sellerId;
  final String sellerHandle;
  final String? sellerName;
  final String? sellerPhotoUrl;
  final String? title;
  final String? status;
  final bool isActive;
  final String? muxPlaybackId;
  final String? muxVodPlaybackId;
  final int viewerCount;
  final DateTime? wentLiveAt;
  final DateTime? createdAt;
  final String? publishBackend;
  final String? coverId;

  bool get isLiveNow =>
      liveRowIsLiveNow(status: status, isActive: isActive);

  /// Alinhado a [liveRowIsEnded] / [liveRowIsLiveNow].
  bool get isEnded =>
      liveRowIsEnded(status: status, isActive: isActive);

  bool get isScheduled => (status ?? '').toLowerCase() == 'scheduled';

  String? get effectivePlaybackId {
    if (isLiveNow) return muxPlaybackId;
    return muxVodPlaybackId ?? muxPlaybackId;
  }

  factory HubLive.fromMap(Map<String, dynamic> map) {
    final status = map['status']?.toString();
    final rawActive = map['is_active'];
    // null + status live → activo (não forçar Gravado / isLive:false no Hub).
    final bool isActive;
    if (rawActive == null) {
      isActive = (status ?? '').trim().toLowerCase() == 'live';
    } else {
      isActive = rawActive == true;
    }
    return HubLive(
      id: map['id']?.toString() ?? '',
      sellerId: map['seller_id']?.toString() ?? '',
      sellerHandle: map['seller_handle']?.toString() ?? '',
      sellerName: map['seller_name']?.toString(),
      sellerPhotoUrl: map['seller_photo_url']?.toString(),
      title: map['title']?.toString(),
      status: status,
      isActive: isActive,
      muxPlaybackId: map['mux_playback_id']?.toString(),
      muxVodPlaybackId: map['mux_vod_playback_id']?.toString(),
      viewerCount: (map['viewer_count'] as num?)?.toInt() ?? 0,
      wentLiveAt: HubProfile._parseDate(map['went_live_at']),
      createdAt: HubProfile._parseDate(map['created_at']),
      publishBackend: map['publish_backend']?.toString(),
      coverId: map['cover_id']?.toString(),
    );
  }
}

/// Produto marketplace — view `hub_products_public`.
class HubProduct {
  const HubProduct({
    required this.id,
    required this.sellerId,
    required this.sellerHandle,
    required this.title,
    this.price,
    this.imageUrls = const [],
    this.category,
    this.state,
    this.description,
    this.refCode,
    this.isSold = false,
  });

  final String id;
  final String sellerId;
  final String sellerHandle;
  final String title;
  final double? price;
  final List<String> imageUrls;
  final String? category;
  final String? state;
  final String? description;
  final String? refCode;
  final bool isSold;

  String? get primaryImage =>
      imageUrls.isNotEmpty ? imageUrls.first : null;

  factory HubProduct.fromMap(Map<String, dynamic> map) {
    final rawImages = map['image_urls'];
    final urls = <String>[];
    if (rawImages is List) {
      for (final e in rawImages) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) urls.add(s);
      }
    }
    return HubProduct(
      id: map['id']?.toString() ?? '',
      sellerId: map['seller_id']?.toString() ?? '',
      sellerHandle: map['seller_handle']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble(),
      imageUrls: urls,
      category: map['category']?.toString(),
      state: map['state']?.toString(),
      description: map['description']?.toString(),
      refCode: map['ref_code']?.toString(),
      isSold: map['is_sold'] == true,
    );
  }
}

/// Artigo de directo — view `hub_live_items_public`.
class HubLiveItem {
  const HubLiveItem({
    required this.id,
    required this.liveId,
    required this.sellerId,
    required this.sellerHandle,
    this.refCode,
    this.title,
    this.photoUrl,
    this.price,
    this.isActive = false,
    this.status,
    this.itemKind,
  });

  final String id;
  final String liveId;
  final String sellerId;
  final String sellerHandle;
  final String? refCode;
  final String? title;
  final String? photoUrl;
  final double? price;
  final bool isActive;
  final String? status;
  final String? itemKind;

  factory HubLiveItem.fromMap(Map<String, dynamic> map) {
    return HubLiveItem(
      id: map['id']?.toString() ?? '',
      liveId: map['live_id']?.toString() ?? '',
      sellerId: map['seller_id']?.toString() ?? '',
      sellerHandle: map['seller_handle']?.toString() ?? '',
      refCode: map['ref_code']?.toString(),
      title: map['title']?.toString(),
      photoUrl: map['photo_url']?.toString(),
      price: (map['price'] as num?)?.toDouble(),
      isActive: map['is_active'] == true,
      status: map['status']?.toString(),
      itemKind: map['item_kind']?.toString(),
    );
  }
}

/// Avaliação — view `hub_reviews_public` / RPC page.
class HubReview {
  const HubReview({
    required this.id,
    required this.targetId,
    required this.stars,
    this.comment,
    this.createdAt,
    this.authorDisplay,
    this.isAutomatic = false,
  });

  final String id;
  final String targetId;
  final int stars;
  final String? comment;
  final DateTime? createdAt;
  final String? authorDisplay;
  final bool isAutomatic;

  factory HubReview.fromMap(Map<String, dynamic> map) {
    return HubReview(
      id: map['id']?.toString() ?? '',
      targetId: map['target_id']?.toString() ?? '',
      stars: (map['stars'] as num?)?.toInt() ?? 0,
      comment: map['comment']?.toString(),
      createdAt: HubProfile._parseDate(map['created_at']),
      authorDisplay: map['author_display']?.toString(),
      isAutomatic: map['is_automatic'] == true,
    );
  }
}

/// Stats globais Página 05 (`batata_hub_reviews_public_stats`).
class HubReviewsStatsResult {
  const HubReviewsStatsResult({
    required this.count,
    required this.average,
    required this.distribution,
    this.ok = true,
  });

  const HubReviewsStatsResult.empty()
      : count = 0,
        average = 0,
        distribution = const [0, 0, 0, 0, 0],
        ok = true;

  final int count;
  final double average;
  /// Index 0 = 5★ … index 4 = 1★
  final List<int> distribution;
  final bool ok;

  factory HubReviewsStatsResult.fromMap(Map<String, dynamic> map) {
    final distMap = map['distribution'];
    final d = <int>[0, 0, 0, 0, 0];
    if (distMap is Map) {
      for (var stars = 5; stars >= 1; stars--) {
        d[5 - stars] = (distMap['$stars'] as num?)?.toInt() ?? 0;
      }
    }
    return HubReviewsStatsResult(
      ok: map['ok'] != false,
      count: (map['count'] as num?)?.toInt() ?? 0,
      average: (map['average'] as num?)?.toDouble() ?? 0,
      distribution: d,
    );
  }
}

/// Página keyset Página 05 (`batata_hub_reviews_public_page`).
class HubReviewsPageResult {
  const HubReviewsPageResult({
    required this.items,
    required this.hasMore,
    this.ok = true,
  });

  const HubReviewsPageResult.empty()
      : items = const [],
        hasMore = false,
        ok = true;

  final List<HubReview> items;
  final bool hasMore;
  final bool ok;

  factory HubReviewsPageResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    final list = <HubReview>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          list.add(HubReview.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    return HubReviewsPageResult(
      ok: map['ok'] != false,
      items: list,
      hasMore: map['has_more'] == true,
    );
  }
}

/// Mensagem chat público — view `hub_live_messages_public`.
class HubLiveMessage {
  const HubLiveMessage({
    required this.id,
    required this.liveId,
    required this.kind,
    this.body,
    this.senderLabel,
    this.tipAmount,
    this.createdAt,
    this.channel = 'fleaber',
  });

  final String id;
  final String liveId;
  final String kind;
  final String? body;
  final String? senderLabel;
  final double? tipAmount;
  final DateTime? createdAt;
  final String channel;

  bool get isFromFacebook => channel.trim().toLowerCase() == 'facebook';

  factory HubLiveMessage.fromMap(Map<String, dynamic> map) {
    final ch = map['channel']?.toString().trim().toLowerCase();
    return HubLiveMessage(
      id: map['id']?.toString() ?? '',
      liveId: map['live_id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'chat',
      body: map['body']?.toString(),
      senderLabel: map['sender_label']?.toString(),
      tipAmount: (map['tip_amount'] as num?)?.toDouble(),
      createdAt: HubProfile._parseDate(map['created_at']),
      channel: (ch == 'facebook' || ch == 'hub' || ch == 'fleaber')
          ? ch!
          : 'fleaber',
    );
  }
}

/// Item FOMO — RPC `batata_hub_live_fomo_snapshot`.
class HubFomoItem {
  const HubFomoItem({
    required this.liveItemId,
    required this.status,
    this.availableQty = 0,
    this.pendingQueueCount = 0,
    this.isLastUnit = false,
    this.displayReservedQty = 0,
  });

  final String liveItemId;
  final String status;
  final int availableQty;
  final int pendingQueueCount;
  final bool isLastUnit;
  final int displayReservedQty;

  factory HubFomoItem.fromMap(Map<String, dynamic> map) {
    return HubFomoItem(
      liveItemId: map['live_item_id']?.toString() ?? '',
      status: map['status']?.toString() ?? '',
      availableQty: (map['available_qty'] as num?)?.toInt() ?? 0,
      pendingQueueCount: (map['pending_queue_count'] as num?)?.toInt() ?? 0,
      isLastUnit: map['is_last_unit'] == true,
      displayReservedQty: (map['display_reserved_qty'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Snapshot FOMO agregado.
class HubFomoSnapshot {
  const HubFomoSnapshot({
    required this.liveId,
    required this.viewerCount,
    required this.liveStatus,
    required this.isActive,
    required this.items,
  });

  final String liveId;
  final int viewerCount;
  final String liveStatus;
  final bool isActive;
  final List<HubFomoItem> items;

  HubFomoItem? fomoForItem(String liveItemId) {
    for (final i in items) {
      if (i.liveItemId == liveItemId) return i;
    }
    return null;
  }

  factory HubFomoSnapshot.fromRpc(dynamic raw) {
    if (raw is! Map || raw['ok'] != true) {
      return const HubFomoSnapshot(
        liveId: '',
        viewerCount: 0,
        liveStatus: '',
        isActive: false,
        items: [],
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final rawItems = map['items'];
    final items = <HubFomoItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(HubFomoItem.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    return HubFomoSnapshot(
      liveId: map['live_id']?.toString() ?? '',
      viewerCount: (map['viewer_count'] as num?)?.toInt() ?? 0,
      liveStatus: map['live_status']?.toString() ?? '',
      isActive: map['is_active'] == true,
      items: items,
    );
  }
}

/// Pacote de dados Hub Perfil.
class HubProfileBundle {
  const HubProfileBundle({
    required this.profile,
    required this.lives,
    required this.products,
    required this.reviews,
  });

  final HubProfile profile;
  final List<HubLive> lives;
  final List<HubProduct> products;
  final List<HubReview> reviews;

  HubLive? get activeLive {
    HubLive? best;
    for (final l in lives) {
      if (!hubLiveIsCredibleNow(l)) continue;
      if (best == null ||
          hubLiveRecency(l).isAfter(hubLiveRecency(best))) {
        best = l;
      }
    }
    return best;
  }

  List<HubLive> get upcomingLives =>
      lives.where((l) => l.isScheduled).toList();

  List<HubLive> get pastLives {
    final ended = lives.where((l) => l.isEnded).toList();
    final playable = <HubLive>[];
    final preparing = <HubLive>[];
    final now = DateTime.now().toUtc();
    for (final l in ended) {
      final pb = (l.effectivePlaybackId ?? '').trim();
      if (pb.isNotEmpty) {
        playable.add(l);
        continue;
      }
      // Sem VOD: só manter «a preparar» recente (≤24h). Stubs redteam/zombies → ocultar.
      final when = (l.wentLiveAt ?? l.createdAt)?.toUtc();
      if (when != null && now.difference(when) <= const Duration(hours: 24)) {
        preparing.add(l);
      }
    }
    int byRecency(HubLive a, HubLive b) {
      final ta = a.wentLiveAt ?? a.createdAt;
      final tb = b.wentLiveAt ?? b.createdAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    }

    playable.sort(byRecency);
    preparing.sort(byRecency);
    return [...playable, ...preparing];
  }

  double? get averageRating {
    if (reviews.isEmpty) return null;
    final sum = reviews.fold<int>(0, (a, r) => a + r.stars);
    return sum / reviews.length;
  }
}

/// Pacote Hub Direto.
class HubLiveBundle {
  const HubLiveBundle({
    required this.profile,
    required this.live,
    required this.items,
    required this.messages,
    required this.products,
    required this.fomo,
  });

  final HubProfile profile;
  final HubLive? live;
  final List<HubLiveItem> items;
  final List<HubLiveMessage> messages;
  final List<HubProduct> products;
  final HubFomoSnapshot? fomo;

  HubLiveItem? get activeItem {
    for (final i in items) {
      if (i.isActive) return i;
    }
    return items.isNotEmpty ? items.first : null;
  }
}

enum HubLivePresentation {
  liveActive,
  vodReplay,
  scheduledOnly,
  noLive,
}

HubLivePresentation hubLivePresentation(HubLive? live) {
  if (live == null) return HubLivePresentation.noLive;
  if (hubLiveIsCredibleNow(live)) {
    return HubLivePresentation.liveActive;
  }
  if (live.isEnded && live.effectivePlaybackId != null) {
    return HubLivePresentation.vodReplay;
  }
  if (live.isScheduled) return HubLivePresentation.scheduledOnly;
  if (live.effectivePlaybackId != null) return HubLivePresentation.vodReplay;
  return HubLivePresentation.noLive;
}

/// Badge AO VIVO / GRAVADO / GRAVAÇÃO A PREPARAR (B12).
enum HubLiveDisplayStatus {
  live,
  recorded,
  preparing,
}

HubLiveDisplayStatus hubLiveDisplayStatus(HubLive live) {
  if (hubLiveIsCredibleNow(live)) return HubLiveDisplayStatus.live;
  if (live.isEnded &&
      (live.effectivePlaybackId == null ||
          live.effectivePlaybackId!.trim().isEmpty)) {
    return HubLiveDisplayStatus.preparing;
  }
  if (live.isEnded || (live.effectivePlaybackId?.trim().isNotEmpty ?? false)) {
    return HubLiveDisplayStatus.recorded;
  }
  if (live.isScheduled) return HubLiveDisplayStatus.preparing;
  return HubLiveDisplayStatus.recorded;
}

/// Live «ao vivo» credível para Hub: status live + playback + não-zombie antigo.
/// Zombies redteam (`status=live` sem went_live_at / sem mux / idade alta) → ignorar.
bool hubLiveIsCredibleNow(HubLive live) {
  if (!live.isLiveNow) return false;
  final pb = (live.effectivePlaybackId ?? '').trim();
  if (pb.isEmpty) return false;
  final now = DateTime.now().toUtc();
  final went = live.wentLiveAt?.toUtc();
  if (went != null) {
    return now.difference(went) <= const Duration(hours: 6);
  }
  final created = live.createdAt?.toUtc();
  if (created == null) return false;
  return now.difference(created) <= const Duration(hours: 2);
}

DateTime hubLiveRecency(HubLive live) {
  return live.wentLiveAt?.toUtc() ??
      live.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Capabilities futuras FleaHub — v1 stub (sempre desactivado).
class HubCapabilities {
  const HubCapabilities({
    this.crossChannelReservations = false,
    this.externalPayments = false,
  });

  /// Reservas cross-canal (PS → Hub) — ver `docs/live-cross-channel-ingest-spec.md`.
  final bool crossChannelReservations;
  final bool externalPayments;

  static const v1 = HubCapabilities();
}

/// Feed da landing FleaHub — Diretos (live→gravados) + Marketplace + lojas.
class HubDiscoveryFeed {
  const HubDiscoveryFeed({
    required this.liveNow,
    required this.recentRecordings,
    required this.publishedHubs,
    this.marketplaceProducts = const [],
  });

  final List<HubLive> liveNow;
  final List<HubLive> recentRecordings;
  final List<HubProfile> publishedHubs;
  final List<HubProduct> marketplaceProducts;

  /// Há conteúdo em Diretos (ao vivo ou gravados de fallback).
  bool get hasDiretos => liveNow.isNotEmpty || recentRecordings.isNotEmpty;

  bool get isEmpty =>
      !hasDiretos &&
      publishedHubs.isEmpty &&
      marketplaceProducts.isEmpty;
}

/// Resultado da pesquisa pública da landing (vendedores + live items + marketplace).
class HubSearchResult {
  const HubSearchResult({
    required this.profiles,
    required this.items,
    this.products = const [],
  });

  final List<HubProfile> profiles;
  final List<HubLiveItem> items;
  final List<HubProduct> products;

  bool get isEmpty =>
      profiles.isEmpty && items.isEmpty && products.isEmpty;
}
