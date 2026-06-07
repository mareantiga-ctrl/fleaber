import 'dart:async';
import 'dart:math' as math;

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_catalog_cache.dart';
import '/utils/live_publish_config.dart';
import '/utils/mux_playback_resolve.dart';
import '/utils/mux_urls.dart';
import '/utils/fleaber_screen_wake.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/live_hls_viewer.dart';
import '/widgets/live_public_chat_line.dart';
import '/widgets/live_tip_gift_bubble.dart';
import '/widgets/profile_avatar.dart';
import '/utils/live_room_service.dart';
import '/utils/live_private_room_service.dart';
import '/live_tip/live_tip_flow.dart';
import '/auth/supabase_auth/auth_util.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_tip_context.dart';
import '/utils/live_in_stream_checkout.dart';
import '/widgets/live_bag_checkout_sheet.dart';
import '/widgets/live_bag_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/order_cancel_eligibility.dart';
import '/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fleaber_live_player_model.dart';
export 'fleaber_live_player_model.dart';

/// Arena live (viewer): vídeo + overlays glass (Stack / Positioned).
const Color _kLiveAccent = Color(0xFF00A3AD);
const Color _kLiveAccentDeep = Color(0xFF14828C);

const List<Shadow> _kOverlayTextShadow = [
  Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
  Shadow(color: Colors.black54, blurRadius: 3),
];

/// Escala visual dos botões da barra lateral direita (A5: −10%).
const double _kSidebarButtonScale = 0.9;

/// Painéis translúcidos — contraste mais alto no directo.
const double _kPanelOpacityCards = 0.52;
const double _kGlassChrome = 0.58;
const double _kGlassButton = 0.50;

class FleaberLivePlayerWidget extends StatefulWidget {
  const FleaberLivePlayerWidget({
    super.key,
    this.liveId,
    this.playbackId,
    this.isLive,
    this.sellerId,
  });

  final String? liveId;
  final String? playbackId;
  /// Hint da Home (evita esperar query Supabase para começar HLS).
  final bool? isLive;
  /// Vendedor (Home passa logo — gorjeta não depende da query lives).
  final String? sellerId;

  static String routeName = 'FleaberLivePlayer';
  static String routePath = '/fleaberLivePlayer';

  @override
  State<FleaberLivePlayerWidget> createState() =>
      _FleaberLivePlayerWidgetState();
}

class _PlaybackSource {
  const _PlaybackSource({
    required this.url,
    required this.isLive,
    this.thumbnailUrl,
  });

  final String url;
  final bool isLive;
  final String? thumbnailUrl;
}

