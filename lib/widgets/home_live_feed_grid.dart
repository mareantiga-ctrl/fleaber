import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_actions.dart';
import '/index.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/utils/seller_vacation_mode.dart';
import '/utils/mux_urls.dart';
import '/utils/live_publish_cleanup.dart';
import '/utils/live_row_playback_status.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/live_cover_assign.dart';
import '/utils/live_cover_catalog.dart';
import '/widgets/home_mux_live_card.dart';

/// Grelha Home: diretos ao vivo primeiro, depois gravações (máx. 50), recente → antigo.
class HomeLiveFeedGrid extends StatefulWidget {
  const HomeLiveFeedGrid({
    super.key,
    required this.search,
    required this.ratingLabelForSeller,
    this.pageSize = 20,
    this.maxEndedOnHome = 50,
  });

  final String search;
  final String Function(String? sellerId) ratingLabelForSeller;
  final int pageSize;
  final int maxEndedOnHome;

  @override
  State<HomeLiveFeedGrid> createState() => HomeLiveFeedGridState();
}

/// Estado público para pull-to-refresh na Home.
class HomeLiveFeedGridState extends State<HomeLiveFeedGrid> {

  /// Pull-to-refresh na Home.
  Future<void> reload() => _loadFeed(reset: true);

  final List<HomeLiveFeedItem> _items = [];
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMoreEnded = true;
  int _endedPage = 0;
  String? _error;
  Timer? _liveStatusPoll;
  VoidCallback? _liveFeedRefreshListener;
  int _loadSeq = 0;

  /// Direto «ao vivo» — alinhado a [liveRowIsLiveNow].
  ///
  /// Não demotar por `mux_vod_playback_id` (Mux pode gravar VOD enquanto o
  /// stream ainda corre) nem por idade do `created_at` (lives longas >45 min
  /// apareciam como GRAVADO no Home / Lab). Fantasmas = scrub + cleanup.
  static bool feedIsLiveStream(LivesRow live) {
    return liveRowIsLiveNow(status: live.status, isActive: live.isActive);
  }

