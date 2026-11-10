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
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_hls_viewer.dart';
import '/utils/live_system_chat_humanizer.dart';
import '/widgets/live_public_chat_line.dart';
import '/widgets/live_tip_gift_bubble.dart';
import '/widgets/profile_avatar.dart';
import '/utils/live_room_service.dart';
import '/utils/live_private_room_service.dart';
import '/live_tip/live_tip_flow.dart';
import '/auth/supabase_auth/auth_util.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_catalog_item_attributes.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_tip_context.dart';
import '/utils/live_in_stream_checkout.dart';
import '/widgets/live_bag_checkout_sheet.dart';
import '/widgets/live_bag_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/utils/live_raffle_service.dart';
import '/utils/live_raffle_share.dart';
import '/utils/raffle_log.dart';
import '/utils/live_embed_host.dart';
import '/hub/hub_actions.dart';
import '/hub/hub_ps_claim.dart';
import '/utils/live_row_playback_status.dart';
import '/hub/hub_player_diag.dart';
import '/hub/data/hub_public_repository.dart';
import '/hub/hub_qa_diag.dart';
import '/hub/hub_live_reservation_ui.dart';
import '/hub/theme/hub_theme.dart';
import '/hub/widgets/hub_facebook_reservations_entry.dart';
import '/widgets/live_raffle_buyer_card.dart';
import '/widgets/live_raffle_winner_celebration.dart';
import '/order_cancel_eligibility.dart';
import '/utils/seller_professional.dart';
import '/widgets/professional_seller_badge.dart';
import '/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
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
    this.raffleRef,
    this.embedInHub = false,
    this.onEmbedClose,
    this.showEmbedClose = true,
    this.hubShowBagReservationHint = false,
    this.sharePreferredLink,
    this.hubExternalChat = false,
    this.hubExternalProducts = false,
    this.hubLightShell = false,
    this.hubHideOverlaySideActions = false,
    this.hubTrailing,
  });

  final String? liveId;
  final String? playbackId;
  /// Hint da Home (evita esperar query Supabase para começar HLS).
  final bool? isLive;
  /// Vendedor (Home passa logo — gorjeta não depende da query lives).
  final String? sellerId;
  /// Código referral da Rifa da Live (`?ref=` no link partilhado).
  final String? raffleRef;
  /// Dentro do FleaHub — mesma UX Fleaber; fechar via [onEmbedClose].
  final bool embedInHub;
  final VoidCallback? onEmbedClose;
  /// Hub: false quando entrada directa (URL externa) — esconde botão fechar.
  final bool showEmbedClose;
  /// Hub: coachmark junto ao saco quando há reservas activas.
  final bool hubShowBagReservationHint;
  /// Link a copiar na partilha (ex. Hub `fleaber.pt/.../live`). Null → fleaber.app/live.
  final String? sharePreferredLink;
  /// Hub B1 desktop: chat na coluna ao lado do vídeo (mesma State / LiveRoom).
  /// Não cria segunda subscrição — só muda apresentação.
  final bool hubExternalChat;
  /// Hub B2 desktop: produtos desta live na coluna esquerda (mesmo catálogo /
  /// `_onReservarItem` / stock — sem lógica paralela).
  final bool hubExternalProducts;

  /// H03 FleaHub claro — colunas laterais e fundo do shell em superfície branca
  /// (o vídeo mantém-se escuro). Sem alterar Mux / reservas / stock.
  final bool hubLightShell;

  /// Marketplace (ou outra zona) na mesma Row do shell — evita vão entre chat e MP.
  final Widget? hubTrailing;

  /// H03 desktop: esconde a coluna de ícones sobreposta ao vídeo (partilhar /
  /// saco / chat) quando essas acções estão fora do player. Mantém rifa se
  /// activa. Não altera Mux nem lógica de reservas.
  final bool hubHideOverlaySideActions;

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
  /// 168: título 2 linhas + preço + «Reservas: N» + botão cabem sem overflow (APP QA 2026-08-09).
  static const double _kCatalogCardBodyH = 168;
  /// Espaço extra no topo para o selo "A MOSTRAR" à meia-altura na borda.
  static const double _kCatalogSealOverhang = 14;
  static double get _kCatalogStackH =>
      _kCatalogCardBodyH + _kCatalogSealOverhang;

  static const double _kCarouselStripH = 198;
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
  Map<String, LiveCatalogStockSnapshot> _catalogStockByItemId = {};
  /// Foto marketplace quando `live_items.photo_url` está vazio.
  Map<String, String> _catalogFallbackPhotoByItemId = {};
  List<LiveItemShowEventsRow> _catalogShowEvents = [];
  String? _vodActiveItemId;
  bool _catalogLoading = true;
  bool _catalogInitialLoadPending = true;
  int _catalogEmptyRetries = 0;
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
  RealtimeChannel? _sellerCatalogStockChannel;
  RealtimeChannel? _buyerCheckoutChannel;
  RealtimeChannel? _liveBagChannel;
  int _liveViewerCount = 0;
  int _liveBagCount = 0;
  /// Linhas do saco (mesma fetch que o badge) — painel B3 desktop.
  List<LiveReservationRequestsRow> _liveBagRows = const [];
  /// Claim RPC devolveu `facebook_login_required` — UI no painel B3.
  bool _needsFacebookLogin = false;
  bool _facebookContinueBusy = false;
  final Set<String> _purchaseBroadcastAnnounced = {};
  final Set<String> _acceptedReservationNotified = {};
  final Set<String> _buyerAcceptedNoticeDismissed = {};
  final List<_BuyerAcceptedReservationNotice> _buyerAcceptedNotices = [];
  StreamSubscription<int>? _viewerCountSub;
  StreamSubscription<List<LiveRoomMessage>>? _liveMessagesSub;
  final Set<String> _seenTipIds = <String>{};
  final Set<String> _seenAcceptBroadcastMsgIds = <String>{};
  bool _chatAcceptBroadcastsPrimed = false;
  final Set<String> _seenPriceDefinedMsgIds = <String>{};
  bool _chatPriceBroadcastsPrimed = false;
  final Set<String> _systemHighlightMsgIds = <String>{};
  final Set<String> _seenBackofficeSnackMsgIds = <String>{};
  bool _chatSystemEffectsPrimed = false;
  _PriceDefinedBroadcastNotice? _priceDefinedNotice;
  Timer? _priceDefinedNoticeTimer;
  Timer? _catalogActivePollTimer;
  Timer? _catalogStockPollTimer;
  /// Coalesce realtime/poll stock refreshes (evita 80 RPCs × N eventos).
  Timer? _catalogStockRefreshDebounce;
  bool _catalogStockRefreshAllPending = false;
  final Set<String> _pendingCatalogStockIds = <String>{};
  LiveRaffleState? _raffleState;
  bool _raffleRefVisitRegistered = false;
  int? _raffleParticipantCount;
  bool _raffleJoinLoading = false;
  bool? _isFollowingSeller;
  Timer? _rafflePollTimer;
  RealtimeChannel? _raffleChannel;
  StreamSubscription<List<Map<String, dynamic>>>? _raffleStreamSub;
  bool? _raffleWinnerCelebrationShown;
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
    // Sempre tentar catálogo público primeiro (iframe Lab / web anon sem login).
    // embedInHub já usava isto; o player standalone no Lab ficava sem cards.
    try {
      final hubRows =
          await HubPublicRepository().fetchLiveItemsAsPlayerRows(liveId);
      HubPlayerDiag.log('hub_catalog_fetch', {
        'live_id': liveId,
        'item_count': hubRows.length,
        'source': 'hub_live_items_public',
        'embed_in_hub': widget.embedInHub,
      });
      if (hubRows.isNotEmpty) return hubRows;
    } catch (e) {
      HubPlayerDiag.log('hub_catalog_fetch_error', {
        'live_id': liveId,
        'error': e.toString(),
      });
    }
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

  Future<void> _initCatalog({bool skipCache = false}) async {
    final liveId = widget.liveId?.trim() ?? '';
    final hintSeen = await LiveCatalogCache.scrollHintDismissed();

    HubPlayerDiag.logCatalogStart(liveId: liveId, skipCache: skipCache);

    if (liveId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _catalogRows = _demoCatalogRows();
        _catalogLoading = false;
        _catalogInitialLoadPending = false;
        _showCatalogScrollHint = !hintSeen && _catalogRows!.length > 1;
      });
      return;
    }

    final cached = skipCache ? null : await LiveCatalogCache.read(liveId);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _catalogRows = cached;
        _catalogLoading = false;
        _showCatalogScrollHint = !hintSeen && cached.length > 1;
      });
      HubPlayerDiag.logCatalogResult(
        liveId: liveId,
        itemCount: cached.length,
        fromCache: true,
        definitive: false,
      );
      unawaited(_prefetchCatalogFallbackPhotos(cached));
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
      } else if (_catalogEmptyRetries < 2) {
        _catalogEmptyRetries++;
        HubPlayerDiag.logCatalogEmptyReason(
          liveId: liveId,
          reason: 'network_empty_retry_$_catalogEmptyRetries',
          loading: true,
        );
        await Future.delayed(
          Duration(milliseconds: 700 * _catalogEmptyRetries),
        );
        if (!mounted) return;
        return _initCatalog(skipCache: true);
      } else {
        HubPlayerDiag.logCatalogEmptyReason(
          liveId: liveId,
          reason: 'network_empty_final',
          loading: false,
        );
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
        _catalogInitialLoadPending = false;
        _showCatalogScrollHint = !hintSeen && rows.length > 1;
      });
      HubPlayerDiag.logCatalogResult(
        liveId: liveId,
        itemCount: rows.length,
        fromCache: false,
        definitive: true,
      );
      unawaited(_refreshCatalogStock(rows));
      unawaited(_prefetchCatalogFallbackPhotos(rows));
      _startCatalogStockPoll();
      _notifyActiveCatalogItemIfChanged(rows);
      _syncVodCatalogHighlight(force: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || rows.isEmpty) return;
        if (_isVodReplay) return;
        final activeI = rows.indexWhere((r) => _isCatalogRowActive(r));
        _scrollCatalogToIndex(activeI >= 0 ? activeI : 0);
      });
    } catch (e, st) {
      HubPlayerDiag.logCatalogError(liveId: liveId, error: e);
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
        _catalogInitialLoadPending = false;
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
      unawaited(_initCatalog());
      final sellerId = _liveRow!.sellerId;
      if (sellerId != null && sellerId.isNotEmpty) {
        unawaited(SellerProfessionalCache.warm([sellerId]));
        final profiles = await ProfilesDirectoryTable().queryRows(
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
        final reviews = await ReviewsPublicRatingsTable().queryRows(
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
      await _refreshFollowState();
      if (_liveRow != null) {
        if (_liveIsEnded(_liveRow!)) {
          _playbackIsLive = false;
        } else if (!_playbackIsLive) {
          // Row ainda live: nunca ficar preso em Gravado por flag antiga.
          _playbackIsLive = true;
        }
      }
      if (mounted) {
        setState(() {});
        _logHeaderBadgeOnce();
        _ensureLiveClock();
        _subscribeBuyerCheckoutRealtime(liveId);
        _subscribeSellerCatalogStockRealtime();
      }
      _ensurePrivateRoom();
      if (liveId.isNotEmpty &&
          _liveRow != null &&
          _liveIsEnded(_liveRow!) &&
          (_liveRow?.muxVodPlaybackId?.trim().isEmpty ?? true)) {
        _startEndedVodPoll(liveId);
      }
    } catch (e, st) {
      HubPlayerDiag.logError(liveId: liveId, phase: 'load_live_context', error: e);
      // Catálogo já arrancou se a row existia; garantir fetch mesmo em erro parcial.
      if (liveId.isNotEmpty && _catalogRows == null) {
        unawaited(_initCatalog());
      }
    }
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

  /// Auth contextual FleaHub embed — modal B20 (player Hub live/gravado).
  Future<bool> _ensureHubAuth({
    required String intentLabel,
    String? titleOverride,
  }) async {
    if (currentUserUid.isNotEmpty) return true;
    if (!widget.embedInHub) return false;
    await HubActions.requireAuth(
      context,
      intentLabel: intentLabel,
      titleOverride: titleOverride,
      inLivePlayer: true,
    );
    // requireAuth abre login e sai — só true se a sessão já existir.
    return currentUserUid.isNotEmpty;
  }

  Future<bool> _promptAuthForAction({
    required String intentLabel,
    required String legacySnack,
    String? titleOverride,
  }) async {
    if (currentUserUid.isNotEmpty) return true;
    if (widget.embedInHub) {
      return _ensureHubAuth(
        intentLabel: intentLabel,
        titleOverride: titleOverride,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(legacySnack)),
      );
    }
    return false;
  }

  Future<void> _openTipSheet() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) {
      await _showTipMessage('Este directo ainda não está disponível para gorjetas.');
      return;
    }
    if (currentUserUid.isEmpty) {
      if (widget.embedInHub) {
        await _ensureHubAuth(intentLabel: 'enviar uma gorjeta');
      } else {
        await _showTipMessage('Inicia sessão para enviar uma gorjeta.');
      }
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
    if (widget.embedInHub) {
      if (widget.showEmbedClose && widget.onEmbedClose != null) {
        widget.onEmbedClose!();
      }
      return;
    }
    final seller = widget.sellerId?.trim() ?? '';
    final isOwnEndedLive =
        seller.isNotEmpty && seller == currentUserUid && !_liveIsActive;
    if (isOwnEndedLive) {
      context.goNamed(HomePageWidget.routeName);
      return;
    }
    context.safePop();
  }

  void _showCatalogSpotlight(String activeId, List<LiveItemsRow> rows) {
    if (activeId.isEmpty || _isVodReplay) return;
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
    setState(() => _spotlightItemId = activeId);
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
    if (activeId == _lastTrackedActiveCatalogId && !_catalogMinimized) return;
    _lastTrackedActiveCatalogId = activeId;
    _showCatalogSpotlight(activeId, rows);
  }

  void _patchCatalogActiveItem(String activeItemId, {bool force = false}) {
    final id = activeItemId.trim();
    if (id.isEmpty) return;
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return;
    var changed = false;
    for (final r in rows) {
      final rid = r.id?.trim() ?? '';
      final shouldBeActive = rid == id;
      if (r.isActive != shouldBeActive) {
        r.isActive = shouldBeActive;
        changed = true;
      }
    }
    if (!mounted) return;
    // Só faz scroll quando a montra MUDA. Poll/force com o mesmo id
    // não deve puxar o carrossel de volta enquanto o utilizador vê outros artigos.
    if (changed) {
      _lastTrackedActiveCatalogId = null;
      setState(() {});
      _showCatalogSpotlight(id, rows);
    } else if (force) {
      // Actualiza flags locais sem animateTo.
      setState(() {});
    }
  }

  void _onCatalogShowEvent(Map<String, dynamic> record) {
    if (_isVodReplay) return;
    final itemId = record['live_item_id']?.toString().trim() ?? '';
    if (itemId.isEmpty) return;
    _patchCatalogActiveItem(itemId, force: true);
    unawaited(_initCatalog(skipCache: true));
  }

  Future<void> _syncActiveCatalogItemFromServer(String liveId) async {
    if (_isVodReplay || liveId.isEmpty || !mounted) return;
    try {
      final rows = await LiveItemsTable().queryRows(
        queryFn: (q) => q.eqOrNull('live_id', liveId),
      );
      String? activeId;
      for (final r in rows) {
        if (r.isActive == true) {
          activeId = r.id?.trim();
          break;
        }
      }
      if (activeId != null && activeId.isNotEmpty) {
        _patchCatalogActiveItem(activeId, force: true);
      } else {
        final local = _catalogRows;
        if (local != null) {
          var cleared = false;
          for (final r in local) {
            if (r.isActive == true) {
              r.isActive = false;
              cleared = true;
            }
          }
          if (cleared && mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  void _startCatalogActivePoll(String liveId) {
    if (liveId.isEmpty || _isVodReplay) return;
    _catalogActivePollTimer?.cancel();
    _catalogActivePollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_syncActiveCatalogItemFromServer(liveId));
    });
  }

  void _startCatalogStockPoll() {
    _catalogStockPollTimer?.cancel();
    // Realtime cobre a maioria das mudanças; poll é fallback (menos agressivo).
    _catalogStockPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final rows = _catalogRows;
      if (rows == null || rows.isEmpty) return;
      _scheduleCatalogStockRefresh();
    });
  }

  void _scheduleCatalogStockRefresh({Iterable<String>? onlyIds}) {
    if (onlyIds == null) {
      _catalogStockRefreshAllPending = true;
      _pendingCatalogStockIds.clear();
    } else if (!_catalogStockRefreshAllPending) {
      for (final id in onlyIds) {
        final t = id.trim();
        if (t.isNotEmpty) _pendingCatalogStockIds.add(t);
      }
    }
    _catalogStockRefreshDebounce?.cancel();
    _catalogStockRefreshDebounce =
        Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final rows = _catalogRows;
      if (rows == null || rows.isEmpty) return;
      final all = _catalogStockRefreshAllPending;
      final only = Set<String>.from(_pendingCatalogStockIds);
      _catalogStockRefreshAllPending = false;
      _pendingCatalogStockIds.clear();
      if (!all && only.isEmpty) return;
      unawaited(
        _refreshCatalogStock(rows, onlyIds: all ? null : only),
      );
    });
  }

  void _onLiveItemRealtimeChange(PostgresChangePayload payload) {
    if (_isVodReplay) return;
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return;
    unawaited(_syncActiveCatalogItemFromServer(liveId));
    final itemId = payload.newRecord['id']?.toString().trim() ?? '';
    if (itemId.isNotEmpty) {
      _scheduleCatalogStockRefresh(onlyIds: [itemId]);
    } else {
      _scheduleCatalogStockRefresh();
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
    final itemId = row.id?.trim() ?? '';
    final stockSnap =
        itemId.isNotEmpty ? _catalogStockByItemId[itemId] : null;
    final reservationsQty = _reservationsCountFromStock(stockSnap);
    final availableNow = stockSnap?.availableQty;
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
                  if (LiveCatalogItemAttributes.subtitle(
                        clothingSize: row.clothingSize,
                        color: row.gender,
                      ) !=
                      null) ...[
                    const SizedBox(height: 2),
                    Text(
                      LiveCatalogItemAttributes.subtitle(
                        clothingSize: row.clothingSize,
                        color: row.gender,
                      )!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                  if (!unavailable &&
                      (reservationsQty > 0 || availableNow != null)) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (reservationsQty > 0)
                          Expanded(
                            child: Text(
                              'Reservas: $reservationsQty',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (availableNow != null)
                          Expanded(
                            child: Text(
                              'Disp: $availableNow',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF00A3AD),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
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
      if (!mounted || source.url.isEmpty) {
        HubPlayerDiag.logUi(
          liveId: liveId,
          state: 'upgrade_skipped',
          reason: !mounted ? 'unmounted' : 'empty_url',
        );
        return;
      }
      final rowStillLive =
          _liveRow != null && !_liveIsEnded(_liveRow!);
      final assumeStillLive = rowStillLive ||
          (_liveRow == null && widget.isLive != false && previous.isLive);
      if (!source.isLive && assumeStillLive) {
        RaffleLog.d('playback upgrade BLOCKED (row still live)', {
          'liveId': liveId,
          'prevLive': previous.isLive,
          'rowNull': _liveRow == null,
        });
        HubPlayerDiag.logUi(
          liveId: liveId,
          state: 'upgrade_blocked',
          reason: rowStillLive
              ? 'source_vod_row_still_live'
              : 'source_vod_row_pending_hint_live',
        );
        return;
      }
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
      HubPlayerDiag.logError(liveId: liveId, phase: 'upgrade_playback', error: e);
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

  static bool _liveIsEnded(LivesRow live) =>
      liveRowIsEnded(status: live.status, isActive: live.isActive);

  /// Anon / Hub web: `lives` está revogada — fallback `hub_lives_public`.
  Future<LivesRow?> _fetchLiveRowForViewer(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await LivesTable()
          .queryRows(
            queryFn: (q) => q.eqOrNull('id', id),
            limit: 1,
          )
          .timeout(const Duration(seconds: 8));
      if (rows.isNotEmpty) return rows.first;
    } catch (e) {
      HubPlayerDiag.logUi(
        liveId: id,
        state: 'lives_table_unavailable',
        reason: e.toString(),
      );
    }
    try {
      final client = SupaFlow.client;
      for (final view in ['hub_lives_public', 'hub_lives_discovery_public']) {
        final rows = await client.from(view).select().eq('id', id).limit(1);
        if (rows.isEmpty) continue;
        final m = Map<String, dynamic>.from(rows.first as Map);
        HubPlayerDiag.logUi(
          liveId: id,
          state: 'hub_lives_public_fallback',
          reason: view,
        );
        return LivesRow({
          'id': m['id'],
          'seller_id': m['seller_id'],
          'status': m['status'],
          'is_active': m['is_active'],
          'mux_playback_id': m['mux_playback_id'],
          'mux_vod_playback_id': m['mux_vod_playback_id'],
          'publish_backend': m['publish_backend'],
          'title': m['title'],
          'went_live_at': m['went_live_at'],
          'created_at': m['created_at'],
          'viewer_count': m['viewer_count'],
        });
      }
    } catch (e) {
      HubPlayerDiag.logError(
        liveId: id,
        phase: 'hub_lives_public_fallback',
        error: e,
      );
    }
    return null;
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
    HubPlayerDiag.logPoll(liveId: liveId, action: 'start');
    var ticks = 0;
    _endedVodPoll = Timer.periodic(const Duration(seconds: 6), (_) async {
      ticks++;
      if (!mounted || ticks > 20) {
        if (ticks > 20) {
          HubPlayerDiag.logPoll(
            liveId: liveId,
            action: 'stop_max_ticks',
            tick: ticks,
          );
        }
        _endedVodPoll?.cancel();
        return;
      }
      HubPlayerDiag.logPoll(liveId: liveId, action: 'tick', tick: ticks);
      await _upgradePlaybackFromDb(liveId);
    });
  }

  Future<_PlaybackSource> _loadPlaybackSource({bool retryResolve = false}) async {
    final directPlayback = widget.playbackId?.trim();
    final liveId = widget.liveId?.trim() ?? '';

    if (liveId.isNotEmpty) {
      try {
        final live = await _fetchLiveRowForViewer(liveId);
        if (live != null) {
          _liveRow = live;
          final playbackId = live.muxPlaybackId?.trim() ?? '';
          final isEnded = _liveIsEnded(live);
          HubPlayerDiag.logLiveRow(
            liveId: liveId,
            status: live.status,
            isActive: live.isActive,
            muxPlaybackId: live.muxPlaybackId,
            muxVodPlaybackId: live.muxVodPlaybackId,
            derivedEnded: isEnded,
            derivedLiveNow: liveRowIsLiveNow(
              status: live.status,
              isActive: live.isActive,
            ),
          );
          // Não confiar no hint de `widget.isLive` (pode vir errado da Home).
          // Forçamos VOD apenas quando o backend indica mesmo “ended”.
          final forceVod = isEnded;

          // Live activa: Mux servidor primeiro (mux_playback_id pode ainda não estar na BD).
          if (!forceVod) {
            final server = await MuxPlaybackResolve.fetchFromServer(
              liveId,
              logContext: retryResolve ? 'poll_live' : 'initial_live',
              timeout: retryResolve
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 28),
            );
            if (server != null && server.ok && server.url.isNotEmpty) {
              // Live row ainda activa: NUNCA marcar Gravado só porque o Mux
              // devolveu isLive=false (asset/VOD transitório) — isso fazia o
              // iframe Lab saltar directo → gravado sozinho.
              final playAsLive = true;
              final playUrl = server.isLive
                  ? server.url
                  : MuxUrls.playbackHls(server.playbackId, live: true);
              final source = _PlaybackSource(
                url: playUrl,
                isLive: playAsLive,
                thumbnailUrl: MuxUrls.portraitThumbnail(
                  server.playbackId,
                  width: 720,
                  live: playAsLive,
                ),
              );
              if (!server.isLive) {
                RaffleLog.d('playback mux said vod; keep live UI', {
                  'liveId': liveId,
                  'muxSource': server.source,
                  'playbackId': server.playbackId,
                });
                HubPlayerDiag.logUi(
                  liveId: liveId,
                  state: 'mux_vod_ignored_while_live_row',
                  reason: 'server_isLive_false_db_active',
                );
              }
              _logPlaybackSourceChosen(live, source, server.source);
              HubPlayerDiag.logPlaybackResolve(
                liveId: liveId,
                forceVod: forceVod,
                isEnded: isEnded,
                resolveSource: server.source,
                url: playUrl,
                playAsLive: playAsLive,
                retryResolve: retryResolve,
              );
              return source;
            }
            // Preferir playback da BD/view; senão hint do embed Hub / query URL.
            final effectivePlayback = playbackId.isNotEmpty
                ? playbackId
                : (directPlayback ?? '');
            if (effectivePlayback.isNotEmpty) {
              final playUrl = MuxUrls.playbackHls(effectivePlayback, live: true);
              final source = _PlaybackSource(
                url: playUrl,
                isLive: true,
                thumbnailUrl: MuxUrls.portraitThumbnail(
                  effectivePlayback,
                  width: 720,
                  live: true,
                ),
              );
              _logPlaybackSourceChosen(
                live,
                source,
                playbackId.isNotEmpty
                    ? 'db_mux_playback_id'
                    : 'playback_id_hint',
              );
              HubPlayerDiag.logPlaybackResolve(
                liveId: liveId,
                forceVod: forceVod,
                isEnded: isEnded,
                resolveSource: playbackId.isNotEmpty
                    ? 'db_mux_playback_id'
                    : 'playback_id_hint',
                url: playUrl,
                playAsLive: true,
                retryResolve: retryResolve,
              );
              return source;
            }
          }

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
              HubPlayerDiag.logPlaybackResolve(
                liveId: liveId,
                forceVod: forceVod,
                isEnded: isEnded,
                resolveSource: server.source,
                url: playUrl,
                playAsLive: playAsLive,
                retryResolve: retryResolve,
              );
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
              HubPlayerDiag.logPlaybackResolve(
                liveId: liveId,
                forceVod: forceVod,
                isEnded: isEnded,
                resolveSource: 'vod_db_fallback',
                url: source.url,
                playAsLive: false,
                retryResolve: retryResolve,
              );
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
          // Enquanto a row não está ended, UI + HLS = live (mesmo se resolve VOD).
          final playAsLive = !forceVod;
          final playUrl = playAsLive && !resolved.isLive && playbackId.isNotEmpty
              ? MuxUrls.playbackHls(playbackId, live: true)
              : resolved.url;
          final thumbId =
              live.muxVodPlaybackId?.trim().isNotEmpty == true
                  ? live.muxVodPlaybackId!
                  : playbackId;
          final source = _PlaybackSource(
            url: playUrl,
            isLive: playAsLive,
            thumbnailUrl: thumbId.isNotEmpty
                ? MuxUrls.portraitThumbnail(
                    thumbId,
                    width: 720,
                    live: playAsLive,
                  )
                : null,
          );
          if (!forceVod && !resolved.isLive) {
            RaffleLog.d('playback db_resolve vod coerced to live', {
              'liveId': liveId,
              'playbackId': playbackId,
            });
          }
          _logPlaybackSourceChosen(live, source, 'db_resolve');
          HubPlayerDiag.logPlaybackResolve(
            liveId: liveId,
            forceVod: forceVod,
            isEnded: isEnded,
            resolveSource: 'db_resolve',
            url: playUrl,
            playAsLive: playAsLive,
            retryResolve: retryResolve,
          );
          return source;
        } else {
          HubPlayerDiag.logUi(
            liveId: liveId,
            state: 'live_row_missing',
            reason: 'lives_and_hub_public_empty',
          );
        }
      } catch (e, st) {
        HubPlayerDiag.logError(liveId: liveId, phase: 'load_playback_source', error: e);
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
    final endedHint =
        _liveRow != null && _liveIsEnded(_liveRow!);
    HubPlayerDiag.logPlaybackResolve(
      liveId: liveId,
      forceVod: endedHint,
      isEnded: endedHint,
      resolveSource: 'empty_fallback',
      url: '',
      playAsLive: !endedHint && (widget.isLive ?? true),
      retryResolve: retryResolve,
    );
    HubPlayerDiag.logUi(
      liveId: liveId,
      state: 'empty_playback_source',
      reason: endedHint ? 'ended_no_url_yet' : 'no_playback_resolved',
    );
    return _PlaybackSource(
      url: '',
      isLive: !endedHint && (widget.isLive ?? true),
    );
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

  String? _lastBadgeDiagKey;

  /// Fonte de verdade = row BD (status/is_active), NÃO `_playbackIsLive`.
  /// Antes: `!_playbackIsLive → false` fazia o badge saltar para GRAVADO quando
  /// o Mux/resolve mentia VOD (iframe Lab APP-216b-IFRAME).
  bool get _liveIsActive {
    final live = _liveRow;
    if (live != null) return !_liveIsEnded(live);
    // Row ainda a carregar: confiar no hint / flag de playback.
    if (widget.isLive == false) return false;
    return _playbackIsLive;
  }

  ({String label, String reason}) _headerBadgeInfo() {
    final live = _liveRow;
    final rowLive = live != null && !_liveIsEnded(live);
    final rowEnded = live != null && _liveIsEnded(live);

    // Enquanto a BD diz live: SEMPRE AO VIVO (mesmo se HLS for VOD transitório).
    if (rowLive) {
      return (label: 'AO VIVO', reason: 'db_row_live');
    }
    if (live == null && _playbackIsLive && widget.isLive != false) {
      return (label: 'AO VIVO', reason: 'hint_live_row_pending');
    }
    if (rowEnded && _hasWatchablePlayback) {
      return (label: 'GRAVADO', reason: 'replay_with_playback_id');
    }
    if (rowEnded || !_playbackIsLive) {
      return (
        label: 'GRAVAÇÃO A PREPARAR',
        reason: 'no_replay_playback_yet',
      );
    }
    return (label: '', reason: 'none');
  }

  void _logHeaderBadgeOnce() {
    final info = _headerBadgeInfo();
    if (info.label.isEmpty) return;
    final key =
        '${info.label}|${info.reason}|$_playbackIsLive|${_liveRow?.status}|${_liveRow?.isActive}';
    if (key == _lastBadgeDiagKey) return;
    _lastBadgeDiagKey = key;
    HubPlayerDiag.logBadge(
      liveId: widget.liveId,
      label: info.label,
      reason: info.reason,
      playbackIsLive: _playbackIsLive,
      liveIsActive: _liveIsActive,
    );
  }

  bool get _isVodReplay => !_liveIsActive;

  bool get _hasWatchablePlayback {
    final live = _liveRow;
    if (live == null) return widget.playbackId?.trim().isNotEmpty ?? false;
    final vod = live.muxVodPlaybackId?.trim() ?? '';
    if (vod.isNotEmpty) return true;
    return live.muxPlaybackId?.trim().isNotEmpty ?? false;
  }

  bool get _catalogStripLoading =>
      _catalogLoading ||
      _catalogRows == null ||
      (_catalogInitialLoadPending && (_catalogRows?.isEmpty ?? true));

  bool get _showChatInput => _liveIsActive;

  bool get _showChatPanel {
    final liveId = widget.liveId?.trim() ?? '';
    return liveId.isEmpty || _liveRoom != null;
  }

  /// Overlay de chat no vídeo — desligado no shell desktop B1 (coluna externa).
  bool get _showChatOverlay => _showChatPanel && !widget.hubExternalChat;

  /// Carrossel/spotlight no vídeo — desligado no shell desktop B2 (coluna esquerda).
  bool get _showCatalogOverlay => !widget.hubExternalProducts;

  /// B2.1 — shell Hub já tem chrome (vendedor/Seguir/badge/fechar). Esconde só a
  /// barra superior duplicada no vídeo; rail/ações do player mantêm-se.
  bool get _hideDuplicatePlayerHeader =>
      widget.hubExternalChat || widget.hubExternalProducts;

  /// Produto actual desta live (active / VOD highlight) — mesma regra do carousel.
  LiveItemsRow? get _featuredCatalogRow {
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      if (_isCatalogRowActive(r)) return r;
    }
    return rows.first;
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
      final rows = await ProfilesDirectoryTable().queryRows(
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
    if (!_isPlaceholderChatName(trimmed)) return trimmed;
    final uid = userId?.trim() ?? '';
    if (uid.isEmpty) {
      return trimmed.isEmpty ? 'Utilizador' : trimmed;
    }
    final cached = _userNameCacheById[uid]?.trim() ?? '';
    if (cached.isNotEmpty && !_isPlaceholderChatName(cached)) {
      return cached;
    }
    if (uid == currentUserUid) {
      final mine = currentUserDisplayName.trim();
      if (mine.isNotEmpty) return mine;
    }
    return trimmed.isEmpty ? 'Utilizador' : trimmed;
  }

  static bool _isPlaceholderChatName(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return true;
    final lower = trimmed.toLowerCase();
    return lower == 'utilizador' || lower == 'user' || trimmed.length <= 3;
  }

  String _resolveHumanChatLabel({
    required String? senderLabel,
    required String? userId,
    bool isSeller = false,
  }) {
    final raw = senderLabel?.trim() ?? '';
    final uid = userId?.trim() ?? '';
    if (!_isPlaceholderChatName(raw)) return raw;

    final cached = uid.isNotEmpty ? _userNameCacheById[uid]?.trim() : null;
    if (cached != null &&
        cached.isNotEmpty &&
        !_isPlaceholderChatName(cached)) {
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
      final profiles = await ProfilesDirectoryTable().queryRows(
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

  void _seedChatIdentityFromMessages(List<LiveRoomMessage> msgs) {
    var changed = false;
    for (final m in msgs) {
      final uid = m.userId?.trim();
      if (uid == null || uid.isEmpty) continue;
      final label = m.senderLabel?.trim() ?? '';
      if (!_isPlaceholderChatName(label)) {
        final cached = _userNameCacheById[uid];
        if (_isPlaceholderChatName(cached)) {
          _userNameCacheById[uid] = label;
          changed = true;
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _ensureUserNamesResolved(List<LiveRoomMessage> msgs) {
    _seedChatIdentityFromMessages(msgs);

    final now = DateTime.now();
    if (now.difference(_lastUserNameFetchAt) < const Duration(milliseconds: 200)) {
      return;
    }

    final ids = msgs
        .map((m) => m.userId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .where((id) => !_userNameFetchInFlight.contains(id))
        .where((id) {
          if (!_userNameCacheById.containsKey(id)) return true;
          if (_isPlaceholderChatName(_userNameCacheById[id])) return true;
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
        final profiles = await ProfilesDirectoryTable().queryRows(
          queryFn: (q) => q.inFilter('id', ids),
        );
        final names = <String, String>{};
        final photos = <String, String>{};
        for (final p in profiles) {
          final pid = p.id?.trim();
          if (pid == null || pid.isEmpty) continue;
          final full = p.fullName?.trim();
          if (full != null && full.isNotEmpty && !_isPlaceholderChatName(full)) {
            names[pid] = full;
          }
          final photo = p.photoUrl?.trim() ?? '';
          if (photo.isNotEmpty) {
            photos[pid] = photo;
          }
        }
        for (final m in msgs) {
          final uid = m.userId?.trim();
          if (uid == null || !ids.contains(uid)) continue;
          if (names.containsKey(uid)) continue;
          final label = m.senderLabel?.trim() ?? '';
          if (!_isPlaceholderChatName(label)) {
            names[uid] = label;
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
    // Hub: coluna de chat externa (fundo claro) mostra o histórico completo
    // do gravado — o sync por posição fica só no overlay sobre o vídeo.
    if (widget.hubExternalChat) return msgs;

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
      if (!await _promptAuthForAction(
        intentLabel: 'enviar mensagem privada',
        legacySnack: 'Inicia sessão para enviar mensagem privada.',
      )) {
        return;
      }
      _ensurePrivateRoom();
      final priv = _privateRoom;
      final seller = _sellerId?.trim();
      if (priv == null || seller == null || seller.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o chat privado.'),
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
      if (!await _promptAuthForAction(
        intentLabel: 'escrever no chat',
        legacySnack: 'Inicia sessão para escrever no chat.',
      )) {
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
    unawaited(() async {
      if (!await _promptAuthForAction(
        intentLabel: 'reservar este artigo',
        legacySnack: 'Inicia sessão para reservar.',
      )) {
        return;
      }
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
              () {
                final base = LiveReservationQueueService.buyerReserveSnackMessage(
                  priorOpenCount: priorOpen,
                  queuePosition: pos,
                  waitlist: waitlist,
                  othersWantItem: othersCount > 0,
                );
                final raffleItemId =
                    _raffleState?.raffle?.liveItemId?.trim() ?? '';
                if (raffleItemId.isNotEmpty && raffleItemId == itemId.trim()) {
                  return '$base Reserva independente da participação na Rifa.';
                }
                return base;
              }(),
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

  Future<ProductsRow?> _resolveProductForLiveItem(LiveItemsRow row) async {
    return LiveItemPriceGate.resolveProductForCheckout(
      itemRow: row,
      sellerId: _sellerId,
      liveId: widget.liveId,
    );
  }

  /// Foto do artigo: `live_items.photo_url`, senão imagem marketplace pré-carregada.
  String _photoUrlForCatalogRow(LiveItemsRow row) {
    final direct = row.photoUrl?.trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final id = row.id?.trim() ?? '';
    if (id.isEmpty) return '';
    return (_catalogFallbackPhotoByItemId[id] ?? '').trim();
  }

  Future<void> _prefetchCatalogFallbackPhotos(List<LiveItemsRow> rows) async {
    final need = rows
        .where((r) =>
            (r.photoUrl?.trim().isEmpty ?? true) &&
            (r.id?.trim().isNotEmpty ?? false))
        .take(24)
        .toList();
    if (need.isEmpty) return;
    final next = <String, String>{..._catalogFallbackPhotoByItemId};
    for (final row in need) {
      final id = row.id!.trim();
      if (next[id]?.isNotEmpty == true) continue;
      try {
        final p = await _resolveProductForLiveItem(row);
        final url = (p?.imageUrls.isNotEmpty == true)
            ? p!.imageUrls.first.trim()
            : '';
        if (url.isNotEmpty) next[id] = url;
      } catch (_) {}
    }
    if (!mounted || next.length == _catalogFallbackPhotoByItemId.length) {
      return;
    }
    setState(() => _catalogFallbackPhotoByItemId = next);
  }

  Future<void> _refreshCatalogStock(
    List<LiveItemsRow> rows, {
    Set<String>? onlyIds,
  }) async {
    Iterable<String> ids = rows
        .map((r) => r.id?.trim() ?? '')
        .where((id) => id.isNotEmpty);
    if (onlyIds != null) {
      if (onlyIds.isEmpty) return;
      ids = ids.where(onlyIds.contains);
    }
    final idList = ids.toList();
    if (idList.isEmpty) return;
    final snaps = await LiveCatalogStockService.fetchMany(idList);
    if (!mounted) return;
    setState(() {
      if (onlyIds != null) {
        _catalogStockByItemId = {
          ..._catalogStockByItemId,
          ...snaps,
        };
      } else {
        _catalogStockByItemId = snaps;
      }
    });
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

  /// Reservas no card — local + outros directos/gravados (mesma ref).
  int _reservationsCountFromStock(LiveCatalogStockSnapshot? snap) {
    if (snap == null) return 0;
    return snap.displayReservedQty;
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
            LiveReservationQueueService.buyerCanPayBagReservation(reqRows.first.status, notes: reqRows.first.notes, requestKind: reqRows.first.requestKind)) {
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
    final liid = liveItemId?.trim() ?? '';
    var itemRow = liid.isNotEmpty ? _catalogRowById(liid) : null;
    if (liid.isNotEmpty) {
      itemRow = await LiveCatalogStockService.fetchLiveItemById(liid) ?? itemRow;
    }
    final unitOverride = await LiveItemPriceGate.resolveFreshUnitPrice(
      liveItemId: liid,
      fallbackLiveItemPrice: itemRow?.price,
      productPrice: product.price,
    );
    if (unitOverride == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(LiveItemPriceGate.pendingPriceLabel),
        ),
      );
      return;
    }
    await LiveInStreamCheckout.show(
      context: context,
      product: product,
      liveId: liveId,
      liveItemId: liveItemId,
      overrideItemPriceEur: unitOverride,
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
          await _refreshRaffleState(liveId, silent: true);
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
    final itemId = row.id?.trim() ?? '';
    final cachedStock =
        itemId.isNotEmpty ? _catalogStockByItemId[itemId] : null;
    final rowQty = row.quantity;
    var loading = cachedStock == null && (rowQty == null || rowQty < 1);
    ProductsRow? product;
    LiveCatalogStockSnapshot? stock = cachedStock;
    int qtyInBag = 0;
    // Disp. = availableQty (com hold da rifa). Nunca totalQty / product.quantity.
    int? qtyAvailable = cachedStock?.availableQty;
    int soldQty = cachedStock?.soldConvertedQty ?? 0;
    int reservationsQty = _reservationsCountFromStock(cachedStock);
    int raffleHoldQty = cachedStock?.raffleHoldQty ?? 0;

    Timer? stockRefreshTimer;
    final useHubChrome = widget.hubLightShell;
    final wideHub = useHubChrome && MediaQuery.sizeOf(context).width >= 900;

    Future<void> presentItemModal(
      Widget Function(BuildContext ctx, void Function(void Function()) setModalState)
          buildModal,
    ) async {
      if (wideHub) {
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.45),
          builder: (ctx) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 880,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
                ),
                child: StatefulBuilder(
                  builder: (ctx, setModalState) =>
                      buildModal(ctx, setModalState),
                ),
              ),
            );
          },
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        backgroundColor:
            useHubChrome ? Colors.white : const Color(0xFF11181C),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) => buildModal(ctx, setModalState),
          );
        },
      );
    }

    await presentItemModal((ctx, setModalState) {
            Future<void> refreshStockIntoModal({bool force = false}) async {
              final st = await _fetchLiveItemStock(row);
              final p = product ?? await _resolveProductForLiveItem(row);
              // Só fallback marketplace se a RPC live falhar — e mesmo assim
              // não misturar com hold de rifa (melhor mostrar 0 do que total).
              var avail = st?.availableQty;
              if (st == null) {
                avail = await _resolveAvailableQtyForProduct(p);
              }
              final sold = st?.soldConvertedQty ?? await _resolveSoldQty(p);
              final pid = row.id?.trim();
              final lid = widget.liveId?.trim() ?? '';
              var bagQty = qtyInBag;
              if (force || bagQty == 0) {
                bagQty = 0;
                if (pid != null &&
                    pid.isNotEmpty &&
                    lid.isNotEmpty &&
                    currentUserUid.isNotEmpty) {
                  final bag =
                      await LiveReservationQueueService().liveBagRequests(
                    liveId: lid,
                    buyerId: currentUserUid,
                    limit: 120,
                  );
                  bagQty = bag
                      .where((r) => r.liveItemId == pid)
                      .fold<int>(0, (a, b) => a + b.requestedQty);
                }
              }
              if (!ctx.mounted) return;
              setModalState(() {
                loading = false;
                product = p;
                stock = st ?? stock;
                qtyAvailable = avail ?? qtyAvailable;
                soldQty = sold;
                qtyInBag = bagQty;
                reservationsQty = _reservationsCountFromStock(st ?? stock);
                raffleHoldQty = st?.raffleHoldQty ?? raffleHoldQty;
              });
              RaffleLog.d('item detail stock', {
                'itemId': itemId,
                'available': avail,
                'total': st?.totalQty,
                'raffleHold': st?.raffleHoldQty,
                'fromCache': st == null && cachedStock != null,
              });
            }

            stockRefreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
              unawaited(refreshStockIntoModal());
            });
            unawaited(refreshStockIntoModal(force: true));

            final hasExternal = _sellerProfile?.externalPaymentsEnabled == true;
            // Mesma origem que a lista/miniatura — sem transformar URL no modal Hub
            // (ResizeImage/transform Supabase falhava → cinzento com foto válida).
            var image = _photoUrlForCatalogRow(row);
            if (image.isEmpty && product != null) {
              final urls = product!.imageUrls;
              if (urls.isNotEmpty) image = urls.first.trim();
            }
            final ref = (row.refCode ?? '').trim();
            final title = (row.title ?? '').trim();
            final price = _formatPriceEur(row) ?? '—';
            final isUnavailable = _isCatalogRowUnavailable(row);
            final isPaidSold = _isCatalogRowPaidSold(row);
            final unavailableBadge = _catalogUnavailableBadge(row);
            final availableNow = loading
                ? null
                : (qtyAvailable ?? stock?.availableQty ?? 0);
            // Nunca usar «1» como placeholder — parece stock falso ao expandir.
            final totalInitial = stock?.totalQty ??
                ((rowQty != null && rowQty > 0) ? rowQty : null) ??
                product?.quantity;
            final size = row.clothingSize?.trim().isNotEmpty == true
                ? row.clothingSize!.trim()
                : (product?.clothingSize?.trim() ?? '');
            final gender = row.gender?.trim().isNotEmpty == true
                ? row.gender!.trim()
                : (product?.gender?.trim() ?? '');
            final description = product?.description?.trim().isNotEmpty == true
                ? product!.description!.trim()
                : '';
            final isAlreadyInBag = qtyInBag > 0;

            Widget photoPane() {
              final bg = useHubChrome
                  ? const Color(0xFFF0F4F6)
                  : const Color(0xFF1B2428);
              final muted = useHubChrome
                  ? const Color(0xFF57636C)
                  : Colors.white70;
              Widget labeledEmpty(String label) => ColoredBox(
                    color: bg,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            size: 36,
                            color: muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
              final empty = labeledEmpty('Sem fotografia');
              final loadError =
                  labeledEmpty('Não foi possível carregar a fotografia');
              final photoChild = image.isEmpty
                  ? empty
                  : (useHubChrome
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          gaplessPlayback: true,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return batataImagePlaceholder(color: bg);
                          },
                          errorBuilder: (_, __, ___) => loadError,
                        )
                      : BatataCachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          placeholderColor: bg,
                          errorWidget: loadError,
                        ));
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: bg,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: wideHub ? 480 : 260,
                      minHeight: wideHub
                          ? (image.isEmpty ? 180.0 : 300.0)
                          : (image.isEmpty ? 120.0 : 180.0),
                    ),
                    child: photoChild,
                  ),
                ),
              );
            }

            final modalChildren = <Widget>[
                    photoPane(),
                    const SizedBox(height: 10),
                    Text(
                      LiveVendorRefDisplay.itemDisplayName(
                        title: title.isEmpty ? null : title,
                        refCode: ref.isEmpty ? null : ref,
                      ),
                      style: GoogleFonts.inter(
                        color: useHubChrome
                            ? const Color(0xFF101518)
                            : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _miniInfoChip('Preço', price,
                            light: useHubChrome),
                        if (size.isNotEmpty)
                          _miniInfoChip('Tamanho', size, light: useHubChrome),
                        if (gender.isNotEmpty)
                          _miniInfoChip('Género', gender, light: useHubChrome),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Descrição',
                        style: GoogleFonts.inter(
                          color: useHubChrome
                              ? const Color(0xFF57636C)
                              : Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.inter(
                          color: useHubChrome
                              ? const Color(0xFF101518)
                              : Colors.white.withValues(alpha: 0.88),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (isUnavailable) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _kSoldBadge.withValues(
                              alpha: useHubChrome ? 0.12 : 0.22),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _kSoldBadge.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          isPaidSold
                              ? 'Marcado como vendido — podes reservar na mesma (lista de interesse).'
                              : isAlreadyInBag
                                  ? 'Tens pedido(s) no saco. Podes acrescentar mais interesse na fila.'
                                  : 'Stock esgotado no momento — a reserva entra na fila de interesse.',
                          style: GoogleFonts.inter(
                            color: useHubChrome
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFFFFCDD2),
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
                      raffleHoldQty: raffleHoldQty,
                      loading: loading,
                      light: useHubChrome,
                    ),
                    const SizedBox(height: 14),
                    if (!isPaidSold)
                      FleaberPrimaryButton(
                        label: 'Comprar já',
                        height: 44,
                        borderRadius: 12,
                        onPressed: loading || product == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _openCheckoutForProduct(
                                  product!,
                                  liveItemId: row.id,
                                );
                              },
                      ),
                    if (!isPaidSold) const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _onReservarItem(row.id);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: useHubChrome
                            ? (isAlreadyInBag
                                ? const Color(0xFF007782)
                                : const Color(0xFF101518))
                            : (isAlreadyInBag
                                ? const Color(0xFF6ED8DE)
                                : Colors.white),
                        side: BorderSide(
                          color: useHubChrome
                              ? const Color(0xFF007782)
                              : (isAlreadyInBag
                                  ? const Color(0xFF6ED8DE)
                                  : Colors.white54),
                          width: 1.5,
                        ),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isAlreadyInBag
                            ? 'Já está no teu saco ✓'
                            : 'Reservar no saco',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
                        style: TextButton.styleFrom(
                          foregroundColor: useHubChrome
                              ? const Color(0xFF007782)
                              : Colors.white70,
                        ),
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
                          'Últimas unidades: garante com pagamento para não perder.',
                          style: GoogleFonts.inter(
                            color: useHubChrome
                                ? const Color(0xFF8A5A00)
                                : const Color(0xFFFFD180),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
            ];

            Widget column = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: modalChildren,
            );

            if (wideHub) {
              // ~45% fotografia | info/ações
              final img = modalChildren.first;
              final rest = modalChildren.sublist(1);
              column = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 45, child: img),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 55,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rest,
                      ),
                    ),
                  ),
                ],
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: wideHub
                    ? column
                    : SingleChildScrollView(child: column),
              ),
            );
    });
    stockRefreshTimer?.cancel();
  }

  Widget _miniInfoChip(String label, String value, {bool light = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: light
            ? const Color(0xFFF0F4F6)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          color: light ? const Color(0xFF101518) : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLiveStockSummary({
    required int? totalInitial,
    required int soldQty,
    required int reservationsQty,
    required int? availableNow,
    int raffleHoldQty = 0,
    bool loading = false,
    bool light = false,
  }) {
    Widget cell({
      required String label,
      required String value,
      required Color color,
      bool emphasize = false,
    }) {
      final labelFg = light ? const Color(0xFF57636C) : Colors.white70;
      final valueFg = light ? const Color(0xFF101518) : Colors.white;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: light ? 0.10 : (emphasize ? 0.24 : 0.14)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: light ? 0.45 : 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: labelFg,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.inter(
                color: valueFg,
                fontSize: emphasize ? 16 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    final totalLabel = loading
        ? '…'
        : (totalInitial == null ? '—' : '$totalInitial');
    final hold = raffleHoldQty < 0 ? 0 : raffleHoldQty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: cell(
                label: 'Total inicial',
                value: totalLabel,
                color: const Color(0xFF7C8A93),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: cell(
                label: 'Vendidos',
                value: loading ? '…' : '$soldQty',
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
                label: 'Disponíveis agora',
                value: loading ? '…' : '${availableNow ?? 0}',
                color: const Color(0xFF00A3AD),
                emphasize: true,
              ),
            ),
          ],
        ),
        if (!loading && hold > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Rifa retém $hold un. · Disp. = total − reservas − rifa',
            style: GoogleFonts.inter(
              color: light
                  ? const Color(0xFF57636C)
                  : Colors.white.withValues(alpha: 0.65),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _continueWithFacebookFromBag() async {
    if (_facebookContinueBusy) return;
    setState(() => _facebookContinueBusy = true);
    try {
      await HubActions.continueWithFacebook(context);
    } finally {
      if (mounted) setState(() => _facebookContinueBusy = false);
    }
  }

  Future<void> _openLiveBagSheet() async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return;
    if (!await _promptAuthForAction(
      intentLabel: 'ver o teu saco',
      legacySnack: 'Inicia sessão para ver o teu saco.',
    )) {
      return;
    }
    // Hub/embed: claim Face→conta antes de abrir (mesmo fluxo do HubLiveBagSheet).
    if (widget.embedInHub) {
      final claim = await HubPsClaim.claimForLiveDetailed(liveId);
      if (!mounted) return;
      setState(() => _needsFacebookLogin = claim.needsFacebookLogin);
      if (claim.claimed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              claim.claimed == 1
                  ? 'Reserva recuperada.'
                  : 'Reservas recuperadas.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    final byId = {
      for (final c in _catalogRows ?? const <LiveItemsRow>[]) (c.id ?? ''): c,
    };
    await LiveBagSheet.show(
      context: context,
      liveId: liveId,
      buyerId: currentUserUid,
      catalogByItemId: byId,
      focusReservationRequestId: LiveEmbedHost.takeFocusReservationRequestId(),
      // Phase 3: commercial bag is buyer+seller (omnichannel), liveId is navigation context.
      loadRows: () {
        final sid = _sellerId?.trim() ?? '';
        if (sid.isEmpty) {
          return LiveReservationQueueService().liveBagDisplayRequests(
            liveId: liveId,
            buyerId: currentUserUid,
          );
        }
        return LiveReservationQueueService().sellerBagDisplayRequests(
          sellerId: sid,
          buyerId: currentUserUid,
        );
      },
      loadSellerBagMeta: () {
        final sid = _sellerId?.trim() ?? '';
        if (sid.isEmpty) return Future<Map<String, dynamic>?>.value(null);
        return LiveReservationQueueService().loadSellerBag(sellerId: sid);
      },
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
      fleahubChrome: widget.hubLightShell,
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
      _startCatalogActivePoll(liveId);
      if ((widget.sellerId?.trim().isNotEmpty ?? false)) {
        _subscribeBuyerCheckoutRealtime(liveId);
        _subscribeSellerCatalogStockRealtime();
      }
      unawaited(_loadLiveBagCount(liveId));
      _initRaffle(liveId);
      unawaited(_maybeRegisterRaffleReferralVisit(liveId));
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
        if (source.url.isEmpty || (ended && source.isLive)) {
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
      unawaited(_maybeStartTipStripePoll());
      if (!mounted || liveId.isEmpty) return;
      try {
        final uri = GoRouterState.of(context).uri;
        HubPlayerDiag.logOpen(
          routePath: uri.path,
          routeQuery: uri.query,
          handle: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null,
          liveId: liveId,
          embedInHub: widget.embedInHub,
          isLiveHint: hintLive,
          playbackIdHint: directPlayback.isEmpty ? null : directPlayback,
        );
      } catch (_) {
        HubPlayerDiag.logOpen(
          routePath: null,
          routeQuery: null,
          handle: null,
          liveId: liveId,
          embedInHub: widget.embedInHub,
          isLiveHint: hintLive,
          playbackIdHint: directPlayback.isEmpty ? null : directPlayback,
        );
      }
    });

    if (widget.embedInHub) {
      LiveEmbedHost.registerOpenBag(_openLiveBagSheet);
    }
  }

  void _initRaffle(String liveId) {
    unawaited(_refreshRaffleState(liveId));
    _rafflePollTimer?.cancel();
    _rafflePollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_refreshRaffleState(liveId, silent: true));
    });
    _subscribeRaffleRealtime(liveId);
    _subscribeRaffleStream(liveId);
  }

  void _subscribeRaffleStream(String liveId) {
    if (liveId.trim().isEmpty) return;
    try {
      _raffleStreamSub?.cancel();
      _raffleStreamSub = SupaFlow.client
          .from('live_raffles')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) => unawaited(_refreshRaffleState(liveId, silent: true)));
    } catch (_) {}
  }

  Future<void> _maybeRegisterRaffleReferralVisit(String liveId) async {
    final code = widget.raffleRef?.trim() ?? '';
    if (code.isEmpty || liveId.trim().isEmpty || _raffleRefVisitRegistered) {
      return;
    }
    if (currentUserUid.isEmpty) return;
    try {
      await LiveRaffleService.registerReferralVisit(
        liveId: liveId,
        code: code,
      );
      _raffleRefVisitRegistered = true;
    } catch (e) {
      debugPrint('[LiveRaffle] registerReferral: $e');
    }
  }

  @override
  void didUpdateWidget(covariant FleaberLivePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return;
    final oldRef = oldWidget.raffleRef?.trim() ?? '';
    final newRef = widget.raffleRef?.trim() ?? '';
    if (newRef.isNotEmpty && newRef != oldRef) {
      _raffleRefVisitRegistered = false;
      unawaited(_maybeRegisterRaffleReferralVisit(liveId));
    }
  }

  Future<void> _refreshRaffleState(String liveId, {bool silent = false}) async {
    if (liveId.trim().isEmpty) return;
    unawaited(_maybeRegisterRaffleReferralVisit(liveId));
    final prevBefore = _raffleState;
    RaffleLog.d('refresh start', {
      'liveId': liveId,
      'silent': silent,
      'prev': prevBefore?.debugSummary ?? 'null',
    });
    try {
      final raffle = _raffleState?.raffle;
      if (raffle != null && raffle.isActive && raffle.hasTimer) {
        await LiveRaffleService.tick(raffle.id);
      }
      if (currentUserUid.isNotEmpty) {
        unawaited(LiveRaffleService.qualifyReferralVisits(liveId));
      }
      final next = await LiveRaffleService.fetchState(liveId);
      // Nunca apagar rifa visível por um fetch vazio/transitório (sumia o ícone).
      if (!next.hasRaffle || next.raffle == null) {
        if (_raffleState?.hasRaffle == true && _raffleState?.raffle != null) {
          RaffleLog.d('refresh KEEP prev (empty next)', {
            'prev': _raffleState!.debugSummary,
          });
          return;
        }
      }
      int? participants;
      final rid = next.raffle?.id;
      if (rid != null && rid.isNotEmpty) {
        try {
          participants = await LiveRaffleService.fetchParticipantCount(rid);
        } catch (e) {
          RaffleLog.e('refresh participants', e);
        }
      }
      if (!mounted) return;
      final prev = _raffleState;
      LiveRaffleState merged;
      if (prev != null &&
          prev.hasRaffle &&
          prev.raffle != null &&
          next.hasRaffle &&
          next.raffle != null) {
        final sticky = prev.mergePreferringLocalViewer(next);
        final remoteRank = _raffleStatusRank(next.raffle!.status);
        final localRank = _raffleStatusRank(prev.raffle!.status);
        // Status remoto mais avançado (ex. drawn) ganha sempre.
        merged = remoteRank >= localRank
            ? next.copyWith(viewer: sticky.viewer)
            : sticky;
      } else {
        merged = next;
      }
      // Dupla guarda: nunca gravar empty se ainda tínhamos rifa.
      if ((!merged.hasRaffle || merged.raffle == null) &&
          prev != null &&
          prev.hasRaffle &&
          prev.raffle != null) {
        RaffleLog.d('refresh REFUSE wipe', {'prev': prev.debugSummary});
        return;
      }
      final becameWinner = merged.viewer.isWinner &&
          prev?.viewer.isWinner != true &&
          merged.raffle?.isDrawn == true;
      RaffleLog.d('refresh COMMIT', {
        'merged': merged.debugSummary,
        'participants': participants ?? -1,
        'becameWinner': becameWinner,
        'playbackLive': _playbackIsLive,
      });
      setState(() {
        _raffleState = merged;
        if (participants != null) {
          _raffleParticipantCount = participants;
        }
      });
      if (becameWinner && mounted && _raffleWinnerCelebrationShown != true) {
        _raffleWinnerCelebrationShown = true;
        RaffleLog.d('winner celebration trigger becameWinner', {
          'prize': merged.raffle?.title ?? 'Rifa da Live',
          'playbackLive': _playbackIsLive,
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            LiveRaffleWinnerCelebration.show(
              context,
              prizeTitle: merged.raffle?.title ?? 'Rifa da Live',
            ),
          );
        });
      }
      // Stock AM5 no catálogo do player (Disp. nos cards).
      final rows = _catalogRows;
      if (rows != null && rows.isNotEmpty) {
        unawaited(_refreshCatalogStock(rows));
      }
    } catch (e) {
      RaffleLog.e('refresh', e, {'liveId': liveId});
    }
  }

  int _raffleStatusRank(String status) {
    switch (status) {
      case 'drawn':
        return 3;
      case 'closed':
        return 2;
      case 'active':
        return 1;
      default:
        return 0;
    }
  }

  void _subscribeRaffleRealtime(String liveId) {
    if (liveId.trim().isEmpty || _raffleChannel != null) return;
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'live_id',
      value: liveId,
    );
    _raffleChannel = SupaFlow.client
        .channel('live_raffle:$liveId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_raffles',
          filter: filter,
          callback: (_) => unawaited(_refreshRaffleState(liveId, silent: true)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_raffle_entries',
          filter: filter,
          callback: (_) => unawaited(_refreshRaffleState(liveId, silent: true)),
        )
        .subscribe();
  }

  Future<void> _onRaffleTap() async {
    final liveId = widget.liveId?.trim() ?? '';
    RaffleLog.d('buyer raffle tap', {
      'liveId': liveId,
      'embedHub': widget.embedInHub,
      'playbackLive': _playbackIsLive,
      'liveActive': _liveIsActive,
      'status': _liveRow?.status ?? '-',
      'hasRaffle': _raffleState?.hasRaffle == true,
      'raffle': _raffleState?.debugSummary ?? 'null',
    });
    if (liveId.isEmpty || _raffleState?.hasRaffle != true) return;

    if (currentUserUid.isEmpty) {
      await _promptAuthForAction(
        intentLabel: 'participar na Rifa',
        legacySnack: 'Inicia sessão para participar na Rifa.',
      );
      if (!mounted) return;
      if (currentUserUid.isEmpty && widget.embedInHub) return;
    }

    // Refresh antes de abrir — mostra sorteio/vencedor actualizado.
    final wasLive = _playbackIsLive;
    await _refreshRaffleState(liveId, silent: true);
    if (!mounted) return;
    RaffleLog.d('buyer raffle after refresh', {
      'playbackLive': _playbackIsLive,
      'wasLive': wasLive,
      'raffle': _raffleState?.debugSummary ?? 'null',
    });
    // Não deixar um refresh da rifa «empurrar» o player para Gravado.
    if (wasLive && !_playbackIsLive) {
      RaffleLog.d('buyer raffle GUARD restore live flag');
      setState(() => _playbackIsLive = true);
    }

    final state = _raffleState;
    if (state == null || !state.hasRaffle || state.raffle == null) return;

    if (state.raffle!.isDrawn && state.viewer.isWinner) {
      RaffleLog.d('winner celebration trigger raffleTap', {
        'prize': state.raffle!.title,
      });
      await LiveRaffleWinnerCelebration.show(
        context,
        prizeTitle: state.raffle!.title,
      );
      if (!mounted) return;
    }

    await LiveRaffleDetailsSheet.show(
      context,
      liveId: liveId,
      state: state,
      participantCount: _raffleParticipantCount,
      preferredShareLink: widget.sharePreferredLink,
      onNeedAuth: () => _promptAuthForAction(
        intentLabel: 'participar na Rifa',
        legacySnack: 'Inicia sessão para participar na Rifa.',
      ),
      onJoined: (tickets) {
        if (!mounted || _raffleState?.raffle == null) return;
        setState(() {
          _raffleState = _raffleState!.copyWith(
            hasRaffle: true,
            viewer: _raffleState!.viewer.copyWith(
              joined: true,
              ticketBalance: tickets,
            ),
          );
          if ((_raffleParticipantCount ?? 0) < 1) {
            _raffleParticipantCount = 1;
          }
          _raffleJoinLoading = false;
        });
        unawaited(_refreshRaffleState(liveId, silent: true));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estás na Rifa — +1 rifa!')),
        );
      },
      onShareResult: (result) {
        if (!mounted) return;
        RaffleLog.d('onShareResult', {
          'awarded': result.awardedShareBonus,
          'already': result.shareAlreadyClaimed,
          'tickets': result.ticketBalance ?? -1,
          'hasIcon': _raffleState?.hasRaffle == true,
          'msg': result.message,
        });
        final bal = result.ticketBalance;
        if (_raffleState?.raffle != null) {
          setState(() {
            _raffleState = _raffleState!.copyWith(
              hasRaffle: true,
              raffle: _raffleState!.raffle,
              viewer: _raffleState!.viewer.copyWith(
                joined: true,
                shareBonusClaimed: result.awardedShareBonus ||
                        result.shareAlreadyClaimed
                    ? true
                    : _raffleState!.viewer.shareBonusClaimed,
                ticketBalance: bal != null && bal > 0
                    ? bal
                    : _raffleState!.viewer.ticketBalance,
              ),
            );
          });
          RaffleLog.d('onShareResult after setState', {
            'state': _raffleState!.debugSummary,
          });
        } else {
          RaffleLog.d('onShareResult SKIP setState — raffle null');
        }
        // Refresh em soft — nunca deve apagar o ícone.
        unawaited(_refreshRaffleState(liveId, silent: true));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      },
    );
  }

  Future<void> _refreshFollowState() async {
    final sellerId = _sellerId?.trim() ?? '';
    final uid = currentUserUid.trim();
    if (sellerId.isEmpty || uid.isEmpty || sellerId == uid) {
      if (mounted) setState(() => _isFollowingSeller = false);
      return;
    }
    try {
      final rows = await FollowsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('follower_id', uid)
            .eqOrNull('following_id', sellerId),
        limit: 1,
      );
      if (mounted) {
        setState(() => _isFollowingSeller = rows.isNotEmpty);
      }
    } catch (_) {
      if (mounted) setState(() => _isFollowingSeller = false);
    }
  }

  Future<void> _toggleFollowSeller() async {
    final sellerId = _sellerId?.trim() ?? '';
    final uid = currentUserUid.trim();
    final liveId = widget.liveId?.trim() ?? '';
    if (sellerId.isEmpty || uid.isEmpty) {
      if (!mounted) return;
      if (!await _promptAuthForAction(
        intentLabel: 'seguir esta seller',
        legacySnack: 'Inicia sessão para seguir.',
      )) {
        return;
      }
    }
    if (sellerId == uid) return;

    final wasFollowing = _isFollowingSeller == true;
    final hadFollowBonus = _raffleState?.viewer.followBonusClaimed == true;
    try {
      if (wasFollowing) {
        await FollowsTable().delete(
          matchingRows: (rows) => rows
              .eqOrNull('follower_id', uid)
              .eqOrNull('following_id', sellerId),
        );
      } else {
        await FollowsTable().insert({
          'follower_id': uid,
          'following_id': sellerId,
        });
      }
      await _refreshFollowState();
      if (!wasFollowing && liveId.isNotEmpty) {
        await _refreshRaffleState(liveId, silent: true);
      }
      if (!mounted) return;
      if (!wasFollowing &&
          !hadFollowBonus &&
          _raffleState?.viewer.followBonusClaimed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A seguir — +1 rifa!')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível actualizar o seguir.')),
      );
    }
  }

  Future<void> _onShareLiveTap({bool fromRaffleSheet = false}) async {
    final liveId = widget.liveId?.trim() ?? '';
    if (liveId.isEmpty) return;

    RaffleLog.d('sidebar share tap', {
      'liveId': liveId,
      'fromSheet': fromRaffleSheet,
      'prev': _raffleState?.debugSummary ?? 'null',
    });

    final result = await LiveRaffleShare.shareLive(
      liveId: liveId,
      preferredLink: widget.sharePreferredLink,
    );
    if (!mounted) return;

    final bal = result.ticketBalance;
    if (_raffleState?.raffle != null) {
      setState(() {
        _raffleState = _raffleState!.copyWith(
          hasRaffle: true,
          raffle: _raffleState!.raffle,
          viewer: _raffleState!.viewer.copyWith(
            joined: true,
            shareBonusClaimed: result.awardedShareBonus ||
                    result.shareAlreadyClaimed
                ? true
                : _raffleState!.viewer.shareBonusClaimed,
            ticketBalance: bal != null && bal > 0
                ? bal
                : (result.awardedShareBonus
                    ? (_raffleState!.viewer.ticketBalance > 0
                        ? _raffleState!.viewer.ticketBalance + 1
                        : 2)
                    : _raffleState!.viewer.ticketBalance),
          ),
        );
      });
      RaffleLog.d('sidebar share after setState', {
        'state': _raffleState!.debugSummary,
      });
    } else {
      RaffleLog.d('sidebar share — no local raffle to update');
    }

    unawaited(_refreshRaffleState(liveId, silent: true));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    // Nunca Navigator.pop aqui — fechava o player e «sumia» a rifa.
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
      final liveId = widget.liveId?.trim() ?? '';
      if (liveId.isNotEmpty) {
        unawaited(_maybeRegisterRaffleReferralVisit(liveId));
        if (currentUserUid.isNotEmpty) {
          unawaited(LiveRaffleService.qualifyReferralVisits(liveId));
          unawaited(_refreshRaffleState(liveId, silent: true));
        }
      }
    }
  }

  @override
  void dispose() {
    if (widget.embedInHub) {
      LiveEmbedHost.unregisterOpenBag(_openLiveBagSheet);
    }
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
    final sellerStockCh = _sellerCatalogStockChannel;
    _sellerCatalogStockChannel = null;
    if (sellerStockCh != null) {
      unawaited(SupaFlow.client.removeChannel(sellerStockCh));
    }
    final buyerCh = _buyerCheckoutChannel;
    _buyerCheckoutChannel = null;
    if (buyerCh != null) {
      unawaited(SupaFlow.client.removeChannel(buyerCh));
    }
    _spotlightTimer?.cancel();
    _priceDefinedNoticeTimer?.cancel();
    _catalogActivePollTimer?.cancel();
    _catalogStockPollTimer?.cancel();
    _catalogStockRefreshDebounce?.cancel();
    _rafflePollTimer?.cancel();
    _raffleStreamSub?.cancel();
    final raffleCh = _raffleChannel;
    _raffleChannel = null;
    if (raffleCh != null) {
      unawaited(SupaFlow.client.removeChannel(raffleCh));
    }
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
      if (_chatSystemEffectsPrimed) {
        _systemHighlightMsgIds.add('tip:$id');
        Future<void>.delayed(const Duration(seconds: 4), () {
          _systemHighlightMsgIds.remove('tip:$id');
          if (mounted) setState(() {});
        });
        if (mounted) setState(() {});
      }
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
          callback: _onLiveItemRealtimeChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_items',
          filter: filter,
          callback: (_) => unawaited(_initCatalog(skipCache: true)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_item_show_events',
          filter: filter,
          callback: (payload) {
            _onCatalogShowEvent(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: filter,
          callback: (_) => _scheduleCatalogStockRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_reservation_requests',
          filter: filter,
          callback: (_) {
            final rows = _catalogRows;
            if (rows == null || rows.isEmpty) {
              unawaited(_initCatalog(skipCache: true));
              return;
            }
            _scheduleCatalogStockRefresh();
          },
        )
        .subscribe();
  }

  void _subscribeSellerCatalogStockRealtime() {
    final sellerId = _sellerId?.trim() ?? '';
    if (sellerId.isEmpty || _sellerCatalogStockChannel != null) return;
    final sellerFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'seller_id',
      value: sellerId,
    );
    void onSellerStockChange() {
      final rows = _catalogRows;
      if (rows == null || rows.isEmpty) {
        unawaited(_initCatalog(skipCache: true));
        return;
      }
      // Cross-pool: debounce full stock (seller-wide events podem ser frequentes).
      _scheduleCatalogStockRefresh();
    }

    _sellerCatalogStockChannel = SupaFlow.client
        .channel('live_catalog_seller_stock:$sellerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: sellerFilter,
          callback: (_) => onSellerStockChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_reservation_requests',
          filter: sellerFilter,
          callback: (_) => onSellerStockChange(),
        )
        .subscribe();
  }

  Future<void> _loadLiveBagCount(String liveId) async {
    if (liveId.trim().isEmpty || currentUserUid.isEmpty) {
      if (mounted) {
        setState(() {
          _liveBagCount = 0;
          _liveBagRows = const [];
          _needsFacebookLogin = false;
        });
      }
      return;
    }
    try {
      // Face/PS: liga órfãs fb: à conta antes de contar (senão badge/saco ficam a 0).
      HubPsClaimResult? claim;
      if (widget.embedInHub) {
        claim = await HubPsClaim.claimForLiveDetailed(liveId);
      }
      final sellerId = _sellerId?.trim() ?? '';
      late final List<LiveReservationRequestsRow> rows;
      late final int count;
      if (sellerId.isNotEmpty) {
        // Phase 3: badge = seller omnichannel bag (not live_id-only).
        final all = await LiveReservationQueueService().sellerBagDisplayRequests(
          sellerId: sellerId,
          buyerId: currentUserUid,
          limit: 300,
        );
        await _promoteNewAcceptedNoticesFromRows(all);
        final active = all
            .where((r) =>
                (r.status == 'pending' || r.status == 'accepted') &&
                !LiveReservationQueueService.isBuyerCancelledReservation(
                  status: r.status,
                  notes: r.notes,
                ))
            .toList();
        var units = await LiveReservationQueueService()
            .countSellerBagActiveUnits(sellerId: sellerId);
        if (units < 1) {
          units = active.fold<int>(
            0,
            (a, b) => a + (b.requestedQty < 1 ? 1 : b.requestedQty),
          );
        }
        rows = active;
        count = units;
      } else {
        final all = await LiveReservationQueueService().liveBagDisplayRequests(
          liveId: liveId,
          buyerId: currentUserUid,
          limit: 300,
        );
        await _promoteNewAcceptedNoticesFromRows(all);
        final active = all
            .where((r) =>
                r.status == 'pending' ||
                r.status == 'accepted' ||
                r.status == 'converted')
            .toList();
        count = active.fold<int>(
          0,
          (a, b) => a + (b.requestedQty < 1 ? 1 : b.requestedQty),
        );
        rows = active;
      }
      if (!mounted) return;
      setState(() {
        _liveBagCount = count;
        _liveBagRows = rows;
        if (claim != null) {
          _needsFacebookLogin = claim.needsFacebookLogin;
        }
      });
      if (claim != null && claim.claimed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              claim.claimed == 1
                  ? 'Reserva recuperada.'
                  : 'Reservas recuperadas.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      HubQaDiag.logC1(
        source: widget.embedInHub
            ? 'player_badge_hub_embed'
            : 'player_badge_native',
        liveId: liveId,
        rows: rows,
        bagBadgeCount: count,
      );
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

    if (liveId.trim().isEmpty) return;
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
      if (currentUserUid.isNotEmpty && uid.isNotEmpty && uid != currentUserUid) {
        continue;
      }
      _seenAcceptBroadcastMsgIds.add(m.id);
      if (_chatAcceptBroadcastsPrimed) {
        newAcceptForBuyer = true;
      }
    }
    if (!_chatAcceptBroadcastsPrimed) {
      _chatAcceptBroadcastsPrimed = true;
    }
    if (newAcceptForBuyer && currentUserUid.isNotEmpty) {
      unawaited(_syncBuyerAcceptedNoticesOnConnect(liveId));
    }

    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.system) continue;
      if (m.id.isEmpty || _seenPriceDefinedMsgIds.contains(m.id)) continue;
      if (!RegExp(r'preço\s+definido', caseSensitive: false).hasMatch(m.body)) {
        continue;
      }
      _seenPriceDefinedMsgIds.add(m.id);
      if (!_chatPriceBroadcastsPrimed) continue;
      final parsed = _parsePriceDefinedBody(m.body);
      if (parsed != null) _showPriceDefinedNotice(parsed);
    }
    if (!_chatPriceBroadcastsPrimed) {
      _chatPriceBroadcastsPrimed = true;
    }

    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.system) continue;
      if (m.id.isEmpty || _seenBackofficeSnackMsgIds.contains(m.id)) continue;
      final parsed = LiveSystemChatHumanizer.parse(
        m.body,
        normalizeItemLabel: _normalizeSystemChatItemLabel,
        resolveBuyerName: (raw) => _resolveChatBuyerName(raw, m.userId),
      );
      if (parsed.visibility != LiveSystemChatVisibility.backoffice) {
        if (_chatSystemEffectsPrimed &&
            parsed.kind == LiveSystemChatEventKind.raffle &&
            RegExp(r'ganhaste\s+a\s+rifa', caseSensitive: false)
                .hasMatch(m.body) &&
            (m.userId?.trim() ?? '') == currentUserUid &&
            currentUserUid.isNotEmpty &&
            _raffleWinnerCelebrationShown != true) {
          _raffleWinnerCelebrationShown = true;
          RaffleLog.d('winner celebration trigger chatDM', {
            'msgId': m.id,
            'body': m.body.length > 80 ? m.body.substring(0, 80) : m.body,
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(
              LiveRaffleWinnerCelebration.show(
                context,
                prizeTitle: _raffleState?.raffle?.title ?? 'Rifa da Live',
              ),
            );
          });
        }
        if (_chatSystemEffectsPrimed &&
            parsed.highlightDuration != null &&
            parsed.showInPublicChat) {
          _systemHighlightMsgIds.add(m.id);
          final msgId = m.id;
          final dur = parsed.highlightDuration!;
          Future<void>.delayed(dur, () {
            _systemHighlightMsgIds.remove(msgId);
            if (mounted) setState(() {});
          });
        }
        continue;
      }
      _seenBackofficeSnackMsgIds.add(m.id);
      if (!_chatSystemEffectsPrimed) continue;
      final snack = parsed.snackbarLine?.trim() ?? '';
      if (snack.isEmpty || !mounted) continue;
      final uid = m.userId?.trim() ?? '';
      final forMe = uid.isEmpty ||
          uid == currentUserUid ||
          parsed.kind == LiveSystemChatEventKind.backofficeOverStock;
      if (!forMe) continue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snack), duration: const Duration(seconds: 4)),
      );
    }
    if (!_chatSystemEffectsPrimed) {
      _chatSystemEffectsPrimed = true;
    } else if (mounted) {
      setState(() {});
    }
  }

  Set<String> _visibleSystemMessageIds(List<LiveRoomMessage> msgs) {
    final seenSocialKeys = <String>{};
    final out = <String>{};
    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.system) continue;
      final id = m.id.trim();
      if (id.isEmpty) continue;
      if (LivePublicChatSystemLine.shouldRenderSystemMessage(
        m.body,
        seenSocialKeys: seenSocialKeys,
        normalizeItemLabel: _normalizeSystemChatItemLabel,
        resolveBuyerName: (raw) => _resolveChatBuyerName(raw, m.userId),
      )) {
        out.add(id);
      }
    }
    return out;
  }

  bool _shouldAnimateSystemHighlight(String messageId) {
    final id = messageId.trim();
    return id.isNotEmpty && _systemHighlightMsgIds.contains(id);
  }

  bool _shouldAnimateTipHighlight(String? tipId) {
    final id = tipId?.trim() ?? '';
    return id.isNotEmpty && _systemHighlightMsgIds.contains('tip:$id');
  }

  _PriceDefinedBroadcastNotice? _parsePriceDefinedBody(String body) {
    final match = RegExp(
      r'Preço definido\s*·\s*(.+?)\s*·\s*([\d.,]+)\s*€',
      caseSensitive: false,
    ).firstMatch(body.trim());
    if (match == null) return null;
    final rawLabel = match.group(1)!.trim();
    final label = _normalizeSystemChatItemLabel(rawLabel) ?? rawLabel;
    return _PriceDefinedBroadcastNotice(
      itemLabel: label,
      priceLabel: '${match.group(2)!.trim()} €',
    );
  }

  void _dismissPriceDefinedNotice() {
    _priceDefinedNoticeTimer?.cancel();
    if (!mounted) return;
    setState(() => _priceDefinedNotice = null);
  }

  void _showPriceDefinedNotice(_PriceDefinedBroadcastNotice notice) {
    _priceDefinedNoticeTimer?.cancel();
    if (!mounted) return;
    setState(() => _priceDefinedNotice = notice);
    _priceDefinedNoticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _priceDefinedNotice = null);
    });
  }

  Widget _buildPriceDefinedBroadcastCard(
    _PriceDefinedBroadcastNotice notice,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
        children: [
          const Icon(
            Icons.euro_rounded,
            color: Color(0xFF4CAF50),
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Já tem preço',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${notice.itemLabel} — ${notice.priceLabel}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _dismissPriceDefinedNotice,
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.65),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
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
    final itemRow = notice.liveItemId?.trim().isNotEmpty == true
        ? _catalogRowById(notice.liveItemId)
        : null;
    final hasPayablePrice = LiveItemPriceGate.hasPayableUnitPrice(
      liveItemPrice: itemRow?.price,
    );
    final bannerTitle = hasPayablePrice
        ? LiveItemPriceGate.acceptedPlayerBannerPayTitle(notice.title)
        : LiveItemPriceGate.acceptedPlayerBannerTitle(notice.title);
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
                    bannerTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (notice.qty > 1)
                    Text(
                      '${notice.qty} unidades',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (hasPayablePrice)
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
    final stockSnap = itemId != null && itemId.isNotEmpty
        ? _catalogStockByItemId[itemId]
        : null;
    final reservationsQty = _reservationsCountFromStock(stockSnap);

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
                            height: 64,
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
                        if (LiveCatalogItemAttributes.subtitle(
                              clothingSize: row.clothingSize,
                              color: row.gender,
                            ) !=
                            null) ...[
                          const SizedBox(height: 2),
                          Text(
                            LiveCatalogItemAttributes.subtitle(
                              clothingSize: row.clothingSize,
                              color: row.gender,
                            )!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              color: Colors.white.withValues(alpha: 0.68),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                        if (reservationsQty > 0) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Reservas: $reservationsQty',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ],
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

  static Widget _placeholderImage({bool light = false, bool labeled = false}) {
    final bg = light ? const Color(0xFFE8EEF1) : Colors.white.withValues(alpha: 0.08);
    final fg = light ? const Color(0xFF57636C) : Colors.white.withValues(alpha: 0.45);
    return ColoredBox(
      color: bg,
      child: Center(
        child: labeled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 22, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    'Sem fotografia',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: fg,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Icon(Icons.image_outlined, size: 28, color: fg),
      ),
    );
  }

  static Widget _refPlaceholder(String _) {
    // Sem foto: ícone neutro — NÃO mostrar «#RRR1» a ocupar o sítio do título
    // (a ref já aparece na linha de texto por baixo).
    return _placeholderImage();
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
        backgroundColor:
            widget.hubExternalChat ? const Color(0xFF101518) : Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final externalProducts = widget.hubExternalProducts;

            // Cards sempre no fundo; chat/input fixos por cima da faixa dos cards.
            // B2 desktop: catálogo na coluna esquerda — sem ocupar fundo do vídeo.
            final baseBottom = bottomPad + 8;
            final collapsedCatalogBarH =
                (!externalProducts && _catalogMinimized) ? 38.0 : 0.0;
            final catalogStripBottom = baseBottom + collapsedCatalogBarH;
            final catalogStripH =
                externalProducts ? 0.0 : _kCarouselStripH;
            final chatInputBottom = baseBottom + catalogStripH;
            final chatPanelBottom = chatInputBottom +
                (_showChatInput ? _kInputBandH + _kChatGapAboveInput : 0);
            final vodControlsTopInset = _hideDuplicatePlayerHeader
                ? topPad + 12
                : topPad + 78;

            // Com cards minimizados: spotlight e barra lateral descem para a faixa do carrossel.
            final sidebarBottom = (!externalProducts && _catalogMinimized)
                ? catalogStripBottom + 2
                : chatInputBottom + 8;
            final spotlightBottom = catalogStripBottom;
            final stack = Stack(
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
                            if (!mounted) return;
                            final rowStillLive = _liveRow != null &&
                                !_liveIsEnded(_liveRow!);
                            // Race: Future completa antes da row → tratar
                            // hint isLive / embed Lab como «ainda ao vivo».
                            final assumeStillLive = rowStillLive ||
                                (_liveRow == null &&
                                    widget.isLive != false &&
                                    _playbackIsLive);
                            // Bloquear salto UI directo→gravado enquanto a live
                            // continua activa na BD (Mux/resolve mentiroso).
                            if (!source.isLive && assumeStillLive) {
                              RaffleLog.d('playback isLive flip BLOCKED', {
                                'wasLive': _playbackIsLive,
                                'sourceLive': source.isLive,
                                'liveStatus': _liveRow?.status ?? '-',
                                'isActive': _liveRow?.isActive,
                                'rowNull': _liveRow == null,
                                'embedHub': widget.embedInHub,
                              });
                              HubPlayerDiag.logUi(
                                liveId: widget.liveId,
                                state: 'playback_flip_blocked',
                                reason: rowStillLive
                                    ? 'source_vod_row_still_live'
                                    : 'source_vod_row_pending_hint_live',
                              );
                              return;
                            }
                            setState(() {
                              final wasLive = _playbackIsLive;
                              _playbackIsLive = source.isLive;
                              RaffleLog.d('playback isLive flip', {
                                'wasLive': wasLive,
                                'nowLive': source.isLive,
                                'urlEmpty': source.url.isEmpty,
                                'liveStatus': _liveRow?.status ?? '-',
                                'embedHub': widget.embedInHub,
                              });
                              if (!source.isLive) {
                                _privateChatMode = false;
                                _resetChatPlaybackSync();
                                unawaited(_liveRoom?.refreshMessages());
                                _syncVodCatalogHighlight(force: true);
                              } else if (!wasLive && source.isLive) {
                                _resetChatPlaybackSync();
                                _ensureLiveClock();
                              }
                              _logHeaderBadgeOnce();
                            });
                            _ensureLiveClock();
                          });
                        }
                        if (path.isEmpty) {
                          HubPlayerDiag.logUi(
                            liveId: widget.liveId,
                            state: source?.isLive == false
                                ? 'waiting_vod'
                                : 'waiting_live_signal',
                            reason: 'future_builder_empty_url',
                          );
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
                          isLive: (_liveRow != null && !_liveIsEnded(_liveRow!))
                              ? true
                              : (source?.isLive ?? _playbackIsLive),
                          thumbnailUrl: source?.thumbnailUrl,
                          vodControlsAtTop: !(_liveRow != null &&
                                  !_liveIsEnded(_liveRow!)) &&
                              !(source?.isLive ?? false),
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
                // Desktop Hub: oculto (chrome externo) — mobile/standalone intacto.
                if (!_hideDuplicatePlayerHeader)
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
                                    onTap: _sellerId == currentUserUid
                                        ? null
                                        : () => unawaited(_toggleFollowSeller()),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      child: Text(
                                        _isFollowingSeller == true
                                            ? 'A seguir'
                                            : 'Seguir',
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
                                if (_headerBadgeInfo().label == 'AO VIVO') ...[
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
                                          'AO VIVO',
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
                                ] else if (_headerBadgeInfo().label == 'GRAVADO') ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF007782),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'GRAVADO',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ] else if (_headerBadgeInfo().label ==
                                    'GRAVAÇÃO A PREPARAR') ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Text(
                                      'GRAVAÇÃO A PREPARAR',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
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
                                if (!widget.embedInHub || widget.showEmbedClose) ...[
                                  const SizedBox(width: 8),
                                  _glassIconButton(
                                    icon: Icons.close_rounded,
                                    onTap: _closePlayer,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Barra lateral — encostada ao carrossel (sem sobrepor cards).
                // H03 desktop: hubHideOverlaySideActions → só rifa se activa.
                if (!widget.hubHideOverlaySideActions ||
                    _raffleState?.hasRaffle == true)
                Positioned(
                  right: 10,
                  bottom: sidebarBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.hubHideOverlaySideActions) ...[
                        _glassCircleIcon(
                          icon: Icons.share_outlined,
                          onTap: () => unawaited(_onShareLiveTap()),
                          style: _LiveActionStyle.secondary,
                        ),
                        if (_raffleState?.hasRaffle == true) ...[
                          const SizedBox(height: 12),
                          LiveRaffleSidebarButton(
                            state: _raffleState!,
                            loading: _raffleJoinLoading,
                            onTap: () => unawaited(_onRaffleTap()),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _glassCircleIcon(
                          icon: Icons.euro_rounded,
                          onTap: _openTipSheet,
                          style: _LiveActionStyle.monetization,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (widget.embedInHub &&
                                widget.hubShowBagReservationHint) ...[
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 118),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _kLiveAccent.withValues(
                                          alpha: 0.65),
                                    ),
                                  ),
                                  child: Text(
                                    'Vê as tuas reservas no saco',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _liveBagCount > 99
                                            ? '99+'
                                            : '$_liveBagCount',
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
                          ],
                        ),
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
                      ] else if (_raffleState?.hasRaffle == true)
                        LiveRaffleSidebarButton(
                          state: _raffleState!,
                          loading: _raffleJoinLoading,
                          onTap: () => unawaited(_onRaffleTap()),
                        ),
                    ],
                  ),
                ),

                if (_showCatalogOverlay &&
                    _catalogMinimized &&
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

                if (_showCatalogOverlay && _catalogMinimized)
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

                if (_showCatalogOverlay && !_catalogMinimized)
                        Positioned(
                    left: 12,
                    right: 12,
                    bottom: catalogStripBottom,
                          height: _kCarouselStripH,
                    child: ClipRect(
                          child: _catalogStripLoading
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white70,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'A carregar artigos...',
                                        style: GoogleFonts.inter(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
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

                if (_priceDefinedNotice != null ||
                    _buyerAcceptedNotices.isNotEmpty)
                        Positioned(
                    left: 12,
                    right: 72,
                    bottom: chatPanelBottom + _kChatH + 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_priceDefinedNotice != null)
                          _buildPriceDefinedBroadcastCard(
                            _priceDefinedNotice!,
                          ),
                        for (final notice
                            in _buyerAcceptedNotices.take(2))
                          _buildBuyerAcceptedReservationCard(notice),
                      ],
                    ),
                  ),

                if (_showChatOverlay && _showChatInput)
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

                if (_showChatOverlay)
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

            final desktopShell =
                widget.hubExternalChat || widget.hubExternalProducts;
            if (!desktopShell) return stack;

            // H03 desktop — grelha flex contínua:
            // produtos | vídeo 9:16 | rail | chat | [marketplace trailing].
            const gap = 6.0;
            final actionsW =
                widget.hubHideOverlaySideActions ? 48.0 : 0.0;
            final productsMin = HubTheme.liveDesktopProductsMinWidth;
            final chatMin = HubTheme.liveDesktopChatMinWidth;
            final mpMin = HubTheme.liveDesktopMarketplaceMinWidth;
            final hasTrailing = widget.hubTrailing != null;
            final shellBg = widget.hubLightShell
                ? const Color(0xFFF0F4F6)
                : const Color(0xFF101518);
            return ColoredBox(
              color: shellBg,
              child: LayoutBuilder(
                builder: (context, shellBox) {
                  final maxH = shellBox.maxHeight;
                  final maxShellW = shellBox.maxWidth;
                  final padX = 2.0;
                  final fixedSides = actionsW +
                      (widget.hubExternalProducts ? gap : 0) +
                      (widget.hubExternalChat ? gap : 0) +
                      (widget.hubHideOverlaySideActions ? gap : 0) +
                      (hasTrailing ? gap : 0) +
                      padX * 2 +
                      (widget.hubExternalProducts ? productsMin : 0) +
                      (widget.hubExternalChat ? chatMin : 0) +
                      (hasTrailing ? mpMin : 0);
                  var videoH = maxH - 6;
                  var videoW = videoH * 9 / 16;
                  final availForVideo = maxShellW - fixedSides;
                  if (videoW > availForVideo && availForVideo > 140) {
                    videoW = availForVideo;
                    videoH = videoW * 16 / 9;
                  }
                  // Formatos intermédios: cap no vídeo para o surplus ir a
                  // produtos/chat (evita faixa vazia / MP a absorver tudo).
                  final videoCapFrac = maxShellW < 1200
                      ? 0.26
                      : (maxShellW < 1500 ? 0.30 : 0.34);
                  final videoCap = maxShellW * videoCapFrac;
                  if (videoW > videoCap && videoCap > 160) {
                    videoW = videoCap;
                    videoH = videoW * 16 / 9;
                    if (videoH > maxH - 6) {
                      videoH = maxH - 6;
                      videoW = videoH * 9 / 16;
                    }
                  }
                  final colH =
                      math.min(maxH - 4, math.max(videoH, 360)).toDouble();
                  return Padding(
                    padding: EdgeInsets.fromLTRB(padX, 2, padX, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.hubExternalProducts) ...[
                          Expanded(
                            flex:
                                (HubTheme.liveDesktopProductsFlex * 100).round(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: productsMin),
                              child: _buildHubExternalProductsColumn(),
                            ),
                          ),
                          const SizedBox(width: gap),
                        ],
                        SizedBox(
                          width: videoW,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: videoW,
                              height: videoH,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: stack,
                              ),
                            ),
                          ),
                        ),
                        if (widget.hubHideOverlaySideActions) ...[
                          const SizedBox(width: gap),
                          SizedBox(
                            width: actionsW,
                            height: colH,
                            child: _buildHubExternalActionRail(),
                          ),
                        ],
                        if (widget.hubExternalChat) ...[
                          const SizedBox(width: gap),
                          Expanded(
                            flex: (HubTheme.liveDesktopChatFlex * 100).round(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: chatMin),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildHubExternalChatColumn(),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildHubExternalBagPanel(),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (hasTrailing) ...[
                          const SizedBox(width: gap),
                          Expanded(
                            flex: (HubTheme.liveDesktopMarketplaceFlex * 100)
                                .round(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: mpMin),
                              child: widget.hubTrailing!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Color get _hubColBg =>
      widget.hubLightShell ? Colors.white : const Color(0xFF1A2228);
  Color get _hubColBorder => widget.hubLightShell
      ? const Color(0xFFD5DDE3)
      : Colors.white.withValues(alpha: 0.09);
  Color get _hubColTitle =>
      widget.hubLightShell ? const Color(0xFF101518) : Colors.white;
  Color get _hubColMuted => widget.hubLightShell
      ? const Color(0xFF57636C)
      : Colors.white.withValues(alpha: 0.45);

  /// Ações do player fora do frame de vídeo (H03 desktop).
  /// Partilha, propina (só live), saco, chat privado (só live), rifa se activa.
  Widget _buildHubExternalActionRail() {
    final light = widget.hubLightShell;
    final isLive = widget.isLive == true || _showChatInput;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hubColBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hubColBorder),
        boxShadow: light
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            _hubActionRailIcon(
              icon: Icons.share_outlined,
              tooltip: 'Partilhar',
              onTap: () => unawaited(_onShareLiveTap()),
            ),
            const SizedBox(height: 10),
            _hubActionRailIcon(
              icon: Icons.euro_rounded,
              tooltip: 'Apoiar / Gorjeta',
              accent: true,
              onTap: _openTipSheet,
            ),
            const SizedBox(height: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _hubActionRailIcon(
                  icon: Icons.shopping_bag_outlined,
                  tooltip: 'Saco',
                  accent: true,
                  onTap: () => unawaited(_openLiveBagSheet()),
                ),
                if (_liveBagCount > 0)
                  Positioned(
                    right: 2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
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
            if (_sellerId != null &&
                _sellerId!.isNotEmpty &&
                _sellerId != currentUserUid) ...[
              const SizedBox(height: 10),
              _hubActionRailIcon(
                icon: Icons.favorite_border_rounded,
                tooltip: 'Favorito',
                onTap: () {
                  // Mesmo stub do overlay original — sem lógica paralela.
                },
              ),
            ],
            if (isLive && _showChatInput) ...[
              const SizedBox(height: 10),
              _hubActionRailIcon(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: _privateChatMode
                    ? 'Chat privado activo'
                    : 'Chat privado',
                selected: _privateChatMode,
                onTap: () {
                  setState(() => _privateChatMode = !_privateChatMode);
                  if (_privateChatMode) _ensurePrivateRoom();
                },
              ),
            ],
            if (_raffleState?.hasRaffle == true) ...[
              const SizedBox(height: 10),
              LiveRaffleSidebarButton(
                state: _raffleState!,
                loading: _raffleJoinLoading,
                onTap: () => unawaited(_onRaffleTap()),
              ),
            ],
            const Spacer(),
            if (_showCatalogOverlay) ...[
              _hubActionRailIcon(
                icon: _catalogMinimized
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                tooltip: _catalogMinimized
                    ? 'Mostrar artigos'
                    : 'Minimizar artigos',
                onTap: _toggleCatalogMinimized,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hubActionRailIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool accent = false,
    bool selected = false,
  }) {
    final light = widget.hubLightShell;
    final bg = selected
        ? const Color(0xFF007782).withValues(alpha: 0.18)
        : (light ? const Color(0xFFF0F4F6) : Colors.white.withValues(alpha: 0.08));
    final fg = accent || selected
        ? const Color(0xFF007782)
        : (light ? const Color(0xFF101518) : Colors.white);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }

  /// Coluna produtos Hub B2 — reutiliza catálogo / stock / `_onReservarItem`.
  Widget _buildHubExternalProductsColumn() {
    final featured = _featuredCatalogRow;
    final rows = _catalogRows;
    final others = (rows == null || featured == null)
        ? const <LiveItemsRow>[]
        : rows
            .where((r) => (r.id?.trim() ?? '') != (featured.id?.trim() ?? ''))
            .toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hubColBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hubColBorder),
        boxShadow: widget.hubLightShell
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(
              'Produtos desta live',
              style: GoogleFonts.inter(
                color: _hubColTitle,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(height: 1, color: _hubColBorder),
          if (_catalogStripLoading)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.hubLightShell
                          ? const Color(0xFF007782)
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            )
          else if (rows == null || rows.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Sem artigos nesta live',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: _hubColMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: _buildHubFeaturedProductCard(featured!),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(
                'Nesta live',
                style: GoogleFonts.inter(
                  color: _hubColMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: others.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Text(
                        'Só este artigo nesta live',
                        style: GoogleFonts.inter(
                          color: _hubColMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: others.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _buildHubCompactProductTile(others[i]),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHubFeaturedProductCard(LiveItemsRow row) {
    final unavailable = _isCatalogRowUnavailable(row);
    final badge = unavailable
        ? _catalogUnavailableBadge(row)
        : (_isCatalogRowActive(row) ? 'A mostrar' : null);
    final titleLine = _catalogTitleLine(row);
    final price = _formatPriceEur(row);
    final photo = _photoUrlForCatalogRow(row);
    final hasPhoto = photo.isNotEmpty;
    final itemId = row.id;
    final stockSnap = itemId != null && itemId.isNotEmpty
        ? _catalogStockByItemId[itemId]
        : null;
    final reservationsQty = _reservationsCountFromStock(stockSnap);
    final light = widget.hubLightShell;

    return Material(
      color: light ? const Color(0xFFF0F4F6) : const Color(0xFF232B32),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openItemActionsModal(row),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  // Sem foto: bloco baixo com rótulo — evita cinzento alto vazio.
                  aspectRatio: hasPhoto ? 1.15 : 2.4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasPhoto
                          ? BatataCachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              placeholderColor: light
                                  ? const Color(0xFFE8EEF1)
                                  : const Color(0xFF222222),
                              errorWidget: _placeholderImage(
                                light: light,
                                labeled: true,
                              ),
                            )
                          : _placeholderImage(light: light, labeled: true),
                      if (unavailable)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.42),
                        ),
                      if (SellerProfessionalCache.showBadge(_sellerId))
                        const Positioned(
                          left: 6,
                          top: 6,
                          child: ProfessionalSellerBadge(compact: true),
                        ),
                    ],
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 8),
                Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: unavailable ? _kSoldBadge : _kLiveAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                titleLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: light ? _hubColTitle : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (price != null) ...[
                const SizedBox(height: 4),
                Text(
                  price,
                  style: GoogleFonts.interTight(
                    color: const Color(0xFF007782),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              if (reservationsQty > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Reservas: $reservationsQty',
                  style: GoogleFonts.inter(
                    color: light
                        ? _hubColMuted
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FleaberPrimaryButton(
                label: 'Reservar',
                height: 40,
                borderRadius: 12,
                fontSize: 13,
                onPressed: () => _onReservarItem(itemId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubCompactProductTile(LiveItemsRow row) {
    final unavailable = _isCatalogRowUnavailable(row);
    final active = _isCatalogRowActive(row) && !unavailable;
    final titleLine = _catalogTitleLine(row);
    final price = _formatPriceEur(row);
    final photo = _photoUrlForCatalogRow(row);
    final light = widget.hubLightShell;

    return Material(
      color: light
          ? const Color(0xFFF0F4F6)
          : Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openItemActionsModal(row),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? _kLiveAccent
                  : unavailable
                      ? _kSoldBadge.withValues(alpha: 0.7)
                      : (light
                          ? _hubColBorder
                          : Colors.white.withValues(alpha: 0.08)),
              width: active || unavailable ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo.isNotEmpty
                          ? BatataCachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              placeholderColor: light
                                  ? const Color(0xFFE8EEF1)
                                  : const Color(0xFF222222),
                              errorWidget: _placeholderImage(light: light),
                            )
                          : _placeholderImage(light: light, labeled: true),
                      if (unavailable)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.42),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: light
                            ? _hubColTitle
                            : Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        price,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF007782),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Coluna chat Hub B1 — reutiliza `_buildChatOverlay` + input/send existentes.
  Widget _buildHubExternalChatColumn() {
    final liveLabel = _showChatInput ? 'Ao vivo' : 'Gravado';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hubColBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hubColBorder),
        boxShadow: widget.hubLightShell
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Text(
                  'Chat',
                  style: GoogleFonts.inter(
                    color: _hubColTitle,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  liveLabel,
                  style: GoogleFonts.inter(
                    color: _hubColMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _hubColBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: _chatPanelShell(child: _buildChatOverlay()),
            ),
          ),
          Container(height: 1, color: _hubColBorder),
          if (_showChatInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.hubLightShell
                            ? const Color(0xFFF0F4F6)
                            : Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.hubLightShell
                              ? _hubColBorder
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: TextField(
                        controller: _model.chatTextController,
                        focusNode: _model.chatFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendChatMessage(),
                        style: GoogleFonts.inter(
                          color: widget.hubLightShell
                              ? _hubColTitle
                              : Colors.white,
                          fontSize: 12,
                          height: 1.2,
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
                            color: widget.hubLightShell
                                ? _hubColMuted
                                : Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF007782),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => unawaited(_sendChatMessage()),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          'Enviar',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                'Chat só de leitura neste gravado.',
                style: GoogleFonts.inter(
                  color: widget.hubLightShell
                      ? _hubColMuted
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Painel sob o chat — Reservas Facebook + Saco (uma moldura, duas secções).
  Widget _buildHubExternalBagPanel() {
    final loggedIn = currentUserUid.isNotEmpty;
    final summary = HubReservationSummary.fromRows(_liveBagRows);
    final fbKind = !loggedIn
        ? HubFacebookReservationsEntryKind.guest
        : (_needsFacebookLogin
            ? HubFacebookReservationsEntryKind.needsFacebookLogin
            : HubFacebookReservationsEntryKind.openBag);
    final light = widget.hubLightShell;
    final titleFg = light ? const Color(0xFF101518) : Colors.white;
    final bodyFg = light
        ? const Color(0xFF57636C)
        : Colors.white.withValues(alpha: 0.7);
    final bagState = !loggedIn
        ? 'Inicia sessão para ver o saco.'
        : (summary.hasAny
            ? (summary.hubCardSubline.isNotEmpty
                ? summary.hubCardSubline
                : '$_liveBagCount artigo(s) nesta live.')
            : 'Ainda sem artigos nesta live.');

    Widget section({
      required String title,
      required String body,
      required String cta,
      required VoidCallback? onTap,
      bool loading = false,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: titleFg,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.inter(
              color: bodyFg,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          FleaberPrimaryButton(
            label: cta,
            height: 36,
            borderRadius: 12,
            fontSize: 13,
            loading: loading,
            onPressed: loading ? null : onTap,
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hubColBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hubColBorder),
        boxShadow: light
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            section(
              title: 'Compraste num direto do Facebook?',
              body: fbKind == HubFacebookReservationsEntryKind.needsFacebookLogin
                  ? 'Continua com Facebook para recuperar as tuas reservas.'
                  : 'Consulta os artigos que reservaste e termina a tua compra.',
              cta: fbKind == HubFacebookReservationsEntryKind.needsFacebookLogin
                  ? 'Continuar com Facebook'
                  : 'Ver reservas',
              loading: _facebookContinueBusy,
              onTap: () {
                if (fbKind ==
                    HubFacebookReservationsEntryKind.needsFacebookLogin) {
                  unawaited(_continueWithFacebookFromBag());
                } else {
                  unawaited(_openLiveBagSheet());
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: _hubColBorder),
            ),
            section(
              title: 'O teu saco',
              body: bagState,
              cta: summary.hasUrgentAction
                  ? summary.hubCardCta
                  : 'Abrir saco',
              onTap: () => unawaited(_openLiveBagSheet()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubBagPreviewRow(LiveReservationRequestsRow r) {
    final itemId = r.liveItemId?.trim() ?? '';
    final catalog = _catalogRowById(itemId);
    final title = catalog == null ? 'Artigo' : _catalogTitleLine(catalog);
    final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
    // Copy real Phase 3 buyer states — mesma semântica do LiveBagSheet.
    final bagLabel = LiveReservationQueueService.buyerBagStatusLabel(
      r.status ?? '',
      notes: r.notes,
      requestKind: r.requestKind,
      expiresAt: r.expiresAt,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            qty > 1 ? '$title · ×$qty' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: widget.hubLightShell
                  ? _hubColTitle
                  : Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: bagLabel.isNotEmpty
                ? Text(
                    bagLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.inter(
                      color: widget.hubLightShell
                          ? _hubColMuted
                          : Colors.white.withValues(alpha: 0.65),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : HubReservationStatusUi.statusChip(
                    r.status ?? '',
                    notes: r.notes,
                    queuePosition: r.queuePosition,
                  ),
          ),
        ),
      ],
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
          color: widget.hubLightShell
              ? const Color(0xFF57636C)
              : Colors.white.withValues(alpha: 0.55),
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
                  onLightBackground: widget.hubLightShell,
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
        _ensureUserNamesResolved(msgs);
        final visibleSystemIds = _visibleSystemMessageIds(msgs);
        return _buildReversedChatList(
          itemCount: msgs.length,
          enableOlderLoad: !_isVodReplay,
          itemBuilder: (context, index) {
            final m = msgs[index];
            if (m.kind == LiveRoomMessageKind.tip) {
              return LiveTipGiftBubble(
                amountEur: m.tipAmountEur ?? 0,
                animateHighlight: _shouldAnimateTipHighlight(m.tipId),
              );
            }
            if (m.kind == LiveRoomMessageKind.system) {
              if (!visibleSystemIds.contains(m.id)) {
                return const SizedBox.shrink();
              }
              return LivePublicChatSystemLine.fromBody(
                m.body,
                normalizeItemLabel: _normalizeSystemChatItemLabel,
                resolveBuyerName: (raw) =>
                    _resolveChatBuyerName(raw, m.userId),
                animateHighlight: _shouldAnimateSystemHighlight(m.id),
                onLightBackground: widget.hubLightShell,
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
              fromFacebook: m.isFromFacebook,
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
    bool fromFacebook = false,
  }) {
    return LivePublicChatHumanRow(
      label: user,
      text: text,
      userId: userId,
      photoUrl: photoUrl,
      isSeller: isSeller,
      fromFacebook: fromFacebook,
      onLightBackground: widget.hubLightShell,
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
      onLightBackground: widget.hubLightShell,
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

class _PriceDefinedBroadcastNotice {
  const _PriceDefinedBroadcastNotice({
    required this.itemLabel,
    required this.priceLabel,
  });

  final String itemLabel;
  final String priceLabel;
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