class _FleaberLivePlayerWidgetState extends State<FleaberLivePlayerWidget>
    with FleaberScreenWakeMixin, WidgetsBindingObserver {
  late FleaberLivePlayerModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  /// Card vertical compacto (largura fixa no carrossel horizontal).
  static const double _kCatalogCardW = 108;
  static const double _kCatalogSpacing = 12;
  static double get _kCatalogStride => _kCatalogCardW + _kCatalogSpacing;

  /// Corpo do card (sem contar selo que sobrepõe o topo).
  static const double _kCatalogCardBodyH = 156;
  /// Espaço extra no topo para o selo "A MOSTRAR" à meia-altura na borda.
  static const double _kCatalogSealOverhang = 14;
  static double get _kCatalogStackH =>
      _kCatalogCardBodyH + _kCatalogSealOverhang;

  static const double _kCarouselStripH = 186;
  static const double _kInputBandH = 30;
  static const double _kChatH = 205;
  static const double _kInputOverlapCarousel = 4;
  static const double _kChatGapAboveInput = 3;
  /// Margem à direita para o chat não passar por baixo dos botões laterais.
  static const double _kChatRightGutter = 78;

  final ScrollController _catalogScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  bool _chatLoadOlderBusy = false;

  List<LiveItemsRow>? _catalogRows;
  List<LiveItemShowEventsRow> _catalogShowEvents = [];
  String? _vodActiveItemId;
  bool _catalogLoading = true;
  bool _showCatalogScrollHint = false;
  bool _catalogMinimized = false;
  String? _spotlightItemId;
  String? _lastTrackedActiveCatalogId;
  Timer? _spotlightTimer;
  Timer? _tipStripePollTimer;
  late Future<_PlaybackSource> _playbackSourceFuture;
  LivesRow? _liveRow;
  ProfilesRow? _sellerProfile;
  double? _sellerRatingAvg;
  Timer? _endedVodPoll;
  Timer? _liveClockTimer;
  LiveRoomService? _liveRoom;
  LivePrivateRoomService? _privateRoom;
  RealtimeChannel? _catalogChannel;
  RealtimeChannel? _buyerCheckoutChannel;
  RealtimeChannel? _liveBagChannel;
  int _liveViewerCount = 0;
  int _liveBagCount = 0;
  final Set<String> _purchaseBroadcastAnnounced = {};
  final Set<String> _acceptedReservationNotified = {};
  final Set<String> _buyerAcceptedNoticeDismissed = {};
  final List<_BuyerAcceptedReservationNotice> _buyerAcceptedNotices = [];
  StreamSubscription<int>? _viewerCountSub;
  StreamSubscription<List<LiveRoomMessage>>? _liveMessagesSub;
  final Set<String> _seenTipIds = <String>{};
  final Set<String> _seenAcceptBroadcastMsgIds = <String>{};
  bool _chatAcceptBroadcastsPrimed = false;
  bool _playbackIsLive = true;
  Duration _playbackPosition = Duration.zero;
  DateTime? _liveChatAnchor;
  final Map<String, String> _userNameCacheById = {};
  final Map<String, String> _userPhotoCacheById = {};
  final Set<String> _userNameFetchInFlight = {};
  DateTime _lastUserNameFetchAt = DateTime.fromMillisecondsSinceEpoch(0);

  String get _sellerDisplayName {
    final name = _sellerProfile?.fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final title = _liveRow?.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return 'Direto Fleaber';
  }

  String? get _sellerPhotoUrl => _sellerProfile?.photoUrl?.trim();

  String? get _sellerId =>
      widget.sellerId?.trim().isNotEmpty == true
          ? widget.sellerId!.trim()
          : _liveRow?.sellerId?.trim();

  String? get _sellerRatingLabel {
    final r = _sellerRatingAvg;
    if (r == null) return null;
    return r.toStringAsFixed(1);
  }

  String get _viewerCountLabel {
    if (_liveRoom != null) return '$_liveViewerCount';
    final live = _liveRow;
    if (live == null) return '0';
    final raw = live.data['viewer_count'] ?? live.data['viewers'];
    if (raw is num) return raw.toInt().toString();
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return '0';
  }

  static const List<({String user, String text})> _seedChatPublic = [
    (user: 'Ana', text: 'Boa noite!'),
    (user: 'Rui', text: 'Qual é o tamanho?'),
    (user: 'Sofia', text: 'Já está lindo'),
    (user: 'Miguel', text: 'Consigo reservar?'),
  ];

  static const List<({String user, String text})> _seedChatPrivate = [
    (user: 'Tu', text: 'Olá, ainda tens o #42?'),
    (user: 'Vendedor', text: 'Sim, envio amanhã.'),
    (user: 'Tu', text: 'Perfeito, obrigado.'),
  ];

  final List<({String user, String text})> _chatPublic = [];
  final List<({String user, String text})> _chatPrivate = [];

  bool _privateChatMode = false;

  static List<LiveItemsRow> _demoCatalogRows() {
    final now = DateTime.now().toIso8601String();
    return List<LiveItemsRow>.generate(10, (i) {
      final n = i + 1;
      final isActive = n == 5;
      return LiveItemsRow({
        'id': 'demo-cat-$n',
        'live_id': 'demo',
        'ref_code': 'FB-${8800 + n}',
        'title': n == 5 ? 'Ténis Nike Air' : 'Artigo $n',
        'price': 12.0 + n * 3.5,
        'photo_url': 'https://picsum.photos/seed/fleaber_cat_$n/200',
        'is_active': isActive,
        'created_at': now,
      });
    });
  }

  Future<List<LiveItemsRow>> _fetchCatalogFromNetwork(String liveId) async {
    return LiveItemsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', liveId)
          .order('created_at', ascending: true),
    );
  }

  Future<List<LiveItemShowEventsRow>> _fetchCatalogShowEvents(
    String liveId,
  ) async {
    try {
      return await LiveItemShowEventsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', liveId)
            .order('shown_at', ascending: true),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _initCatalog() async {
    final liveId = widget.liveId?.trim() ?? '';
    final hintSeen = await LiveCatalogCache.scrollHintDismissed();

    if (liveId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _catalogRows = _demoCatalogRows();
        _catalogLoading = false;
        _showCatalogScrollHint = !hintSeen && _catalogRows!.length > 1;
      });
      return;
    }

    final cached = await LiveCatalogCache.read(liveId);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _catalogRows = cached;
        _catalogLoading = false;
        _showCatalogScrollHint = !hintSeen && cached.length > 1;
      });
    }

    try {
      final results = await Future.wait([
        _fetchCatalogFromNetwork(liveId),
        _fetchCatalogShowEvents(liveId),
      ]);
      final rows = results[0] as List<LiveItemsRow>;
      final events = results[1] as List<LiveItemShowEventsRow>;
      if (rows.isNotEmpty) {
        await LiveCatalogCache.write(liveId, rows);
      } else {
        unawaited(
          FleaberLogger.instance.event('video.player.catalog.empty', {
            'live_id': liveId,
          }),
        );
      }
      if (!mounted) return;
      setState(() {
        _catalogRows = rows;
        _catalogShowEvents = events;
        _catalogLoading = false;
        _showCatalogScrollHint = !hintSeen && rows.length > 1;
      });
      _notifyActiveCatalogItemIfChanged(rows);
      _syncVodCatalogHighlight(force: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || rows.isEmpty) return;
        if (_isVodReplay) return;
        final activeI = rows.indexWhere((r) => _isCatalogRowActive(r));
        _scrollCatalogToIndex(activeI >= 0 ? activeI : 0);
      });
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'video.player.catalog',
          error: e,
          stackTrace: st,
          contextLines: ['live_id=$liveId'],
        ),
      );
      if (!mounted) return;
      final fallback = cached ?? const <LiveItemsRow>[];
      setState(() {
        _catalogRows = fallback;
        _catalogLoading = false;
        _showCatalogScrollHint = !hintSeen && fallback.length > 1;
      });
    }
  }

  Future<void> _loadLiveContext() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return;
    try {
      final lives = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', liveId),
        limit: 1,
      );
      if (lives.isEmpty || !mounted) return;
      _liveRow = lives.first;
      final sellerId = _liveRow!.sellerId;
      if (sellerId != null && sellerId.isNotEmpty) {
        final profiles = await ProfilesTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', sellerId),
          limit: 1,
        );
        if (profiles.isNotEmpty) {
          _sellerProfile = profiles.first;
          final sid = _sellerProfile!.id?.trim() ?? '';
          final photo = _sellerProfile!.photoUrl?.trim() ?? '';
          if (sid.isNotEmpty && photo.isNotEmpty) {
            _userPhotoCacheById[sid] = photo;
          }
        }
        final reviews = await ReviewsTable().queryRows(
          queryFn: (q) => q.eqOrNull('target_id', sellerId),
          limit: 200,
        );
        if (reviews.isNotEmpty) {
          final stars = reviews
              .map((r) => r.stars)
              .whereType<int>()
              .toList();
          if (stars.isNotEmpty) {
            _sellerRatingAvg =
                stars.reduce((a, b) => a + b) / stars.length;
          }
        }
      }
      await _seedCurrentUserProfilePhoto();
      if (mounted) {
        setState(() {});
        _ensureLiveClock();
        _subscribeBuyerCheckoutRealtime(liveId);
      }
      _ensurePrivateRoom();
      if (liveId.isNotEmpty) {
        unawaited(_initCatalog());
        if (_liveRow != null &&
            _liveIsEnded(_liveRow!) &&
            (_liveRow?.muxVodPlaybackId?.trim().isEmpty ?? true)) {
          _startEndedVodPoll(liveId);
        }
      }
    } catch (_) {}
  }

  Future<String?> _resolveSellerIdForTip() async {
    final cached = _sellerId;
    if (cached != null && cached.isNotEmpty) return cached;
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return null;
    try {
      final lives = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', liveId),
        limit: 1,
      );
      if (lives.isEmpty) return null;
      _liveRow ??= lives.first;
      return lives.first.sellerId?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showTipMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularMd),
        title: Text(
          'Gorjeta',
          style: GoogleFonts.interTight(fontWeight: FontWeight.w800),
        ),
        content: Text(message, style: GoogleFonts.inter(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTipSheet() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) {
      await _showTipMessage('Este directo ainda não está disponível para gorjetas.');
      return;
    }
    if (currentUserUid.isEmpty) {
      await _showTipMessage('Inicia sessão para enviar uma gorjeta.');
      return;
    }

    final sellerId = await _resolveSellerIdForTip();
    if (sellerId == null || sellerId.isEmpty) {
      await _showTipMessage(
        'A carregar dados do vendedor. Tenta outra vez em instantes.',
      );
      return;
    }
    if (sellerId == currentUserUid) {
      await _showTipMessage('Não podes enviar gorjeta ao teu próprio directo.');
      return;
    }

    final source = await _playbackSourceFuture;
    final result = await showLiveTipSheet(
      context,
      LiveTipLaunchArgs(
        liveId: liveId,
        sellerId: sellerId,
        playbackId: widget.playbackId ?? _liveRow?.muxPlaybackId,
        isLive: source.isLive,
        sellerName: _sellerDisplayName,
      ),
    );
    if (!mounted || result == null) return;
    // Confirmação visual passa a ser apenas no chat do direto.
  }

  Future<void> _dismissCatalogScrollHint() async {
    if (!_showCatalogScrollHint) return;
    await LiveCatalogCache.dismissScrollHint();
    if (mounted) setState(() => _showCatalogScrollHint = false);
  }

  void _toggleCatalogMinimized() {
    setState(() {
      _catalogMinimized = !_catalogMinimized;
      if (!_catalogMinimized) {
        _spotlightItemId = null;
        _spotlightTimer?.cancel();
      }
    });
  }

  void _closePlayer() {
    final seller = widget.sellerId?.trim() ?? '';
    final isOwnEndedLive =
        seller.isNotEmpty && seller == currentUserUid && !_liveIsActive;
    if (isOwnEndedLive) {
      context.goNamed(HomePageWidget.routeName);
      return;
    }
    context.safePop();
  }

  void _notifyActiveCatalogItemIfChanged(List<LiveItemsRow> rows) {
    if (_isVodReplay) return;
    String? activeId;
    for (final r in rows) {
      if (r.isActive == true) {
        activeId = r.id?.trim();
        break;
      }
    }
    if (activeId == null || activeId.isEmpty) return;
    if (activeId == _lastTrackedActiveCatalogId) return;
    _lastTrackedActiveCatalogId = activeId;
    _spotlightTimer?.cancel();
    if (!_catalogMinimized) {
      setState(() => _spotlightItemId = null);
      final idx = rows.indexWhere((r) => r.id?.trim() == activeId);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollCatalogToIndex(idx);
        });
      }
      return;
    }
    setState(() {
      _spotlightItemId = activeId;
    });
    _spotlightTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _spotlightItemId = null);
    });
    final idx = rows.indexWhere((r) => r.id?.trim() == activeId);
    if (idx >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollCatalogToIndex(idx);
      });
    }
  }

  LiveItemsRow? _catalogRowById(String? id) {
    final rows = _catalogRows;
    if (rows == null || id == null || id.isEmpty) return null;
    for (final r in rows) {
      if (r.id?.trim() == id) return r;
    }
    return null;
  }

  static bool _isCatalogRowUnavailable(LiveItemsRow row) =>
      LiveVendorSellerCopy.isLiveItemUnavailable(row.status);

  static bool _isCatalogRowPaidSold(LiveItemsRow row) =>
      LiveVendorSellerCopy.isMarkedSold(row.status);

  static String _catalogUnavailableBadge(LiveItemsRow row) =>
      LiveVendorSellerCopy.liveCatalogUnavailableBadge(row.status);

  static const Color _kSoldBadge = Color(0xFFE57373);

  Widget _buildSpotlightCatalogCard(LiveItemsRow row) {
    final unavailable = _isCatalogRowUnavailable(row);
    final badge = _catalogUnavailableBadge(row);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(
            color: unavailable ? _kSoldBadge : _kLiveAccent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: FleaberRadius.circularSm,
              child: SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    row.photoUrl?.trim().isNotEmpty == true
                        ? BatataCachedNetworkImage(
                            imageUrl: row.photoUrl!.trim(),
                            fit: BoxFit.cover,
                            placeholderColor: const Color(0xFF222222),
                            errorWidget: _placeholderImage(),
                          )
                        : _placeholderImage(),
                    if (unavailable)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unavailable ? badge : 'A MOSTRAR AGORA',
                    style: GoogleFonts.interTight(
                      color: unavailable ? _kSoldBadge : _kLiveAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _catalogTitleLine(row),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (_formatPriceEur(row) != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatPriceEur(row)!,
                      style: GoogleFonts.interTight(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upgradePlaybackFromDb(String liveId) async {
    try {
      final previous = await _playbackSourceFuture;
      final source = await _loadPlaybackSource(retryResolve: true);
      if (!mounted || source.url.isEmpty) return;
      if (previous.url == source.url && previous.isLive == source.isLive) {
        return;
      }
      unawaited(
        FleaberLogger.instance.event('video.playback.upgrade', {
          'live_id': liveId,
          'url': source.url,
          'is_live': source.isLive,
          'has_reduced_latency': source.url.contains('reduced_latency'),
        }),
      );
      setState(() {
        _playbackSourceFuture = Future.value(source);
      });
    } catch (e, st) {
      unawaited(
        FleaberLogger.instance.reportFailure(
          category: 'video.playback.upgrade',
          error: e,
          stackTrace: st,
          contextLines: ['live_id=$liveId'],
        ),
      );
    }
  }

  static bool _liveIsEnded(LivesRow live) {
    final status = (live.status ?? '').toLowerCase();
    if (status == 'ended' || status == 'cancelled') return true;
    if (status == 'live') return false;
    // Conservador: se ainda não sabemos (status null/unknown), não forçar VOD.
    // Só consideramos “ended” quando o backend diz explicitamente.
    if (live.isActive == false) return true;
    return false;
  }

  Future<String?> _resolveVodPlaybackUrl(String liveId) async {
    final resolved = await MuxPlaybackResolve.fetchFromServer(
      liveId,
      logContext: 'player_vod_fallback',
    );
    if (resolved != null && resolved.ok && !resolved.isLive) {
      return resolved.url;
    }
    if (resolved != null && resolved.ok && resolved.isLive) {
      unawaited(
        FleaberLogger.instance.event('video.playback.fallback.still_live', {
          'live_id': liveId,
          'playback_id': resolved.playbackId,
          'source': resolved.source,
        }),
      );
    }
    return null;
  }

  void _startEndedVodPoll(String liveId) {
    _endedVodPoll?.cancel();
    var ticks = 0;
    _endedVodPoll = Timer.periodic(const Duration(seconds: 6), (_) async {
      ticks++;
      if (!mounted || ticks > 20) {
        _endedVodPoll?.cancel();
        return;
      }
      await _upgradePlaybackFromDb(liveId);
    });
  }

  Future<_PlaybackSource> _loadPlaybackSource({bool retryResolve = false}) async {
    final directPlayback = widget.playbackId?.trim();
    final liveId = widget.liveId?.trim() ?? '';

    if (liveId.isNotEmpty) {
      try {
        final rows = await LivesTable()
            .queryRows(
              queryFn: (q) => q.eqOrNull('id', liveId),
              limit: 1,
            )
            .timeout(const Duration(seconds: 8));
        if (rows.isNotEmpty) {
          final live = rows.first;
          _liveRow = live;
          final playbackId = live.muxPlaybackId?.trim() ?? '';
          final isEnded = _liveIsEnded(live);
          // Não confiar no hint de `widget.isLive` (pode vir errado da Home).
          // Forçamos VOD apenas quando o backend indica mesmo “ended”.
          final forceVod = isEnded;

          if (playbackId.isNotEmpty || isEnded || forceVod || retryResolve) {
            if (forceVod) {
              final server = await MuxPlaybackResolve.fetchFromServer(
                liveId,
                logContext: retryResolve ? 'poll' : 'initial',
                timeout: retryResolve
                    ? const Duration(seconds: 12)
                    : const Duration(seconds: 28),
              );
              if (server != null && server.ok) {
                final playAsLive = forceVod ? false : server.isLive;
                final thumbId = server.playbackId;
                final playUrl =
                    MuxUrls.playbackHls(server.playbackId, live: playAsLive);
                final source = _PlaybackSource(
                  url: playUrl,
                  isLive: playAsLive,
                  thumbnailUrl: MuxUrls.portraitThumbnail(
                    thumbId,
                    width: 720,
                    live: playAsLive,
                  ),
                );
                _logPlaybackSourceChosen(live, source, server.source);
                return source;
              }
              final vodLocal = live.muxVodPlaybackId?.trim() ?? '';
              if (forceVod && vodLocal.isNotEmpty) {
                final source = _PlaybackSource(
                  url: MuxUrls.playbackHls(vodLocal, live: false),
                  isLive: false,
                  thumbnailUrl: MuxUrls.portraitThumbnail(
                    vodLocal,
                    width: 720,
                    live: false,
                  ),
                );
                _logPlaybackSourceChosen(live, source, 'vod_db_fallback');
                return source;
              }
            }

            if (retryResolve && !forceVod) {
              final server = await MuxPlaybackResolve.fetchFromServer(
                liveId,
                logContext: 'poll_live_refresh',
                timeout: const Duration(seconds: 12),
              );
              if (server != null && server.ok && server.isLive) {
                final source = _PlaybackSource(
                  url: server.url,
                  isLive: true,
                  thumbnailUrl: MuxUrls.portraitThumbnail(
                    server.playbackId,
                    width: 720,
                    live: true,
                  ),
                );
                _logPlaybackSourceChosen(live, source, server.source);
                return source;
              }
            }

            final resolved = await MuxPlaybackResolve.resolveForLive(
              liveId: liveId,
              muxPlaybackId: live.muxPlaybackId,
              muxVodPlaybackId: live.muxVodPlaybackId,
              status: forceVod ? 'ended' : live.status,
              forceVod: forceVod,
            );
            final playAsLive = !forceVod && resolved.isLive;
            final thumbId =
                live.muxVodPlaybackId?.trim().isNotEmpty == true
                    ? live.muxVodPlaybackId!
                    : playbackId;
            final source = _PlaybackSource(
              url: resolved.url,
              isLive: playAsLive,
              thumbnailUrl: thumbId.isNotEmpty
                  ? MuxUrls.portraitThumbnail(
                      thumbId,
                      width: 720,
                      live: playAsLive,
                    )
                  : null,
            );
            _logPlaybackSourceChosen(live, source, 'db_resolve');
            return source;
          }
        }
      } catch (e, st) {
        unawaited(
          FleaberLogger.instance.reportFailure(
            category: 'video.playback.load_source',
            error: e,
            stackTrace: st,
            contextLines: ['live_id=$liveId'],
          ),
        );
      }
      if (directPlayback != null && directPlayback.isNotEmpty) {
        final hintLive =
            widget.isLive == true && (_liveRow == null || !_liveIsEnded(_liveRow!));
        final source = _PlaybackSource(
          url: MuxUrls.playbackHls(directPlayback, live: hintLive),
          isLive: hintLive,
          thumbnailUrl: MuxUrls.portraitThumbnail(
            directPlayback,
            width: 720,
            live: hintLive,
          ),
        );
        _logPlaybackSourceChosen(null, source, 'playback_id_hint');
        return source;
      }
    }

    if (directPlayback != null && directPlayback.isNotEmpty && liveId.isEmpty) {
      final hintLive = widget.isLive ?? (_liveRow != null && !_liveIsEnded(_liveRow!));
      return _PlaybackSource(
        url: MuxUrls.playbackHls(directPlayback, live: hintLive),
        isLive: hintLive,
        thumbnailUrl: MuxUrls.portraitThumbnail(
          directPlayback,
          width: 720,
          live: hintLive,
        ),
      );
    }

    unawaited(
      FleaberLogger.instance.event('video.playback.source.empty', {
        'live_id': liveId.isEmpty ? null : liveId,
        'playback_id_hint': directPlayback,
        'is_live_hint': widget.isLive,
      }),
    );
    return const _PlaybackSource(url: '', isLive: true);
  }

  void _logPlaybackSourceChosen(
    LivesRow? live,
    _PlaybackSource source, [
    String? resolveSource,
  ]) {
    unawaited(
      FleaberLogger.instance.event('video.playback.source', {
        'live_id': widget.liveId,
        'status': live?.status,
        'is_active': live?.isActive,
        'url': source.url,
        'is_live': source.isLive,
        'resolve_source': resolveSource,
        'has_reduced_latency': source.url.contains('reduced_latency'),
        'mux_vod_playback_id': live?.muxVodPlaybackId,
        'mux_playback_id': live?.muxPlaybackId,
        'is_live_hint': widget.isLive,
      }),
    );
  }

  bool get _liveIsActive {
    if (!_playbackIsLive) return false;
    final live = _liveRow;
    if (live != null && (live.status ?? '').toLowerCase() == 'ended') {
      return false;
    }
    return true;
  }

  bool get _isVodReplay => !_liveIsActive;

  bool get _showChatInput => _liveIsActive;

  bool get _showChatPanel {
    final liveId = widget.liveId?.trim() ?? '';
    return liveId.isEmpty || _liveRoom != null;
  }

  static const double _kChatSyncLeadSec = 0.85;

  void _ensureLiveClock() {
    _liveClockTimer?.cancel();
    if (!_liveIsActive || !_playbackIsLive) return;
    if (_streamStartFromLiveRow() == null) {
      unawaited(_pollLiveClockAnchor());
      return;
    }
    _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _pollLiveClockAnchor() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty || !_liveIsActive || !_playbackIsLive) return;
    try {
      final lives = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', liveId),
        limit: 1,
      );
      if (lives.isEmpty || !mounted) return;
      _liveRow = lives.first;
      if (_streamStartFromLiveRow() != null) {
        setState(() {});
        _ensureLiveClock();
      }
    } catch (_) {}
  }

  String _formatClock(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Duration get _liveElapsedNow {
    final start = _streamStartFromLiveRow();
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  Widget _buildLiveInlineTimeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white70, size: 12),
          const SizedBox(width: 5),
          Text(
            _formatClock(_liveElapsedNow),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _streamStartFromLiveRow() {
    final live = _liveRow;
    if (live == null) return null;

    DateTime? streamStart = live.wentLiveAt?.toLocal();

    for (final key in ['went_live_at', 'live_started_at', 'started_at']) {
      final raw = live.data[key];
      if (raw == null) continue;
      final t = raw is DateTime
          ? raw.toLocal()
          : DateTime.tryParse(raw.toString())?.toLocal();
      if (t == null) continue;
      streamStart = streamStart == null || t.isBefore(streamStart) ? t : streamStart;
    }

    streamStart ??= live.createdAt?.toLocal();
    return streamStart;
  }

  /// Âncora do chat no replay — nunca usar `created_at` da live (pode ser horas antes).
  DateTime _resolveChatPlaybackAnchor(List<LiveRoomMessage> dated) {
    if (_liveChatAnchor != null) return _liveChatAnchor!;
    final streamStart = _streamStartFromLiveRow();
    final firstMsg = dated
        .map((m) => m.createdAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final lastMsg = dated
        .map((m) => m.createdAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final anchor = streamStart != null && !streamStart.isAfter(lastMsg)
        ? streamStart
        : firstMsg;
    _liveChatAnchor = anchor;
    return anchor;
  }

  /// VOD Mux costuma começar alguns segundos depois do «went live» (ver MERDA.md).
  double _vodPlaybackSkewSec(DateTime anchor, List<LiveRoomMessage> dated) {
    final firstMsg = dated
        .map((m) => m.createdAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final gapSec = firstMsg.difference(anchor).inSeconds;
    if (gapSec > 0 && gapSec <= 120) return gapSec.toDouble();
    return 0;
  }

  void _resetChatPlaybackSync() {
    _liveChatAnchor = null;
    _playbackPosition = Duration.zero;
    _vodActiveItemId = null;
  }

  DateTime? _resolveCatalogPlaybackAnchor() {
    final datedMsgs = _liveRoom?.messages
            .where((m) => m.createdAt != null)
            .toList() ??
        const <LiveRoomMessage>[];
    if (datedMsgs.isNotEmpty) {
      return _resolveChatPlaybackAnchor(datedMsgs);
    }

    final datedEvents = _catalogShowEvents
        .where((e) => e.shownAt != null)
        .toList();
    if (datedEvents.isEmpty) return _streamStartFromLiveRow();

    final streamStart = _streamStartFromLiveRow();
    final first = datedEvents.first.shownAt!;
    final last = datedEvents.last.shownAt!;
    if (streamStart != null && !streamStart.isAfter(last)) return streamStart;
    return first;
  }

  double _vodCatalogSkewSec(DateTime anchor) {
    final datedMsgs = _liveRoom?.messages
            .where((m) => m.createdAt != null)
            .toList() ??
        const <LiveRoomMessage>[];
    if (datedMsgs.isNotEmpty) {
      return _vodPlaybackSkewSec(anchor, datedMsgs);
    }

    final datedEvents = _catalogShowEvents
        .where((e) => e.shownAt != null)
        .toList();
    if (datedEvents.isEmpty) return 0;
    final first = datedEvents.first.shownAt!;
    final gapSec = first.difference(anchor).inSeconds;
    if (gapSec > 0 && gapSec <= 120) return gapSec.toDouble();
    return 0;
  }

  List<LiveItemShowEventsRow> get _datedCatalogShowEvents {
    final events = _catalogShowEvents
        .where(
          (e) =>
              e.shownAt != null && (e.liveItemId?.trim().isNotEmpty ?? false),
        )
        .toList();
    events.sort((a, b) => a.shownAt!.compareTo(b.shownAt!));
    return events;
  }

  String? _resolveVodActiveItemId() {
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return null;

    final datedEvents = _datedCatalogShowEvents;
    if (datedEvents.isEmpty) {
      for (final r in rows) {
        if (r.isActive == true) return r.id?.trim();
      }
      return rows.first.id?.trim();
    }

    final anchor = _resolveCatalogPlaybackAnchor();
    if (anchor == null) {
      return datedEvents.last.liveItemId?.trim();
    }

    final posSec = _playbackPosition.inMilliseconds / 1000.0;
    final skewSec = _vodCatalogSkewSec(anchor);
    final effectivePos = posSec + skewSec;
    final anchorUtc = anchor.toUtc();

    String? activeId;
    for (final e in datedEvents) {
      final offsetSec = e.shownAt!
          .toUtc()
          .difference(anchorUtc)
          .inMilliseconds /
          1000.0;
      if (offsetSec <= effectivePos + _kChatSyncLeadSec) {
        activeId = e.liveItemId?.trim();
      } else {
        break;
      }
    }
    return activeId;
  }

  bool _isCatalogRowActive(LiveItemsRow row) {
    if (!_isVodReplay) return row.isActive == true;
    if (_datedCatalogShowEvents.isNotEmpty) {
      final highlight = _vodActiveItemId;
      return highlight != null &&
          highlight.isNotEmpty &&
          row.id?.trim() == highlight;
    }
    final highlight = _vodActiveItemId;
    if (highlight != null && highlight.isNotEmpty) {
      return row.id?.trim() == highlight;
    }
    return row.isActive == true;
  }

  void _syncVodCatalogHighlight({bool force = false}) {
    if (!_isVodReplay) {
      if (_vodActiveItemId != null) {
        setState(() => _vodActiveItemId = null);
      }
      return;
    }

    final id = _resolveVodActiveItemId();
    final previousId = _vodActiveItemId;
    if (!force && id == previousId) return;

    final itemChanged = id != previousId;

    setState(() => _vodActiveItemId = id);

    if (itemChanged) {
      _spotlightTimer?.cancel();
      if (id == null || id.isEmpty) {
        if (_spotlightItemId != null) {
          setState(() => _spotlightItemId = null);
        }
      } else if (!_catalogMinimized) {
        if (_spotlightItemId != null) {
          setState(() => _spotlightItemId = null);
        }
      } else {
        setState(() => _spotlightItemId = id);
        _spotlightTimer = Timer(const Duration(seconds: 10), () {
          if (mounted) setState(() => _spotlightItemId = null);
        });
      }
    }

    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return;
    final idx = id == null ? -1 : rows.indexWhere((r) => r.id?.trim() == id);
    if (idx >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollCatalogToIndex(idx);
      });
    }
  }

  Future<String> _resolveBuyerDisplayNameForChat() async {
    final auth = currentUserDisplayName.trim();
    if (auth.isNotEmpty) return auth;
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return 'Utilizador';
    final cached = _userNameCacheById[uid];
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    try {
      final rows = await ProfilesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', uid),
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final n = rows.first.fullName?.trim() ?? '';
        if (n.isNotEmpty) {
          _userNameCacheById[uid] = n;
          return n;
        }
      }
    } catch (_) {}
    return 'Utilizador';
  }

  String _resolveChatBuyerName(String raw, String? userId) {
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'utilizador') {
      return trimmed;
    }
    final uid = userId?.trim() ?? '';
    if (uid.isEmpty) {
      return trimmed.isEmpty ? 'Utilizador' : trimmed;
    }
    final cached = _userNameCacheById[uid]?.trim() ?? '';
    if (cached.isNotEmpty && cached.toLowerCase() != 'utilizador') {
      return cached;
    }
    if (uid == currentUserUid) {
      final mine = currentUserDisplayName.trim();
      if (mine.isNotEmpty) return mine;
    }
    return trimmed.isEmpty ? 'Utilizador' : trimmed;
  }

  String _resolveHumanChatLabel({
    required String? senderLabel,
    required String? userId,
    bool isSeller = false,
  }) {
    final raw = senderLabel?.trim() ?? '';
    final uid = userId?.trim() ?? '';
    if (raw.isNotEmpty && raw.toLowerCase() != 'utilizador') return raw;

    final cached = uid.isNotEmpty ? _userNameCacheById[uid]?.trim() : null;
    if (cached != null &&
        cached.isNotEmpty &&
        cached.toLowerCase() != 'utilizador') {
      return cached;
    }

    if (isSeller) {
      final sellerName = _sellerProfile?.fullName?.trim();
      if (sellerName != null && sellerName.isNotEmpty) return sellerName;
      if (_sellerDisplayName.trim().isNotEmpty) return _sellerDisplayName.trim();
    }

    if (uid.isNotEmpty && uid == currentUserUid) {
      final mine = currentUserDisplayName.trim();
      if (mine.isNotEmpty) return mine;
    }

    return raw.isNotEmpty ? raw : 'Utilizador';
  }

  Future<void> _seedCurrentUserProfilePhoto() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return;
    final authPhoto = currentUserPhoto.trim();
    if (authPhoto.isNotEmpty) {
      _userPhotoCacheById[uid] = authPhoto;
      return;
    }
    try {
      final profiles = await ProfilesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', uid),
        limit: 1,
      );
      if (profiles.isEmpty) return;
      final photo = profiles.first.photoUrl?.trim() ?? '';
      if (photo.isNotEmpty) {
        _userPhotoCacheById[uid] = photo;
      }
    } catch (_) {
      // Ignorar — fallback para placeholder.
    }
  }

  void _ensureUserNamesResolved(List<LiveRoomMessage> msgs) {
    final now = DateTime.now();
    if (now.difference(_lastUserNameFetchAt) < const Duration(milliseconds: 350)) {
      return;
    }

    final ids = msgs
        .map((m) => m.userId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .where((id) => !_userNameFetchInFlight.contains(id))
        .where((id) {
          if (!_userNameCacheById.containsKey(id)) return true;
          final cached = _userNameCacheById[id]?.trim().toLowerCase() ?? '';
          if (cached.isEmpty || cached == 'utilizador') return true;
          final photo = _userPhotoCacheById[id];
          return photo == null || photo.trim().isEmpty;
        })
        .take(24)
        .toList();

    if (ids.isEmpty) return;
    _lastUserNameFetchAt = now;

    for (final id in ids) {
      _userNameFetchInFlight.add(id);
    }

    unawaited(() async {
      try {
        final profiles = await ProfilesTable().queryRows(
          queryFn: (q) => q.inFilter('id', ids),
        );
        final names = <String, String>{};
        final photos = <String, String>{};
        for (final p in profiles) {
          final pid = p.id?.trim();
          if (pid == null || pid.isEmpty) continue;
          final full = p.fullName?.trim();
          if (full != null && full.isNotEmpty) {
            names[pid] = full;
          }
          final photo = p.photoUrl?.trim() ?? '';
          if (photo.isNotEmpty) {
            photos[pid] = photo;
          }
        }
        if (!mounted) return;
        setState(() {
          _userNameCacheById.addAll(names);
          _userPhotoCacheById.addAll(photos);
        });
      } catch (_) {
        // Ignorar — o chat continua com fallback local.
      } finally {
        _userNameFetchInFlight.removeAll(ids);
      }
    }());
  }

  List<LiveRoomMessage> _filterMessagesForPlayback(List<LiveRoomMessage> msgs) {
    if (_showChatInput) return msgs;

    final dated = msgs.where((m) => m.createdAt != null).toList();
    if (dated.isEmpty) return const [];

    var anchor = _resolveChatPlaybackAnchor(dated);
    final skewSec = _vodPlaybackSkewSec(anchor, dated);
    final posSec = _playbackPosition.inMilliseconds / 1000.0;
    final effectivePos = posSec + skewSec;

    // Âncora inválida (ex. relógio à frente das mensagens) → 1.ª mensagem.
    var negative = 0;
    for (final m in dated) {
      if (m.createdAt!.difference(anchor).inSeconds < -2) negative++;
    }
    if (negative > dated.length ~/ 3) {
      anchor = dated
          .map((m) => m.createdAt!)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      _liveChatAnchor = anchor;
    }

    return dated.where((m) {
      final offsetSec = m.createdAt!.difference(anchor).inMilliseconds / 1000.0;
      return offsetSec <= effectivePos + _kChatSyncLeadSec;
    }).toList();
  }

  void _onPlaybackTick(Duration position, Duration duration) {
    if (!_isVodReplay) return;
    if (_playbackPosition.inMilliseconds == position.inMilliseconds) return;
    setState(() => _playbackPosition = position);
    _syncVodCatalogHighlight();
  }

  void _ensurePrivateRoom() {
    final liveId = widget.liveId?.trim() ?? '';
    final seller = _sellerId?.trim() ?? '';
    if (liveId.isEmpty ||
        seller.isEmpty ||
        seller == currentUserUid ||
        currentUserUid.isEmpty) {
      return;
    }
    if (_privateRoom != null) return;
    _privateRoom = LivePrivateRoomService(
      liveId: liveId,
      sellerId: seller,
    );
    unawaited(_privateRoom!.start());
  }

  Future<void> _sendChatMessage() async {
    final text = _model.chatTextController.text.trim();
    if (text.isEmpty) return;
    if (_privateChatMode) {
      _ensurePrivateRoom();
      final priv = _privateRoom;
      final seller = _sellerId?.trim();
      if (priv == null || seller == null || seller.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inicia sessão para enviar mensagem privada.'),
          ),
        );
        return;
      }
      if (!_liveIsActive) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O directo já terminou.')),
        );
        return;
      }
      final ok = await priv.sendPrivate(text, recipientId: seller);
      if (!mounted) return;
      if (ok) {
        _model.chatTextController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível enviar a mensagem privada.'),
          ),
        );
      }
      return;
    }
    final room = _liveRoom;
    if (room != null) {
      if (currentUserUid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicia sessão para escrever no chat.')),
        );
        return;
      }
      if (!_liveIsActive) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O directo já terminou.')),
        );
        return;
      }
      final ok = await room.sendChat(text);
      if (!mounted) return;
      if (ok) {
        _model.chatTextController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível enviar a mensagem. Tenta outra vez.'),
          ),
        );
      }
      return;
    }
    setState(() {
      _chatPublic.add((user: 'Tu', text: text));
    });
    _model.chatTextController.clear();
  }

  void _scrollCatalogToIndex(int index) {
    if (!_catalogScrollController.hasClients) return;
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return;
    final idx = index.clamp(0, rows.length - 1);
    final offset = idx * _kCatalogStride;
    _catalogScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _onReservarItem(String? itemId) {
    final liveId = widget.liveId?.trim() ?? '';
    final sellerId = _sellerId?.trim() ?? _liveRow?.sellerId?.trim() ?? '';
    if (itemId == null || itemId.isEmpty || liveId.isEmpty || sellerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva indisponível neste momento.')),
      );
      return;
    }
    final itemRow = _catalogRowById(itemId);
    if (currentUserUid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para reservar.')),
      );
      return;
    }
    unawaited(() async {
      try {
        final queue = LiveReservationQueueService();
        final priorOpen = await queue.countBuyerOpenReservationsOnItem(
          liveId: liveId,
          liveItemId: itemId,
          buyerId: currentUserUid,
        );
        final req = await queue.createRequest(
          liveId: liveId,
          liveItemId: itemId,
          sellerId: sellerId,
          buyerId: currentUserUid,
          requestedQty: 1,
          source: LiveReservationSource.fleaberLive,
          notes: 'bag:live_player',
        );
        final myName = _truncateUiText(
          await _resolveBuyerDisplayNameForChat(),
          max: 20,
        );
        final itemRow = _catalogRowById(itemId);
        final productLabel = _productDisplayLabel(
          refCode: itemRow?.refCode,
          title: itemRow?.title,
        );
        await queue.postSystemMessage(
          liveId: liveId,
          body: productLabel == null
              ? '🛍️ $myName reservou para o saco da live'
              : '🛍️ $myName reservou $productLabel',
          senderLabel: 'Sistema',
        );
        final others = await LiveReservationRequestsTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('live_id', liveId)
              .eqOrNull('live_item_id', itemId)
              .eqOrNull('source', 'fleaber_live')
              .eqOrNull('status', 'pending'),
          limit: 200,
        );
        final othersCount = others.where((r) => r.buyerId != currentUserUid).length;
        if (!mounted) return;
        final pos = req?.queuePosition;
        final snap = itemRow != null
            ? await LiveCatalogStockService.fetch(itemRow.id!.trim())
            : null;
        final waitlist = LiveReservationQueueService.isWaitlistPosition(
          queuePosition: pos,
          stock: snap,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LiveReservationQueueService.buyerReserveSnackMessage(
                priorOpenCount: priorOpen,
                queuePosition: pos,
                waitlist: waitlist,
                othersWantItem: othersCount > 0,
              ),
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyReservationError(e))),
        );
      }
    }());
  }

  static String _truncateUiText(String text, {int max = 20}) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  static bool _looksLikeUuidOrTechRef(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}$').hasMatch(t)) return true;
    if (RegExp(r'^[A-Z]{2,5}-[0-9a-fA-F]{8,}$').hasMatch(t)) return true;
    return false;
  }

  static String? _productDisplayLabel({
    String? refCode,
    String? title,
  }) {
    final name = LiveVendorRefDisplay.itemDisplayName(
      title: title,
      refCode: refCode,
    );
    return _truncateUiText(name, max: 24);
  }

  static String _formatSystemMessageUi(String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return text;

    final reserve = RegExp(r'^(?:🛍️\s*)?(.*?)\s+reservou\s+(.*)$').firstMatch(text);
    if (reserve != null) {
      final name = _truncateUiText(reserve.group(1) ?? 'Utilizador', max: 20);
      final label = _truncateUiText(
        (reserve.group(2) ?? '').replaceAll('para o saco da live', '').trim(),
        max: 24,
      );
      return label.isEmpty ? '🛍️ $name reservou no saco' : '🛍️ $name reservou $label';
    }

    final bought = RegExp(r'^(?:✅\s*)?(.*?)\s+comprou\s+(.*)$').firstMatch(text);
    if (bought != null) {
      final name = _truncateUiText(bought.group(1) ?? 'Utilizador', max: 20);
      final label = _truncateUiText((bought.group(2) ?? '').trim(), max: 24);
      return label.isEmpty ? '✅ $name comprou' : '✅ $name comprou $label';
    }

    final cleaned = text
        .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _truncateUiText(cleaned, max: 72);
  }

  Future<ProductsRow?> _resolveProductForLiveItem(LiveItemsRow row) async {
    final sellerId = _sellerId?.trim() ?? '';
    if (sellerId.isEmpty) return null;

    final linkedProductId = row.productId?.trim();
    if (linkedProductId != null && linkedProductId.isNotEmpty) {
      final byId = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', linkedProductId),
        limit: 1,
      );
      if (byId.isNotEmpty) return byId.first;
    }

    final checkoutId = row.checkoutProductId?.trim();
    if (checkoutId != null && checkoutId.isNotEmpty) {
      final byCheckout = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', checkoutId),
        limit: 1,
      );
      if (byCheckout.isNotEmpty) return byCheckout.first;
    }

    final ref = (row.refCode ?? '').trim();
    if (ref.isNotEmpty) {
      final byRef = await ProductsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sellerId)
            .eqOrNull('ref_code', ref)
            .order('created_at', ascending: false),
        limit: 1,
      );
      if (byRef.isNotEmpty) return byRef.first;
    }
    final title = (row.title ?? '').trim();
    if (title.isNotEmpty) {
      final byTitle = await ProductsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sellerId)
            .eqOrNull('title', title)
            .order('created_at', ascending: false),
        limit: 1,
      );
      if (byTitle.isNotEmpty) return byTitle.first;
    }
    final liveItemId = row.id?.trim() ?? '';
    if (liveItemId.isNotEmpty && !row.isMarketplaceProduct) {
      final shadowId =
          await LiveCatalogStockService.ensureCheckoutProduct(liveItemId);
      if (shadowId != null && shadowId.isNotEmpty) {
        final shadow = await ProductsTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', shadowId),
          limit: 1,
        );
        if (shadow.isNotEmpty) return shadow.first;
      }
    }
    return null;
  }

  Future<LiveCatalogStockSnapshot?> _fetchLiveItemStock(LiveItemsRow row) async {
    final id = row.id?.trim() ?? '';
    if (id.isEmpty) return null;
    return LiveCatalogStockService.fetch(id);
  }

  Future<int?> _resolveAvailableQtyForProduct(ProductsRow? product) async {
    if (product == null || product.id == null || product.id!.isEmpty) return null;
    final total = product.quantity < 1 ? 1 : product.quantity;
    final orders = await OrdersTable().queryRows(
      queryFn: (q) => q.eqOrNull('product_id', product.id),
      limit: 120,
    );
    var blocked = 0;
    for (final o in orders) {
      if (!orderStatusBlocksOtherBuyers(o.status)) continue;
      blocked += o.quantity < 1 ? 1 : o.quantity;
    }
    final available = total - blocked;
    return available < 0 ? 0 : available;
  }

  Future<int> _resolveSoldQty(ProductsRow? product) async {
    if (product == null || product.id == null || product.id!.isEmpty) return 0;
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('product_id', product.id).eqOrNull('status', 'pago'),
        limit: 200,
      );
      return rows.fold<int>(0, (a, b) => a + (b.quantity < 1 ? 1 : b.quantity));
    } catch (_) {
      return 0;
    }
  }

  /// Reservas no card expandido — mesma regra do catálogo vendedor:
  /// pendentes neste directo + compromissos do mesmo produto noutros directos.
  int _reservationsCountFromStock(LiveCatalogStockSnapshot? snap) {
    if (snap == null) return 0;
    final localRes = snap.pendingBagQty < 0 ? 0 : snap.pendingBagQty;
    final externalHolds = snap.blockedQty < 0 ? 0 : snap.blockedQty;
    return localRes + externalHolds;
  }

  Future<void> _openCheckoutForProduct(
    ProductsRow product, {
    String? liveItemId,
    String? reservationRequestId,
    String? checkoutNotes,
    int payQty = 1,
    VoidCallback? onPaymentStarted,
  }) async {
    if (!mounted) return;
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) {
      context.push(
        ProductDetailsPageWidget.routePath,
        extra: ProductDetailsPageWidget.routeExtraForProduct(product),
      );
      return;
    }
    final byId = {
      for (final c in _catalogRows ?? const <LiveItemsRow>[])
        if ((c.id ?? '').trim().isNotEmpty) (c.id ?? '').trim(): c,
    };
    final reqId = reservationRequestId?.trim() ?? '';
    if (reqId.isNotEmpty) {
      try {
        final reqRows = await LiveReservationRequestsTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', reqId),
          limit: 1,
        );
        if (reqRows.isNotEmpty &&
            LiveReservationQueueService.buyerCanPayBagReservation(
              reqRows.first.status,
              notes: reqRows.first.notes,
            )) {
          if (!mounted) return;
          await LiveBagCheckoutSheet.show(
            context: context,
            rows: reqRows,
            catalogByItemId: byId,
            resolveProduct: (item) => item == null
                ? Future<ProductsRow?>.value(null)
                : _resolveProductForLiveItem(item),
            liveId: liveId,
            playbackId: widget.playbackId?.trim(),
            isLive: _playbackIsLive,
            liveSellerId: _sellerId?.trim(),
            onPaymentStarted: onPaymentStarted,
          );
          return;
        }
      } catch (_) {}
    }
    final itemRow =
        liveItemId != null && liveItemId.trim().isNotEmpty
            ? _catalogRowById(liveItemId.trim())
            : null;
    await LiveInStreamCheckout.show(
      context: context,
      product: product,
      liveId: liveId,
      liveItemId: liveItemId,
      playbackId: widget.playbackId?.trim(),
      isLive: _playbackIsLive,
      liveSellerId: _sellerId?.trim(),
      reservationRequestId: reservationRequestId,
      reservationStatus: reqId.isNotEmpty ? 'accepted' : null,
      initialPayQty: payQty < 1 ? 1 : payQty,
      checkoutNotes: checkoutNotes,
      productPhotoUrl: itemRow?.photoUrl ??
          (product.imageUrls.isNotEmpty ? product.imageUrls.first : null),
      onPaymentStarted: onPaymentStarted,
    );
  }

  Future<void> _refreshBuyerStateAfterCheckout() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty || currentUserUid.isEmpty) return;

    final pending = await FleaberStripeCheckoutContext.peek();
    if (pending != null) {
      final orderId = pending['order_id']?.toString().trim() ?? '';
      final sessionId =
          pending['checkout_session_id']?.toString().trim() ?? '';
      if (sessionId.isNotEmpty) {
        await FleaberStripeCheckoutContext.settleCheckoutSession(sessionId);
      }
      if (orderId.isNotEmpty) {
        final status = await FleaberStripeCheckoutContext.orderStatus(orderId);
        if (status == 'pago') {
          await FleaberStripeCheckoutContext.reconcilePendingBagOrders(
            pending,
            liveId: liveId,
          );
          await FleaberStripeCheckoutContext.loadAndClear();
          final liveItemId =
              pending['live_item_id']?.toString().trim() ?? '';
          if (liveItemId.isNotEmpty) {
            try {
              await SupaFlow.client.rpc(
                'batata_maybe_fomo_last_unit',
                params: {'p_live_item_id': liveItemId},
              );
            } catch (_) {}
          }
          try {
            await SupaFlow.client.rpc(
              'batata_sync_live_item_for_order',
              params: {'p_order_id': orderId},
            );
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pagamento confirmado!')),
            );
          }
        }
      }
    }

    if (await FleaberStripeTipContext.trySettlePendingTip()) {
      _tipStripePollTimer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gorjeta enviada com sucesso!')),
        );
      }
    } else {
      unawaited(_maybeStartTipStripePoll());
    }

    await _initCatalog();
    await _announceRecentPurchases(liveId);
    await _loadLiveBagCount(liveId);
    if (mounted) setState(() {});
    unawaited(
      FleaberLogger.instance.event('live.checkout.refresh', {
        'live_id': liveId,
      }),
    );
  }

  Future<void> _announceRecentPurchases(String liveId) async {
    final buyerId = currentUserUid.trim();
    if (buyerId.isEmpty) return;
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final converted = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', liveId)
            .eqOrNull('buyer_id', buyerId)
            .eqOrNull('source', 'fleaber_live')
            .eqOrNull('status', 'converted')
            .gte('updated_at', since.toIso8601String())
            .order('updated_at', ascending: false),
        limit: 8,
      );
      final queue = LiveReservationQueueService();
      for (final r in converted) {
        final reqId = r.id?.trim() ?? '';
        final itemId = r.liveItemId?.trim() ?? '';
        if (reqId.isEmpty || itemId.isEmpty) continue;
        if (_purchaseBroadcastAnnounced.contains(reqId)) continue;
        await queue.announcePurchaseBroadcast(
          liveId: liveId,
          buyerId: buyerId,
          liveItemId: itemId,
        );
        _purchaseBroadcastAnnounced.add(reqId);
      }
    } catch (e) {
      debugPrint('[LivePlayer] announceRecentPurchases: $e');
    }
  }

  Future<void> _openItemActionsModal(LiveItemsRow row) async {
    var loading = true;
    ProductsRow? product;
    LiveCatalogStockSnapshot? stock;
    int qtyInBag = 1;
    int? qtyAvailable;
    int soldQty = 0;
    int reservationsQty = 0;
    unawaited(() async {
      stock = await _fetchLiveItemStock(row);
      product = await _resolveProductForLiveItem(row);
      qtyAvailable = stock?.availableQty;
      qtyAvailable ??= await _resolveAvailableQtyForProduct(product);
      soldQty = stock?.soldConvertedQty ??
          await _resolveSoldQty(product);
      reservationsQty = _reservationsCountFromStock(stock);
      final pid = row.id?.trim();
      final lid = widget.liveId?.trim() ?? '';
      if (pid != null && pid.isNotEmpty && lid.isNotEmpty && currentUserUid.isNotEmpty) {
        final bag = await LiveReservationQueueService().liveBagRequests(
          liveId: lid,
          buyerId: currentUserUid,
          limit: 120,
        );
        qtyInBag = bag
            .where((r) => r.liveItemId == pid)
            .fold<int>(0, (a, b) => a + b.requestedQty);
      }
      loading = false;
      if (mounted) setState(() {});
    }());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            unawaited(() async {
              if (loading) {
                final st = await _fetchLiveItemStock(row);
                final p = await _resolveProductForLiveItem(row);
                var avail = st?.availableQty;
                avail ??= await _resolveAvailableQtyForProduct(p);
                final sold = st?.soldConvertedQty ?? await _resolveSoldQty(p);
                final pid = row.id?.trim();
                final lid = widget.liveId?.trim() ?? '';
                var bagQty = 0;
                if (pid != null &&
                    pid.isNotEmpty &&
                    lid.isNotEmpty &&
                    currentUserUid.isNotEmpty) {
                  final bag = await LiveReservationQueueService().liveBagRequests(
                    liveId: lid,
                    buyerId: currentUserUid,
                    limit: 120,
                  );
                  bagQty = bag
                      .where((r) => r.liveItemId == pid)
                      .fold<int>(0, (a, b) => a + b.requestedQty);
                }
                if (!ctx.mounted) return;
                setModalState(() {
                  loading = false;
                  product = p;
                  stock = st;
                  qtyAvailable = avail;
                  soldQty = sold;
                  qtyInBag = bagQty;
                  reservationsQty = _reservationsCountFromStock(st);
                });
              }
            }());

            final hasExternal = _sellerProfile?.externalPaymentsEnabled == true;
            final image = (row.photoUrl ?? '').trim();
            final ref = (row.refCode ?? '').trim();
            final title = (row.title ?? '').trim();
            final price = _formatPriceEur(row) ?? '—';
            final isUnavailable = _isCatalogRowUnavailable(row);
            final isPaidSold = _isCatalogRowPaidSold(row);
            final unavailableBadge = _catalogUnavailableBadge(row);
            final availableNow = loading
                ? null
                : (qtyAvailable ?? stock?.availableQty ?? 0);
            final totalInitial =
                stock?.totalQty ?? product?.quantity ?? 1;
            final size = product?.clothingSize?.trim() ?? '';
            final gender = product?.gender?.trim() ?? '';
            final isAlreadyInBag = qtyInBag > 0;

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (image.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 140,
                          child: BatataCachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            placeholderColor: const Color(0xFF1B2428),
                            errorWidget: _placeholderImage(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      LiveVendorRefDisplay.itemDisplayName(
                        title: title.isEmpty ? null : title,
                        refCode: ref.isEmpty ? null : ref,
                      ),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _miniInfoChip('Preço', price),
                        if (size.isNotEmpty) _miniInfoChip('Tamanho', size),
                        if (gender.isNotEmpty) _miniInfoChip('Género', gender),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (isUnavailable) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _kSoldBadge.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kSoldBadge.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          isPaidSold
                              ? 'Marcado como vendido — podes reservar na mesma (lista de interesse).'
                              : isAlreadyInBag
                                  ? 'Tens pedido(s) no saco. Podes acrescentar mais interesse na fila.'
                                  : 'Stock esgotado no momento — a reserva entra na fila de interesse.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFFFFCDD2),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _buildLiveStockSummary(
                      totalInitial: totalInitial,
                      soldQty: soldQty,
                      reservationsQty: reservationsQty,
                      availableNow: availableNow,
                      loading: loading,
                    ),
                    const SizedBox(height: 14),
                    if (!isPaidSold)
                      FilledButton(
                        onPressed: loading || product == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _openCheckoutForProduct(
                                  product!,
                                  liveItemId: row.id,
                                );
                              },
                        child: const Text('Comprar já'),
                      ),
                    if (!isPaidSold) const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _onReservarItem(row.id);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isAlreadyInBag
                            ? const Color(0xFF6ED8DE)
                            : Colors.white,
                        side: BorderSide(
                          color: isAlreadyInBag
                              ? const Color(0xFF6ED8DE)
                              : Colors.white54,
                        ),
                      ),
                      child: Text(
                        isAlreadyInBag
                            ? 'Ja esta no teu saco ✓'
                            : 'Reservar no saco',
                      ),
                    ),
                    if (hasExternal && !isPaidSold) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: loading || product == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _openCheckoutForProduct(
                                  product!,
                                  liveItemId: row.id,
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No checkout escolhe "Pagamento Direto ao Vendedor".',
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Pedir pagamento fora da app'),
                      ),
                    ],
                    if (!isUnavailable &&
                        !loading &&
                        availableNow != null &&
                        availableNow <= 2) ...[
                      const SizedBox(height: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x33FFB74D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x66FFB74D)),
                        ),
                        child: Text(
                          'Ultimas unidades: garante com pagamento para nao perder.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFFFFD180),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLiveStockSummary({
    required int totalInitial,
    required int soldQty,
    required int reservationsQty,
    required int? availableNow,
    bool loading = false,
  }) {
    Widget cell({
      required String label,
      required String value,
      required Color color,
      bool emphasize = false,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: emphasize ? 0.24 : 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: emphasize ? 16 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: cell(
                label: 'Total inicial',
                value: '$totalInitial',
                color: const Color(0xFF7C8A93),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: cell(
                label: 'Vendidos',
                value: '$soldQty',
                color: const Color(0xFFB06A6A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: cell(
                label: 'Reservas',
                value: loading ? '…' : '$reservationsQty',
                color: const Color(0xFFC59A5B),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: cell(
                label: 'Disponiveis agora',
                value: loading ? '…' : '${availableNow ?? 0}',
                color: const Color(0xFF00A3AD),
                emphasize: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openLiveBagSheet() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty || currentUserUid.isEmpty) return;
    final byId = {
      for (final c in _catalogRows ?? const <LiveItemsRow>[]) (c.id ?? ''): c,
    };
    await LiveBagSheet.show(
      context: context,
      liveId: liveId,
      buyerId: currentUserUid,
      catalogByItemId: byId,
      loadRows: () => LiveReservationQueueService().liveBagDisplayRequests(
        liveId: liveId,
        buyerId: currentUserUid,
      ),
      fetchStock: _fetchLiveItemStock,
      resolveProduct: (item) => _resolveProductForLiveItem(item),
      openSingleCheckout: (product, {liveItemId, reservationRequestId, payQty = 1}) =>
          _openCheckoutForProduct(
        product,
        liveItemId: liveItemId,
        reservationRequestId: reservationRequestId,
        payQty: payQty,
      ),
      openMultiCheckout: (rows) => LiveBagCheckoutSheet.show(
        context: context,
        rows: rows,
        catalogByItemId: byId,
        resolveProduct: (item) => item == null
            ? Future<ProductsRow?>.value(null)
            : _resolveProductForLiveItem(item),
        liveId: liveId,
        playbackId: widget.playbackId?.trim(),
        isLive: _playbackIsLive,
        liveSellerId: _sellerId?.trim(),
      ),
      playbackId: widget.playbackId?.trim(),
      isLive: _playbackIsLive,
      liveSellerId: _sellerId?.trim(),
      onBagChanged: () => unawaited(_loadLiveBagCount(liveId)),
    );
  }

  String _friendlyReservationError(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.code == 'PGRST205' || e.code == 'PGRST204') {
        return 'Sistema de fila ainda não está migrado no servidor. '
            'Aplica o SQL de live_reservation_requests e tenta novamente.';
      }
      if (e.code == '42501') {
        return 'Sem permissão para criar esta reserva.';
      }
      return 'Falha ao pedir reserva. Tenta novamente.';
    }
    final msg = e.toString();
    if (msg.contains('item_sold')) {
      return 'Este artigo já foi vendido.';
    }
    if (msg.contains('item_reserved_full')) {
      return 'Este artigo está reservado — aguarda pagamento.';
    }
    if (msg.contains('duplicate_buyer_reservation')) {
      return 'Já tens uma reserva activa para este artigo.';
    }
    if (msg.contains('insufficient_stock')) {
      return 'Sem stock disponível para nova reserva.';
    }
    if (msg.contains('42703') || msg.contains('v_converted')) {
      return 'Erro no servidor de stock. Aplica o SQL live_ops_hotfix_batata.sql e tenta outra vez.';
    }
    if (msg.contains('live_reservation_requests')) {
      return 'Sistema de fila ainda não está migrado no servidor.';
    }
    return 'Falha ao pedir reserva. Tenta novamente.';
  }

  static String? _formatPriceEur(LiveItemsRow row) {
    final p = row.price;
    if (p == null) return null;
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String _refHash(LiveItemsRow row) {
    final r = (row.refCode ?? '').trim();
    if (r.isEmpty) return '#—';
    return r.startsWith('#') ? r : '#$r';
  }

  static String _catalogTitleLine(LiveItemsRow row) {
    return LiveVendorRefDisplay.itemDisplayName(
      title: row.title,
      refCode: row.refCode,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    _model = createModel(context, () => FleaberLivePlayerModel());
    final liveId = widget.liveId?.trim() ?? '';
    final directPlayback = widget.playbackId?.trim() ?? '';
    final hintLive = widget.isLive ?? true;
    _playbackIsLive = hintLive;

    if (liveId.isEmpty) {
      _chatPublic.addAll(_seedChatPublic);
      _chatPrivate.addAll(_seedChatPrivate);
    } else {
      _liveRoom = LiveRoomService(liveId);
      unawaited(_liveRoom!.start().then((_) {
        if (mounted) {
          setState(() => _liveViewerCount = _liveRoom!.viewerCount);
        }
      }));
      _viewerCountSub = _liveRoom!.viewerCountStream.listen((count) {
        if (mounted) setState(() => _liveViewerCount = count);
      });
      _liveMessagesSub = _liveRoom!.messagesStream.listen((msgs) {
        _onLiveRoomMessagesUpdated(msgs, liveId);
      });
      _subscribeCatalogRealtime(liveId);
      _subscribeLiveBagRealtime(liveId);
      if ((widget.sellerId?.trim().isNotEmpty ?? false)) {
        _subscribeBuyerCheckoutRealtime(liveId);
      }
      unawaited(_loadLiveBagCount(liveId));
    }

    unawaited(
      FleaberLogger.instance.event('video.player.open', {
        'live_id': liveId.isEmpty ? null : liveId,
        'playback_id': directPlayback.isEmpty ? null : directPlayback,
        'is_live_hint': hintLive,
      }),
    );
    unawaited(_loadLiveContext());

    if (liveId.isNotEmpty) {
      _playbackSourceFuture = _loadPlaybackSource().then((source) {
        final ended = _liveRow != null && _liveIsEnded(_liveRow!);
        if (ended && (source.isLive || source.url.isEmpty)) {
          _startEndedVodPoll(liveId);
        }
        return source;
      });
    } else if (directPlayback.isNotEmpty) {
      final hintLive = widget.isLive ?? false;
      _playbackSourceFuture = Future.value(
        _PlaybackSource(
          url: MuxUrls.playbackHls(directPlayback, live: hintLive),
          isLive: hintLive,
          thumbnailUrl: MuxUrls.portraitThumbnail(
            directPlayback,
            width: 720,
            live: hintLive,
          ),
        ),
      );
    } else {
      _playbackSourceFuture =
          Future.value(const _PlaybackSource(url: '', isLive: true));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _initCatalog();
      });
      unawaited(_maybeStartTipStripePoll());
    });
  }

  Future<void> _maybeStartTipStripePoll() async {
    final pending = await FleaberStripeTipContext.peek();
    if (!mounted || pending == null) {
      _tipStripePollTimer?.cancel();
      return;
    }
    if (_tipStripePollTimer != null) return;
    var attempts = 0;
    _tipStripePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      attempts++;
      if (!mounted || attempts > 90) {
        _tipStripePollTimer?.cancel();
        _tipStripePollTimer = null;
        return;
      }
      if (await FleaberStripeTipContext.trySettlePendingTip()) {
        _tipStripePollTimer?.cancel();
        _tipStripePollTimer = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gorjeta enviada com sucesso!')),
          );
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBuyerStateAfterCheckout());
      unawaited(_maybeStartTipStripePoll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _endedVodPoll?.cancel();
    unawaited(_viewerCountSub?.cancel());
    unawaited(_liveMessagesSub?.cancel());
    final bagCh = _liveBagChannel;
    _liveBagChannel = null;
    if (bagCh != null) {
      unawaited(SupaFlow.client.removeChannel(bagCh));
    }
    final priv = _privateRoom;
    _privateRoom = null;
    if (priv != null) unawaited(priv.dispose());
    final room = _liveRoom;
    _liveRoom = null;
    if (room != null) unawaited(room.dispose());
    final cat = _catalogChannel;
    _catalogChannel = null;
    if (cat != null) {
      unawaited(SupaFlow.client.removeChannel(cat));
    }
    final buyerCh = _buyerCheckoutChannel;
    _buyerCheckoutChannel = null;
    if (buyerCh != null) {
      unawaited(SupaFlow.client.removeChannel(buyerCh));
    }
    _spotlightTimer?.cancel();
    _tipStripePollTimer?.cancel();
    _liveClockTimer?.cancel();
    _catalogScrollController.dispose();
    _chatScrollController.dispose();
    _model.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );

    super.dispose();
  }

  void _playTipSoundOnNewMessages(List<LiveRoomMessage> msgs) {
    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.tip) continue;
      final id = m.tipId?.trim();
      if (id == null || id.isEmpty || _seenTipIds.contains(id)) continue;
      _seenTipIds.add(id);
      unawaited(_playCashRegisterThinThin());
    }
  }

  Future<void> _playCashRegisterThinThin() async {
    try {
      SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  void _subscribeCatalogRealtime(String liveId) {
    if (liveId.trim().isEmpty || _catalogChannel != null) return;
    void onCatalogChange() {
      unawaited(_initCatalog());
    }

    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'live_id',
      value: liveId,
    );
    _catalogChannel = SupaFlow.client
        .channel('live_catalog:$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'live_items',
          filter: filter,
          callback: (_) => onCatalogChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_items',
          filter: filter,
          callback: (_) => onCatalogChange(),
        )
        .subscribe();
  }

  Future<void> _loadLiveBagCount(String liveId) async {
    if (liveId.trim().isEmpty || currentUserUid.isEmpty) return;
    try {
      final rows = await LiveReservationQueueService().liveBagDisplayRequests(
        liveId: liveId,
        buyerId: currentUserUid,
        limit: 300,
      );
      await _promoteNewAcceptedNoticesFromRows(rows);
      final count = rows
          .where((r) =>
              r.status == 'pending' ||
              r.status == 'accepted' ||
              r.status == 'converted')
          .fold<int>(0, (a, b) => a + (b.requestedQty < 1 ? 1 : b.requestedQty));
      if (!mounted) return;
      setState(() => _liveBagCount = count);
    } catch (_) {}
  }

  /// Card verde no player: só reservas aceites ainda não notificadas/dispensadas.
  Future<void> _promoteNewAcceptedNoticesFromRows(
    List<LiveReservationRequestsRow> rows,
  ) async {
    if (!mounted || currentUserUid.isEmpty) return;
    for (final r in rows) {
      if (r.status != 'accepted') continue;
      final id = r.id?.trim() ?? '';
      if (id.isEmpty) continue;
      if (_acceptedReservationNotified.contains(id) ||
          _buyerAcceptedNoticeDismissed.contains(id)) {
        continue;
      }
      await _promoteAcceptedNoticeFromRealtime(
        Map<String, dynamic>.from(r.data),
      );
    }
  }

  void _onLiveRoomMessagesUpdated(
    List<LiveRoomMessage> msgs,
    String liveId,
  ) {
    _playTipSoundOnNewMessages(msgs);
    _ensureUserNamesResolved(msgs);

    if (liveId.trim().isEmpty || currentUserUid.isEmpty) return;
    var newAcceptForBuyer = false;
    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.system) continue;
      if (m.id.isEmpty || _seenAcceptBroadcastMsgIds.contains(m.id)) {
        continue;
      }
      if (!RegExp(r'reserva\s+aceite', caseSensitive: false).hasMatch(m.body)) {
        continue;
      }
      final uid = m.userId?.trim() ?? '';
      if (uid.isNotEmpty && uid != currentUserUid) continue;
      _seenAcceptBroadcastMsgIds.add(m.id);
      if (_chatAcceptBroadcastsPrimed) {
        newAcceptForBuyer = true;
      }
    }
    if (!_chatAcceptBroadcastsPrimed) {
      _chatAcceptBroadcastsPrimed = true;
    }
    if (newAcceptForBuyer) {
      unawaited(_syncBuyerAcceptedNoticesOnConnect(liveId));
    }
  }

  void _subscribeLiveBagRealtime(String liveId) {
    final buyerId = currentUserUid.trim();
    if (liveId.trim().isEmpty || buyerId.isEmpty) return;
    try {
      final prev = _liveBagChannel;
      _liveBagChannel = null;
      if (prev != null) {
        unawaited(SupaFlow.client.removeChannel(prev));
      }
      _liveBagChannel = SupaFlow.client
          .channel('live_bag:$liveId:$buyerId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_reservation_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'buyer_id',
              value: buyerId,
            ),
            callback: (payload) {
              final record = payload.newRecord;
              if (record['live_id']?.toString() != liveId) return;
              if (record['status']?.toString() == 'accepted') {
                unawaited(_promoteAcceptedNoticeFromRealtime(record));
              }
              unawaited(_loadLiveBagCount(liveId));
              unawaited(_announceRecentPurchases(liveId));
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _subscribeBuyerCheckoutRealtime(String liveId) {
    final sellerId = _sellerId?.trim() ?? '';
    final buyerId = currentUserUid.trim();
    if (liveId.trim().isEmpty || sellerId.isEmpty || buyerId.isEmpty) return;
    if (_buyerCheckoutChannel != null) return;
    _buyerCheckoutChannel = SupaFlow.client
        .channel('live_buyer_checkout:$liveId:$buyerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_id',
            value: buyerId,
          ),
          callback: (_) {
            unawaited(_refreshBuyerStateAfterCheckout());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'seller_id',
            value: sellerId,
          ),
          callback: (_) {
            unawaited(_refreshBuyerStateAfterCheckout());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_reservation_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_id',
            value: buyerId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['live_id']?.toString() != liveId) return;
            final newStatus = record['status']?.toString();
            if (newStatus == 'accepted') {
              unawaited(_promoteAcceptedNoticeFromRealtime(record));
            }
            unawaited(_loadLiveBagCount(liveId));
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_syncBuyerAcceptedNoticesOnConnect(liveId));
          }
        });
  }

  Future<void> _promoteAcceptedNoticeFromRealtime(
    Map<String, dynamic> record,
  ) async {
    if (currentUserUid.isEmpty || !mounted) return;
    final id = record['id']?.toString().trim() ?? '';
    if (id.isEmpty || record['status']?.toString() != 'accepted') return;
    if (_acceptedReservationNotified.contains(id) ||
        _buyerAcceptedNoticeDismissed.contains(id)) {
      return;
    }
    _acceptedReservationNotified.add(id);

    final row = LiveReservationRequestsTable().createRow(
      Map<String, dynamic>.from(record),
    );
    final itemId = (row.liveItemId ?? '').trim();
    final itemRow = itemId.isNotEmpty ? _catalogRowById(itemId) : null;
    final label = itemRow != null
        ? LiveVendorRefDisplay.itemDisplayName(
            title: itemRow.title,
            refCode: itemRow.refCode,
          )
        : 'A tua reserva';
    final qty = row.requestedQty < 1 ? 1 : row.requestedQty;
    if (!mounted) return;
    unawaited(
      FleaberLogger.instance.event('live.player.c8b_accept_card', {
        'phase': 'show',
        'request_id': id,
        'qty': qty,
        'notices_count': _buyerAcceptedNotices.length + 1,
        'chat_h': _kChatH,
        'is_web': kIsWeb,
        ...LiveInStreamCheckout.c8bUiStackSnapshot(context),
      }),
    );
    setState(() {
      _buyerAcceptedNotices.removeWhere((n) => n.requestId == id);
      _buyerAcceptedNotices.insert(
        0,
        _BuyerAcceptedReservationNotice(
          requestId: id,
          title: label,
          qty: qty,
          photoUrl: itemRow?.photoUrl,
          liveItemId: itemId.isEmpty ? null : itemId,
          reservation: row,
        ),
      );
      if (_buyerAcceptedNotices.length > 3) {
        _buyerAcceptedNotices.removeRange(3, _buyerAcceptedNotices.length);
      }
    });
  }

  /// Só ao ligar realtime: repõe cards aceites ainda não dispensados (não em cada +1 no saco).
  Future<void> _syncBuyerAcceptedNoticesOnConnect(String liveId) async {
    if (currentUserUid.isEmpty || !mounted) return;
    try {
      final rows = await LiveReservationQueueService().liveBagDisplayRequests(
        liveId: liveId,
        buyerId: currentUserUid,
        limit: 50,
      );
      for (final r in rows) {
        final id = r.id?.trim() ?? '';
        if (id.isEmpty || r.status != 'accepted') continue;
        if (_acceptedReservationNotified.contains(id) ||
            _buyerAcceptedNoticeDismissed.contains(id)) {
          continue;
        }
        await _promoteAcceptedNoticeFromRealtime(
          Map<String, dynamic>.from(r.data),
        );
      }
    } catch (_) {}
  }

  void _dismissBuyerAcceptedNotice(String requestId) {
    final id = requestId.trim();
    if (id.isEmpty || !mounted) return;
    _buyerAcceptedNoticeDismissed.add(id);
    setState(() {
      _buyerAcceptedNotices.removeWhere((n) => n.requestId == id);
    });
  }

  Future<void> _payFromBuyerAcceptedNotice(
    _BuyerAcceptedReservationNotice notice,
  ) async {
    final itemId = notice.liveItemId?.trim() ?? '';
    final itemRow =
        itemId.isNotEmpty ? _catalogRowById(itemId) : null;
    if (itemRow == null) {
      await _openLiveBagSheet();
      return;
    }
    final product = await _resolveProductForLiveItem(itemRow);
    if (product == null || !mounted) {
      await _openLiveBagSheet();
      return;
    }
    await _openCheckoutForProduct(
      product,
      liveItemId: itemId,
      reservationRequestId: notice.requestId,
      payQty: notice.qty,
      onPaymentStarted: () => _dismissBuyerAcceptedNotice(notice.requestId),
    );
  }

  Widget _buildBuyerAcceptedReservationCard(
    _BuyerAcceptedReservationNotice notice,
  ) {
    final photo = notice.photoUrl?.trim() ?? '';
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2329).withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF4CAF50),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  photo,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF4CAF50),
                    size: 44,
                  ),
                ),
              )
            else
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF4CAF50),
                size: 44,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reserva aceite',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4CAF50),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${notice.title} · ${notice.qty} un.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '5 dias para pagar',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () =>
                  unawaited(_payFromBuyerAcceptedNotice(notice)),
              child: Text(
                'Pagar',
                style: GoogleFonts.inter(
                  color: _kLiveAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _dismissBuyerAcceptedNotice(notice.requestId),
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
    );
  }

  /// Card vertical glass: preto 20% + blur 12; selo "A MOSTRAR" por cima da borda superior se ativo.
  Widget _buildCatalogCard(LiveItemsRow row) {
    final unavailable = _isCatalogRowUnavailable(row);
    final unavailableBadge = _catalogUnavailableBadge(row);
    final unavailableAction =
        LiveVendorSellerCopy.liveCatalogUnavailableActionLabel(row.status);
    final active = _isCatalogRowActive(row) && !unavailable;
    final titleLine = _catalogTitleLine(row);
    final refH = _refHash(row);
    final price = _formatPriceEur(row);
    final photo = row.photoUrl;
    final itemId = row.id;

    return GestureDetector(
      onTap: () => _openItemActionsModal(row),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
      width: _kCatalogCardW,
      height: _kCatalogStackH,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _kCatalogCardBodyH,
            child: ClipRRect(
              borderRadius: FleaberRadius.circularMd,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: _kPanelOpacityCards),
                  borderRadius: FleaberRadius.circularMd,
                  border: Border.all(
                    color: unavailable
                        ? _kSoldBadge.withValues(alpha: 0.85)
                        : active
                        ? _kLiveAccent
                        : Colors.white.withValues(alpha: 0.18),
                    width: (active || unavailable) ? 1.0 : 0.6,
                  ),
                ),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: FleaberRadius.circularSm,
                          child: SizedBox(
                            height: 70,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                photo != null && photo.isNotEmpty
                                ? BatataCachedNetworkImage(
                                    imageUrl: photo,
                                    fit: BoxFit.cover,
                                        placeholderColor:
                                            const Color(0xFF222222),
                                    errorWidget: _placeholderImage(),
                                  )
                                : _refPlaceholder(refH),
                                if (unavailable)
                                  ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.42),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          titleLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontSize: 9.5,
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (price != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: FleaberRadius.circularSm,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              price,
                              style: GoogleFonts.interTight(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: _kLiveAccent,
                                height: 1,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Align(
                          alignment: Alignment.center,
                          child: Material(
                            color: _kLiveAccent,
                            borderRadius: FleaberRadius.circularSm,
                            child: InkWell(
                              onTap: () => _onReservarItem(itemId),
                              borderRadius: FleaberRadius.circularSm,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                child: Text(
                                  'Reservar',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ),
          ),
          if (unavailable)
            Positioned(
              bottom: _kCatalogCardBodyH - 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _kSoldBadge.withValues(alpha: 0.95),
                    borderRadius: FleaberRadius.circularLg,
                  ),
                  child: Text(
                    unavailableBadge,
                    style: GoogleFonts.interTight(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.3,
                      height: 1,
                    ),
                  ),
                ),
              ),
              ),
            )
          else if (active)
            Positioned(
              bottom: _kCatalogCardBodyH - 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _kLiveAccent.withValues(alpha: 0.95),
                    borderRadius: FleaberRadius.circularLg,
                  ),
                  child: Text(
                    'A MOSTRAR',
                    style: GoogleFonts.interTight(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.3,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  static Widget _placeholderImage() {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  static Widget _refPlaceholder(String refLabel) {
    return ColoredBox(
      color: const Color(0xFF1A2A2C),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            refLabel,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.interTight(
              color: _kLiveAccent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;

            // Cards sempre no fundo; chat/input fixos por cima da faixa dos cards.
            final baseBottom = bottomPad + 8;
            final collapsedCatalogBarH = _catalogMinimized ? 38.0 : 0.0;
            final catalogStripBottom = baseBottom + collapsedCatalogBarH;
            final chatInputBottom = baseBottom + _kCarouselStripH;
            final chatPanelBottom = chatInputBottom +
                (_showChatInput ? _kInputBandH + _kChatGapAboveInput : 0);
            final vodControlsTopInset = topPad + 78;

            // Com cards minimizados: spotlight e barra lateral descem para a faixa do carrossel.
            final sidebarBottom = _catalogMinimized
                ? catalogStripBottom + 2
                : chatInputBottom + 8;
            final spotlightBottom = catalogStripBottom;

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: FutureBuilder<_PlaybackSource>(
                      future: _playbackSourceFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                color: _kLiveAccent,
                                strokeWidth: 2.5,
                              ),
                            ),
                          );
                        }
                        final source = snapshot.data;
                        final path = source?.url ?? '';
                        if (source != null && source.isLive != _playbackIsLive) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                final wasLive = _playbackIsLive;
                                _playbackIsLive = source.isLive;
                                if (!source.isLive) {
                                  _privateChatMode = false;
                                  _resetChatPlaybackSync();
                                  unawaited(_liveRoom?.refreshMessages());
                                  _syncVodCatalogHighlight(force: true);
                                } else if (!wasLive && source.isLive) {
                                  _resetChatPlaybackSync();
                                  _ensureLiveClock();
                                }
                              });
                              _ensureLiveClock();
                            }
                          });
                        }
                        if (path.isEmpty) {
                          return Center(
                            child: Text(
                              source?.isLive == false
                                  ? 'Gravação indisponível.'
                                  : 'A aguardar sinal do direto...',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return LiveHlsViewer(
                          key: ValueKey(path),
                          path: path,
                          liveId: widget.liveId,
                          // HLS Mux: sem espelhar (só o preview do vendedor espelha).
                          flipHorizontal: false,
                          muxLandscapePlayback:
                              publishBackendUsesLandscapeMux(
                                    _liveRow?.publishBackend,
                                  ) ||
                              kLivekitMuxLandscapeEncode,
                          isLive: source?.isLive ?? false,
                          thumbnailUrl: source?.thumbnailUrl,
                          vodControlsAtTop: !(source?.isLive ?? false),
                          vodControlsTopInset: vodControlsTopInset,
                          vodControlsBottomInset: 0,
                          onPlaybackTick: _onPlaybackTick,
                          onLivePlaybackFailed: widget.liveId != null &&
                                  widget.liveId!.trim().isNotEmpty
                              ? () => _resolveVodPlaybackUrl(
                                    widget.liveId!.trim(),
                                  )
                              : null,
                        );
                      },
                    ),
                  ),
                ),

                // Top bar — seller em destaque estilo host.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, topPad + 2, 10, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FleaberProfileAvatar(
                          userId: _sellerProfile?.id,
                          fullName: _sellerProfile?.fullName,
                          photoUrl: _sellerPhotoUrl,
                          radius: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _sellerDisplayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        height: 1.05,
                                        shadows: _kOverlayTextShadow,
                                      ),
                                    ),
                                  ),
                                  if (_sellerRatingLabel != null) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFFFFD700),
                                      size: 13,
                                    ),
                                    Text(
                                      _sellerRatingLabel!,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        shadows: _kOverlayTextShadow,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Material(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: () {},
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      child: Text(
                                        'Seguir',
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          shadows: _kOverlayTextShadow,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_liveIsActive && _playbackIsLive) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFF5148),
                                          Color(0xFFE11F2B),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x66E11F2B),
                                          blurRadius: 10,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.fiber_manual_record_rounded,
                                          color: Colors.white,
                                          size: 9,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'LIVE',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildLiveInlineTimeChip(),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.remove_red_eye_outlined,
                                  color: Colors.white,
                                        size: 15,
                                  shadows: _kOverlayTextShadow,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _viewerCountLabel,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    shadows: _kOverlayTextShadow,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _glassIconButton(
                                  icon: Icons.close_rounded,
                                  onTap: _closePlayer,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Barra lateral — encostada ao carrossel (sem sobrepor cards).
                Positioned(
                  right: 10,
                  bottom: sidebarBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        _glassCircleIcon(
                          icon: Icons.share_outlined,
                          onTap: () {},
                        style: _LiveActionStyle.secondary,
                        ),
                        const SizedBox(height: 12),
                        _glassCircleIcon(
                          icon: Icons.euro_rounded,
                          onTap: _openTipSheet,
                        style: _LiveActionStyle.monetization,
                      ),
                      const SizedBox(height: 12),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Semantics(
                            label: 'Saco da live',
                            button: true,
                            child: _glassCircleIcon(
                              icon: Icons.shopping_bag_outlined,
                              onTap: _openLiveBagSheet,
                              style: _LiveActionStyle.primary,
                            ),
                          ),
                          if (_liveBagCount > 0)
                            Positioned(
                              right: -3,
                              top: -3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _kLiveAccent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _liveBagCount > 99 ? '99+' : '$_liveBagCount',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                        ),
                        // Espaçamento explícito para não sobrepor com o botão do chat.
                        const SizedBox(height: 12),
                        if (_sellerId != null &&
                            _sellerId!.isNotEmpty &&
                            _sellerId != currentUserUid) ...[
                          _glassCircleIcon(
                            icon: Icons.favorite_border_rounded,
                            onTap: () {},
                          style: _LiveActionStyle.defaultAction,
                          ),
                        ],
                        if (_showChatInput) ...[
                          // Sempre que o favorito existir, garante espaçamento consistente.
                          const SizedBox(height: 12),
                          _glassCircleIcon(
                            selected: _privateChatMode,
                            icon: Icons.chat_bubble_outline_rounded,
                          style: _LiveActionStyle.primary,
                            onTap: () {
                              setState(() {
                                _privateChatMode = !_privateChatMode;
                              });
                              if (_privateChatMode) _ensurePrivateRoom();
                            },
                          ),
                        ] else if (_showChatPanel) ...[
                          const SizedBox(height: 12),
                          _glassCircleIcon(
                            icon: Icons.forum_outlined,
                            onTap: () {},
                          style: _LiveActionStyle.primary,
                          ),
                        ],
                      ],
                    ),
                ),

                if (_catalogMinimized &&
                    _spotlightItemId != null &&
                    _catalogRowById(_spotlightItemId) != null)
                  Positioned(
                    left: 12,
                    bottom: spotlightBottom,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(maxW * 0.68, 280),
                      ),
                      child: _buildSpotlightCatalogCard(
                        _catalogRowById(_spotlightItemId)!,
                      ),
                    ),
                  ),

                if (_catalogMinimized)
                Positioned(
                  left: 12,
                  right: 12,
                    bottom: baseBottom,
                    child: Material(
                      color: Colors.black.withValues(alpha: _kGlassChrome),
                      borderRadius: FleaberRadius.circularLg,
                      child: InkWell(
                        onTap: _toggleCatalogMinimized,
                        borderRadius: FleaberRadius.circularLg,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                              const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Mostrar artigos',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (!_catalogMinimized)
                        Positioned(
                    left: 12,
                    right: 12,
                    bottom: catalogStripBottom,
                          height: _kCarouselStripH,
                    child: ClipRect(
                          child: _catalogLoading || _catalogRows == null
                              ? const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white70,
                                      ),
                                    ),
                                  ),
                                )
                              : _catalogRows!.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Sem artigos nesta live',
                                        style: GoogleFonts.inter(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    )
                                  : Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                  NotificationListener<ScrollNotification>(
                                          onNotification: (n) {
                                            if (n is ScrollUpdateNotification &&
                                                n.metrics.pixels > 6) {
                                              _dismissCatalogScrollHint();
                                            }
                                            return false;
                                          },
                                          child: ListView.separated(
                                            controller: _catalogScrollController,
                                            scrollDirection: Axis.horizontal,
                                            padding: EdgeInsets.zero,
                                            itemCount: _catalogRows!.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(
                                              width: _kCatalogSpacing,
                                            ),
                                            itemBuilder: (context, i) {
                                              return Align(
                                          alignment: Alignment.bottomCenter,
                                                child: _buildCatalogCard(
                                                  _catalogRows![i],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Material(
                                      color: Colors.black
                                          .withValues(alpha: _kGlassChrome),
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _toggleCatalogMinimized,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                        if (_showCatalogScrollHint &&
                                            _catalogRows!.length > 1)
                                          Positioned(
                                            left: 6,
                                            top: 12,
                                            child: GestureDetector(
                                              onTap: _dismissCatalogScrollHint,
                                              child: Container(
                                          padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: _kGlassChrome),
                                                  borderRadius:
                                                      FleaberRadius.circularLg,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.22),
                                                  ),
                                                ),
                                                child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Desliza',
                                                style: GoogleFonts.inter(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.9),
                                                        fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    Icon(
                                                Icons.chevron_right_rounded,
                                                      size: 16,
                                                      color: Colors.white
                                                          .withValues(alpha: 0.9),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                              ),
                                    ),
                        ),

                if (_buyerAcceptedNotices.isNotEmpty)
                        Positioned(
                    left: 12,
                    right: 12,
                    bottom: chatPanelBottom + _kChatH + 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final notice
                            in _buyerAcceptedNotices.take(2))
                          _buildBuyerAcceptedReservationCard(notice),
                      ],
                    ),
                  ),

                if (_showChatPanel && _showChatInput)
                  Positioned(
                    left: 12,
                    right: _kChatRightGutter,
                    bottom: chatInputBottom,
                            height: _kInputBandH,
                    child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                              borderRadius: FleaberRadius.circularLg,
                              border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 0.7,
                              ),
                            ),
                            child: TextField(
                              controller: _model.chatTextController,
                              focusNode: _model.chatFocusNode,
                              textAlignVertical: TextAlignVertical.center,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendChatMessage(),
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                height: 1.0,
                              ),
                              cursorColor: _kLiveAccent,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                hintText: _privateChatMode
                                    ? 'Mensagem privada…'
                                    : 'Diz alguma coisa…',
                                hintStyle: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 10,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                              ),
                            ),
                          ),
                        ),

                if (_showChatPanel)
                        Positioned(
                    left: 12,
                    right: _kChatRightGutter,
                    bottom: chatPanelBottom,
                    // Altura fixa: sem isto o filho (_kChatH) fica colado ao topo
                    // do Stack e o viewport do scroll pinta cinzento sobre o vídeo.
                          height: _kChatH,
                    child: _chatPanelShell(child: _buildChatOverlay()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Evita fundo cinzento do canvas (tema claro / VOD web) no viewport do chat.
  Widget _chatPanelShell({required Widget child}) {
    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        dialogBackgroundColor: Colors.transparent,
      ),
      child: Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.transparent),
          child: child,
        ),
      ),
    );
  }

  void _maybeLoadOlderChatMessages() {
    if (_chatLoadOlderBusy) return;
    final room = _liveRoom;
    if (room == null) return;
    if (!_chatScrollController.hasClients) return;
    final pos = _chatScrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 40) return;
    _chatLoadOlderBusy = true;
    final beforeExtent = pos.maxScrollExtent;
    final beforeOffset = pos.pixels;
    unawaited(() async {
      try {
        await room.loadOlderMessages();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_chatScrollController.hasClients) return;
          final after = _chatScrollController.position;
          final delta = after.maxScrollExtent - beforeExtent;
          if (delta > 0) {
            _chatScrollController.jumpTo(beforeOffset + delta);
          }
        });
      } finally {
        _chatLoadOlderBusy = false;
      }
    }());
  }

  Widget _buildReversedChatList({
    required int itemCount,
    required Widget Function(BuildContext context, int index) itemBuilder,
    bool enableOlderLoad = false,
  }) {
    if (itemCount <= 0) return const SizedBox.shrink();
    // reverse:true + índice invertido → mais recente em baixo; scroll up = mais antigo.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (enableOlderLoad &&
            (notification is ScrollUpdateNotification ||
                notification is ScrollEndNotification)) {
          _maybeLoadOlderChatMessages();
        }
        return false;
      },
      child: ListView.builder(
        controller: _chatScrollController,
        reverse: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        primary: false,
        itemCount: itemCount,
        itemBuilder: (context, index) =>
            itemBuilder(context, itemCount - 1 - index),
      ),
    );
  }

  Widget _chatEmptyHint(String text) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildChatOverlay() {
    if (_privateChatMode && _showChatInput) {
      final priv = _privateRoom;
      if (priv != null) {
        return StreamBuilder<List<LivePrivateMessage>>(
          stream: priv.messagesStream,
          initialData: List.unmodifiable(priv.messages),
          builder: (context, snap) {
            final msgs = snap.data ?? const <LivePrivateMessage>[];
            if (msgs.isEmpty) {
              return _chatEmptyHint('Mensagem privada à vendedora');
            }
            return _buildReversedChatList(
              itemCount: msgs.length,
              itemBuilder: (context, index) {
                final m = msgs[index];
                final isMine = m.senderId == currentUserUid;
                return LivePublicChatHumanRow(
                  label: isMine
                      ? (currentUserDisplayName.trim().isNotEmpty
                          ? currentUserDisplayName.trim()
                          : 'Tu')
                      : _sellerDisplayName,
                  text: m.body,
                  userId: isMine ? currentUserUid : _sellerId,
                  photoUrl: isMine
                      ? (currentUserPhoto.trim().isNotEmpty
                          ? currentUserPhoto.trim()
                          : _userPhotoCacheById[currentUserUid])
                      : _sellerPhotoUrl,
                  isSeller: !isMine,
                );
              },
            );
          },
        );
      }
      final chat = _chatPrivate;
      return _buildReversedChatList(
        itemCount: chat.length,
        itemBuilder: (context, index) {
          final m = chat[index];
          return _buildPrivateLegacyChatRow(user: m.user, text: m.text);
        },
      );
    }
    if (_liveRoom == null) {
      final chat = _chatPublic;
      return _buildReversedChatList(
        itemCount: chat.length,
        itemBuilder: (context, index) {
          final m = chat[index];
          return _buildPublicChatHumanRow(user: m.user, text: m.text);
        },
      );
    }
    final room = _liveRoom!;
    return StreamBuilder<List<LiveRoomMessage>>(
      stream: room.messagesStream,
      initialData: List.unmodifiable(room.messages),
      builder: (context, snap) {
        final all = snap.data ?? const <LiveRoomMessage>[];
        final tippedUserIds = all
            .where((x) =>
                x.kind == LiveRoomMessageKind.tip &&
                (x.userId?.trim().isNotEmpty ?? false))
            .map((x) => x.userId!.trim())
            .toSet();
        final msgs = _filterMessagesForPlayback(all);
        if (msgs.isEmpty) {
          return _chatEmptyHint(
              _isVodReplay ? 'Chat da gravação…' : 'Sem mensagens ainda',
          );
        }
        return _buildReversedChatList(
          itemCount: msgs.length,
          enableOlderLoad: !_isVodReplay,
          itemBuilder: (context, index) {
            final m = msgs[index];
            if (m.kind == LiveRoomMessageKind.tip) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: LiveTipGiftBubble(
                  amountEur: m.tipAmountEur ?? 0,
                ),
              );
            }
            if (m.kind == LiveRoomMessageKind.system) {
              return LivePublicChatSystemLine.fromBody(
                m.body,
                normalizeItemLabel: _normalizeSystemChatItemLabel,
                resolveBuyerName: (raw) =>
                    _resolveChatBuyerName(raw, m.userId),
              );
            }
            final userId = m.userId?.trim() ?? '';

            // Se quem escreveu já deu gorjeta, anonimizamos o nome.
            if (userId.isNotEmpty && tippedUserIds.contains(userId)) {
              return _buildPublicChatHumanRow(
                user: 'Utilizador',
                text: m.body,
              );
            }

            final isSeller = userId.isNotEmpty &&
                _sellerId != null &&
                userId == _sellerId;
            final resolvedLabel = _resolveHumanChatLabel(
              senderLabel: m.senderLabel,
              userId: userId.isNotEmpty ? userId : null,
              isSeller: isSeller,
            );
            return _buildPublicChatHumanRow(
              user: resolvedLabel,
              text: m.body,
              userId: userId.isNotEmpty ? userId : null,
              photoUrl: _photoUrlForChatUser(
                userId: userId.isNotEmpty ? userId : null,
                isSeller: isSeller,
              ),
              isSeller: isSeller,
            );
          },
        );
      },
    );
  }

  String? _photoUrlForChatUser({String? userId, bool isSeller = false}) {
    final uid = userId?.trim() ?? '';
    final sellerUid = _sellerId?.trim() ?? '';

    if (uid.isNotEmpty && uid == currentUserUid) {
      final mine = currentUserPhoto.trim();
      if (mine.isNotEmpty) return mine;
      final cached = _userPhotoCacheById[uid];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    if (uid.isNotEmpty && sellerUid.isNotEmpty && uid == sellerUid) {
      final sellerPhoto = _sellerPhotoUrl;
      if (sellerPhoto != null && sellerPhoto.isNotEmpty) return sellerPhoto;
    }

    if (isSeller) {
      final sellerPhoto = _sellerPhotoUrl;
      return sellerPhoto != null && sellerPhoto.isNotEmpty ? sellerPhoto : null;
    }

    if (uid.isEmpty) return null;
    final cached = _userPhotoCacheById[uid];
    return cached != null && cached.isNotEmpty ? cached : null;
  }

  String? _normalizeSystemChatItemLabel(String raw) {
    var segment = raw.trim();
    if (segment.isEmpty) return null;
    if (segment.toLowerCase().startsWith('ref ')) {
      segment = segment.substring(4).trim();
    }
    for (final row in _catalogRows ?? const <LiveItemsRow>[]) {
      final code = (row.refCode ?? '').trim();
      if (code.isEmpty) continue;
      final formatted = LiveVendorRefDisplay.formatRef(code);
      final refLabel = LiveVendorRefDisplay.refLabel(code);
      if (segment == formatted ||
          segment == code ||
          segment == refLabel ||
          raw.trim() == refLabel ||
          raw.trim() == 'Ref $formatted') {
        return LiveVendorRefDisplay.itemDisplayName(
          title: row.title,
          refCode: row.refCode,
        );
      }
    }
    if (!raw.trim().toLowerCase().startsWith('ref ')) {
      return raw.trim();
    }
    return raw.trim();
  }

  Widget _buildPublicChatHumanRow({
    required String user,
    required String text,
    String? userId,
    String? photoUrl,
    bool isSeller = false,
  }) {
    return LivePublicChatHumanRow(
      label: user,
      text: text,
      userId: userId,
      photoUrl: photoUrl,
      isSeller: isSeller,
    );
  }

  Widget _buildPrivateLegacyChatRow({
    required String user,
    required String text,
    bool isSeller = false,
  }) {
    final isMine =
        user == 'Tu' || user.trim() == currentUserDisplayName.trim();
    return LivePublicChatHumanRow(
      label: user,
      text: text,
      userId: isMine ? currentUserUid : (isSeller ? _sellerId : null),
      photoUrl: isMine
          ? (currentUserPhoto.trim().isNotEmpty
              ? currentUserPhoto.trim()
              : _userPhotoCacheById[currentUserUid])
          : (isSeller ? _sellerPhotoUrl : null),
      isSeller: isSeller,
    );
  }

  static Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: _kGlassButton),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  static Widget _glassCircleIcon({
    required IconData icon,
    required VoidCallback onTap,
    bool selected = false,
    _LiveActionStyle style = _LiveActionStyle.defaultAction,
  }) {
    return _LiveActionButton(
      icon: icon,
      onTap: onTap,
      selected: selected,
      style: style,
    );
  }
}