  /// Gravação terminada mas ainda sem vídeo Mux disponível.
  static bool feedIsRecordingPreparing(LivesRow live) {
    if (feedIsLiveStream(live)) return false;
    final vod = live.muxVodPlaybackId?.trim() ?? '';
    final mux = live.muxPlaybackId?.trim() ?? '';
    return vod.isEmpty && mux.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapFeed());
    _liveFeedRefreshListener = () {
      if (!mounted) return;
      // Recarga em fundo — não esconder cards nem fechar o teclado.
      unawaited(_loadFeed(reset: true));
    };
    liveFeedRefreshTick.addListener(_liveFeedRefreshListener!);
    _liveStatusPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (MediaQuery.viewInsetsOf(context).bottom > 80) return;
      final hasLive = _items.any((e) => e.isLiveStream);
      if (hasLive) {
        unawaited(_loadFeed(reset: true));
      }
    });
  }

  @override
  void dispose() {
    if (_liveFeedRefreshListener != null) {
      liveFeedRefreshTick.removeListener(_liveFeedRefreshListener!);
    }
    _liveStatusPoll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeLiveFeedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.maxEndedOnHome != widget.maxEndedOnHome) {
      _loadFeed(reset: true);
    }
  }

  Future<void> _bootstrapFeed() async {
    await LivePublishCleanup.reconcileOnAppStart(fullSweep: true);
    if (!mounted) return;
    await _loadFeed(reset: true);
  }

  /// Fecha lives do utilizador actual que ainda estão «ao vivo» na BD
  /// sem sessão de broadcast nesta app (fantasma pós-crash / saída forçada).
  ///
  /// **Nunca** fecha o liveId marcado em prefs/memória (directo TCL activo).
  /// Antes, ir a Perfil/Home perdia o flag em memória e o scrub matava o
  /// directo → saltava para GRAVADO.
  Future<void> _scrubOwnGhostLives(List<LivesRow> liveRows) async {
    // Web/Lab: NUNCA fechar lives daqui — o iframe Home do vendedor matava o
    // directo no TCL (≥10 min) e o player saltava sozinho para GRAVADO (Mux).
    if (kIsWeb) return;
    final protectedId =
        await LivePublishCleanup.preferredActiveBroadcastId() ?? '';
    if (protectedId.isNotEmpty) {
      debugPrint(
        '[HomeLiveFeed] scrub skip — broadcast activo protectedId=$protectedId',
      );
      return;
    }
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return;
    // Scrub sem prefs: só fantasmas muito antigos. Ligar espelho USB /
    // resume Stripe já não deve matar um directo recente.
    const scrubMinAge = Duration(hours: 2);
    final now = DateTime.now().toUtc();
    var closed = 0;
    for (final row in liveRows) {
      if ((row.sellerId ?? '').trim() != uid) continue;
      if (!feedIsLiveStream(row)) continue;
      final id = row.id?.trim() ?? '';
      if (id.isEmpty) continue;
      final anchor = row.wentLiveAt ?? row.createdAt;
      if (anchor != null && now.difference(anchor.toUtc()) < scrubMinAge) {
        debugPrint(
          '[HomeLiveFeed] scrub skip young liveId=$id '
          'ageMin=${now.difference(anchor.toUtc()).inMinutes}',
        );
        continue;
      }
      debugPrint(
        '[HomeLiveFeed] scrub candidate ghost liveId=$id title=${row.title}',
      );
      if (await LivePublishCleanup.finalizeEnded(
        id,
        reason: 'home_feed_ghost_scrub',
      )) {
        closed++;
      }
    }
    if (closed > 0) {
      debugPrint('[HomeLiveFeed] scrub closed=$closed ghosts');
      // Não pedir outro refresh: o _loadFeed que chamou o scrub já reconsulta.
    }
  }

  Future<List<LivesRow>> _queryLives({
    required bool live,
    required int from,
    required int to,
  }) async {
    return LivesTable().queryRows(
      queryFn: (q) {
        var query = live
            ? q.eqOrNull('status', 'live').eqOrNull('is_active', true)
            : q.or(
                'status.eq.ended,and(status.eq.live,is_active.eq.false)',
              );
        return query.order('created_at', ascending: false).range(from, to);
      },
    );
  }

  /// ID Mux para card/player: live stream ao vivo; VOD quando terminou.
  static String? _playbackIdForFeed(
    LivesRow live, {
    required bool isLiveStream,
  }) {
    if (isLiveStream) {
      return live.muxPlaybackId?.trim();
    }
    final vod = live.muxVodPlaybackId?.trim();
    if (vod != null && vod.isNotEmpty) return vod;
    return live.muxPlaybackId?.trim();
  }

  Future<List<HomeLiveFeedItem>> _buildItemsFromLives(List<LivesRow> lives) async {
    final sellerIds = lives
        .map((l) => l.sellerId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    var profiles = <ProfilesRow>[];
    if (sellerIds.isNotEmpty) {
      profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) {
          final base = q.inFilter('id', sellerIds);
          if (widget.search.isEmpty) return base;
          return base.ilike('full_name', '%${widget.search}%');
        },
      );
    }

    final profileById = {for (final p in profiles) if (p.id != null) p.id!: p};
    final batch = <HomeLiveFeedItem>[];
    for (final live in lives) {
      final sellerId = live.sellerId;
      if (sellerId == null || sellerId.isEmpty) continue;
      final profile = profileById[sellerId];
      if (profile == null) continue;
      if (SellerVacationMode.hideSellerFromPublicDiscovery(
        sellerOnVacation: profile.vacationMode == true,
        sellerId: sellerId,
      )) {
        continue;
      }
      final isLiveStream = feedIsLiveStream(live);
      final playbackId = _playbackIdForFeed(live, isLiveStream: isLiveStream);
      if (playbackId == null || playbackId.isEmpty) continue;
      batch.add(
        HomeLiveFeedItem(
          profile: profile,
          live: live,
          isLiveStream: isLiveStream,
        ),
      );
    }
    return batch;
  }

  Future<void> _loadFeed({required bool reset}) async {
    final seq = reset ? ++_loadSeq : _loadSeq;
    if (reset) {
      // Só spinner no 1.º load. Refresh seguinte mantém os cards (senão o
      // ecrã salta, os vídeos desaparecem e o teclado da pesquisa fecha).
      final blocking = _items.isEmpty;
      setState(() {
        if (blocking) _initialLoading = true;
        _error = null;
        _endedPage = 0;
        _hasMoreEnded = true;
      });
    } else {
      if (_loadingMore || !_hasMoreEnded) return;
      setState(() => _loadingMore = true);
    }

    try {
      if (reset) {
        final liveRowsRaw = await _queryLives(live: true, from: 0, to: 19);
        await _scrubOwnGhostLives(liveRowsRaw);
        final endedRows = await _queryLives(
          live: false,
          from: 0,
          to: widget.pageSize - 1,
        );
        // Re-query live after scrub so fantasmas não entram no feed.
        final liveRowsFresh = await _queryLives(live: true, from: 0, to: 19);
        final liveRows = liveRowsFresh.where(feedIsLiveStream).toList();
        final reclassifiedEnded =
            liveRowsFresh.where((l) => !feedIsLiveStream(l));
        final endedMerged = <LivesRow>[...endedRows, ...reclassifiedEnded];

        var liveItems = await _buildItemsFromLives(liveRows);
        var endedItems = await _buildItemsFromLives(endedMerged);

        final liveIds =
            liveItems.map((e) => e.live.id).whereType<String>().toSet();
        endedItems = endedItems
            .where((e) => e.live.id == null || !liveIds.contains(e.live.id))
            .toList();

        if (!mounted || seq != _loadSeq) return;
        setState(() {
          _items
            ..clear()
            ..addAll(liveItems)
            ..addAll(endedItems);
          _endedPage = 1;
          _hasMoreEnded = endedMerged.length >= widget.pageSize &&
              _items.length < widget.maxEndedOnHome;
        });
        return;
      }

      final from = _endedPage * widget.pageSize;
      final to = from + widget.pageSize - 1;
      final endedRows = await _queryLives(live: false, from: from, to: to);
      var endedItems = await _buildItemsFromLives(endedRows);

      final existingIds =
          _items.map((e) => e.live.id).whereType<String>().toSet();
      endedItems = endedItems
          .where((e) => e.live.id == null || !existingIds.contains(e.live.id))
          .toList();

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _items.addAll(endedItems);
        _endedPage += 1;
        _hasMoreEnded = endedRows.length >= widget.pageSize &&
            _items.length < widget.maxEndedOnHome;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
      });
    }
  }

  void _openSellerProfile(String sellerId) {
    unawaited(
      HubActions.openPublicProfile(
        context,
        sellerId: sellerId,
        initialTab: 'diretos',
      ),
    );
  }

  void _openSellerOpinions(String sellerId) {
    unawaited(
      HubActions.openPublicProfile(
        context,
        sellerId: sellerId,
        initialTab: 'opinioes',
      ),
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels <
        notification.metrics.maxScrollExtent - 320) {
      return false;
    }
    _loadFeed(reset: false);
    return false;
  }

  /// Spinner a ocupar a grelha só no 1.º load (sem cards). Refresh em fundo
  /// não pode esconder os vídeos — senão o teclado da Home também fecha.
  @visibleForTesting
  static bool showBlockingSpinner({
    required bool loading,
    required bool hasItems,
  }) =>
      loading && !hasItems;

  @override
  Widget build(BuildContext context) {
    if (showBlockingSpinner(
      loading: _initialLoading,
      hasItems: _items.isNotEmpty,
    )) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(color: Color(0xFF007782)),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadFeed(reset: true),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      final hasSearch = widget.search.isNotEmpty;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 72, color: Color(0xFF007782)),
              const SizedBox(height: 12),
              Text(
                hasSearch
                    ? 'Vendedora não encontrada'
                    : 'Ainda não há diretos a carregar.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Color(0xFF57636C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  (constraints.maxWidth - kFleaberTwoColumnGridGap) / 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: kFleaberTwoColumnGridGap,
                  mainAxisSpacing: kFleaberTwoColumnGridGap,
                  childAspectRatio: 9 / 16,
                ),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final playbackId = _playbackIdForFeed(
                        item.live,
                        isLiveStream: item.isLiveStream,
                      ) ??
                      item.live.muxPlaybackId!;
                  final profile = item.profile;
                  final sellerId = profile.id ?? '';
                  final landscapeThumb = MuxUrls.publishBackendUsesLandscapeThumb(
                    item.live.publishBackend,
                  );
                  final preparing = HomeLiveFeedGridState.feedIsRecordingPreparing(
                    item.live,
                  );
                  final liveId = item.live.id ?? '';
                  final feedCoverIds = LiveCoverCatalog.decorrelateProvisional(
                    _items.map((e) => e.live.id ?? '').toList(),
                  );
                  final dbCover = item.live.coverId?.trim();
                  final coverId = (dbCover != null && dbCover.isNotEmpty)
                      ? LiveCoverAssign.resolveCoverId(
                          liveId: liveId,
                          persistedCoverId: dbCover,
                        )
                      : (index < feedCoverIds.length
                          ? feedCoverIds[index]
                          : LiveCoverCatalog.provisionalCoverId(liveId));
                  return HomeMuxLiveCard(
                    key: ValueKey<String>(item.live.id ?? '$index'),
                    width: cardWidth,
                    sellerName:
                        valueOrDefault<String>(profile.fullName, 'Vendedor'),
                    liveTitle: item.live.title,
                    coverId: coverId,
                    thumbnailUrl: landscapeThumb
                        ? MuxUrls.landscapeThumbnail(
                            playbackId,
                            width: 200,
                            live: item.isLiveStream,
                          )
                        : MuxUrls.portraitThumbnail(
                            playbackId,
                            width: 200,
                            live: item.isLiveStream,
                          ),
                    thumbnailQuarterTurns: 0,
                    fallbackAvatarUrl: profile.photoUrl,
                    ratingLabel: widget.ratingLabelForSeller(profile.id),
                    isLive: item.isLiveStream,
                    isRecordingPreparing: preparing,
                    onOpenSellerProfile: sellerId.isEmpty
                        ? null
                        : () => _openSellerProfile(sellerId),
                    onOpenSellerOpinions: sellerId.isEmpty
                        ? null
                        : () => _openSellerOpinions(sellerId),
                    onOpenLive: () {
                      final liveId = item.live.id;
                      if (liveId == null || liveId.isEmpty) return;
                      final openAsLive = feedIsLiveStream(item.live);
                      context.pushNamed(
                        FleaberLivePlayerWidget.routeName,
                        queryParameters: {
                          'liveId': serializeParam(
                            liveId,
                            ParamType.String,
                          ),
                          'playbackId': serializeParam(
                            playbackId,
                            ParamType.String,
                          ),
                          'isLive': serializeParam(
                            openAsLive,
                            ParamType.bool,
                          ),
                          if (sellerId.isNotEmpty)
                            'sellerId': serializeParam(
                              sellerId,
                              ParamType.String,
                            ),
                        }.withoutNulls,
                      );
                    },
                  );
                },
              );
            },
          ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF007782),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class HomeLiveFeedItem {
  const HomeLiveFeedItem({
    required this.profile,
    required this.live,
    required this.isLiveStream,
  });

  final ProfilesRow profile;
  final LivesRow live;
  final bool isLiveStream;
}
