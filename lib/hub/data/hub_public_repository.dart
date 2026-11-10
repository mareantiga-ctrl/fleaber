import '/backend/supabase/supabase.dart';

import 'hub_models.dart';

/// Leitura pública Hub — **só** views `hub_*` + RPC FOMO (anon OK).
class HubPublicRepository {
  HubPublicRepository({SupabaseClient? client})
      : _client = client ?? SupaFlow.client;

  final SupabaseClient _client;

  Future<HubProfile?> fetchProfileById(String profileId) async {
    final id = profileId.trim();
    if (id.isEmpty) return null;
    final rows = await _client
        .from('hub_profiles_public')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isNotEmpty) {
      return HubProfile.fromMap(Map<String, dynamic>.from(rows.first));
    }
    final discovery = await _client
        .from('hub_profiles_discovery_public')
        .select()
        .eq('id', id)
        .limit(1);
    if (discovery.isEmpty) return null;
    return HubProfile.fromMap(Map<String, dynamic>.from(discovery.first));
  }

  /// Escape mínimo para `ilike` / `or` PostgREST (landing search).
  static String sanitizeSearchQuery(String raw) {
    return raw
        .trim()
        .replaceAll(',', ' ')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ');
  }

  /// Pesquisa pública: vendedores + artigos live discovery + marketplace.
  ///
  /// Usa apenas views `hub_*` já expostas a anon. Sem endpoint dedicado.
  Future<HubSearchResult> searchPublic({
    required String query,
    int profileLimit = 12,
    int itemLimit = 24,
    int productLimit = 24,
  }) async {
    final q = sanitizeSearchQuery(query);
    if (q.length < 2) {
      return const HubSearchResult(profiles: [], items: [], products: []);
    }
    final pattern = '%$q%';

    final profilesFuture = _client
        .from('hub_profiles_public')
        .select()
        .or('handle.ilike.$pattern,full_name.ilike.$pattern')
        .order('is_live', ascending: false)
        .order('follower_count', ascending: false)
        .limit(profileLimit.clamp(1, 48));

    final itemsFuture = _client
        .from('hub_live_items_discovery_public')
        .select()
        .or('title.ilike.$pattern,ref_code.ilike.$pattern')
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(itemLimit.clamp(1, 48));

    final productsFuture = _client
        .from('hub_products_public')
        .select()
        .or('title.ilike.$pattern,ref_code.ilike.$pattern')
        .order('created_at', ascending: false)
        .limit(productLimit.clamp(1, 48));

    final results =
        await Future.wait([profilesFuture, itemsFuture, productsFuture]);
    final profileRows = results[0] as List<dynamic>;
    final itemRows = results[1] as List<dynamic>;
    final productRows = results[2] as List<dynamic>;

    final profiles = profileRows
        .map((e) => HubProfile.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((p) => p.handle.trim().isNotEmpty)
        .toList();
    final items = itemRows
        .map((e) => HubLiveItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((i) => i.sellerHandle.trim().isNotEmpty)
        .toList();
    final products = productRows
        .map((e) => HubProduct.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((p) => p.id.isNotEmpty)
        .toList();

    return HubSearchResult(
      profiles: profiles,
      items: items,
      products: products,
    );
  }

  /// Vitrines publicadas para a landing `/fleahub`.
  Future<List<HubProfile>> fetchFeaturedProfiles({int limit = 12}) async {
    final cap = limit.clamp(1, 48);
    final rows = await _client
        .from('hub_profiles_public')
        .select()
        .order('is_live', ascending: false)
        .order('follower_count', ascending: false)
        .limit(cap);
    return rows
        .map((e) => HubProfile.fromMap(Map<String, dynamic>.from(e)))
        .where((p) => p.handle.trim().isNotEmpty)
        .toList();
  }

  /// Descoberta: directos agora (máx. 3) → gravados recentes (máx. 12) →
  /// marketplace (`hub_products_public`) → vitrines (acesso lojas sem tab órfã).
  /// Gravados alinhados à Home app: `ended` **ou** `live`+inactivo, com playback
  /// (VOD ?? mux_playback), só hubs publicados (filtro da view).
  static const discoveryLiveCap = 3;
  static const discoveryRecordingCap = 12;
  /// Pool maior que o cap — filtra playback no cliente (como a Home).
  static const discoveryRecordingFetch = 48;
  static const discoveryMarketplaceCap = 40;

  Future<HubDiscoveryFeed> fetchDiscoveryFeed() async {
    final liveRaw = await _client
        .from('hub_lives_discovery_public')
        .select()
        .eq('is_active', true)
        .order('went_live_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(24);

    final liveNow = <HubLive>[];
    final liveSellerIds = <String>{};
    for (final row in liveRaw) {
      final l = HubLive.fromMap(Map<String, dynamic>.from(row));
      // Credível: evita zombies redteam como «ao vivo» na landing.
      if (!hubLiveIsCredibleNow(l) || l.sellerHandle.trim().isEmpty) continue;
      if (!liveSellerIds.add(l.sellerId)) continue;
      liveNow.add(l);
      if (liveNow.length >= discoveryLiveCap) break;
    }

    // Mesmo critério da Home (`status.ended` ∪ `live`+`is_active=false`).
    final recRaw = await _client
        .from('hub_lives_discovery_public')
        .select()
        .or('status.eq.ended,and(status.eq.live,is_active.eq.false)')
        .order('went_live_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(discoveryRecordingFetch);

    final recentRecordings = recRaw
        .map((e) => HubLive.fromMap(Map<String, dynamic>.from(e)))
        .where(
          (l) =>
              l.sellerHandle.trim().isNotEmpty &&
              l.isEnded &&
              (l.effectivePlaybackId ?? '').trim().isNotEmpty,
        )
        .take(discoveryRecordingCap)
        .toList();

    final shownSellerIds = {
      ...liveNow.map((l) => l.sellerId),
      ...recentRecordings.map((l) => l.sellerId),
    };

    final publishedAll = await fetchFeaturedProfiles(limit: 12);
    final publishedHubs = publishedAll
        .where((p) => !shownSellerIds.contains(p.id))
        .take(6)
        .toList();

    final marketplaceProducts =
        await fetchMarketplaceDiscovery(limit: discoveryMarketplaceCap);

    return HubDiscoveryFeed(
      liveNow: liveNow,
      recentRecordings: recentRecordings,
      publishedHubs: publishedHubs,
      marketplaceProducts: marketplaceProducts,
    );
  }

  /// Catálogo marketplace público — view `hub_products_public` (mesma fonte das lojas).
  Future<List<HubProduct>> fetchMarketplaceDiscovery({int limit = 40}) async {
    final cap = limit.clamp(1, 48);
    final rows = await _client
        .from('hub_products_public')
        .select()
        .eq('is_sold', false)
        .order('created_at', ascending: false)
        .limit(cap);
    return rows
        .map((e) => HubProduct.fromMap(Map<String, dynamic>.from(e)))
        .where(
          (p) =>
              p.id.isNotEmpty &&
              p.sellerHandle.trim().isNotEmpty &&
              p.title.trim().isNotEmpty,
        )
        .toList();
  }

  Future<List<HubLive>> fetchLivesForSeller(
    String sellerId, {
    int limit = 24,
    int offset = 0,
  }) async {
    final id = sellerId.trim();
    if (id.isEmpty) return const [];
    final lim = limit.clamp(1, 48);
    final off = offset < 0 ? 0 : offset;
    final rows = await _client
        .from('hub_lives_public')
        .select()
        .eq('seller_id', id)
        .order('is_active', ascending: false)
        .order('went_live_at', ascending: false)
        .range(off, off + lim - 1);
    return rows
        .map((e) => HubLive.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<HubProduct>> fetchProductsForSeller(
    String sellerId, {
    int limit = 24,
    int offset = 0,
  }) async {
    final id = sellerId.trim();
    if (id.isEmpty) return const [];
    final lim = limit.clamp(1, 48);
    final off = offset < 0 ? 0 : offset;
    final rows = await _client
        .from('hub_products_public')
        .select()
        .eq('seller_id', id)
        .eq('is_sold', false)
        .order('created_at', ascending: false)
        .range(off, off + lim - 1);
    return rows
        .map((e) => HubProduct.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Preview (Página 02) — amostra pequena; stats globais via [fetchReviewsStatsForSeller].
  Future<List<HubReview>> fetchReviewsForSeller(
    String sellerId, {
    int limit = 12,
  }) async {
    final page = await fetchReviewsPageForSeller(
      sellerId,
      limit: limit.clamp(1, 48),
    );
    return page.items;
  }

  /// Stats do conjunto completo elegível (não só a página carregada).
  Future<HubReviewsStatsResult> fetchReviewsStatsForSeller(
    String sellerId,
  ) async {
    final id = sellerId.trim();
    if (id.isEmpty) {
      return const HubReviewsStatsResult.empty();
    }
    final raw = await _client.rpc(
      'batata_hub_reviews_public_stats',
      params: {'p_seller_id': id},
    );
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return HubReviewsStatsResult.fromMap(map);
  }

  /// Página keyset — servidor; [limit] tipicamente 10.
  Future<HubReviewsPageResult> fetchReviewsPageForSeller(
    String sellerId, {
    int limit = 10,
    int? starsFilter,
    String sort = 'newest',
    DateTime? cursorCreatedAt,
    String? cursorId,
    int? cursorStars,
  }) async {
    final id = sellerId.trim();
    if (id.isEmpty) {
      return const HubReviewsPageResult.empty();
    }
    final raw = await _client.rpc(
      'batata_hub_reviews_public_page',
      params: {
        'p_seller_id': id,
        'p_limit': limit.clamp(1, 50),
        'p_stars': starsFilter,
        'p_sort': sort,
        'p_cursor_created_at': cursorCreatedAt?.toUtc().toIso8601String(),
        'p_cursor_id': cursorId,
        'p_cursor_stars': cursorStars,
      },
    );
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return HubReviewsPageResult.fromMap(map);
  }

  /// Bundle leve para H02 — primeiras páginas; tabs carregam o resto sob demanda.
  Future<HubProfileBundle?> fetchProfileBundle(
    String profileId, {
    int livesLimit = 12,
    int productsLimit = 12,
    int reviewsLimit = 6,
  }) async {
    try {
      final profile = await fetchProfileById(profileId);
      if (profile == null) return null;
      final results = await Future.wait([
        fetchLivesForSeller(profileId, limit: livesLimit, offset: 0),
        fetchProductsForSeller(profileId, limit: productsLimit, offset: 0),
        fetchReviewsForSeller(profileId, limit: reviewsLimit),
      ]);
      return HubProfileBundle(
        profile: profile,
        lives: results[0] as List<HubLive>,
        products: results[1] as List<HubProduct>,
        reviews: results[2] as List<HubReview>,
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<HubLive?> fetchLiveById(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    var rows = await _client
        .from('hub_lives_public')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) {
      rows = await _client
          .from('hub_lives_discovery_public')
          .select()
          .eq('id', id)
          .limit(1);
    }
    if (rows.isEmpty) return null;
    return HubLive.fromMap(Map<String, dynamic>.from(rows.first));
  }

  Future<List<HubLiveItem>> fetchLiveItems(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return const [];
    var rows = await _client
        .from('hub_live_items_public')
        .select()
        .eq('live_id', id)
        .order('is_active', ascending: false)
        .order('created_at', ascending: true);
    if (rows.isEmpty) {
      rows = await _client
          .from('hub_live_items_discovery_public')
          .select()
          .eq('live_id', id)
          .order('is_active', ascending: false)
          .order('created_at', ascending: true);
    }
    return rows
        .map((e) => HubLiveItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Catálogo Hub → formato `live_items` (player embed / gravados públicos).
  Future<List<LiveItemsRow>> fetchLiveItemsAsPlayerRows(String liveId) async {
    final items = await fetchLiveItems(liveId);
    return items.map(_hubLiveItemToPlayerRow).toList();
  }

  static LiveItemsRow _hubLiveItemToPlayerRow(HubLiveItem item) {
    return LiveItemsRow({
      'id': item.id,
      'live_id': item.liveId,
      'ref_code': item.refCode ?? '',
      'title': item.title,
      'photo_url': item.photoUrl,
      'price': item.price,
      'is_active': item.isActive,
      'status': item.status,
      'item_kind': item.itemKind,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<HubLiveMessage>> fetchLiveMessages(
    String liveId, {
    int limit = 40,
  }) async {
    final id = liveId.trim();
    if (id.isEmpty) return const [];
    final rows = await _client
        .from('hub_live_messages_public')
        .select()
        .eq('live_id', id)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((e) => HubLiveMessage.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<HubFomoSnapshot?> fetchFomoSnapshot(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    final raw = await _client.rpc(
      'batata_hub_live_fomo_snapshot',
      params: {'p_live_id': id},
    );
    final snap = HubFomoSnapshot.fromRpc(raw);
    if (snap.liveId.isEmpty) return null;
    return snap;
  }

  /// Live pedida por `?liveId=` (gravado/directo específico) ou fallback primário.
  Future<HubLive?> resolveLiveForPage(
    String sellerId, {
    String? liveId,
  }) async {
    final seller = sellerId.trim();
    final requested = liveId?.trim();
    if (requested != null && requested.isNotEmpty) {
      final live = await fetchLiveById(requested);
      if (live != null && live.sellerId == seller) {
        return live;
      }
    }
    return pickPrimaryLive(seller);
  }

  /// Escolhe live principal para `/{handle}/live` (sem `liveId`).
  Future<HubLive?> pickPrimaryLive(String sellerId) async {
    final lives = await fetchLivesForSeller(sellerId);
    if (lives.isEmpty) return null;
    HubLive? bestLive;
    for (final l in lives) {
      if (!hubLiveIsCredibleNow(l)) continue;
      if (bestLive == null ||
          hubLiveRecency(l).isAfter(hubLiveRecency(bestLive))) {
        bestLive = l;
      }
    }
    if (bestLive != null) return bestLive;
    HubLive? bestEnded;
    for (final l in lives) {
      if (!l.isEnded) continue;
      final pb = (l.effectivePlaybackId ?? '').trim();
      if (pb.isEmpty) continue;
      if (bestEnded == null ||
          hubLiveRecency(l).isAfter(hubLiveRecency(bestEnded))) {
        bestEnded = l;
      }
    }
    if (bestEnded != null) return bestEnded;
    for (final l in lives) {
      if (l.isEnded) return l;
    }
    for (final l in lives) {
      if (l.isScheduled) return l;
    }
    return lives.first;
  }

  Future<HubLiveBundle?> fetchLiveBundle(
    String profileId, {
    String? liveId,
  }) async {
    try {
      final profile = await fetchProfileById(profileId);
      if (profile == null) return null;
      final live = await resolveLiveForPage(profileId, liveId: liveId);
      if (live == null) {
        final products = await fetchProductsForSeller(profileId);
        return HubLiveBundle(
          profile: profile,
          live: null,
          items: const [],
          messages: const [],
          products: products,
          fomo: null,
        );
      }
      final results = await Future.wait([
        fetchLiveItems(live.id),
        fetchLiveMessages(live.id),
        fetchProductsForSeller(profileId, limit: 12),
        fetchFomoSnapshot(live.id),
      ]);
      return HubLiveBundle(
        profile: profile,
        live: live,
        items: results[0] as List<HubLiveItem>,
        messages: results[1] as List<HubLiveMessage>,
        products: results[2] as List<HubProduct>,
        fomo: results[3] as HubFomoSnapshot?,
      );
    } catch (_) {
      rethrow;
    }
  }
}