class _BuyerAcceptedReservationNotice {
  const _BuyerAcceptedReservationNotice({
    required this.requestId,
    required this.title,
    required this.qty,
    this.photoUrl,
    this.liveItemId,
    required this.reservation,
  });

  final String requestId;
  final String title;
  final int qty;
  final String? photoUrl;
  final String? liveItemId;
  final LiveReservationRequestsRow reservation;
}

enum _LiveActionStyle {
  primary,
  monetization,
  secondary,
  defaultAction,
}

class _LiveActionButton extends StatefulWidget {
  const _LiveActionButton({
    required this.icon,
    required this.onTap,
    required this.selected,
    required this.style,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final _LiveActionStyle style;

  @override
  State<_LiveActionButton> createState() => _LiveActionButtonState();
}

class _LiveActionButtonState extends State<_LiveActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.style == _LiveActionStyle.primary;
    final isMonetization = widget.style == _LiveActionStyle.monetization;
    final isSecondary = widget.style == _LiveActionStyle.secondary;
    final bg = widget.selected
        ? _kLiveAccent.withValues(alpha: 0.92)
        : isMonetization
            ? const Color(0xFF0E4D57).withValues(alpha: 0.92)
            : isPrimary
                ? Colors.black.withValues(alpha: 0.68)
                : isSecondary
                    ? Colors.black.withValues(alpha: 0.42)
                    : Colors.black.withValues(alpha: _kGlassButton);
    const scale = _kSidebarButtonScale;
    final size = (isPrimary ? 54.0 : isMonetization ? 50.0 : 46.0) * scale;
    final iconSize = (isPrimary ? 24.0 : 21.0) * scale;
    final glow = isMonetization
        ? const [
            BoxShadow(
              color: Color(0x7700A3AD),
              blurRadius: 14,
              spreadRadius: 0.5,
              offset: Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[];

    return AnimatedScale(
      scale: _pressed ? 0.93 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: glow),
        child: Material(
          color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
            splashColor: Colors.white.withValues(alpha: 0.16),
            highlightColor: Colors.white.withValues(alpha: 0.10),
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Center(
              child: Icon(widget.icon, color: Colors.white, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
