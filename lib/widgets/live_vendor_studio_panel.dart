import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/utils/live_private_room_service.dart';
import '/utils/live_room_service.dart';
import '/utils/live_system_chat_humanizer.dart';
import '/widgets/live_public_chat_line.dart';
import '/widgets/live_tip_gift_bubble.dart';
import '/widgets/live_vendor_catalog_card.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/profile_avatar.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';
import '/utils/live_ref_scheme.dart';
import '/utils/clothing_option_lists.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_catalog_sync.dart';
import '/utils/live_raffle_service.dart';
import '/utils/raffle_log.dart';
import '/utils/ps_ingest_service.dart';
import '/widgets/live_raffle_seller_sheet.dart';
import '/widgets/live_raffle_seller_ops_bar.dart';
import '/hub/hub_urls.dart';
import '/hub/seller/hub_seller_service.dart';
import '/hub/seller/hub_seller_sheet.dart';
import '/utils/live_item_price_gate.dart';
import '/utils/maestro_studio_debug_log.dart';
import '/widgets/live_ref_chip_editor_sheet.dart';
import '/utils/live_fomo_broadcaster.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_snack.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fee_calculator.dart';
import '/utils/live_in_stream_checkout.dart';
import '/utils/live_catalog_item_attributes.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/widgets/fleaber_primary_button.dart';
import '/batata_reservation_actions.dart';
import '/live_amazon/live_amazon_live_bridge.dart';
import '/live_amazon/live_amazon_present_overlay.dart';
import '/live_amazon/live_amazon_scan_sheet.dart';
import '/utils/seller_commerce_trust_actions.dart';
import '/utils/seller_reservation_policy_service.dart';

enum _VendorChatFilter { all, questions, reservations, system }

enum _ReservationListCategory { inBag, pending, accepted, external, unpaid }

/// Mesmos tokens do input de chat do [FleaberLivePlayerWidget].
const Color _kVendorLiveChatAccent = Color(0xFF00A3AD);
const double _kVendorLiveChatGlass = 0.58;
const double _kVendorLiveChatInputH = 30;

/// Barra superior do vendedor em directo (LIVE + espectadores), alinhada ao viewer.
/// Botão circular na barra lateral direita (público ↔ privado), como no viewer.
class LiveVendorSidebarChatButton extends StatelessWidget {
  const LiveVendorSidebarChatButton({
    super.key,
    required this.selected,
    required this.onTap,
    this.unreadCount = 0,
  });

  final bool selected;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: selected
              ? FleaberColors.teal.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.68),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                selected
                    ? Icons.lock_outline_rounded
                    : Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: FleaberColors.teal,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LiveVendorBroadcastHeader extends StatefulWidget {
  const LiveVendorBroadcastHeader({
    super.key,
    required this.liveId,
    required this.sellerId,
    this.startedAt,
    this.leading,
    this.title,
  });

  final String liveId;
  final String sellerId;
  final DateTime? startedAt;
  final Widget? leading;
  final String? title;

  @override
  State<LiveVendorBroadcastHeader> createState() =>
      _LiveVendorBroadcastHeaderState();
}

class _LiveVendorBroadcastHeaderState extends State<LiveVendorBroadcastHeader> {
  LiveRoomService? _room;
  Timer? _durationTimer;
  String _durationLabel = '00:00';

  @override
  void initState() {
    super.initState();
    final id = widget.liveId.trim();
    if (id.isEmpty) return;
    _room = LiveRoomService(id);
    unawaited(_room!.start());
    _tickDuration();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickDuration();
    });
  }

  void _tickDuration() {
    final start = widget.startedAt;
    if (start == null) return;
    final sec = DateTime.now().difference(start).inSeconds.clamp(0, 999999);
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    final label = '$m:$s';
    if (label != _durationLabel && mounted) {
      setState(() => _durationLabel = label);
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    final pub = _room;
    _room = null;
    if (pub != null) unawaited(pub.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();

    final title = widget.title?.trim() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: 2),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: FleaberColors.danger.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.6,
            ),
          ),
          child: Text(
            'LIVE',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _durationLabel,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.95),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            shadows: const [
              Shadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
        ),
        if (title.isNotEmpty) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.96),
                fontWeight: FontWeight.w700,
                fontSize: 13,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (title.isEmpty) const Spacer(),
        StreamBuilder<int>(
          stream: room.viewerCountStream,
          initialData: room.viewerCount,
          builder: (context, snap) {
            final count = snap.data ?? 0;
            if (count < 5) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.white.withValues(alpha: 0.88),
                  size: 15,
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Painel do vendedor durante o directo (inspirado no Whatnot: stats + chat + privados).
class LiveVendorStudioPanel extends StatefulWidget {
  const LiveVendorStudioPanel({
    super.key,
    required this.liveId,
    required this.sellerId,
    this.startedAt,
    this.catalogItemCount = 0,
    this.hideTopChrome = false,
    this.viewerStyleLayout = false,
    this.privateChatMode = false,
    this.onPrivateChatModeChanged,
    this.onPrivateUnreadChanged,
    this.onOpsTotalsChanged,
    this.activePanel = SellerLiveActivePanel.none,
    this.onActivePanelChanged,
    this.sellerOverlayLayout = false,
    this.showTopNav = false,
    this.onMoreTap,
    this.modalHostContext,
    this.onModalVisibilityChanged,
  });

  final String liveId;
  final String sellerId;
  final DateTime? startedAt;
  final int catalogItemCount;
  /// Quando true, o LIVE/espectadores vive no topo do ecrã (fora deste painel).
  final bool hideTopChrome;
  /// Chat acima dos cards (como no viewer).
  final bool viewerStyleLayout;
  final bool privateChatMode;
  final ValueChanged<bool>? onPrivateChatModeChanged;
  final ValueChanged<int>? onPrivateUnreadChanged;
  final ValueChanged<LiveOpsTotals>? onOpsTotalsChanged;
  final SellerLiveActivePanel activePanel;
  final ValueChanged<SellerLiveActivePanel>? onActivePanelChanged;
  /// Layout em overlay: nav no topo, produto+acções no fundo, vídeo no centro.
  final bool sellerOverlayLayout;
  final bool showTopNav;
  final VoidCallback? onMoreTap;
  /// Contexto estável para modais (ex.: harness Maestro).
  final BuildContext? modalHostContext;
  final ValueChanged<bool>? onModalVisibilityChanged;

  @override
  State<LiveVendorStudioPanel> createState() => LiveVendorStudioPanelState();
}

class LiveVendorStudioPanelState extends State<LiveVendorStudioPanel> {
  LiveRoomService? _publicRoom;
  LivePrivateRoomService? _privateRoom;
  Map<String, String> _tipContributors = {};
  List<LiveItemsRow>? _catalogRows;
  bool _catalogLoading = true;
  Map<String, LiveRefChipDetail> _prepRefDetails = {};
  Map<String, ProductsRow> _productByNormRef = {};
  _VendorChatFilter _filter = _VendorChatFilter.all;
  Timer? _durationTimer;
  String _durationLabel = '00:00';
  int _privateUnread = 0;
  int _publicChatUnread = 0;
  DateTime _publicChatReadAt = DateTime.now().toUtc();
  final TextEditingController _publicReplyController = TextEditingController();
  bool _sendingPublicReply = false;
  List<LiveReservationRequestsRow> _reservationQueue = const [];
  bool _reservationLoading = true;
  int _opsActionsLastHour = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _reservationRealtimeSub;
  StreamSubscription<List<Map<String, dynamic>>>? _sellerReservationRealtimeSub;
  Timer? _reservationPollTimer;
  Timer? _catalogStockPollTimer;
  /// Coalesce refreshes stock completos (realtime + poll).
  Timer? _stockRefreshDebounce;
  bool _stockRefreshAllPending = false;
  final Set<String> _pendingStockItemIds = <String>{};
  final Set<String> _dismissedUrgentRequestIds = {};
  StreamSubscription<List<Map<String, dynamic>>>? _catalogRealtimeSub;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersRealtimeSub;
  StreamSubscription<List<Map<String, dynamic>>>? _tipsRealtimeSub;
  int _livePaidOrdersCount = 0;
  double _livePaidOrdersValueEur = 0;
  int _liveTipsCount = 0;
  double _liveTipsValueEur = 0;
  List<({String buyerLabel, double amountEur})> _liveTipPayments = const [];
  double _lastWalletLogTotalEur = -1;
  /// Chaves `liveItemId|buyerId` de encomendas `aguarda_confirmacao` (prova enviada
  /// pelo comprador, à espera da vendedora confirmar) — usado para não mostrar
  /// «aguarda pagamento» quando na verdade já há prova por confirmar.
  Set<String> _liveOrdersAwaitingConfirmationKeys = const {};
  int _publicTipMsgCount = 0;
  Timer? _catalogReloadDebounce;
  final ScrollController _catalogListScroll = ScrollController();
  DateTime? _lastCatalogLoadLogUtc;

  static const double _kChatPreviewH = 52;
  static const double _kChatExpandedH = 120;
  static const double _kChatFocusH = 148;
  static const double _kPanelMaxH = 320;
  /// Lista vertical do catalogo (altura fixa; evita Expanded com altura 0).
  static const double _kCatalogListBodyH = 252;

  _ReservationListCategory? _expandedReservationCategory;
  SellerOperationSection _operationSection = SellerOperationSection.queue;

  bool _chatCompact = false;
  bool _chatFocused = false;
  LiveItemOpsSnapshot? _activeOpsSnapshot;
  int _teamHelpersActive = 0;
  final Map<String, LiveCatalogStockSnapshot> _stockByItemId = {};
  LiveRaffleState? _raffleState;
  int? _raffleParticipantCount;
  int? _raffleTicketTotal;
  bool _raffleActionLoading = false;
  Timer? _rafflePollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _raffleEntriesRealtimeSub;
  StreamSubscription<List<Map<String, dynamic>>>? _raffleRealtimeSub;
  /// Mantém o artigo da vitrine visível após vendido (is_active pode ficar false).
  String? _pinnedVitrineItemId;
  List<LiveOpsActivityEvent> _activityEvents = [];
  List<StaffActionLogsRow> _recentStaffLogs = [];
  bool _activityCacheReady = false;
  final Map<String, String> _reservationStatusCache = {};
  final Set<String> _staffLogIdsSeen = {};
  final Map<String, String> _buyerNameCache = {};
  final Map<String, String> _chatUserNameCache = {};
  final Set<String> _systemHighlightMsgIds = {};
  bool _chatSystemEffectsPrimed = false;
  final Set<String> _chatUserNameFetchInFlight = {};
  final Map<String, String> _catalogStatusCache = {};
  final Map<String, String> _helperNameCache = {};
  late final LiveFomoBroadcaster _fomoBroadcaster;
  final Set<String> _activitySystemMsgIds = {};
  bool _activitySystemReady = false;
  final Map<String, int> _lastLowStockActivityQty = {};
  int _panelRebuildLockCount = 0;
  bool _stockSheetOpen = false;
  bool _deferredCatalogReload = false;
  bool _deferredCatalogReloadSilent = true;
  bool _deferPanelVisualRefresh = false;

  bool get _panelRebuildsLocked => _panelRebuildLockCount > 0;

  bool get _deferCatalogSync => _stockSheetOpen || _panelRebuildsLocked;

  void _acquirePanelRebuildLock() {
    _panelRebuildLockCount++;
  }

  void _releasePanelRebuildLock({bool flushDeferredCatalog = false}) {
    if (_panelRebuildLockCount <= 0) return;
    _panelRebuildLockCount--;
    if (_panelRebuildLockCount > 0 || !mounted) return;

    final needsRefresh = _deferPanelVisualRefresh;
    _deferPanelVisualRefresh = false;
    _maestroLog(
      'panel.rebuild_lock.release',
      data: {
        'needs_refresh': needsRefresh,
        'flush_deferred_catalog': flushDeferredCatalog,
        'deferred_catalog': _deferredCatalogReload,
      },
    );
    if (needsRefresh) {
      super.setState(() {});
    }

    if (flushDeferredCatalog && _deferredCatalogReload) {
      unawaited(_runDeferredPanelRebuilds());
    }
  }

  Future<void> _runDeferredPanelRebuilds() async {
    if (!mounted || _panelRebuildsLocked || !_deferredCatalogReload) return;
    _deferredCatalogReload = false;
    final silent = _deferredCatalogReloadSilent;
    await _loadCatalogRows(silent: silent, bypassRebuildLock: true);
    if (!mounted) return;
    await _refreshStockCache(bypassRebuildLock: true);
    if (!mounted) return;
    await _refreshActiveOpsSnapshot(forceFetch: true, bypassRebuildLock: true);
  }

  @override
  void setState(VoidCallback fn) {
    if (_panelRebuildsLocked) {
      fn();
      _deferPanelVisualRefresh = true;
      if (MaestroStudioDebugLog.enabled) {
        unawaited(MaestroStudioDebugLog.log('panel.setState.deferred'));
      }
      return;
    }
    super.setState(fn);
  }

  void _maestroLog(String event, {Map<String, Object?> data = const {}}) {
    if (!MaestroStudioDebugLog.enabled) return;
    unawaited(MaestroStudioDebugLog.log(event, data: data));
  }

  String? _maestroHarnessCategoryId(_ReservationListCategory category) {
    if (!MaestroStudioDebugLog.enabled) return null;
    return switch (category) {
      _ReservationListCategory.inBag => 'maestro_harness_cat_inbag',
      _ReservationListCategory.pending => 'maestro_harness_cat_pending',
      _ReservationListCategory.accepted => 'maestro_harness_cat_accepted',
      _ReservationListCategory.external => 'maestro_harness_cat_external',
      _ReservationListCategory.unpaid => 'maestro_harness_cat_unpaid',
    };
  }

  Widget _maestroHarnessSemantics({
    required String? id,
    required String label,
    required Widget child,
  }) {
    if (id == null) return child;
    return Semantics(
      identifier: id,
      label: label,
      container: true,
      child: child,
    );
  }

  void _setModalVisible(bool open) {
    _stockSheetOpen = open;
    widget.onModalVisibilityChanged?.call(open);
    _maestroLog('panel.modal_visibility', data: {'open': open});
  }

  @override
  void initState() {
    super.initState();
    final id = widget.liveId.trim();
    if (id.isEmpty) return;
    _activityEvents = [];
    _activityCacheReady = false;
    _reservationStatusCache.clear();
    _staffLogIdsSeen.clear();
    _catalogStatusCache.clear();
    _lastLowStockActivityQty.clear();
    _fomoBroadcaster = LiveFomoBroadcaster(liveId: id);
    _publicRoom = LiveRoomService(id);
    _privateRoom = LivePrivateRoomService(
      liveId: id,
      sellerId: widget.sellerId.trim(),
    );
    unawaited(_publicRoom!.start());
    unawaited(_loadSellerChatLabel());
    unawaited(_privateRoom!.start().then((_) async {
      if (!mounted) return;
      final count = await _privateRoom!.unreadCountForSeller();
      if (!mounted) return;
      setState(() => _privateUnread = count);
      widget.onPrivateUnreadChanged?.call(count);
    }));
    _privateRoom!.unreadStream.listen((n) {
      if (!mounted) return;
      setState(() => _privateUnread = n);
      widget.onPrivateUnreadChanged?.call(n);
    });
    _publicRoom!.messagesStream.listen((msgs) {
      unawaited(_prefetchChatUserNames(msgs));
      unawaited(_refreshTipContributors(msgs));
      _ingestSystemMessagesForActivity(msgs);
      _trackSystemChatHighlights(msgs);
      _updatePublicChatUnread(msgs);
      final tipCount =
          msgs.where((m) => m.kind == LiveRoomMessageKind.tip).length;
      if (tipCount != _publicTipMsgCount) {
        _publicTipMsgCount = tipCount;
        unawaited(_refreshLiveOrderMetrics());
      }
    });
    unawaited(_loadCatalogRows());
    unawaited(_loadReservationQueue());
    unawaited(_refreshRaffleState());
    _subscribeRaffleRealtime(id);
    _rafflePollTimer?.cancel();
    _rafflePollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_raffleState?.hasRaffle == true) {
        unawaited(_refreshRaffleState());
      }
    });
    unawaited(SellerStaffContext.instance.refresh().then((_) {
      if (!mounted) return;
      final helpers = SellerStaffContext.instance.myTeamHelpers.where(
        (h) => (h.invitationStatus ?? '') == 'accepted' && h.active == true,
      );
      for (final h in SellerStaffContext.instance.myTeamHelpers) {
        final uid = (h.helperUserId ?? '').trim();
        final name = (h.displayName ?? '').trim();
        if (uid.isNotEmpty && name.isNotEmpty) {
          _helperNameCache[uid] = name;
        }
      }
      setState(() => _teamHelpersActive = helpers.length);
    }));
    _subscribeReservationRealtime();
    _subscribeSellerReservationRealtime();
    _reservationPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      unawaited(_loadReservationQueue(refreshMetrics: false));
    });
    _catalogStockPollTimer?.cancel();
    // Realtime cobre a maior parte; poll é fallback menos agressivo.
    _catalogStockPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _scheduleStockCacheRefresh();
    });
    _subscribeCatalogRealtime();
    _subscribeOrdersRealtime();
    _subscribeLiveTipsRealtime();
    unawaited(_refreshLiveOrderMetrics());
    _tickDuration();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickDuration();
    });
    _logStudio('panel.init');
  }

  final Map<String, DateTime> _studioLogLastUtc = {};

  static const _studioChatterSteps = <String>{
    'reservation.load',
    'wallet.kpi_compute',
    'payments.refresh',
    'catalog.load',
  };

  void _logStudio(
    String step, {
    String? liveItemId,
    String? requestId,
    String status = 'ok',
    Map<String, dynamic>? data,
    Object? error,
  }) {
    // Polls a cada 2–4s — sem throttle isto saturava app_logs + disco.
    // Erros e acções do utilizador passam sempre.
    if (error == null &&
        status == 'ok' &&
        _studioChatterSteps.contains(step) &&
        !_studioLogAllowed(step)) {
      return;
    }
    unawaited(
      FleaberLogger.instance.logLiveVendorStudio(
        step,
        liveId: widget.liveId.trim(),
        sellerId: widget.sellerId.trim(),
        liveItemId: liveItemId,
        requestId: requestId,
        status: status,
        data: data,
        error: error,
      ),
    );
  }

  bool _studioLogAllowed(String step) {
    const minGap = Duration(seconds: 45);
    final now = DateTime.now().toUtc();
    final last = _studioLogLastUtc[step];
    if (last != null && now.difference(last) < minGap) return false;
    _studioLogLastUtc[step] = now;
    return true;
  }

  Future<void> _loadCatalogRows({
    bool silent = false,
    bool bypassRebuildLock = false,
  }) async {
    if (!bypassRebuildLock && _deferCatalogSync) {
      _deferredCatalogReload = true;
      _deferredCatalogReloadSilent = silent;
      return;
    }
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      if (!silent) {
        setState(() => _catalogLoading = true);
      }
      final sid = currentUserUid.trim();
      if (sid.isNotEmpty) {
        await LiveCatalogSync.enforcePrepAllowList(
          liveId: liveId,
          sellerId: sid,
        );
      }
      final rows = await LiveItemsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', liveId)
            .order('created_at', ascending: true),
        // Teto alinhado ao resto do studio (ganhos/stock): todos os artigos
        // que a vendedora levou ao directo, não um corte de paginação a 50.
        limit: 500,
      );
      if (!mounted) return;
      final activeId = rows
          .where((r) => r.isActive == true)
          .map((r) => r.id?.trim() ?? '')
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      setState(() {
        _catalogRows = rows;
        _catalogLoading = false;
        if (activeId.isNotEmpty) _pinnedVitrineItemId = activeId;
      });
      unawaited(_loadCatalogSupportData());
      unawaited(_refreshStockCache());
      unawaited(_refreshActiveOpsSnapshot(forceFetch: true));
      unawaited(_refreshActivityEvents());
      _scrollCatalogToActive();
      if (!silent) {
        final now = DateTime.now().toUtc();
        final last = _lastCatalogLoadLogUtc;
        if (last == null || now.difference(last) > const Duration(seconds: 15)) {
          _lastCatalogLoadLogUtc = now;
          _logStudio(
            'catalog.load',
            data: {'items': rows.length},
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _catalogLoading = false);
      if (!silent) {
        _logStudio('catalog.load', status: 'error', error: e);
      }
    }
  }

  void _scheduleCatalogReload({bool silent = true}) {
    if (_deferCatalogSync) {
      _deferredCatalogReload = true;
      _deferredCatalogReloadSilent = silent;
      return;
    }
    _catalogReloadDebounce?.cancel();
    _catalogReloadDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_loadCatalogRows(silent: silent));
    });
  }

  void _scrollCatalogToActive() {
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return;
    final idx = rows.indexWhere((r) => r.isActive == true);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_catalogListScroll.hasClients) return;
      const rowStride = 100.0;
      final target =
          (idx * rowStride).clamp(0.0, _catalogListScroll.position.maxScrollExtent);
      _catalogListScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _syncLiveOpsMetrics() async {
    await _loadReservationQueue(refreshMetrics: false);
    if (!mounted) return;
    await _refreshLiveOrderMetrics();
    if (!mounted) return;
    await _refreshStockCache();
    if (!mounted) return;
    await _refreshActiveOpsSnapshot(forceFetch: true);
    if (!mounted) return;
    var activityChanged = false;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      final itemId = r.id?.trim() ?? '';
      if (itemId.isEmpty) continue;
      final snap = _stockByItemId[itemId];
      if (snap == null) continue;
      final before = _activityEvents.length;
      _maybeRecordLowStockActivity(
        liveItemId: itemId,
        refLabel: LiveVendorRefDisplay.itemDisplayName(
          title: r.title,
          refCode: r.refCode,
        ),
        availableQty: snap.availableQty,
      );
      if (_activityEvents.length > before) activityChanged = true;
    }
    unawaited(_refreshActivityEvents());
    if (activityChanged && mounted) setState(() {});
  }

  Future<void> _loadCatalogSupportData() async {
    try {
      final prep = await LivePrepRefDetails.readAll();
      final products = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', widget.sellerId.trim()),
        limit: 200,
      );
      final byRef = <String, ProductsRow>{};
      for (final p in products) {
        final k = LivePrepRefDetails.normalizeRefKey(p.refCode ?? '');
        if (k.isNotEmpty) byRef[k] = p;
      }
      if (!mounted) return;
      setState(() {
        _prepRefDetails = prep;
        _productByNormRef = byRef;
      });
    } catch (_) {}
  }

  void _syncCatalogRowAfterStockChange(
    String liveItemId,
    LiveCatalogStockSnapshot snap,
  ) {
    final id = liveItemId.trim();
    if (id.isEmpty) return;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() != id) continue;
      r.quantity = snap.totalQty;
      if (LiveVendorSellerCopy.isMarkedSold(r.status)) {
        break;
      }
      if (snap.availableQty > 0) {
        r.status = 'available';
      } else if (snap.soldConvertedQty >= snap.totalQty) {
        r.status = 'sold';
      }
      break;
    }
  }

  Future<void> _refreshStockCache({
    Iterable<String>? itemIds,
    bool bypassRebuildLock = false,
  }) async {
    final rows = _catalogRows ?? const <LiveItemsRow>[];
    final ids = itemIds ??
        rows.map((r) => r.id?.trim() ?? '').where((s) => s.isNotEmpty);
    if (ids.isEmpty) return;
    final snaps = await LiveCatalogStockService.fetchMany(ids);
    if (!mounted) return;
    for (final entry in snaps.entries) {
      _syncCatalogRowAfterStockChange(entry.key, entry.value);
    }
    _stockByItemId.addAll(snaps);
    if (!bypassRebuildLock && _panelRebuildsLocked) return;
    if (!mounted) return;
    setState(() {});
  }

  /// Junta pedidos de stock num único fetchMany após 400ms.
  void _scheduleStockCacheRefresh({Iterable<String>? itemIds}) {
    if (itemIds == null) {
      _stockRefreshAllPending = true;
      _pendingStockItemIds.clear();
    } else if (!_stockRefreshAllPending) {
      for (final id in itemIds) {
        final t = id.trim();
        if (t.isNotEmpty) _pendingStockItemIds.add(t);
      }
    }
    _stockRefreshDebounce?.cancel();
    _stockRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final all = _stockRefreshAllPending;
      final only = Set<String>.from(_pendingStockItemIds);
      _stockRefreshAllPending = false;
      _pendingStockItemIds.clear();
      if (!all && only.isEmpty) return;
      unawaited(
        _refreshStockCache(itemIds: all ? null : only),
      );
    });
  }

  Future<void> _refreshRaffleState() async {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      final raffle = _raffleState?.raffle;
      if (raffle != null && raffle.isActive && raffle.hasTimer) {
        await LiveRaffleService.tick(raffle.id);
      }
      final next = await LiveRaffleService.fetchState(liveId);
      int? participants;
      int? tickets;
      final rid = next.raffle?.id;
      if (rid != null && rid.isNotEmpty) {
        final stats = await LiveRaffleService.fetchParticipationStats(rid);
        participants = stats?.participants;
        tickets = stats?.tickets;
      }
      if (mounted) {
        setState(() {
          _raffleState = next;
          _raffleParticipantCount = participants;
          _raffleTicketTotal = tickets;
        });
      }
    } catch (_) {}
  }

  void _subscribeRaffleRealtime(String liveId) {
    if (liveId.isEmpty) return;
    try {
      _raffleRealtimeSub?.cancel();
      _raffleRealtimeSub = SupaFlow.client
          .from('live_raffles')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) => unawaited(_refreshRaffleState()));

      _raffleEntriesRealtimeSub?.cancel();
      _raffleEntriesRealtimeSub = SupaFlow.client
          .from('live_raffle_entries')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) => unawaited(_refreshRaffleState()));
    } catch (_) {}
  }

  Future<void> _openRaffleSellerSheet() async {
    final raffle = _raffleState?.raffle;
    // Só bloquear se ainda há rifa a decorrer (active) ou fechada à espera de sorteio.
    if (raffle != null && (raffle.isActive || raffle.isClosed)) {
      RaffleLog.d('openCreate blocked', {
        'status': raffle.status,
        'id': raffle.id,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              raffle.isActive
                  ? 'Encerra ou cancela a rifa actual antes de criar outra.'
                  : 'Sorteia ou cancela a rifa fechada antes de criar outra.',
            ),
          ),
        );
      }
      return;
    }
    RaffleLog.d('openCreate sheet', {
      'prevStatus': raffle?.status ?? 'none',
    });
    final active = _activeCatalogRow;
    await LiveRaffleSellerSheet.show(
      context,
      liveId: widget.liveId.trim(),
      activeItem: active,
      liveCatalogRows: _catalogRows ?? const [],
      marketplaceProducts: _productByNormRef.values.toList(),
      onChanged: () async {
        await _refreshRaffleState();
        // Stock AM5: refrescar artigos após criar/cancelar rifa.
        await _refreshStockCache(bypassRebuildLock: true);
      },
    );
  }

  Future<void> _closeRaffleEntries() async {
    final id = _raffleState?.raffle?.id;
    if (id == null) return;
    setState(() => _raffleActionLoading = true);
    try {
      await LiveRaffleService.closeEntries(id);
      await _refreshRaffleState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível encerrar.')),
        );
      }
    } finally {
      if (mounted) setState(() => _raffleActionLoading = false);
    }
  }

  Future<void> _drawRaffle() async {
    final id = _raffleState?.raffle?.id;
    if (id == null) return;
    final participants = _raffleParticipantCount ?? 0;
    if (participants < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sem participantes. Cancela a rifa para criar outra.',
            ),
          ),
        );
      }
      return;
    }
    RaffleLog.d('draw start', {
      'raffleId': id,
      'participants': participants,
      'liveItemId': _raffleState?.raffle?.liveItemId ?? '-',
    });
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2228),
        title: Text(
          'Sortear vencedor?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          participants == 1
              ? 'Sorteio automático e auditável · 1 participante.'
              : 'Sorteio automático e auditável · $participants participantes.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sortear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _raffleActionLoading = true);
    try {
      await LiveRaffleService.draw(id);
      await _refreshRaffleState();
      await _refreshStockCache(bypassRebuildLock: true);
      requestMarketplaceFeedRefresh();
      RaffleLog.d('draw ok', {
        'status': _raffleState?.raffle?.status ?? '-',
        'winners': _raffleState?.winners.length ?? 0,
      });
      if (mounted) {
        final linked = (_raffleState?.raffle?.liveItemId ?? '').trim().isNotEmpty;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              linked
                  ? 'Sorteio feito. O vencedor deve ter a encomenda em Mensagens.'
                  : 'Sorteio feito. Sem artigo ligado — não há encomenda automática.',
            ),
          ),
        );
      }
    } catch (e) {
      RaffleLog.e('draw', e);
      if (mounted) {
        final s = e.toString();
        final msg = s.contains('prize_order_missing')
            ? 'Sorteio feito, mas a encomenda do prémio não foi criada. '
                'Cria a rifa a partir do catálogo do directo ou do marketplace '
                '(não uses prémio manual) e tenta novamente. '
                'Se o problema continuar, contacta o suporte Fleaber.'
            : 'Não foi possível sortear. Tenta novamente.';
        // ignore: avoid_print
        print('RAFFLE_DRAW_ERR: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _raffleActionLoading = false);
    }
  }

  Future<void> _cancelRaffle() async {
    final id = _raffleState?.raffle?.id;
    final liveItemId = _raffleState?.raffle?.liveItemId;
    if (id == null) return;
    RaffleLog.d('cancel start', {'raffleId': id, 'liveItemId': liveItemId ?? '-'});
    setState(() => _raffleActionLoading = true);
    try {
      await LiveRaffleService.cancel(id);
      await _refreshRaffleState();
      await _refreshStockCache(bypassRebuildLock: true);
      RaffleLog.d('cancel ok');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rifa cancelada. Podes criar outra.')),
        );
      }
    } catch (e) {
      RaffleLog.e('cancel', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível cancelar.')),
        );
      }
    } finally {
      if (mounted) setState(() => _raffleActionLoading = false);
    }
  }

  ProductsRow? _productForLiveItem(LiveItemsRow row) {
    final k = LivePrepRefDetails.normalizeRefKey(row.refCode ?? '');
    if (k.isEmpty) return null;
    return _productByNormRef[k];
  }

  LiveVendorCatalogItemMetrics _metricsForLiveItem(LiveItemsRow row) {
    final itemId = row.id?.trim() ?? '';
    final snap = _stockByItemId[itemId];

    if (snap != null) {
      final soldCount = snap.soldConvertedQty < 0 ? 0 : snap.soldConvertedQty;
      return LiveVendorCatalogItemMetrics(
        quantity: snap.totalQty,
        available: snap.availableQty,
        sold: soldCount,
        reservations: snap.displayReservedQty,
      );
    }

    var reservations = 0;
    var sold = 0;
    for (final r in _reservationQueue) {
      if ((r.liveItemId ?? '').trim() != itemId) continue;
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      final st = r.status ?? '';
      if ((st == 'pending' || st == 'accepted') &&
          LiveReservationQueueService.isOpenSellerTreatReservation(
            status: r.status,
            notes: r.notes,
          )) {
        reservations += q;
      }
      if (st == 'converted') sold += q;
    }

    int? qty;
    final product = _productForLiveItem(row);
    if (product != null) {
      qty = product.quantity;
    } else {
      final detail = _prepRefDetails[
          LivePrepRefDetails.normalizeRefKey(row.refCode ?? '')];
      if (detail != null) qty = detail.quantity;
    }
    return LiveVendorCatalogItemMetrics(
      quantity: qty,
      sold: sold,
      reservations: reservations,
    );
  }

  Future<void> _markCatalogItemSold(LiveItemsRow row) async {
    final id = row.id?.trim();
    if (id == null || id.isEmpty) return;
    try {
      final updated = await LiveCatalogStockService.markItemSold(id);
      if (updated != null && mounted) {
        setState(() {
          _stockByItemId[id] = updated;
          for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
            if ((r.id ?? '').trim() == id) {
              r.status = 'sold';
            }
          }
        });
      }
      await _loadCatalogRows(silent: true);
      await _refreshStockCache(itemIds: [id]);
      await _syncLiveOpsMetrics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Artigo marcado como esgotado.')),
        );
      }
      _logStudio(
        'item.mark_sold',
        liveItemId: id,
        data: {
          if (updated != null) 'available_qty': updated.availableQty,
          if (updated != null) 'sold_qty': updated.soldConvertedQty,
        },
      );
    } catch (e) {
      _logStudio('item.mark_sold', liveItemId: id, status: 'error', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível marcar como esgotado: ${_soldActionErrorMessage(e)}',
            ),
          ),
        );
      }
    }
  }

  String _soldActionErrorMessage(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('not_allowed')) {
      return 'sem permissão para marcar como esgotado.';
    }
    if (raw.contains('live_item_not_found')) {
      return 'artigo não encontrado.';
    }
    return 'tenta outra vez.';
  }

  Future<void> _showStockAdjustSheet(LiveItemsRow row) async {
    final id = row.id?.trim() ?? '';
    if (id.isEmpty) return;

    var snap = _stockByItemId[id] ?? await LiveCatalogStockService.fetch(id);
    final current = (snap?.totalQty ?? 1).clamp(1, 9999);
    var removing = false;
    var selectedDelta = 1;
    var stockApplyBusy = false;
    final manualCtrl = TextEditingController(text: '1');

    if (!mounted) return;
    _logStudio('stock.sheet.open', liveItemId: id, data: {'current_qty': current});
    _maestroLog('stock.sheet.open', data: {'live_item_id': id, 'current': current});
    _StockAdjustSheetOutcome? outcome;
    _setModalVisible(true);
    final sheetHost = widget.modalHostContext ?? context;
    try {
      outcome = await showModalBottomSheet<_StockAdjustSheetOutcome>(
      context: sheetHost,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> applyAdjust({required bool remove}) async {
              FocusScope.of(context).unfocus();
              _maestroLog('stock.apply.start', data: {'remove': remove});
              final parsed = int.tryParse(manualCtrl.text.trim());
              final amount = (parsed != null && parsed > 0)
                  ? parsed
                  : (selectedDelta > 0 ? selectedDelta : 1);
              final change = remove ? -amount : amount;
              final next = current + change;
              if (next < 1) {
                FleaberSnack.showAboveSheet(
                  ctx,
                  'Stock mínimo: 1 unidade.',
                );
                return;
              }
              if (stockApplyBusy) return;
              setSheetState(() => stockApplyBusy = true);
              _acquirePanelRebuildLock();
              try {
                final updated = await LiveCatalogStockService.updateItem(
                  liveItemId: id,
                  quantity: next,
                );
                if (updated == null) {
                  _releasePanelRebuildLock(flushDeferredCatalog: true);
                  if (ctx.mounted) {
                    setSheetState(() => stockApplyBusy = false);
                    FleaberSnack.showAboveSheet(
                      ctx,
                      'Não foi possível actualizar stock.',
                    );
                  }
                  return;
                }
                if (!ctx.mounted) {
                  _releasePanelRebuildLock(flushDeferredCatalog: true);
                  return;
                }
                _maestroLog(
                  'stock.apply.api_ok',
                  data: {'next': next, 'available': updated.availableQty},
                );
                Navigator.pop(
                  ctx,
                  _StockAdjustSheetOutcome(
                    updated: updated,
                    current: current,
                    amount: amount,
                    remove: remove,
                    change: change,
                    next: next,
                  ),
                );
              } catch (e, st) {
                _releasePanelRebuildLock(flushDeferredCatalog: true);
                unawaited(
                  MaestroStudioDebugLog.log(
                    'stock.apply.error',
                    error: e,
                    stack: st,
                  ),
                );
                _logStudio(
                  remove ? 'stock.remove' : 'stock.add',
                  liveItemId: id,
                  status: 'error',
                  data: {'from_qty': current, 'attempt_qty': next},
                  error: e,
                );
                if (ctx.mounted) {
                  setSheetState(() => stockApplyBusy = false);
                  FleaberSnack.showAboveSheet(
                    ctx,
                    'Não foi possível actualizar stock.',
                  );
                }
              }
            }

            Widget deltaChip(int value) {
              final selected = selectedDelta == value;
              return FilterChip(
                label: Text(removing ? '-$value' : '+$value'),
                selected: selected,
                onSelected: stockApplyBusy
                    ? null
                    : (_) => setSheetState(() {
                          selectedDelta = value;
                          manualCtrl.text = '$value';
                        }),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ajustar stock · ${_itemRefLabel(row)}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Atual: $current un. · Disponível: ${snap?.availableQty ?? current}',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      deltaChip(1),
                      deltaChip(2),
                      deltaChip(5),
                      deltaChip(10),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: manualCtrl,
                    enabled: !stockApplyBusy,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: removing ? 'Unidades a retirar' : 'Quantidade',
                      labelStyle: GoogleFonts.inter(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: FleaberRadius.circularSm,
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: FleaberRadius.circularSm,
                        borderSide: const BorderSide(color: FleaberColors.teal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Retirar stock',
                      style: GoogleFonts.inter(color: Colors.white),
                    ),
                    value: removing,
                    activeThumbColor: FleaberColors.teal,
                    onChanged: stockApplyBusy
                        ? null
                        : (v) => setSheetState(() => removing = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              stockApplyBusy ? null : () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: stockApplyBusy
                              ? null
                              : () => applyAdjust(remove: removing),
                          style: FilledButton.styleFrom(
                            backgroundColor: FleaberColors.teal,
                          ),
                          child: stockApplyBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(removing ? 'Retirar' : 'Adicionar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    } finally {
      _setModalVisible(false);
    }

    if (!mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => manualCtrl.dispose());
      if (_deferredCatalogReload) unawaited(_runDeferredPanelRebuilds());
      return;
    }
    if (outcome == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => manualCtrl.dispose());
      if (_deferredCatalogReload) await _runDeferredPanelRebuilds();
      return;
    }

    try {
      _deferredCatalogReload = false;
      _maestroLog('stock.sheet.apply_outcome', data: {'next': outcome.next});
      final updated = outcome.updated;
      setState(() {
        _stockByItemId[id] = updated;
        _syncCatalogRowAfterStockChange(id, updated);
      });
      // Refresh leve: UI já optimista; ops/support em background.
      await _refreshStockCache(itemIds: [id], bypassRebuildLock: true);
      unawaited(_loadCatalogRows(silent: true, bypassRebuildLock: true));
      unawaited(_loadCatalogSupportData());
      unawaited(
        _refreshActiveOpsSnapshot(
          forceFetch: true,
          bypassRebuildLock: true,
        ),
      );
      if (!mounted) return;
      final disp = updated.availableQty;
      FleaberSnack.show(
        context,
        disp != outcome.next
            ? 'Stock na live: ${outcome.next} un. · Disponível: $disp un.'
            : 'Stock actualizado: ${outcome.next} un.',
      );
      _logStudio(
        outcome.remove ? 'stock.remove' : 'stock.add',
        liveItemId: id,
        data: {
          'from_qty': outcome.current,
          'to_qty': outcome.next,
          'delta': outcome.change,
          'amount': outcome.amount,
          'available_qty': updated.availableQty,
          'blocked_qty': updated.blockedQty,
        },
      );
      final ref = _itemRefLabel(row);
      if (!outcome.remove) {
        _appendActivity(
          'stock-adj-$id-${DateTime.now().millisecondsSinceEpoch}',
          '➕ ${_actorSellerLabel} adicionou +${outcome.amount} un. $ref',
          DateTime.now(),
          LiveOpsActivityKind.stockAdjust,
          id,
          null,
          'Ver artigo',
        );
      }
      _maybeRecordLowStockActivity(
        liveItemId: id,
        refLabel: LiveVendorRefDisplay.itemDisplayName(
          title: row.title,
          refCode: row.refCode,
        ),
        availableQty: updated.availableQty,
      );
      _maestroLog('stock.sheet.done', data: {'next': outcome.next});
    } finally {
      _releasePanelRebuildLock(flushDeferredCatalog: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => manualCtrl.dispose());
    }
  }

  Future<void> _addStockForCatalogItem(LiveItemsRow row, {int delta = 1}) async {
    await _showStockAdjustSheet(row);
  }

  Future<String> _suggestNextLiveRefLabel() async {
    final usedKeys = <String>{};
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      final key = LivePrepRefDetails.normalizeRefKey(r.refCode ?? '');
      if (key.isNotEmpty) usedKeys.add(key);
    }

    try {
      final schemes = await LivePrepRefs.readSchemes();
      for (final scheme in schemes) {
        for (final ref in scheme.expandRefs()) {
          final key = LivePrepRefDetails.normalizeRefKey(ref);
          if (key.isNotEmpty && !usedKeys.contains(key)) {
            return ref.startsWith('#') ? ref : '#$ref';
          }
        }
      }
    } catch (_) {
      // Esquemas locais são opcionais durante o directo.
    }

    var maxN = 0;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      final ref = LiveVendorRefDisplay.formatRef(r.refCode);
      final digits = ref.replaceAll(RegExp(r'[^0-9]'), '');
      final n = int.tryParse(digits);
      if (n != null && n > maxN) maxN = n;
    }
    return '#${maxN + 1}';
  }

  Future<void> _openQuickCreateCatalogItem({bool showAfterSave = true}) async {
    final liveId = widget.liveId.trim();
    final sellerId = widget.sellerId.trim();
    if (liveId.isEmpty || sellerId.isEmpty) return;

    final refLabel = await _suggestNextLiveRefLabel();
    final refKey = LivePrepRefDetails.normalizeRefKey(refLabel);
    final initial = await LivePrepRefDetails.read(refKey);

    if (!mounted) return;
    final existingRefs = {
      for (final r in _catalogRows ?? const <LiveItemsRow>[])
        LivePrepRefDetails.normalizeRefKey(
          LiveVendorRefDisplay.formatRef(r.refCode),
        ),
    };
    final saved = await showLiveRefChipEditorSheet(
      context: context,
      refLabel: refLabel,
      initial: initial ?? const LiveRefChipDetail(),
      creatingNew: true,
      existingRefKeys: existingRefs,
    );
    if (saved == null || !mounted) return;

    final refToUse = saved.refLabel.trim().isNotEmpty
        ? saved.refLabel.trim()
        : refLabel;

    try {
      final upsert = await LiveCatalogStockService.upsertLiveOnlyItem(
        sellerId: sellerId,
        refCode: refToUse,
        title: saved.detail.buildLiveItemTitle(refToUse),
        price: saved.detail.price,
        quantity: saved.detail.quantity,
        clothingSize:
            saved.detail.isClothing ? saved.detail.clothingSize : null,
        liveId: liveId,
      );
      final itemId = upsert?.liveItemId;
      final refKeyToSave =
          LivePrepRefDetails.normalizeRefKey(refToUse);
      await LivePrepRefDetails.save(refKeyToSave, saved.detail);
      // Protege FX manuais do prune enforcePrepAllowList (allow-list prep).
      final m = RegExp(r'^#?([A-Za-z]*)(\d+)$').firstMatch(refToUse.trim());
      if (m != null) {
        final n = int.tryParse(m.group(2)!);
        if (n != null) {
          await LivePrepRefs.appendScheme(
            LiveRefScheme(prefix: m.group(1) ?? '', from: n, to: n),
          );
        }
      }
        await _loadCatalogRows(silent: true);
      if (!mounted) return;
      _scrollCatalogListToEnd();

      _logStudio(
        'catalog.create',
        liveItemId: itemId,
        data: {
          'ref': refToUse,
          'show_after': showAfterSave,
        },
      );

      final id = itemId?.trim() ?? '';
      LiveItemsRow? rowToShow;
      if (id.isNotEmpty) {
        for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
          if ((r.id ?? '').trim() == id) {
            rowToShow = r;
            break;
          }
        }
      }

      if (showAfterSave && rowToShow != null) {
        await _setActiveCatalogRow(rowToShow);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Referência $refToUse no direto.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Referência $refToUse criada.')),
        );
      }
    } catch (e) {
      _logStudio('catalog.create', status: 'error', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível criar a referência agora.'),
          ),
        );
      }
    }
  }

  void _scrollCatalogListToEnd() {
    void scroll() {
      if (!mounted || !_catalogListScroll.hasClients) return;
      _catalogListScroll.animateTo(
        _catalogListScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => scroll());
    });
  }

  Widget _buildCatalogQuickAddButton({bool compact = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: const Color(0xFFFFB300),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: InkWell(
          onTap: () => unawaited(
            _openQuickCreateCatalogItem(showAfterSave: false),
          ),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 7 : 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: compact ? 18 : 20,
                  color: const Color(0xFF1A1A1A),
                ),
                SizedBox(width: compact ? 6 : 8),
                Text(
                  'Nova referência',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 12 : 13.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleCatalogMenu(String action, LiveItemsRow row) {
    switch (action) {
      case 'edit':
        unawaited(_showCatalogQuickEditSheet(row));
        break;
      case 'stock':
        unawaited(_addStockForCatalogItem(row));
        break;
      case 'sold':
        unawaited(_markCatalogItemSold(row));
        break;
    }
  }

  Future<void> _showQuickEditErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101518),
          shape: RoundedRectangleBorder(
            borderRadius: FleaberRadius.circularLg,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Não foi possível guardar',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(dialogCtx),
                tooltip: 'Fechar',
              ),
            ],
          ),
          content: Text(
            message,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Fechar',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<ProductsRow?> _shadowProductForLiveItem(LiveItemsRow row) async {
    final pid = row.checkoutProductId?.trim();
    if (pid == null || pid.isEmpty) return null;
    try {
      final rows = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', pid),
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showCatalogQuickEditSheet(LiveItemsRow row) async {
    final itemId = row.id?.trim() ?? '';
    var itemRow = row;
    if (itemId.isNotEmpty) {
      for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
        if ((r.id ?? '').trim() == itemId) {
          itemRow = r;
          break;
        }
      }
      final fresh = await LiveCatalogStockService.fetchLiveItemById(itemId);
      if (fresh != null) itemRow = fresh;
    }

    final product =
        itemRow.isMarketplaceProduct ? _productForLiveItem(itemRow) : null;
    final shadowProduct = await _shadowProductForLiveItem(itemRow);
    final refKey = LivePrepRefDetails.normalizeRefKey(itemRow.refCode ?? '');
    final prep = _prepRefDetails[refKey];
    final snap = itemId.isNotEmpty
        ? (_stockByItemId[itemId] ?? await LiveCatalogStockService.fetch(itemId))
        : null;
    final lockRef = itemRow.isMarketplaceProduct || product?.id != null;

    final qtyCtrl = TextEditingController(
      text:
          '${snap?.totalQty ?? product?.quantity ?? shadowProduct?.quantity ?? prep?.quantity ?? itemRow.quantity ?? 1}',
    );
    final priceCtrl = TextEditingController(
      text: itemRow.price?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
    );
    final initialSize = itemRow.clothingSize?.trim().isNotEmpty == true
        ? itemRow.clothingSize!.trim()
        : (shadowProduct?.clothingSize?.trim() ??
            product?.clothingSize?.trim() ??
            prep?.clothingSize?.trim() ??
            '');
    final initialColor = itemRow.gender?.trim().isNotEmpty == true
        ? itemRow.gender!.trim()
        : (shadowProduct?.gender?.trim() ??
            prep?.clothingColor?.trim() ??
            product?.gender?.trim() ??
            '');
    final titleCtrl = TextEditingController(text: _itemTitle(itemRow));
    final descCtrl = TextEditingController(
      text: shadowProduct?.description?.trim() ??
          product?.description?.trim() ??
          '',
    );
    final refCtrl = TextEditingController(
      text: LiveVendorRefDisplay.formatRef(itemRow.refCode),
    );

    if (!mounted) return;

    var initialPhotos = <String>[];
    if (shadowProduct?.imageUrls.isNotEmpty == true) {
      initialPhotos = List<String>.from(shadowProduct!.imageUrls);
    } else if (product?.imageUrls.isNotEmpty == true) {
      initialPhotos = List<String>.from(product!.imageUrls);
    } else if (itemRow.photoUrl?.trim().isNotEmpty == true) {
      initialPhotos = [itemRow.photoUrl!.trim()];
    }

    BuildContext? quickEditSheetContext;

    List<String> effectiveMarketplacePhotos(List<String> editPhotos) {
      if (editPhotos.isNotEmpty) return editPhotos;
      return initialPhotos;
    }

    var marketplaceInlineError = '';
    void Function(void Function())? rebuildQuickEditSheet;

    Future<void> save({
      required bool andShow,
      required String? selectedSize,
      required String? selectedColor,
      required List<String> photos,
      required bool photosChanged,
      required bool listOnMarketplace,
    }) async {
      final priceRaw = priceCtrl.text.trim().replaceAll(',', '.');
      final price = double.tryParse(priceRaw);
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
      final id = itemRow.id?.trim();
      if (id == null || id.isEmpty) return;

      final titleOut = titleCtrl.text.trim();
      final descOut = descCtrl.text.trim();
      final isClothing = (selectedSize?.isNotEmpty ?? false) ||
          (selectedColor?.isNotEmpty ?? false) ||
          (prep?.isClothing ?? false);
      if (listOnMarketplace) {
        final missing = _quickEditMarketplaceMissing(
          title: titleOut,
          price: price,
          photos: effectiveMarketplacePhotos(photos),
          description: descOut,
          isClothing: isClothing,
          size: selectedSize,
          color: selectedColor,
        );
        if (missing.isNotEmpty) {
          marketplaceInlineError = missing.length == 1
              ? 'Para o marketplace falta: ${missing.first}.'
              : 'Para o marketplace falta: ${missing.join(', ')}.';
          rebuildQuickEditSheet?.call(() {});
          return;
        }
      }

      try {
        _maestroLog('quick_edit.apply.start');
        _acquirePanelRebuildLock();
        final wasListed =
            itemRow.isMarketplaceProduct && product?.listOnMarketplace == true;
        final listParam = listOnMarketplace
            ? true
            : (wasListed && !listOnMarketplace ? false : null);

        final updated = await LiveCatalogStockService.updateItem(
          liveItemId: id,
          quantity: qty < 1 ? 1 : qty,
          price: price,
          title: titleOut.isEmpty ? null : titleOut,
          description: descOut.isEmpty ? '' : descOut,
          clothingSize:
              selectedSize == null || selectedSize.isEmpty ? null : selectedSize,
          gender:
              selectedColor == null || selectedColor.isEmpty ? null : selectedColor,
          refCode: lockRef ? null : refCtrl.text.trim(),
          photoUrl: photosChanged
              ? (photos.isEmpty ? '' : photos.first)
              : null,
          listOnMarketplace: listParam,
        );
        var productIdForPhotos = itemRow.isMarketplaceProduct
            ? (itemRow.productId ?? product?.id)?.trim()
            : itemRow.checkoutProductId?.trim();
        if (!itemRow.isMarketplaceProduct &&
            (photosChanged ||
                descOut.isNotEmpty ||
                listOnMarketplace ||
                (selectedSize?.isNotEmpty ?? false) ||
                (selectedColor?.isNotEmpty ?? false))) {
          final shadowId =
              await LiveCatalogStockService.ensureCheckoutProduct(id);
          if (shadowId != null && shadowId.trim().isNotEmpty) {
            productIdForPhotos = shadowId.trim();
          }
        }
        if (productIdForPhotos != null && productIdForPhotos.isNotEmpty) {
          final patch = <String, dynamic>{};
          if (photosChanged) patch['image_urls'] = photos;
          if (descOut.isNotEmpty) patch['description'] = descOut;
          if (selectedSize != null && selectedSize.isNotEmpty) {
            patch['clothing_size'] = selectedSize;
          }
          if (selectedColor != null && selectedColor.isNotEmpty) {
            patch['gender'] = selectedColor;
          }
          if (patch.isNotEmpty) {
            await ProductsTable().update(
              data: patch,
              matchingRows: (rows) => rows.eqOrNull('id', productIdForPhotos),
            );
          }
        }
        if (updated == null) {
          await _refreshStockCache(itemIds: [id]);
        }

        final refRaw = itemRow.refCode?.trim() ?? refCtrl.text.trim();
        if (refRaw.isNotEmpty) {
          await LivePrepRefDetails.save(
            refRaw,
            LiveRefChipDetail(
              title: titleCtrl.text.trim().isEmpty
                  ? null
                  : titleCtrl.text.trim(),
              price: price,
              quantity: qty < 1 ? 1 : qty,
              clothingSize: selectedSize,
              clothingColor: selectedColor,
              isClothing: (selectedSize?.isNotEmpty ?? false) ||
                  (selectedColor?.isNotEmpty ?? false),
              quantityExplicit: true,
              titleExplicit: titleCtrl.text.trim().isNotEmpty,
            ),
          );
        }

        final sheetCtx = quickEditSheetContext;
        if (sheetCtx == null || !sheetCtx.mounted) {
          _releasePanelRebuildLock(flushDeferredCatalog: true);
          return;
        }
        _maestroLog('quick_edit.apply.api_ok', data: {'qty': qty});
        Navigator.pop(
          sheetCtx,
          _QuickEditSheetOutcome(
            updated: updated,
            qty: qty < 1 ? 1 : qty,
            andShow: andShow,
            liveItemId: id,
          ),
        );
      } catch (e) {
        _releasePanelRebuildLock(flushDeferredCatalog: true);
        _logStudio(
          'quick.edit',
          liveItemId: id,
          status: 'error',
          error: e,
        );
        if (mounted) {
          final err = e.toString();
          final msg = err.contains('price_locked_after_sale')
              ? 'Preço bloqueado após venda neste artigo.'
              : err.contains('product_quantity_increase_blocked_live_catalog')
                  ? 'Não podes aumentar o stock enquanto o artigo está no catálogo deste directo. Termina o directo ou altera a quantidade no anúncio fora da live.'
                  : err.contains('product_quantity_increase_blocked_active_order')
                      ? 'Não podes aumentar o stock enquanto há encomendas ativas neste artigo.'
                      : err.contains('product_quantity_below_applied_stock')
                          ? 'A quantidade não pode ficar abaixo do stock já reservado/vendido.'
                          : err.contains('marketplace_missing_photo')
                              ? 'Para o marketplace é obrigatória pelo menos uma foto.'
                              : err.contains('marketplace_missing_description')
                                  ? 'Para o marketplace é obrigatória a descrição.'
                                  : err.contains('marketplace_missing_title')
                                      ? 'Para o marketplace é obrigatório o título.'
                                      : err.contains('marketplace_missing_price')
                                          ? 'Para o marketplace o preço mínimo é 1,00 €.'
                                          : err.contains('marketplace_missing_size')
                                              ? 'Para o marketplace falta o tamanho.'
                                              : err.contains(
                                                      'marketplace_missing_color')
                                                  ? 'Para o marketplace falta a cor.'
                                                  : 'Não foi possível guardar agora.';
          await _showQuickEditErrorDialog(msg);
        }
      }
    }

    var selectedSize = initialSize.isEmpty ? null : initialSize;
    var selectedColor = initialColor.isEmpty ? null : initialColor;
    var editPhotos = List<String>.from(initialPhotos);
    var photosDirty = false;
    var listOnMarketplace =
        itemRow.isMarketplaceProduct && product?.listOnMarketplace == true;

    _QuickEditSheetOutcome? outcome;
    _maestroLog('quick_edit.sheet.open', data: {'live_item_id': itemId});
    _setModalVisible(true);
    final sheetHost = widget.modalHostContext ?? context;
    try {
      outcome = await showModalBottomSheet<_QuickEditSheetOutcome>(
      context: sheetHost,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        quickEditSheetContext = ctx;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              rebuildQuickEditSheet = setSheetState;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Editar rápido',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fotos',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 84,
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: editPhotos.length,
                        onReorder: (oldIndex, newIndex) {
                          setSheetState(() {
                            photosDirty = true;
                            if (newIndex > oldIndex) newIndex -= 1;
                            final moved = editPhotos.removeAt(oldIndex);
                            editPhotos.insert(newIndex, moved);
                          });
                        },
                        itemBuilder: (ctx, i) {
                          final url = editPhotos[i];
                          return Padding(
                            key: ValueKey(url),
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: ReorderableDragStartListener(
                                    index: i,
                                    child: const Icon(
                                      Icons.drag_handle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    onPressed: () => setSheetState(() {
                                      photosDirty = true;
                                      editPhotos.removeAt(i);
                                    }),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final urls = await _uploadQuickEditPhotos(
                          remaining: 12 - editPhotos.length,
                        );
                        if (urls.isEmpty) return;
                        if (!ctx.mounted) return;
                        setSheetState(() {
                          photosDirty = true;
                          editPhotos.addAll(urls);
                        });
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Adicionar fotos'),
                    ),
                    const SizedBox(height: 12),
                    if (snap != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A3AD).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF00A3AD).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          snap.raffleHoldQty > 0
                              ? 'Disponível agora: ${snap.availableQty} un. · Rifa retém ${snap.raffleHoldQty}'
                              : 'Disponível agora: ${snap.availableQty} un.',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _quickField(
                      'Stock total (live)',
                      qtyCtrl,
                      keyboard: TextInputType.number,
                    ),
                    _quickField(
                      'Preço (€)',
                      priceCtrl,
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                    ),
                    _quickDropdown(
                      label: 'Tamanho',
                      value: selectedSize,
                      items: ClothingOptionLists.sizes,
                      onChanged: (v) => setSheetState(() => selectedSize = v),
                    ),
                    _quickDropdown(
                      label: 'Cor',
                      value: selectedColor,
                      items: ClothingOptionLists.colors,
                      onChanged: (v) => setSheetState(() => selectedColor = v),
                    ),
                    _quickField('Título', titleCtrl),
                    _quickField(
                      'Descrição',
                      descCtrl,
                      maxLines: 3,
                    ),
                    _quickField(
                      'Ref',
                      refCtrl,
                      readOnly: lockRef,
                    ),
                    const SizedBox(height: 8),
                    if (marketplaceInlineError.isNotEmpty) ...[
                      Text(
                        marketplaceInlineError,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFF8A80),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    CheckboxListTile(
                      value: listOnMarketplace,
                      onChanged: (v) {
                        if (v == true) {
                          final priceRaw =
                              priceCtrl.text.trim().replaceAll(',', '.');
                          final price = double.tryParse(priceRaw);
                          final isClothing = (selectedSize?.isNotEmpty ?? false) ||
                              (selectedColor?.isNotEmpty ?? false) ||
                              (prep?.isClothing ?? false);
                          final missing = _quickEditMarketplaceMissing(
                            title: titleCtrl.text.trim(),
                            price: price,
                            photos: effectiveMarketplacePhotos(editPhotos),
                            description: descCtrl.text.trim(),
                            isClothing: isClothing,
                            size: selectedSize,
                            color: selectedColor,
                          );
                          if (missing.isNotEmpty) {
                            marketplaceInlineError = missing.length == 1
                                ? 'Para o marketplace falta: ${missing.first}.'
                                : 'Para o marketplace falta: ${missing.join(', ')}.';
                            setSheetState(() {});
                            return;
                          }
                        }
                        marketplaceInlineError = '';
                        setSheetState(() => listOnMarketplace = v == true);
                      },
                      activeColor: FleaberColors.teal,
                      checkColor: Colors.white,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'Adicionar ao marketplace',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        'Só publica se tiveres título, preço, foto e descrição.',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => save(
                              andShow: false,
                              selectedSize: selectedSize,
                              selectedColor: selectedColor,
                              photos: editPhotos,
                              photosChanged: photosDirty,
                              listOnMarketplace: listOnMarketplace,
                            ),
                            child: const Text('Guardar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => save(
                              andShow: true,
                              selectedSize: selectedSize,
                              selectedColor: selectedColor,
                              photos: editPhotos,
                              photosChanged: photosDirty,
                              listOnMarketplace: listOnMarketplace,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: FleaberColors.teal,
                            ),
                            child: const Text('Guardar e mostrar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    } finally {
      _setModalVisible(false);
    }

    void disposeQuickEditCtrls() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        qtyCtrl.dispose();
        priceCtrl.dispose();
        titleCtrl.dispose();
        descCtrl.dispose();
        refCtrl.dispose();
      });
    }

    if (!mounted) {
      disposeQuickEditCtrls();
      if (_deferredCatalogReload) unawaited(_runDeferredPanelRebuilds());
      return;
    }
    if (outcome == null) {
      disposeQuickEditCtrls();
      if (_deferredCatalogReload) await _runDeferredPanelRebuilds();
      return;
    }

    final appliedId = outcome.liveItemId;
    try {
      _deferredCatalogReload = false;
      _maestroLog('quick_edit.sheet.apply_outcome', data: {'qty': outcome.qty});
      final updated = outcome.updated;
      if (updated != null && appliedId.isNotEmpty) {
        setState(() {
          _stockByItemId[appliedId] = updated;
          _syncCatalogRowAfterStockChange(appliedId, updated);
        });
      }
      try {
        await SupaFlow.client.rpc(
          'batata_recompute_live_item_status',
          params: {'p_live_item_id': appliedId},
        );
      } catch (_) {}
      await _loadCatalogRows(silent: true, bypassRebuildLock: true);
      await _refreshStockCache(itemIds: [appliedId], bypassRebuildLock: true);
      if (!mounted) return;
      if (outcome.andShow) {
        var rowToShow = itemRow;
        for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
          if ((r.id ?? '').trim() == appliedId) {
            rowToShow = r;
            break;
          }
        }
        try {
          await _setActiveCatalogRow(rowToShow);
        } catch (e) {
          _logStudio(
            'quick.edit',
            liveItemId: appliedId,
            status: 'error',
            error: e,
          );
          if (mounted) {
            FleaberSnack.show(context, 'Guardado — não foi possível mostrar o artigo.');
          }
        }
      } else {
        FleaberSnack.show(context, 'Alterações guardadas.');
      }
      _logStudio(
        'quick.edit',
        liveItemId: appliedId,
        data: {
          'qty': outcome.qty,
          'and_show': outcome.andShow,
        },
      );
      _maestroLog('quick_edit.sheet.done', data: {'qty': outcome.qty});
    } catch (e) {
      // Evita erro async não tratado a derrubar o studio (volta a Preparar directo).
      _logStudio(
        'quick.edit',
        liveItemId: appliedId,
        status: 'error',
        error: e,
      );
      _maestroLog('quick_edit.sheet.apply_error', data: {'error': '$e'});
      if (mounted) {
        FleaberSnack.show(context, 'Alterações guardadas — catálogo a actualizar.');
      }
    } finally {
      _releasePanelRebuildLock(flushDeferredCatalog: false);
      disposeQuickEditCtrls();
    }
  }

  List<String> _quickEditMarketplaceMissing({
    required String title,
    required double? price,
    required List<String> photos,
    required String description,
    required bool isClothing,
    String? size,
    String? color,
  }) {
    final missing = <String>[];
    if (price == null || price < 1) missing.add('Preço mínimo 1,00 €');
    if (title.trim().isEmpty) missing.add('Título');
    if (photos.isEmpty) missing.add('Pelo menos uma foto');
    if (description.trim().isEmpty) missing.add('Descrição');
    if (isClothing) {
      if (size == null || size.isEmpty) missing.add('Tamanho');
      if (color == null || color.isEmpty) missing.add('Cor');
    }
    return missing;
  }

  Widget _quickField(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboard,
    bool readOnly = false,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: keyboard,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: const BorderSide(color: FleaberColors.teal),
          ),
        ),
      ),
    );
  }

  Widget _quickDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: value != null && items.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: const BorderSide(color: FleaberColors.teal),
          ),
        ),
        dropdownColor: const Color(0xFF1A2329),
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text('—', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          ...items.map(
            (s) => DropdownMenuItem<String>(
              value: s,
              child: Text(s),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _setActiveCatalogRow(LiveItemsRow row) async {
    final liveId = widget.liveId.trim();
    final id = row.id?.trim();
    if (liveId.isEmpty || id == null || id.isEmpty) return;

    setState(() {
      _pinnedVitrineItemId = id;
      for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
        r.isActive = (r.id?.trim() ?? '') == id;
      }
    });
    _scrollCatalogToActive();

    try {
      await LiveItemsTable().update(
        data: {'is_active': false},
        matchingRows: (q) => q.eqOrNull('live_id', liveId),
      );
      await LiveItemsTable().update(
        data: {'is_active': true},
        matchingRows: (q) => q.eqOrNull('id', id),
      );
      try {
        await LiveItemShowEventsTable().insert({
          'live_id': liveId,
          'live_item_id': id,
          'shown_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {
        // Tabela ainda não migrada no Supabase — o live continua via is_active.
      }
      if (!mounted) return;
      await _refreshStockCache(itemIds: [id]);
      await _refreshActiveOpsSnapshot(forceFetch: true);
      _logStudio('catalog.show', liveItemId: id);
      _scheduleCatalogReload(silent: true);
    } catch (e) {
      _logStudio('catalog.show', liveItemId: id, status: 'error', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível mostrar este artigo.')),
        );
      }
      unawaited(_loadCatalogRows(silent: true));
    }
  }

  Future<void> _loadReservationQueue({bool refreshMetrics = true}) async {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      // Só spinner na 1.ª carga. Poll periódico (4s) mantém a lista antiga
      // visível até chegar a nova — evita «piscar» zeros / lista vazia.
      final initialLoad = _reservationQueue.isEmpty;
      if (initialLoad && mounted) {
        setState(() => _reservationLoading = true);
      }
      final queue = LiveReservationQueueService();
      var staleReconciled = 0;
      try {
        staleReconciled =
            await queue.reconcileStalePaidReservationsForLive(liveId);
      } catch (_) {}
      var rows = await queue.queueForLive(
        liveId: liveId,
        includeHistory: true,
      );
      if (!mounted) return;

      var logs = const <StaffActionLogsRow>[];
      try {
        final since = DateTime.now().toUtc().subtract(const Duration(hours: 1));
        logs = await StaffActionLogsTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('seller_id', widget.sellerId.trim())
              .gte('created_at', since.toIso8601String())
              .order('created_at', ascending: false),
          limit: 200,
        );
        logs = logs.where((log) {
          final meta = log.metadataRaw;
          final lid = meta['live_id']?.toString().trim() ?? '';
          return lid.isEmpty || lid == liveId;
        }).toList();
      } catch (_) {
        // Staff logs são opcionais — não bloquear fila de reservas.
      }

      setState(() {
        _reservationQueue = rows;
        _opsActionsLastHour = logs.length;
        _recentStaffLogs = logs;
        _reservationLoading = false;
        if (_expandedReservationCategory == null) {
          for (final cat in const [
            _ReservationListCategory.inBag,
            _ReservationListCategory.pending,
            _ReservationListCategory.accepted,
            _ReservationListCategory.external,
            _ReservationListCategory.unpaid,
          ]) {
            if (_reservationsForCategory(cat).isNotEmpty) {
              _expandedReservationCategory = cat;
              break;
            }
          }
        }
      });
      if (refreshMetrics) {
        await _refreshLiveOrderMetrics();
        await _resolveBuyerNames(rows.map((r) => r.buyerId ?? ''));
        _syncBuyerCancelActivities(rows);
        _syncExpiredActivities(rows);
        unawaited(_refreshActiveOpsSnapshot(forceFetch: true));
        unawaited(_refreshActivityEvents());
        final itemIds = rows
            .map((r) => (r.liveItemId ?? '').trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (itemIds.isNotEmpty) {
          unawaited(_refreshStockCache(itemIds: itemIds));
          unawaited(_loadCatalogRows(silent: true));
        }
      }
      if (mounted) _notifyOpsTotals();
      var pending = 0;
      var accepted = 0;
      for (final r in rows) {
        final st = r.status ?? '';
        if (st == 'pending') pending++;
        if (st == 'accepted') accepted++;
      }
      _logStudio(
        'reservation.load',
        data: {
          'total': rows.length,
          'pending': pending,
          'accepted': accepted,
          'stale_reconciled': staleReconciled,
          'initial_load': initialLoad,
        },
      );
    } catch (e) {
      if (mounted) setState(() => _reservationLoading = false);
      _logStudio('reservation.load', status: 'error', error: e);
    }
  }

  void _notifyOpsTotals() {
    final totals = _computeOpsTotals();
    _logStudio(
      'wallet.kpi_compute',
      data: {
        'sales_value_eur': totals.salesValueEur,
        'live_paid_orders_eur': _livePaidOrdersValueEur,
        'live_tips_eur': _liveTipsValueEur,
        'live_tips_count': _liveTipsCount,
        'sales_count': totals.salesCount,
        'operation_section': _operationSection.name,
        'active_panel': widget.activePanel.name,
      },
    );
    widget.onOpsTotalsChanged?.call(totals);
  }

  /// Garante entrada no histórico quando o comprador cancelou (mesmo sem transição em cache).
  void _syncBuyerCancelActivities(List<LiveReservationRequestsRow> rows) {
    var changed = false;
    for (final r in rows) {
      if (!LiveReservationQueueService.isBuyerCancelledReservation(
        status: r.status,
        notes: r.notes,
      )) {
        continue;
      }
      final id = (r.id ?? '').trim();
      if (id.isEmpty) continue;
      _reservationStatusCache[id] = r.status;
      final activityId = 'res-can-$id';
      if (_activityEvents.any((e) => e.id == activityId)) continue;

      final name = _buyerNameLabel(r);
      final ref = _refForLiveItem(r.liveItemId);
      _appendActivity(
        activityId,
        '$name cancelou a reserva · $ref',
        r.updatedAt ?? r.createdAt,
        LiveOpsActivityKind.bagAdd,
        r.liveItemId,
        id,
        'Ver reservas',
      );
      _activityEvents.removeWhere(
        (e) =>
            e.requestId == id &&
            (e.id == 'res-new-$id' || e.id == 'res-acc-$id'),
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// Histórico a partir do estado canónico `expired` (mesmo padrão do cancel).
  void _syncExpiredActivities(List<LiveReservationRequestsRow> rows) {
    var changed = false;
    for (final r in rows) {
      if ((r.status ?? '').trim() != 'expired') continue;
      final id = (r.id ?? '').trim();
      if (id.isEmpty) continue;
      _reservationStatusCache[id] = r.status;
      final activityId = 'res-exp-$id';
      if (_activityEvents.any((e) => e.id == activityId)) continue;

      final name = _buyerNameLabel(r);
      final ref = _refForLiveItem(r.liveItemId);
      _appendActivity(
        activityId,
        'A reserva de $name expirou · $ref',
        r.updatedAt ?? r.createdAt,
        LiveOpsActivityKind.system,
        r.liveItemId,
        id,
        'Ver artigo',
      );
      _activityEvents.removeWhere(
        (e) =>
            e.requestId == id &&
            (e.id == 'res-new-$id' || e.id == 'res-acc-$id'),
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  LiveItemsRow? get _activeCatalogRow {
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      if (r.isActive == true) {
        _pinnedVitrineItemId = r.id?.trim();
        return r;
      }
    }
    final pin = _pinnedVitrineItemId?.trim() ?? '';
    if (pin.isNotEmpty) {
      for (final r in rows) {
        if ((r.id ?? '').trim() == pin) return r;
      }
    }
    return null;
  }

  SellerLiveActivePanel get _panel => widget.activePanel;

  bool get _panelExpanded => _panel != SellerLiveActivePanel.none;

  double get _effectiveChatHeight {
    if (_panel != SellerLiveActivePanel.chat) return _kChatPreviewH;
    if (_chatFocused) return _kChatFocusH;
    if (_chatCompact) return _kChatPreviewH + 8;
    return _kChatExpandedH;
  }

  bool get _chatProminent => _panel == SellerLiveActivePanel.chat;

  String? _itemAttributes(LiveItemsRow row) {
    return LiveCatalogItemAttributes.subtitle(
      clothingSize: row.clothingSize,
      color: row.gender,
    );
  }

  Future<List<String>> _uploadQuickEditPhotos({required int remaining}) async {
    if (remaining < 1) return const [];
    final picked = await FleaberGalleryPicker.pickImages(limit: remaining);
    if (picked.isEmpty) return const [];
    final uid = currentUserUid;
    if (uid.isEmpty) return const [];
    final urls = <String>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path =
          'live_item_photos/$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await SupaFlow.client.storage.from('chat_media').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );
      urls.add(SupaFlow.client.storage.from('chat_media').getPublicUrl(path));
    }
    return urls;
  }

  String _itemTitle(LiveItemsRow row) {
    final title = (row.title ?? '').trim();
    if (title.isNotEmpty && !LiveVendorRefDisplay.looksLikeTechRef(title)) {
      return title;
    }
    final ref = LiveVendorRefDisplay.formatRef(row.refCode);
    return ref.isEmpty ? 'Artigo' : ref;
  }

  String _itemRefLabel(LiveItemsRow row) =>
      LiveVendorRefDisplay.refLabel(row.refCode);

  String? _itemPriceLabel(LiveItemsRow row) {
    final p = LiveVendorRefDisplay.formatPrice(row.price);
    return p.isEmpty ? null : p;
  }

  String? _priceLabelForLiveItem(String? liveItemId) {
    final id = (liveItemId ?? '').trim();
    if (id.isEmpty) return null;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == id) return _itemPriceLabel(r);
    }
    return null;
  }

  void _appendActivityEvent(
    LiveOpsActivityEvent event,
  ) {
    if (_activityEvents.any((e) => e.id == event.id)) return;
    _activityEvents.insert(0, event);
    if (_activityEvents.length > 50) {
      _activityEvents.removeRange(50, _activityEvents.length);
    }
  }

  void _appendActivity(
    String id,
    String text, [
    DateTime? at,
    LiveOpsActivityKind? kind,
    String? liveItemId,
    String? requestId,
    String? actionLabel,
  ]) {
    _appendActivityEvent(
      LiveOpsActivityEvent(
        id: id,
        text: text,
        at: at ?? DateTime.now(),
        kind: kind,
        liveItemId: liveItemId,
        requestId: requestId,
        actionLabel: actionLabel,
      ),
    );
  }

  void _ingestSystemMessagesForActivity(List<LiveRoomMessage> msgs) {
    var changed = false;
    for (final m in msgs) {
      if (m.kind != LiveRoomMessageKind.system) continue;
      final id = m.id.trim();
      if (id.isEmpty || _activitySystemMsgIds.contains(id)) continue;
      _activitySystemMsgIds.add(id);

      final body = m.body.trim();
      if (body.contains('reservou') ||
          body.contains('pediu') ||
          body.contains('cancelou')) {
        unawaited(_loadReservationQueue());
        unawaited(_syncLiveOpsMetrics());
        unawaited(_refreshActiveOpsSnapshot(forceFetch: true));
      }

      if (!_activitySystemReady) continue;

      if (body.isEmpty) continue;

      if (body.contains('comprou')) {
        final clean = body
            .replaceFirst(RegExp(r'^[✅💳]\s*'), '')
            .trim();
        _appendActivity(
          'sys-$id',
          clean.isEmpty ? body : clean,
          m.createdAt,
          LiveOpsActivityKind.purchase,
          null,
          null,
          'Ver pagamentos',
        );
        changed = true;
      } else if (body.contains('esgotado')) {
        final clean = body.replaceFirst(RegExp(r'^🔴\s*'), '').trim();
        _appendActivity(
          'sys-sold-$id',
          clean.isEmpty ? body : clean,
          m.createdAt,
          LiveOpsActivityKind.soldOut,
          null,
          null,
          null,
        );
        changed = true;
      } else if (body.contains('reservou') || body.contains('pediu')) {
        _appendActivity(
          'sys-bag-$id',
          body.replaceFirst(RegExp(r'^[🛍️🛒]\s*'), '').trim(),
          m.createdAt,
          LiveOpsActivityKind.bagAdd,
          null,
          null,
          'Ver reservas',
        );
        changed = true;
      }
    }
    if (!_activitySystemReady && msgs.isNotEmpty) {
      _activitySystemReady = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _onActivityEventAction(LiveOpsActivityEvent event) {
    switch (event.kind) {
      case LiveOpsActivityKind.purchase:
        openOperationalQueue(section: SellerOperationSection.payments);
        break;
      case LiveOpsActivityKind.bagAdd:
      case LiveOpsActivityKind.reservationAccepted:
      case LiveOpsActivityKind.externalPayment:
        openOperationalQueue(section: SellerOperationSection.queue);
        if (event.requestId != null && event.requestId!.isNotEmpty) {
          _expandedReservationCategory = _ReservationListCategory.inBag;
        }
        break;
      case LiveOpsActivityKind.stockAdjust:
      case LiveOpsActivityKind.stockLow:
      case LiveOpsActivityKind.soldOut:
      case LiveOpsActivityKind.helperAction:
        final itemId = event.liveItemId?.trim() ?? '';
        if (itemId.isNotEmpty) {
          unawaited(_focusLiveItem(itemId));
        }
        break;
      case LiveOpsActivityKind.system:
        final itemId = event.liveItemId?.trim() ?? '';
        if (itemId.isNotEmpty) {
          unawaited(_focusLiveItem(itemId));
        }
        break;
      case null:
        break;
    }
  }

  Future<void> _focusLiveItem(String liveItemId) async {
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == liveItemId) {
        await _setActiveCatalogRow(r);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artigo não encontrado no catálogo.')),
      );
    }
  }

  void _maybeRecordLowStockActivity({
    required String liveItemId,
    required String refLabel,
    required int availableQty,
  }) {
    final prev = _lastLowStockActivityQty[liveItemId];

    if (prev == null) {
      _lastLowStockActivityQty[liveItemId] = availableQty;
      return;
    }
    if (prev == availableQty) return;

    final crossedToLastUnit = prev > 1 && availableQty == 1;
    _lastLowStockActivityQty[liveItemId] = availableQty;

    if (!crossedToLastUnit) return;

    _appendActivity(
      'low-$liveItemId-1',
      '📦 Ultima unidade de $refLabel',
      DateTime.now(),
      LiveOpsActivityKind.stockLow,
      liveItemId,
      null,
      'Ver artigo',
    );
    unawaited(
      _fomoBroadcaster.notifyCrossedToLastUnit(
        liveItemId: liveItemId,
        refLabel: refLabel,
        previousAvailableQty: prev,
        availableQty: availableQty,
      ),
    );
  }

  void _maybeRecordSoldOutActivity(LiveItemsRow row) {
    final id = row.id?.trim() ?? '';
    if (id.isEmpty) return;
    final label = LiveVendorRefDisplay.itemDisplayName(
      title: row.title,
      refCode: row.refCode,
    );
    _appendActivity(
      'sold-out-$id',
      '🔴 $label esgotado',
      DateTime.now(),
      LiveOpsActivityKind.soldOut,
      id,
      null,
      'Ver artigo',
    );
    unawaited(
      _fomoBroadcaster.maybeSoldOut(
        liveItemId: id,
        refLabel: label,
      ),
    );
  }

  String get _actorSellerLabel {
    final n = currentUserDisplayName.trim();
    return n.isEmpty ? 'Seller' : n.split(' ').first;
  }

  Future<void> _loadSellerChatLabel() async {
    final sid = widget.sellerId.trim();
    if (sid.isEmpty) return;
    try {
      final rows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sid),
        limit: 1,
      );
      if (rows.isEmpty) return;
      final name = rows.first.fullName?.trim();
      if (name == null || name.isEmpty) return;
      _chatUserNameCache[sid] = name;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _prefetchChatUserNames(List<LiveRoomMessage> msgs) async {
    final ids = msgs
        .map((m) => m.userId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .where((id) => id != widget.sellerId.trim())
        .where((id) => !_chatUserNameCache.containsKey(id))
        .where((id) => !_chatUserNameFetchInFlight.contains(id))
        .take(24)
        .toList();
    if (ids.isEmpty) return;
    for (final id in ids) {
      _chatUserNameFetchInFlight.add(id);
    }
    try {
      final profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.inFilter('id', ids),
      );
      for (final p in profiles) {
        if (p.id == null) continue;
        final name = p.fullName?.trim();
        _chatUserNameCache[p.id!] =
            (name != null && name.isNotEmpty) ? name : 'Utilizador';
      }
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      _chatUserNameFetchInFlight.removeAll(ids);
    }
  }

  String _chatSenderLabel(LiveRoomMessage m) {
    final userId = m.userId?.trim() ?? '';
    if (userId == widget.sellerId.trim()) {
      final cached = _chatUserNameCache[userId];
      if (cached != null && cached.trim().isNotEmpty) return cached;
    }
    final senderLabel = m.senderLabel?.trim() ?? '';
    final placeholder = senderLabel.isEmpty ||
        senderLabel.toLowerCase() == 'utilizador' ||
        senderLabel.length <= 4;
    if (!placeholder && senderLabel.isNotEmpty) return senderLabel;
    if (userId.isNotEmpty) {
      final cached = _chatUserNameCache[userId];
      if (cached != null && cached.trim().isNotEmpty) return cached;
    }
    return senderLabel.isNotEmpty ? senderLabel : 'Utilizador';
  }

  Future<void> _resolveBuyerNames(Iterable<String> ids) async {
    final missing = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && !_buyerNameCache.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      final profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.inFilter('id', missing.toList()),
      );
      for (final p in profiles) {
        if (p.id == null) continue;
        _buyerNameCache[p.id!] =
            (p.fullName?.trim().isNotEmpty ?? false) ? p.fullName!.trim() : 'Cliente';
      }
    } catch (_) {}
  }

  String _buyerNameLabel(LiveReservationRequestsRow r) {
    final ext = (r.externalDisplayName ?? '').trim();
    if (ext.isNotEmpty) return ext;
    final notes = (r.notes ?? '').trim();
    if (notes.startsWith('manual:')) {
      return notes.substring('manual:'.length).trim();
    }
    final id = (r.buyerId ?? '').trim();
    if (id.isEmpty) {
      if (r.source == 'facebook_manual') return 'Facebook';
      return 'Cliente';
    }
    return _buyerNameCache[id] ?? 'Cliente';
  }

  Future<void> _showPsReaderPairingDialog() async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A gerar código PS Reader…'),
        duration: Duration(seconds: 3),
      ),
    );

    Map<String, dynamic>? result;
    try {
      result = await PsIngestService.createPairing(
        liveId: widget.liveId,
      );
    } catch (e) {
      result = {'ok': false, 'error': e.toString()};
    }

    if (!mounted) return;

    if (result == null || result['ok'] != true) {
      final err = (result?['error'] ?? 'pairing').toString();
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF101518),
          title: Text(
            'Emparelhar PS Reader',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          content: Text(
            'Não foi possível gerar o código.\n\n$err',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final code = (result['code'] ?? '').toString();
    if (code.length != 6) {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF101518),
          title: Text(
            'Emparelhar PS Reader',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          content: Text(
            'Resposta inválida do servidor (código em falta).',
            style: GoogleFonts.inter(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final expires = result['expires_at']?.toString() ?? '';
    final liveTitle = (result['live_title'] ?? 'Live').toString();

    String? hubLiveUrl;
    try {
      final status = await HubSellerService().fetchStatus();
      final handle = status?.handle?.trim() ?? '';
      if (handle.isNotEmpty) {
        hubLiveUrl = HubUrls.liveWebHash(handle, liveId: widget.liveId);
      }
    } catch (_) {}

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101518),
        title: Text(
          'Emparelhar PS Reader',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No PC abre «Fleaber PS Reader» → Emparelhar live → introduz:',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SelectableText(
                code,
                style: GoogleFonts.inter(
                  color: const Color(0xFF00A3AD),
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Live: $liveTitle\nVálido até: $expires',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              ),
              if (hubLiveUrl != null && hubLiveUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Link FleaHub (cola no Facebook):',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  hubLiveUrl,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00A3AD),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (hubLiveUrl != null && hubLiveUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: hubLiveUrl!));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Link FleaHub copiado')),
                );
              },
              child: const Text('Copiar link'),
            ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Código copiado')),
              );
            },
            child: const Text('Copiar código'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Legado admin — token manual.
  Future<void> _showPsReaderTokenDialog() async {
    if (!mounted) return;

    final deviceId = await _promptPsReaderDeviceFields();
    if (deviceId == null || !mounted) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A gerar token PS Reader…'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final result = await PsIngestService.createDeviceToken(
      deviceId: deviceId.$1,
      label: deviceId.$2,
    );
    if (!mounted) return;

    if (result == null || result['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${result?['error'] ?? 'token'}')),
      );
      return;
    }

    final token = (result['token'] ?? '').toString();
    final liveId = widget.liveId.trim();
    // URL do ambiente actual (staging por omissão; prod via dart-define).
    final bundle =
        'live_id=$liveId\ndevice_token=$token\nsupabase_url=${SupaFlow.supabaseUrl}';
    await Clipboard.setData(ClipboardData(text: bundle));
    if (!mounted) return;

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101518),
        title: Text(
          'Token copiado',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            'Cola no PC (reader.py setup).\n\n'
            'Live ID:\n$liveId\n\n'
            'Token (só mostrado desta vez):\n$token',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Retorna (deviceId, label) ou null se cancelou.
  Future<(String, String?)?> _promptPsReaderDeviceFields() async {
    final deviceCtrl = TextEditingController(text: 'pc-reader-1');
    final labelCtrl = TextEditingController(text: 'PC Facebook');
    try {
      final picked = await showDialog<(String, String?)?>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF101518),
          title: Text(
            'Token PS Reader',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: deviceCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: const InputDecoration(labelText: 'ID do PC'),
              ),
              TextField(
                controller: labelCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nome (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final id = deviceCtrl.text.trim();
                if (id.length < 3) return;
                final label = labelCtrl.text.trim();
                Navigator.pop(ctx, (id, label.isEmpty ? null : label));
              },
              child: const Text('Gerar'),
            ),
          ],
        ),
      );
      return picked;
    } finally {
      deviceCtrl.dispose();
      labelCtrl.dispose();
    }
  }

  Future<void> _confirmPsReservation(
    LiveReservationRequestsRow req,
    String action, {
    int? refNumber,
  }) async {
    final id = req.id?.trim() ?? '';
    if (id.isEmpty) return;
    final res = await PsIngestService.confirmReservation(
      requestId: id,
      action: action,
      refNumber: refNumber,
    );
    if (!mounted) return;
    if (res?['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PS: ${res?['error'] ?? 'falhou'}')),
      );
      return;
    }
    await _loadReservationQueue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reserva Facebook actualizada')),
    );
  }

  bool _isActiveItemRafflePrize(String? itemId) {
    final id = (itemId ?? '').trim();
    if (id.isEmpty) return false;
    final raffleItemId = _raffleState?.raffle?.liveItemId?.trim() ?? '';
    return raffleItemId.isNotEmpty && raffleItemId == id;
  }

  Widget _buildActiveItemPendingReservationPrompt() {
    // Evita duplicar Aceitar/Recusar: com Operação aberta a fila já decide.
    if (_panel.isOperationFamily ||
        _panel == SellerLiveActivePanel.operation) {
      return const SizedBox.shrink();
    }
    final active = _activeCatalogRow;
    if (active == null) return const SizedBox.shrink();
    final itemId = active.id?.trim() ?? '';
    if (itemId.isEmpty) return const SizedBox.shrink();

    final pendingForItem = _sellerOpenPendingReservations()
        .where((r) => (r.liveItemId ?? '').trim() == itemId)
        .toList();
    if (pendingForItem.isEmpty) return const SizedBox.shrink();
    if (!SellerStaffContext.instance
        .can(SellerStaffPermissions.canManageReservations)) {
      return const SizedBox.shrink();
    }

    final req = _sortReservationsByUrgency(pendingForItem).first;
    final isRafflePrize = _isActiveItemRafflePrize(itemId);
    final waitlist = LiveReservationQueueService.isWaitlistPosition(
      queuePosition: req.queuePosition,
      stock: _stockByItemId[itemId],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF007782).withValues(alpha: 0.18),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(color: const Color(0xFF007782).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isRafflePrize
                ? 'Prémio da Rifa · reserva normal'
                : 'Reserva pendente',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_buyerNameLabel(req)}${_qtySeg(req)}'
            '${waitlist ? ' · lista de espera' : ''}',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 10),
          ),
          if (isRafflePrize) ...[
            const SizedBox(height: 4),
            Text(
              'Aceita para confirmar ou entrar na lista de espera se não houver stock.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 9.5),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _queueAction('Aceitar', () => _processReservation(req, 'accept')),
              _queueAction('Recusar', () => _processReservation(req, 'reject')),
            ],
          ),
        ],
      ),
    );
  }

  String _sellerWaitlistSuffix(LiveReservationRequestsRow r) {
    if (r.status != 'pending') return '';
    final itemId = (r.liveItemId ?? '').trim();
    final snap = itemId.isEmpty ? null : _stockByItemId[itemId];
    if (!LiveReservationQueueService.isWaitlistPosition(
      queuePosition: r.queuePosition,
      stock: snap,
    )) {
      return '';
    }
    return ' · lista de espera';
  }

  /// Comprador já enviou prova de pagamento (order `aguarda_confirmacao`) —
  /// distinguir de «aceite, ainda à espera que o comprador pague».
  String _sellerAwaitingConfirmationSuffix(LiveReservationRequestsRow r) {
    if (r.status != 'accepted') return '';
    final key =
        '${(r.liveItemId ?? '').trim()}|${(r.buyerId ?? '').trim()}';
    if (!_liveOrdersAwaitingConfirmationKeys.contains(key)) return '';
    return ' · pago fora da app · confirma';
  }

  String _refForLiveItem(String? liveItemId) {
    final id = (liveItemId ?? '').trim();
    if (id.isEmpty) return 'item';
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == id) {
        return LiveVendorRefDisplay.refLabel(r.refCode);
      }
    }
    return 'item';
  }

  String _itemDisplayLabelForLiveItem(String? liveItemId) {
    final id = (liveItemId ?? '').trim();
    if (id.isEmpty) return 'Artigo';
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == id) {
        return LiveVendorRefDisplay.itemDisplayName(
          title: r.title,
          refCode: r.refCode,
        );
      }
    }
    return _refForLiveItem(liveItemId);
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
        resolveBuyerName: (raw) =>
            _resolveSystemChatBuyerName(raw, m.userId),
      )) {
        out.add(id);
      }
    }
    return out;
  }

  String? _resolveSystemChatBuyerName(String raw, String? userId) {
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty &&
        trimmed.toLowerCase() != 'utilizador' &&
        trimmed.length > 4) {
      return trimmed;
    }
    final uid = userId?.trim() ?? '';
    if (uid.isNotEmpty) {
      final cached = _chatUserNameCache[uid];
      if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    }
    return null;
  }

  void _trackSystemChatHighlights(List<LiveRoomMessage> msgs) {
    var changed = false;
    for (final m in msgs) {
      if (m.kind == LiveRoomMessageKind.tip) {
        final tipId = m.tipId?.trim() ?? '';
        if (tipId.isEmpty || !_chatSystemEffectsPrimed) continue;
        final key = 'tip:$tipId';
        if (_systemHighlightMsgIds.add(key)) {
          changed = true;
          Future<void>.delayed(const Duration(seconds: 4), () {
            _systemHighlightMsgIds.remove(key);
            if (mounted) setState(() {});
          });
        }
        continue;
      }
      if (m.kind != LiveRoomMessageKind.system) continue;
      if (m.id.isEmpty) continue;
      final parsed = LiveSystemChatHumanizer.parse(
        m.body,
        normalizeItemLabel: _normalizeSystemChatItemLabel,
        resolveBuyerName: (raw) =>
            _resolveSystemChatBuyerName(raw, m.userId),
      );
      if (!_chatSystemEffectsPrimed ||
          !parsed.showInPublicChat ||
          parsed.highlightDuration == null) {
        continue;
      }
      if (_systemHighlightMsgIds.add(m.id)) {
        changed = true;
        final msgId = m.id;
        final dur = parsed.highlightDuration!;
        Future<void>.delayed(dur, () {
          _systemHighlightMsgIds.remove(msgId);
          if (mounted) setState(() {});
        });
      }
    }
    if (!_chatSystemEffectsPrimed) {
      _chatSystemEffectsPrimed = true;
    } else if (changed && mounted) {
      setState(() {});
    }
  }

  bool _shouldAnimateSystemHighlight(String messageId) {
    final id = messageId.trim();
    return id.isNotEmpty && _systemHighlightMsgIds.contains(id);
  }

  bool _shouldAnimateTipHighlight(String? tipId) {
    final id = tipId?.trim() ?? '';
    return id.isNotEmpty && _systemHighlightMsgIds.contains('tip:$id');
  }

  String? _staffLogToActivity(StaffActionLogsRow log) {
    final action = (log.actionType ?? '').trim();
    final meta = log.metadataRaw;
    final actorId = (log.performedByUserId ?? '').trim();
    final isSeller = actorId == widget.sellerId.trim();
    final actorName = isSeller
        ? 'Vendedora'
        : (_helperNameCache[actorId] ??
            meta['display_name']?.toString().trim() ??
            'Equipa');
    final ref = LiveVendorRefDisplay.refLabel(meta['ref_code']?.toString());
    switch (action) {
      case 'mark_item_sold':
      case 'live_item_sold':
      case 'item_marked_sold':
        return '✅ $actorName marcou vendido · $ref';
      case 'live_reservation_accept':
      case 'reservation_accepted':
        return '✅ $actorName aceitou reserva · $ref';
      case 'live_reservation_reject':
      case 'reservation_rejected':
        return '❌ $actorName recusou reserva · $ref';
      default:
        return null;
    }
  }

  Future<void> _refreshActivityEvents() async {
    final rows = _reservationQueue;
    if (!_activityCacheReady) {
      for (final r in rows) {
        final id = (r.id ?? '').trim();
        if (id.isNotEmpty) _reservationStatusCache[id] = r.status;
      }
      for (final log in _recentStaffLogs) {
        final id = (log.id ?? '').trim();
        if (id.isNotEmpty) _staffLogIdsSeen.add(id);
      }
      for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
        final id = (r.id ?? '').trim();
        if (id.isNotEmpty) _catalogStatusCache[id] = r.status ?? '';
      }
      _activityCacheReady = true;
      if (mounted) setState(() {});
      return;
    }

    await _resolveBuyerNames(rows.map((r) => r.buyerId ?? ''));

    var changed = false;
    for (final r in rows) {
      final id = (r.id ?? '').trim();
      if (id.isEmpty) continue;
      final prev = _reservationStatusCache[id];
      final status = r.status;
      if (prev == status && prev != null) continue;
      _reservationStatusCache[id] = status;

      final ref = _refForLiveItem(r.liveItemId);
      if (prev == null &&
          status == 'pending' &&
          LiveReservationQueueService.isOpenSellerTreatReservation(
            status: status,
            notes: r.notes,
          )) {
        final name = _buyerNameLabel(r);
        if (r.source == 'facebook_manual' || r.source == 'helper_manual') {
          _appendActivity(
            'res-new-$id',
            '$name pediu pagamento externo · $ref',
            r.createdAt,
            LiveOpsActivityKind.externalPayment,
            r.liveItemId,
            id,
            'Ver reserva',
          );
        } else {
          _appendActivity(
            'res-new-$id',
            '$name adicionou $ref ao saco',
            r.createdAt,
            LiveOpsActivityKind.bagAdd,
            r.liveItemId,
            id,
            'Ver artigo',
          );
        }
        changed = true;
      } else if (status == 'accepted' && prev != 'accepted') {
        final name = _buyerNameLabel(r);
        _appendActivity(
          'res-acc-$id',
          '$name — reserva aceite · $ref${_reservationDeadlineLabel(r)}',
          r.updatedAt ?? r.createdAt,
          LiveOpsActivityKind.reservationAccepted,
          r.liveItemId,
          id,
          'Ver reserva',
        );
        changed = true;
      } else if (status == 'converted' && prev != 'converted') {
        final name = _buyerNameLabel(r);
        final price = _priceLabelForLiveItem(r.liveItemId);
        _appendActivity(
          'res-conv-$id',
          price != null
              ? '$name comprou $ref ($price)'
              : '$name comprou $ref',
          r.updatedAt ?? r.createdAt,
          LiveOpsActivityKind.purchase,
          r.liveItemId,
          id,
          'Ver pagamento',
        );
        changed = true;
      } else if (status == 'rejected' &&
          prev != 'rejected' &&
          LiveReservationQueueService.isBuyerCancelledReservation(
            status: status,
            notes: r.notes,
          )) {
        final name = _buyerNameLabel(r);
        _appendActivity(
          'res-can-$id',
          '$name cancelou a reserva · $ref',
          r.updatedAt ?? r.createdAt,
          LiveOpsActivityKind.bagAdd,
          r.liveItemId,
          id,
          'Ver reservas',
        );
        _activityEvents.removeWhere(
          (e) =>
              e.requestId == id &&
              (e.id == 'res-new-$id' || e.id == 'res-acc-$id'),
        );
        changed = true;
      } else if (status == 'expired' && prev != 'expired') {
        final name = _buyerNameLabel(r);
        _appendActivity(
          'res-exp-$id',
          'A reserva de $name expirou · $ref',
          r.updatedAt ?? r.createdAt,
          LiveOpsActivityKind.system,
          r.liveItemId,
          id,
          'Ver artigo',
        );
        _activityEvents.removeWhere(
          (e) =>
              e.requestId == id &&
              (e.id == 'res-new-$id' || e.id == 'res-acc-$id'),
        );
        changed = true;
      }
    }

    for (final log in _recentStaffLogs) {
      final id = (log.id ?? '').trim();
      if (id.isEmpty || _staffLogIdsSeen.contains(id)) continue;
      final actorId = (log.performedByUserId ?? '').trim();
      final action = (log.actionType ?? '').trim();
      if (actorId == widget.sellerId.trim() &&
          (action == 'live_reservation_accept' ||
              action == 'reservation_accepted')) {
        _staffLogIdsSeen.add(id);
        continue;
      }
      _staffLogIdsSeen.add(id);
      final text = _staffLogToActivity(log);
      if (text != null) {
        final meta = log.metadataRaw;
        final isAccept = (log.actionType ?? '').contains('accept');
        _appendActivity(
          'staff-$id',
          text,
          log.createdAt,
          LiveOpsActivityKind.helperAction,
          meta['live_item_id']?.toString(),
          meta['request_id']?.toString() ?? meta['target_id']?.toString(),
          isAccept ? 'Ver reserva' : 'Ver artigo',
        );
        changed = true;
      }
    }

    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      final id = (r.id ?? '').trim();
      if (id.isEmpty) continue;
      final status = r.status ?? '';
      final prev = _catalogStatusCache[id];
      if (prev == status) continue;
      _catalogStatusCache[id] = status;
      if (status == 'sold' && prev != 'sold') {
        _maybeRecordSoldOutActivity(r);
        changed = true;
      } else if (status != 'sold') {
        final itemId = id;
        final snap = _stockByItemId[itemId];
        if (snap != null) {
          _maybeRecordLowStockActivity(
            liveItemId: itemId,
            refLabel: _itemRefLabel(r),
            availableQty: snap.availableQty,
          );
        }
      }
    }

    if (changed && mounted) setState(() {});
  }

  Future<void> _refreshLiveOrderMetrics() async {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      final seenOrderIds = <String>{};
      var count = 0;
      var value = 0.0;

      double unitPriceForOrder(OrdersRow o) {
        final pid = o.productId?.trim() ?? '';
        if (pid.isEmpty) return 0;
        for (final row in _catalogRows ?? const <LiveItemsRow>[]) {
          if (row.productId?.trim() == pid ||
              row.checkoutProductId?.trim() == pid) {
            return row.price ?? 0;
          }
        }
        return 0;
      }

      double priceForOrder(OrdersRow o) {
        final qty = o.quantity < 1 ? 1 : o.quantity;
        final unit = unitPriceForOrder(o);
        final shipping = LiveInStreamCheckout.shippingCostForMethod(
          o.shippingMethod ?? '',
        );
        final isDirect = (o.paymentMethod ?? '').trim() ==
            LiveInStreamCheckout.paymentDirect;
        return liveSellerEarningsEur(
          storedPriceTotal: o.priceTotal ?? 0,
          isDirectPayment: isDirect,
          lineItemEur: unit > 0 ? unit * qty : 0,
          shippingEur: shipping,
        );
      }

      void absorb(OrdersRow o) {
        final id = o.id?.trim() ?? '';
        if (id.isNotEmpty && seenOrderIds.contains(id)) return;
        if (normalizeOrderStatusKey(o.status) != 'pago') return;
        if (id.isNotEmpty) seenOrderIds.add(id);
        count += o.quantity < 1 ? 1 : o.quantity;
        value += priceForOrder(o);
      }

      final orders = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('live_id', liveId),
        limit: 500,
      );
      for (final o in orders) {
        absorb(o);
      }

      final awaitingConfirmationKeys = <String>{};
      for (final o in orders) {
        if (normalizeOrderStatusKey(o.status) != 'aguarda_confirmacao') {
          continue;
        }
        final liid = o.liveItemId?.trim() ?? '';
        final bid = o.buyerId?.trim() ?? '';
        if (liid.isEmpty || bid.isEmpty) continue;
        awaitingConfirmationKeys.add('$liid|$bid');
      }
      if (mounted) {
        setState(() {
          _liveOrdersAwaitingConfirmationKeys = awaitingConfirmationKeys;
        });
      }

      final productIds = <String>{};
      void addProductId(String? pid) {
        final id = pid?.trim() ?? '';
        if (id.isNotEmpty) productIds.add(id);
      }

      try {
        final catalogRows = await LiveItemsTable().queryRows(
          queryFn: (q) => q.eqOrNull('live_id', liveId),
          limit: 500,
        );
        for (final row in catalogRows) {
          addProductId(row.productId);
          addProductId(row.checkoutProductId);
        }
      } catch (_) {}
      for (final row in _catalogRows ?? const <LiveItemsRow>[]) {
        addProductId(row.productId);
        addProductId(row.checkoutProductId);
      }

      var legacyRowsScanned = 0;
      var pagoWithLiveId = 0;
      var legacyPagoNoLiveIdCount = 0;
      var legacyPagoNoLiveIdEur = 0.0;
      var legacyPagoOtherLiveIdCount = 0;
      for (final o in orders) {
        if (normalizeOrderStatusKey(o.status) == 'pago') pagoWithLiveId++;
      }
      if (productIds.isNotEmpty) {
        final legacy = await OrdersTable().queryRows(
          queryFn: (q) => q
              .inFilter('product_id', productIds.toList())
              .eqOrNull('seller_id', widget.sellerId.trim()),
          limit: 500,
        );
        legacyRowsScanned = legacy.length;
        for (final o in legacy) {
          if (normalizeOrderStatusKey(o.status) != 'pago') continue;
          final orderLiveId = o.liveId?.trim() ?? '';
          final qty = o.quantity < 1 ? 1 : o.quantity;
          final lineEur = priceForOrder(o);
          if (orderLiveId.isEmpty) {
            legacyPagoNoLiveIdCount += qty;
            legacyPagoNoLiveIdEur += lineEur;
            continue;
          }
          if (orderLiveId != liveId) {
            legacyPagoOtherLiveIdCount += qty;
            continue;
          }
          absorb(o);
        }
      }

      var tipCount = 0;
      var tipValueEur = 0.0;
      final tipPayments = <({String buyerLabel, double amountEur})>[];
      try {
        final tipRows = await SupaFlow.client
            .from('live_tips')
            .select('id, buyer_id, seller_amount, amount, status')
            .eq('live_id', liveId)
            .eq('status', 'completed');
        final buyerIds = <String>{};
        final tipEntries = <({String buyerId, double amountEur})>[];
        final tipRowLog = <Map<String, dynamic>>[];
        for (final row in tipRows as List) {
          final map = Map<String, dynamic>.from(row as Map);
          final sellerAmount = map['seller_amount'];
          final gross = map['amount'];
          num? amount;
          if (sellerAmount is num) {
            amount = sellerAmount;
          } else if (gross is num) {
            amount = gross;
          }
          if (amount == null) continue;
          final buyerId = map['buyer_id']?.toString().trim() ?? '';
          tipValueEur += amount.toDouble();
          tipCount += 1;
          tipEntries.add((buyerId: buyerId, amountEur: amount.toDouble()));
          tipRowLog.add({
            'id': map['id']?.toString(),
            'seller_amount': sellerAmount,
            'amount': gross,
            'used_eur': amount.toDouble(),
          });
          if (buyerId.isNotEmpty) buyerIds.add(buyerId);
        }
        _logStudio(
          'wallet.tips_query',
          data: {
            'rows_raw': (tipRows as List).length,
            'rows_used': tipCount,
            'tip_value_eur': tipValueEur,
            'tips': tipRowLog,
          },
        );
        final buyerNames = <String, String>{};
        if (buyerIds.isNotEmpty) {
          final profiles = await ProfilesDirectoryTable().queryRows(
            queryFn: (q) => q.inFilter('id', buyerIds.toList()),
          );
          for (final p in profiles) {
            final id = p.id?.trim() ?? '';
            if (id.isEmpty) continue;
            buyerNames[id] = (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim()
                : 'Utilizador';
          }
        }
        for (final entry in tipEntries) {
          final label = entry.buyerId.isEmpty
              ? 'Utilizador'
              : (buyerNames[entry.buyerId] ?? 'Utilizador');
          tipPayments.add((buyerLabel: label, amountEur: entry.amountEur));
        }
      } catch (e) {
        _logStudio('wallet.tips_query', status: 'error', error: e);
      }

      if (!mounted) return;
      setState(() {
        _livePaidOrdersCount = count;
        _livePaidOrdersValueEur = value;
        _liveTipsCount = tipCount;
        _liveTipsValueEur = tipValueEur;
        _liveTipPayments = tipPayments;
      });
      _logStudio(
        'wallet.state_applied',
        data: {
          'paid_count': count,
          'paid_value_eur': value,
          'tips_count': tipCount,
          'tips_value_eur': tipValueEur,
          'wallet_total_eur': value + tipValueEur,
        },
      );
      _notifyOpsTotals();
      _logStudio(
        'payments.refresh',
        data: {
          'paid_count': count,
          'paid_value_eur': value,
          'orders_with_live_id': orders.length,
          'pago_with_live_id': pagoWithLiveId,
          'catalog_product_ids': productIds.length,
          'legacy_orders_scanned': legacyRowsScanned,
          'legacy_pago_no_live_id_count': legacyPagoNoLiveIdCount,
          'legacy_pago_no_live_id_eur': legacyPagoNoLiveIdEur,
          'legacy_pago_other_live_id_count': legacyPagoOtherLiveIdCount,
          'phantom_risk': legacyPagoNoLiveIdEur > 0.01,
          'tips_completed_count': tipCount,
          'tips_completed_eur': tipValueEur,
          'live_wallet_total_eur': value + tipValueEur,
        },
      );
      if (legacyPagoNoLiveIdEur > 0.01) {
        _logStudio(
          'payments.ghost_audit',
          data: {
            'live_id': liveId,
            'would_be_phantom_eur': legacyPagoNoLiveIdEur,
            'would_be_phantom_qty': legacyPagoNoLiveIdCount,
            'panel_shows_eur': value,
          },
        );
      }
    } catch (e) {
      _logStudio('payments.refresh', status: 'error', error: e);
    }
  }

  void _markPublicChatRead() {
    _publicChatReadAt = DateTime.now().toUtc();
    if (_publicChatUnread != 0 && mounted) {
      setState(() => _publicChatUnread = 0);
    }
  }

  void _updatePublicChatUnread(List<LiveRoomMessage> msgs) {
    if (!mounted) return;
    final sellerId = widget.sellerId.trim();
    var unread = 0;
    for (final m in msgs) {
      if (m.kind == LiveRoomMessageKind.system ||
          m.kind == LiveRoomMessageKind.tip) {
        continue;
      }
      final uid = m.userId?.trim() ?? '';
      if (uid.isNotEmpty && uid == sellerId) continue;
      final at = m.createdAt;
      if (at != null && at.isAfter(_publicChatReadAt)) unread++;
    }
    if (unread == _publicChatUnread) return;
    setState(() => _publicChatUnread = unread);
  }

  int get _chatNavBadge => _privateUnread + _publicChatUnread;

  void _subscribeOrdersRealtime() {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      _ordersRealtimeSub?.cancel();
    _tipsRealtimeSub?.cancel();
      // Scope à live actual — evita refreshes por encomendas marketplace noutros sítios.
      _ordersRealtimeSub = SupaFlow.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) {
            // Um caminho só: métricas + fila + stock (sem triplicar fetchMany).
            unawaited(_syncLiveOpsMetrics());
          });
    } catch (_) {}
  }

  void _subscribeLiveTipsRealtime() {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      _tipsRealtimeSub?.cancel();
      _tipsRealtimeSub = SupaFlow.client
          .from('live_tips')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) {
            unawaited(_refreshLiveOrderMetrics());
            unawaited(_syncLiveOpsMetrics());
          });
    } catch (_) {}
  }

  LiveOpsTotals _computeOpsTotals() {
    final pending = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isOpenSellerTreatReservation(
            status: r.status,
            notes: r.notes,
          ) &&
              r.status == 'pending',
        )
        .toList();
    final accepted = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();
    final converted =
        _reservationQueue.where((r) => r.status == 'converted').toList();
    final rowsById = {
      for (final r in _catalogRows ?? const <LiveItemsRow>[]) (r.id ?? ''): r,
    };
    var bag = 0;
    var external = 0;
    for (final r in pending) {
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      final src = r.source;
      if (src == 'fleaber_live') {
        bag += q;
      } else if (src == 'facebook_manual' || src == 'helper_manual') {
        external += q;
      }
    }
    var salesCount = 0;
    var estimatedCatalogEur = 0.0;
    for (final r in converted) {
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      salesCount += q;
      final item = rowsById[(r.liveItemId ?? '').trim()];
      final unit = item?.price ?? 0;
      estimatedCatalogEur += liveSellerEarningsEstimateFromCatalog(unit * q);
    }
    if (_livePaidOrdersCount > salesCount) {
      salesCount = _livePaidOrdersCount;
    }
    // Ganhos = totais das encomendas pagas (o que realmente entrou).
    // Sem encomenda ainda: só artigos do catálogo — nunca taxa de protecção.
    var salesValue = _livePaidOrdersValueEur > 0.009
        ? _livePaidOrdersValueEur
        : estimatedCatalogEur;
    // Gorjetas concluídas (líquido vendedor) entram na carteira/KPI do directo.
    salesValue += _liveTipsValueEur;
    var stalePending = 0;
    for (final r in pending) {
      if (_isReservationStale(r)) stalePending++;
    }
    final conflicts = _reservationQueue
        .where((r) => r.status == 'rejected' || r.status == 'expired')
        .length;
    final actionPending = pending.length +
        _reservationQueue
            .where(
              (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
                status: r.status,
                notes: r.notes,
              ),
            )
            .length;
    return LiveOpsTotals(
      bagCount: bag,
      externalCount: external,
      pendingPaymentCount: pending.length,
      conflictCount: conflicts,
      lowStockCount: _activeOpsSnapshot?.lowStock == true ? 1 : 0,
      activeHelpers: _teamHelpersActive,
      queuePending: pending.length,
      salesCount: salesCount,
      salesValueEur: salesValue,
      pendingCheckoutCount: accepted.length,
      actionPendingCount: actionPending,
      stalePendingCount: stalePending,
    );
  }

  static const _reservationStaleAfter = Duration(minutes: 10);

  bool _isReservationStale(LiveReservationRequestsRow r) {
    if (r.status != 'pending') return false;
    final c = r.createdAt;
    if (c == null) return false;
    return DateTime.now().difference(c.toLocal()) >= _reservationStaleAfter;
  }

  List<LiveReservationRequestsRow> _sortReservationsByUrgency(
    List<LiveReservationRequestsRow> items,
  ) {
    final copy = List<LiveReservationRequestsRow>.from(items);
    copy.sort((a, b) {
      final qa = LiveReservationQueueService.notesNeedQtyConfirm(a.notes);
      final qb = LiveReservationQueueService.notesNeedQtyConfirm(b.notes);
      if (qa != qb) return qa ? -1 : 1;
      final sa = _isReservationStale(a);
      final sb = _isReservationStale(b);
      if (sa != sb) return sa ? -1 : 1;
      final sameItem = (a.liveItemId ?? '').trim() == (b.liveItemId ?? '').trim() &&
          (a.liveItemId ?? '').trim().isNotEmpty;
      if (sameItem) {
        final pa = a.queuePosition ?? 9999;
        final pb = b.queuePosition ?? 9999;
        if (pa != pb) return pa.compareTo(pb);
      }
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return copy;
  }

  Future<void> _advanceToNextCatalogItem() async {
    final rows = _catalogRows;
    if (rows == null || rows.isEmpty) return;
    final active = _activeCatalogRow;
    final activeId = active?.id?.trim() ?? '';
    var startIdx = 0;
    if (activeId.isNotEmpty) {
      final idx = rows.indexWhere((r) => (r.id ?? '').trim() == activeId);
      if (idx >= 0) startIdx = idx + 1;
    }
    for (var i = startIdx; i < rows.length; i++) {
      final row = rows[i];
      if (LiveVendorSellerCopy.isLiveItemUnavailable(row.status)) continue;
      await _setActiveCatalogRow(row);
      return;
    }
    for (var i = 0; i < startIdx; i++) {
      final row = rows[i];
      if (LiveVendorSellerCopy.isLiveItemUnavailable(row.status)) continue;
      await _setActiveCatalogRow(row);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há mais artigos disponíveis no catálogo.'),
        ),
      );
    }
  }

  Future<void> _refreshActiveOpsSnapshot({
    bool forceFetch = false,
    bool bypassRebuildLock = false,
  }) async {
    final active = _activeCatalogRow;
    if (active == null) {
      if (!mounted) return;
      if (!bypassRebuildLock && _deferCatalogSync) {
        _activeOpsSnapshot = null;
        return;
      }
      setState(() => _activeOpsSnapshot = null);
      return;
    }
    final itemId = active.id?.trim() ?? '';
    LiveCatalogStockSnapshot? snap;
    if (forceFetch) {
      snap = await LiveCatalogStockService.fetch(itemId);
    } else {
      snap = _stockByItemId[itemId];
      snap ??= await LiveCatalogStockService.fetch(itemId);
    }
    if (snap != null && mounted) {
      _stockByItemId[itemId] = snap;
    }

    var inBag = snap?.pendingBagQty ?? 0;
    var external = 0;
    var interested = snap?.pendingBagQty ?? 0;
    if (snap == null) {
      final pending = _reservationQueue.where(
        (r) =>
            LiveReservationQueueService.isOpenSellerTreatReservation(
              status: r.status,
              notes: r.notes,
            ) &&
            r.status == 'pending' &&
            (r.liveItemId ?? '').trim() == itemId,
      );
      for (final r in pending) {
        final q = r.requestedQty < 1 ? 1 : r.requestedQty;
        final src = r.source;
        if (src == 'fleaber_live') {
          inBag += q;
        } else {
          external += q;
        }
        interested += q;
      }
    } else {
      for (final r in _reservationQueue) {
        if ((r.liveItemId ?? '').trim() != itemId) continue;
        if (!LiveReservationQueueService.isOpenSellerTreatReservation(
          status: r.status,
          notes: r.notes,
        )) {
          continue;
        }
        if (r.status != 'pending') continue;
        final src = r.source;
        if (src == 'facebook_manual' || src == 'helper_manual') {
          external += r.requestedQty < 1 ? 1 : r.requestedQty;
        }
      }
    }
    final metrics = _metricsForLiveItem(active);
    final reservationsTotal = metrics.reservations;
    final sold = snap?.soldConvertedQty ?? metrics.sold;
    final availQty = snap?.availableQty ?? metrics.available;

    if (!mounted) return;
    final snapshot = LiveItemOpsSnapshot(
      available: availQty,
      sold: sold,
      inBag: inBag,
      interested: reservationsTotal,
      externalRequests: external,
      pendingPayments: reservationsTotal,
    );
    if (!bypassRebuildLock && _deferCatalogSync) {
      _activeOpsSnapshot = snapshot;
      _notifyOpsTotals();
      return;
    }
    setState(() {
      _activeOpsSnapshot = snapshot;
    });
    _notifyOpsTotals();
  }

  @override
  void didUpdateWidget(covariant LiveVendorStudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activePanel != widget.activePanel) {
      if (widget.activePanel.isOperationFamily) {
        _operationSection = widget.activePanel.defaultOperationSection;
      }
      if (widget.activePanel == SellerLiveActivePanel.chat) {
        _chatCompact = false;
        _chatFocused = false;
      }
    }
  }

  void setActivePanel(
    SellerLiveActivePanel panel, {
    SellerOperationSection? section,
  }) {
    final normalized = panel.normalized;
    if (section != null && _operationSection != section) {
      setState(() => _operationSection = section);
    } else if (panel.isOperationFamily && panel != SellerLiveActivePanel.operation) {
      final sec = panel.defaultOperationSection;
      if (_operationSection != sec) {
        setState(() => _operationSection = sec);
      }
    }

    if (_panel.normalized == normalized &&
        normalized != SellerLiveActivePanel.operation) {
      return;
    }
    if (normalized == SellerLiveActivePanel.operation &&
        _panel.isOperationFamily &&
        section == null &&
        _panel.normalized == normalized) {
      return;
    }

    if (normalized != SellerLiveActivePanel.chat && widget.privateChatMode) {
      widget.onPrivateChatModeChanged?.call(false);
    }
    if (normalized == SellerLiveActivePanel.chat) {
      _markPublicChatRead();
    }
    widget.onActivePanelChanged?.call(normalized);
    unawaited(_refreshActiveOpsSnapshot(forceFetch: true));
  }

  void setOperationSection(SellerOperationSection section) {
    if (_operationSection != section) {
      setState(() => _operationSection = section);
    }
    if (!_panel.isOperationFamily) {
      setActivePanel(SellerLiveActivePanel.operation, section: section);
    }
  }

  void togglePanel(SellerLiveActivePanel panel) {
    if (panel == SellerLiveActivePanel.operation || panel.isOperationFamily) {
      if (_panel.isOperationFamily) {
        setActivePanel(SellerLiveActivePanel.none);
      } else {
        setActivePanel(SellerLiveActivePanel.operation);
      }
      return;
    }
    final target = panel.normalized;
    final next =
        _panel.normalized == target ? SellerLiveActivePanel.none : target;
    setActivePanel(next);
  }

  void setOpsMode(LiveSellerOpsMode mode) {
    final panel = switch (mode) {
      LiveSellerOpsMode.minimal => SellerLiveActivePanel.none,
      LiveSellerOpsMode.operation => SellerLiveActivePanel.operation,
      LiveSellerOpsMode.catalog => SellerLiveActivePanel.catalog,
    };
    setActivePanel(panel);
  }

  void openOperationalQueue({SellerOperationSection? section}) =>
      setActivePanel(
        SellerLiveActivePanel.operation,
        section: section ?? SellerOperationSection.queue,
      );

  /// Harness Maestro (debug): abre Operação e expande categoria de reservas.
  void prepareMaestroHarnessUi({
    SellerOperationSection section = SellerOperationSection.queue,
    String? expandCategory,
  }) {
    openOperationalQueue(section: section);
    final wanted = _categoryFromHarnessParam(expandCategory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _loadReservationQueue(refreshMetrics: true).then((_) async {
          if (!mounted) return;
          await _refreshActiveOpsSnapshot(forceFetch: true);
          if (!mounted) return;
          if (section != SellerOperationSection.queue) return;
          if (wanted != null) {
            if (_reservationsForCategory(wanted).isNotEmpty) {
              setState(() => _expandedReservationCategory = wanted);
            }
            return;
          }
          for (final cat in _ReservationListCategory.values) {
            if (_reservationsForCategory(cat).isNotEmpty) {
              setState(() => _expandedReservationCategory = cat);
              break;
            }
          }
        }),
      );
    });
  }

  _ReservationListCategory? _categoryFromHarnessParam(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'inbag' || 'in_bag' || 'nosaco' => _ReservationListCategory.inBag,
      'pending' || 'pendentes' => _ReservationListCategory.pending,
      'accepted' || 'aceites' => _ReservationListCategory.accepted,
      'external' || 'externos' => _ReservationListCategory.external,
      'unpaid' || 'sempagamento' => _ReservationListCategory.unpaid,
      _ => null,
    };
  }

  int get queuePendingBadge => _computeOpsTotals().actionPendingCount;

  Future<void> _openAmazonScanFlow() async {
    final liveId = widget.liveId.trim();
    final sellerId = widget.sellerId.trim();
    if (liveId.isEmpty || sellerId.isEmpty || !mounted) return;
    final item = await LiveAmazonScanSheet.open(context);
    if (item == null || !mounted) return;
    LiveAmazonPresentOverlay.show(
      context,
      item: item,
      seconds: 10,
      onAddToVitrine: () async {
        try {
          final liveItemId = await LiveAmazonLiveBridge.instance.addToVitrine(
            liveId: liveId,
            sellerId: sellerId,
            item: item,
          );
          if (liveItemId == null || liveItemId.isEmpty) return;
          await LiveAmazonLiveBridge.instance.setActiveLiveItem(
            liveId: liveId,
            liveItemId: liveItemId,
          );
          LiveAmazonPresentOverlay.hide();
          if (!mounted) return;
          _pinnedVitrineItemId = liveItemId;
          await _loadCatalogRows(silent: true);
          await _refreshStockCache(itemIds: [liveItemId]);
          _logStudio('amazon.scan.add', liveItemId: liveItemId);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Artigo na montra do directo.')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Montra: $e')),
          );
        }
      },
    );
  }

  Future<void> _handleQuickAction(String id) async {
    final active = _activeCatalogRow;
    switch (id) {
      case 'show':
        if (active != null) await _setActiveCatalogRow(active);
        break;
      case 'sold':
        if (active != null) {
          await _markCatalogItemSold(active);
        }
        break;
      case 'next':
        await _advanceToNextCatalogItem();
        break;
      case 'last_unit':
        await LiveReservationQueueService().postSystemMessage(
          liveId: widget.liveId,
          body: '🔥 Última unidade disponível!',
        );
        break;
      case 'stock':
        if (active != null) {
          await _showStockAdjustSheet(active);
        }
        break;
      case 'amazon_scan':
        await _openAmazonScanFlow();
        break;
      case 'external':
        if (active != null) {
          await _addManualReservation(
            active,
            LiveReservationSource.facebookManual,
          );
        }
        break;
      case 'queue':
      case 'conflict':
        openOperationalQueue(section: SellerOperationSection.queue);
        break;
      case 'helper':
        unawaited(_openTeamSheet());
        break;
    }
    unawaited(_loadReservationQueue());
  }

  void _subscribeReservationRealtime() {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      _reservationRealtimeSub?.cancel();
      _reservationRealtimeSub = SupaFlow.client
          .from('live_reservation_requests')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) {
            if (_deferCatalogSync) {
              _deferredCatalogReload = true;
              _deferredCatalogReloadSilent = true;
              return;
            }
            // Fila + stock + métricas numa passagem (sem reload catálogo + stock ×2).
            unawaited(_syncLiveOpsMetrics());
            if (mounted) setState(() {});
          });
    } catch (_) {}
  }

  /// Reservas noutros directos/gravados (mesma ref) → actualizar stock dos cards.
  void _subscribeSellerReservationRealtime() {
    final sellerId = widget.sellerId.trim();
    if (sellerId.isEmpty) return;
    try {
      _sellerReservationRealtimeSub?.cancel();
      _sellerReservationRealtimeSub = SupaFlow.client
          .from('live_reservation_requests')
          .stream(primaryKey: ['id'])
          .eq('seller_id', sellerId)
          .listen((_) {
            if (_deferCatalogSync) {
              _deferredCatalogReload = true;
              _deferredCatalogReloadSilent = true;
              return;
            }
            // Só stock (cross-pool); sem sync métricas completo da live.
            _scheduleStockCacheRefresh();
            if (mounted) setState(() {});
          });
    } catch (_) {}
  }

  void _subscribeCatalogRealtime() {
    final liveId = widget.liveId.trim();
    if (liveId.isEmpty) return;
    try {
      _catalogRealtimeSub?.cancel();
      _catalogRealtimeSub = SupaFlow.client
          .from('live_items')
          .stream(primaryKey: ['id'])
          .eq('live_id', liveId)
          .listen((_) => _scheduleCatalogReload(silent: true));
    } catch (_) {}
  }

  void _tickDuration() {
    final start = widget.startedAt;
    if (start == null) return;
    final sec = DateTime.now().difference(start).inSeconds.clamp(0, 999999);
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    final label = '$m:$s';
    if (label != _durationLabel && mounted) {
      setState(() => _durationLabel = label);
    }
  }

  Future<void> _refreshTipContributors(List<LiveRoomMessage> msgs) async {
    final tipIds = msgs
        .map((m) => m.tipId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (tipIds.isEmpty) return;
    try {
      final rows = await SupaFlow.client
          .from('live_tips')
          .select('id, buyer_id')
          .inFilter('id', tipIds);
      final tipToBuyer = <String, String>{};
      final buyerIds = <String>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row);
        final tipId = map['id']?.toString();
        final buyerId = map['buyer_id']?.toString();
        if (tipId != null && buyerId != null) {
          tipToBuyer[tipId] = buyerId;
          buyerIds.add(buyerId);
        }
      }
      if (buyerIds.isEmpty) return;
      final profiles = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.inFilter('id', buyerIds.toList()),
      );
      final names = {
        for (final p in profiles)
          if (p.id != null)
            p.id!: (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim()
                : 'Utilizador',
      };
      final next = <String, String>{};
      tipToBuyer.forEach((tipId, buyerId) {
        final n = names[buyerId];
        if (n != null) next[tipId] = n;
      });
      if (mounted) setState(() => _tipContributors = next);
    } catch (_) {}
  }

  @override
  void dispose() {
    _publicReplyController.dispose();
    _durationTimer?.cancel();
    _catalogReloadDebounce?.cancel();
    _stockRefreshDebounce?.cancel();
    _catalogListScroll.dispose();
    _reservationRealtimeSub?.cancel();
    _sellerReservationRealtimeSub?.cancel();
    _reservationPollTimer?.cancel();
    _catalogStockPollTimer?.cancel();
    _rafflePollTimer?.cancel();
    _raffleRealtimeSub?.cancel();
    _raffleEntriesRealtimeSub?.cancel();
    _catalogRealtimeSub?.cancel();
    _ordersRealtimeSub?.cancel();
    _tipsRealtimeSub?.cancel();
    final pub = _publicRoom;
    final priv = _privateRoom;
    _publicRoom = null;
    _privateRoom = null;
    if (pub != null) unawaited(pub.dispose());
    if (priv != null) unawaited(priv.dispose());
    super.dispose();
  }

  String _reservationActionLabel(String action) {
    return switch (action) {
      'accept' => 'aceitar',
      'reject' => 'recusar',
      'skip' => 'ignorar',
      _ => action,
    };
  }

  String _reservationProcessErrorMessage(String action, Object error) {
    final err = error.toString().toLowerCase();
    if (err.contains('request_not_found')) {
      return 'Reserva já não existe.';
    }
    if (err.contains('item_sold')) {
      return 'Artigo já vendido — reserva indisponível.';
    }
    if (err.contains('not_allowed') || err.contains('permission')) {
      return 'Sem permissão para ${_reservationActionLabel(action)} esta reserva.';
    }
    if (err.contains('insufficient_stock') || err.contains('out_of_stock')) {
      return 'Sem stock livre — podes aceitar para lista de espera.';
    }
    // Guard prod antigo: marketplace_product com live_items.quantity NULL
    // → live_item_qty_below_reservations ao aceitar (fix: migration 20260920).
    if (err.contains('live_item_qty_below_reservations')) {
      return 'Não foi possível aceitar: stock do artigo no catálogo '
          'não está alinhado com o guard da live. Contacta suporte Fleaber.';
    }
    if (err.contains('invalid_action')) {
      return 'Acção inválida para esta reserva.';
    }
    return 'Não foi possível ${_reservationActionLabel(action)} a reserva. Tenta outra vez.';
  }

  void _showReservationProcessError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_reservationProcessErrorMessage(action, error)),
      ),
    );
  }

  Future<bool> _confirmAcceptOverbook(LiveReservationRequestsRow row) async {
    final itemId = (row.liveItemId ?? '').trim();
    if (itemId.isEmpty) return true;
    final snap =
        _stockByItemId[itemId] ?? await LiveCatalogStockService.fetch(itemId);
    if (snap == null) return true;
    final reqQty = row.requestedQty < 1 ? 1 : row.requestedQty;
    final afterAccept = snap.reservedAcceptedQty + reqQty;
    final overStock = afterAccept > snap.totalQty;
    LiveItemsRow? itemRow;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == itemId) {
        itemRow = r;
        break;
      }
    }
    final st = (itemRow?.status ?? '').trim().toLowerCase();
    final noStockBadge = st == 'sold' ||
        st == 'reserved_full' ||
        snap.availableQty <= 0;
    if (!overStock && !noStockBadge) return true;
    if (!mounted) return false;
    final ref = _refForLiveItem(itemId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2228),
        title: Text(
          'Aceitar sem stock?',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Este artigo ($ref) já não tem stock disponível para mais uma reserva aceite. '
          'Queres mesmo aceitar este pedido na mesma?',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007782),
            ),
            child: const Text('Sim, aceitar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _processReservation(
    LiveReservationRequestsRow row,
    String action,
  ) async {
    final requestId = row.id?.trim() ?? '';
    if (requestId.isEmpty) {
      _showReservationProcessError(action, 'request_not_found');
      return;
    }
    if (action == 'accept') {
      final confirmed = await _confirmAcceptOverbook(row);
      if (!confirmed) return;
    }
    try {
      final res = await LiveReservationQueueService().processRequest(
        requestId: requestId,
        action: action,
      );
      if (res['ok'] != true) {
        _logStudio(
          'reservation.$action',
          liveItemId: row.liveItemId,
          requestId: requestId,
          status: 'error',
          data: {'rpc_error': res['error']?.toString()},
          error: res['error'] ?? 'reservation_failed',
        );
        _showReservationProcessError(
          action,
          res['error']?.toString() ?? 'reservation_failed',
        );
        return;
      }
      _logStudio(
        'reservation.$action',
        liveItemId: row.liveItemId,
        requestId: requestId,
        data: {
          'item_status': res['item_status']?.toString(),
          'reserved_qty': res['reserved_qty'],
          'item_qty': res['item_qty'],
          'source': row.source,
        },
      );
      await StaffActionLog.record(
        sellerId: widget.sellerId.trim(),
        actionType: 'live_reservation_$action',
        targetEntity: 'live_reservation_requests',
        targetId: row.id,
        metadata: {
          'live_id': row.liveId,
          'live_item_id': row.liveItemId,
          'source': row.source,
          'queue_position': row.queuePosition,
        },
      );
      // Aceite nas Operações do directo deve também promover a encomenda
      // `reserva_pendente` (pagamento fora da app) — senão o saco fica
      // «aguarda vendedora» com o card de aceite já resolvido nas ops.
      if (action == 'accept') {
        await _promotePendingDirectOrdersForReservation(row);
      }
      final liveId = row.liveId?.trim() ?? '';
      final qtyConfirm =
          LiveReservationQueueService.notesNeedQtyConfirm(row.notes);
      if (qtyConfirm && liveId.isNotEmpty) {
        final label = _itemDisplayLabelForLiveItem(row.liveItemId);
        final q = row.requestedQty < 1 ? 1 : row.requestedQty;
        if (action == 'accept') {
          setState(() => _dismissedUrgentRequestIds.add(requestId));
        } else if (action == 'reject' || action == 'skip') {
          setState(() => _dismissedUrgentRequestIds.add(requestId));
          await LiveReservationQueueService().postSystemMessage(
            liveId: liveId,
            body:
                '❌ Recusaste o pedido de $q un. · $label (acima do stock na live)',
            senderLabel: 'Sistema',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pedido recusado — stock insuficiente'),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
      await _loadReservationQueue(refreshMetrics: true);
      final itemId = row.liveItemId?.trim() ?? '';
      if (itemId.isNotEmpty) {
        await _refreshStockCache(itemIds: [itemId]);
      }
      await _syncLiveOpsMetrics();
      if (mounted) setState(() {});
    } catch (e) {
      _logStudio(
        'reservation.$action',
        liveItemId: row.liveItemId,
        requestId: requestId,
        status: 'error',
        error: e,
      );
      _showReservationProcessError(action, e);
    }
  }

  /// Após aceite nas ops (`live_reservation_requests`), promove encomendas
  /// directas ainda em `reserva_pendente` do mesmo comprador+artigo.
  Future<void> _promotePendingDirectOrdersForReservation(
    LiveReservationRequestsRow row,
  ) async {
    final buyerId = row.buyerId?.trim() ?? '';
    final liveItemId = row.liveItemId?.trim() ?? '';
    if (buyerId.isEmpty || liveItemId.isEmpty) return;

    String productId = '';
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() != liveItemId) continue;
      productId = (r.checkoutProductId ?? r.productId)?.trim() ?? '';
      break;
    }

    try {
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('buyer_id', buyerId)
            .eqOrNull('live_item_id', liveItemId)
            .eqOrNull('status', 'reserva_pendente'),
        limit: 10,
      );
      for (final o in orders) {
        final oid = o.id?.trim() ?? '';
        if (oid.isEmpty) continue;
        final pid = (o.productId ?? productId).trim();
        if (pid.isEmpty) continue;
        await batataSellerAcceptReservaPendente(
          orderId: oid,
          buyerId: buyerId,
          productId: pid,
        );
        _logStudio(
          'reservation.accept.promote_order',
          liveItemId: liveItemId,
          requestId: row.id,
          data: {'order_id': oid},
        );
      }
    } catch (e) {
      _logStudio(
        'reservation.accept.promote_order',
        liveItemId: liveItemId,
        requestId: row.id,
        status: 'error',
        error: e,
      );
    }
  }

  Future<void> _addManualReservation(
    LiveItemsRow row,
    LiveReservationSource source,
  ) async {
    final buyerCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          source == LiveReservationSource.facebookManual
              ? 'Reserva manual (Facebook)'
              : 'Reserva manual (helper)',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: buyerCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome comprador',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final buyer = buyerCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
    if (buyer.isEmpty) return;
    await LiveReservationQueueService().addManualRequest(
      liveId: widget.liveId.trim(),
      liveItemId: row.id ?? '',
      sellerId: widget.sellerId.trim(),
      buyerLabel: buyer,
      source: source,
      qty: qty,
    );
    await _loadReservationQueue();
  }

  Future<void> _sendPublicReply() async {
    final room = _publicRoom;
    if (room == null || _sendingPublicReply) return;
    final text = _publicReplyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingPublicReply = true);
    try {
      final ok = await room.sendChat(text);
      if (!mounted) return;
      if (ok) {
        _publicReplyController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingPublicReply = false);
    }
  }

  bool _passesFilter(LiveRoomMessage m) {
    switch (_filter) {
      case _VendorChatFilter.all:
        return true;
      case _VendorChatFilter.questions:
        final t = m.body.toLowerCase();
        return t.contains('?') ||
            t.contains('tamanho') ||
            t.contains('preco') ||
            t.contains('preço') ||
            t.contains('envio');
      case _VendorChatFilter.reservations:
        final t = m.body.toLowerCase();
        return t.contains('reserv') ||
            t.contains('saco') ||
            t.contains('comprou') ||
            t.contains('pedido') ||
            t.contains('pagou');
      case _VendorChatFilter.system:
        return m.kind == LiveRoomMessageKind.system;
    }
  }

  void showMoreMenu() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xE6101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.groups_outlined, color: FleaberColors.teal),
                title: Text(
                  'Equipa · $_teamHelpersActive '
                  '${_teamHelpersActive == 1 ? 'ativo' : 'ativos'}',
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_openTeamSheet());
                },
              ),
              ListTile(
                leading: const Icon(Icons.facebook_outlined, color: Colors.white70),
                title: Text(
                  'Reserva manual (Facebook)',
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final active = _activeCatalogRow;
                  if (active != null) {
                    unawaited(_addManualReservation(
                      active,
                      LiveReservationSource.facebookManual,
                    ));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.desktop_windows_outlined,
                    color: Color(0xFF6ED8DE)),
                title: Text(
                  'Emparelhar PS Reader',
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                subtitle: Text(
                  'Código de 6 dígitos — comentários Facebook → fila',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_showPsReaderPairingDialog());
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTeamSheet() async {
    final helpers = SellerStaffContext.instance.myTeamHelpers
        .where(
          (h) =>
              (h.invitationStatus ?? '') == 'accepted' && h.active == true,
        )
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Equipa neste directo',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (helpers.isEmpty)
                  Text(
                    'Sem colaboradores activos. Convida helpers no perfil da loja.',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  )
                else
                  ...helpers.map(
                    (h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: FleaberColors.teal.withValues(alpha: 0.3),
                        child: Text(
                          (h.displayName ?? '?').trim().isNotEmpty
                              ? (h.displayName!.trim()[0]).toUpperCase()
                              : '?',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        h.displayName?.trim().isNotEmpty == true
                            ? h.displayName!.trim()
                            : 'Colaborador',
                        style: GoogleFonts.inter(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Activo no directo',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                if (_recentStaffLogs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Últimas acções (${_recentStaffLogs.length})',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._recentStaffLogs.take(5).map((log) {
                    final text = _staffLogToActivity(log);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        text ?? log.actionType ?? 'Acção',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 10,
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPrivateInbox() async {
    final priv = _privateRoom;
    if (priv == null) return;
    final threads = await priv.listThreadsForSeller();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mensagens privadas',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (threads.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Ainda não há mensagens privadas.',
                      style: GoogleFonts.inter(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = threads[i];
                        return ListTile(
                          leading: FleaberProfileAvatar(
                            userId: t.viewerId,
                            fullName: t.viewerLabel,
                            radius: 18,
                          ),
                          title: Text(
                            t.viewerLabel,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            t.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: Colors.white70),
                          ),
                          trailing: t.unreadCount > 0
                              ? CircleAvatar(
                                  radius: 11,
                                  backgroundColor: FleaberColors.teal,
                                  child: Text(
                                    '${t.unreadCount}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_openViewerThread(t.viewerId, t.viewerLabel));
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openViewerThread(String viewerId, String viewerLabel) async {
    final priv = _privateRoom;
    if (priv == null) return;
    await priv.markThreadRead(viewerId);
    if (!mounted) return;
    final replyCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        var entries = const <LiveThreadEntry>[];
        var loading = true;
        Future<void> reload(StateSetter setModal) async {
          final next = await priv.threadWithViewer(viewerId);
          if (!ctx.mounted) return;
          setModal(() {
            entries = next;
            loading = false;
          });
        }

        return StatefulBuilder(
          builder: (ctx, setModal) {
            if (loading) {
              unawaited(reload(setModal));
            }
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * 0.62,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            FleaberProfileAvatar(
                              userId: viewerId,
                              fullName: viewerLabel,
                              radius: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                viewerLabel,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: loading
                            ? const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: entries.length,
                                itemBuilder: (context, i) {
                                  final e = entries[i];
                                  return _threadEntryTile(e, viewerLabel);
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: replyCtrl,
                                style: GoogleFonts.inter(color: Colors.white),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) async {
                                  final text = replyCtrl.text.trim();
                                  if (text.isEmpty) return;
                                  final ok = await priv.sendPrivate(
                                    text,
                                    recipientId: viewerId,
                                  );
                                  if (ok) {
                                    replyCtrl.clear();
                                    await reload(setModal);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Responder…',
                                  hintStyle:
                                      GoogleFonts.inter(color: Colors.white54),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: FleaberRadius.circularMd,
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                final text = replyCtrl.text.trim();
                                if (text.isEmpty) return;
                                final ok = await priv.sendPrivate(
                                  text,
                                  recipientId: viewerId,
                                );
                                if (ok) {
                                  replyCtrl.clear();
                                  await reload(setModal);
                                }
                              },
                              icon: const Icon(Icons.send_rounded,
                                  color: FleaberColors.teal),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    replyCtrl.dispose();
    if (mounted) setState(() {});
  }

  Widget _threadEntryTile(LiveThreadEntry e, String viewerLabel) {
    final kindLabel = switch (e.kind) {
      LiveThreadEntryKind.publicChat => 'Chat público',
      LiveThreadEntryKind.private => 'Privado',
      LiveThreadEntryKind.reservation => 'Reserva',
      LiveThreadEntryKind.purchase => 'Compra',
    };
    final isMine = e.senderId == widget.sellerId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: FleaberRadius.circularSm,
            ),
            child: Text(
              kindLabel,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isMine
                  ? FleaberColors.teal.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: FleaberRadius.circularMd,
            ),
            child: Text(
              e.body,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStatsSheet() async {
    final room = _publicRoom;
    if (room == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Estatísticas do directo',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _statRow('Duração', _durationLabel),
                StreamBuilder<int>(
                  stream: room.viewerCountStream,
                  initialData: room.viewerCount,
                  builder: (context, snap) =>
                      _statRow('Espectadores', '${snap.data ?? 0}'),
                ),
                _statRow(
                  'Vendas pagas nesta live',
                  '${_livePaidOrdersValueEur.toStringAsFixed(2).replaceAll('.', ',')} €',
                ),
                _statRow(
                  'Gorjetas nesta live',
                  '${_liveTipsValueEur.toStringAsFixed(2).replaceAll('.', ',')} €',
                ),
                _statRow(
                  'Total pago nesta live',
                  '${(_livePaidOrdersValueEur + _liveTipsValueEur).toStringAsFixed(2).replaceAll('.', ',')} €',
                ),
                Text(
                  'O Saldo (Wallet) é outro ecrã no Perfil — não é este total.',
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                _statRow('Artigos no catálogo', '${widget.catalogItemCount}'),
                _statRow('Mensagens privadas', '$_privateUnread por ler'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _vendorGlass({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8),
    double radius = 12,
    double fillOpacity = 0.28,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: fillOpacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.6,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopChromeRow(LiveRoomService room) {
    return _vendorGlass(
      fillOpacity: 0.2,
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FleaberColors.danger,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'LIVE',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _durationLabel,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          StreamBuilder<int>(
            stream: room.viewerCountStream,
            initialData: room.viewerCount,
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return InkWell(
                onTap: _openStatsSheet,
                borderRadius: FleaberRadius.circularMd,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (count >= 5) ...[
                        const Icon(Icons.remove_red_eye_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ] else
                        Icon(
                          Icons.insights_outlined,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 18,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          const HubSellerLiveLinkButton(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _openPrivateInbox,
                icon: const Icon(Icons.mark_chat_unread_outlined,
                    color: Colors.white),
                tooltip: 'Mensagens privadas',
              ),
              if (_privateUnread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: FleaberColors.teal,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _privateUnread > 9 ? '9+' : '$_privateUnread',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }


  void togglePrivateChatMode() {
    final next = !widget.privateChatMode;
    widget.onPrivateChatModeChanged?.call(next);
  }

  Widget _buildPrivateChatInboxSection() {
    final priv = _privateRoom;
    if (priv == null) return const SizedBox.shrink();

    return SizedBox(
      height: _effectiveChatHeight,
      child: FutureBuilder<List<LivePrivateThreadSummary>>(
        future: priv.listThreadsForSeller(),
        builder: (context, snap) {
          final threads = snap.data ?? const [];
          if (snap.connectionState == ConnectionState.waiting &&
              threads.isEmpty) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (threads.isEmpty) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mensagens privadas aparecem aqui',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 10,
                ),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: EdgeInsets.zero,
            itemCount: threads.length,
            itemBuilder: (context, index) {
              final t = threads[threads.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: FleaberRadius.circularSm,
                  child: InkWell(
                    onTap: () => unawaited(
                      _openViewerThread(t.viewerId, t.viewerLabel),
                    ),
                    borderRadius: FleaberRadius.circularSm,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.viewerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: FleaberColors.teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.lastMessage,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Toca para abrir e responder',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (t.unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 6, right: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: FleaberColors.teal,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${t.unreadCount}',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.45),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChatSection(LiveRoomService room) {
    if (widget.privateChatMode) {
      return _buildPrivateChatInboxSection();
    }

    final h = _effectiveChatHeight;
    if (h <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: h,
      child: StreamBuilder<List<LiveRoomMessage>>(
        stream: room.messagesStream,
        initialData: List.unmodifiable(room.messages),
        builder: (context, snap) {
          final msgs = (snap.data ?? const []).where(_passesFilter).toList();
          final visibleSystemIds = _visibleSystemMessageIds(msgs);
          if (msgs.isEmpty) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'As mensagens do chat aparecerão aqui',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: _chatProminent ? 11 : 10,
                  height: 1.25,
                ),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: EdgeInsets.zero,
            itemCount: msgs.length,
            itemBuilder: (context, index) {
              final m = msgs[msgs.length - 1 - index];
              if (m.kind == LiveRoomMessageKind.tip) {
                return LiveTipGiftBubble(
                  amountEur: m.tipAmountEur ?? 0,
                  showPrivacyNote: false,
                  contributorLabel:
                      m.tipId != null ? _tipContributors[m.tipId!] : null,
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
                      _resolveSystemChatBuyerName(raw, m.userId),
                  animateHighlight: _shouldAnimateSystemHighlight(m.id),
                );
              }
              final label = _chatSenderLabel(m);
              final isSeller = (m.userId?.trim() ?? '') == widget.sellerId;
              return LivePublicChatLine(
                label: label,
                text: m.body,
                isSeller: isSeller,
                compact: !_chatProminent,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildReplyRow() {
    return SizedBox(
      height: _kVendorLiveChatInputH,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _kVendorLiveChatGlass),
          borderRadius: FleaberRadius.circularLg,
          border: Border.all(
            color: _kVendorLiveChatAccent.withValues(alpha: 0.45),
            width: 0.9,
          ),
        ),
        child: TextField(
          controller: _publicReplyController,
          enabled: !_sendingPublicReply,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendPublicReply(),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
            height: 1.0,
          ),
          cursorColor: _kVendorLiveChatAccent,
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            hintText: 'Diz alguma coisa…',
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
    );
  }

  Widget _buildChatHeaderRow({bool fullPanel = false}) {
    final showFilters = fullPanel && !widget.privateChatMode;
    return Row(
      children: [
        Icon(
          widget.privateChatMode
              ? Icons.lock_outline_rounded
              : Icons.forum_outlined,
          color: widget.privateChatMode
              ? FleaberColors.teal
              : Colors.white.withValues(alpha: 0.75),
          size: 13,
        ),
        const SizedBox(width: 5),
        Text(
          widget.privateChatMode ? 'Chat privado' : 'Chat público',
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (fullPanel) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: togglePrivateChatMode,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: widget.privateChatMode
                    ? FleaberColors.teal.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: widget.privateChatMode
                      ? FleaberColors.teal
                      : Colors.white24,
                ),
              ),
              child: Text(
                widget.privateChatMode ? 'Público' : 'Privado',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (!widget.privateChatMode && _privateUnread > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: FleaberColors.teal,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _privateUnread > 9 ? '9+' : '$_privateUnread',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
        if (showFilters) ...[
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _filterChip('Todos', _VendorChatFilter.all),
                  const SizedBox(width: 4),
                  _filterChip('Perguntas', _VendorChatFilter.questions),
                  const SizedBox(width: 4),
                  _filterChip('Reservas', _VendorChatFilter.reservations),
                  const SizedBox(width: 4),
                  _filterChip('Sistema', _VendorChatFilter.system),
                ],
              ),
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }

  Widget _buildChatPreviewTap(LiveRoomService room) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setActivePanel(SellerLiveActivePanel.chat),
        borderRadius: FleaberRadius.circularSm,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: FleaberRadius.circularSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Chat — tocar para ver',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: _kChatPreviewH - 22,
                child: _buildChatSection(room),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelShell({
    required String title,
    required Widget child,
    VoidCallback? onClose,
    bool dropdown = false,
  }) {
    return _vendorGlass(
      fillOpacity: dropdown ? 0.36 : 0.48,
      radius: 12,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildPaymentsPanel() {
    final pending = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isOpenSellerTreatReservation(
            status: r.status,
            notes: r.notes,
          ) &&
              r.status == 'pending',
        )
        .toList();
    final accepted = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();
    final cancelledByBuyer = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isBuyerCancelledReservation(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();
    final converted =
        _reservationQueue.where((r) => r.status == 'converted').toList();
    final external = pending
        .where(
          (r) =>
              r.source == 'facebook_manual' || r.source == 'helper_manual',
        )
        .toList();

    if (pending.isEmpty &&
        accepted.isEmpty &&
        cancelledByBuyer.isEmpty &&
        converted.isEmpty &&
        _livePaidOrdersCount <= 0 &&
        _liveTipsCount <= 0) {
      return Text(
        'Ainda sem pagamentos — quando alguém pagar, aparece aqui.',
        style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
      );
    }

    final walletTotal = _livePaidOrdersValueEur + _liveTipsValueEur;
    if ((walletTotal - _lastWalletLogTotalEur).abs() > 0.001) {
      _lastWalletLogTotalEur = walletTotal;
      _logStudio(
        'wallet.payments_render',
        data: {
          'wallet_total_eur': walletTotal,
          'paid_eur': _livePaidOrdersValueEur,
          'tips_eur': _liveTipsValueEur,
          'tips_count': _liveTipsCount,
          'shows_wallet_line': walletTotal > 0.009,
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (walletTotal > 0.009) ...[
          Text(
            'Total pago nesta live: '
            '${walletTotal.toStringAsFixed(2).replaceAll('.', ',')} €',
            style: GoogleFonts.inter(
              color: const Color(0xFF6ED8DE),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          Text(
            'Encomendas pagas e gorjetas · o Saldo fica no Perfil',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_liveTipPayments.isNotEmpty) ...[
          Text(
            'Gorjetas (${_liveTipsCount})',
            style: GoogleFonts.inter(
              color: const Color(0xFFFFB74D),
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ..._liveTipPayments.take(8).map(_tipPaymentRow),
          const SizedBox(height: 8),
        ],
        if (_livePaidOrdersValueEur > 0) ...[
          Text(
            'Valor vendido neste directo: '
            '${_livePaidOrdersValueEur.toStringAsFixed(2).replaceAll('.', ',')} €',
            style: GoogleFonts.inter(
              color: const Color(0xFF00A3AD),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_livePaidOrdersCount > 0 && converted.isEmpty) ...[
          Text(
            'Pagamentos Stripe confirmados: $_livePaidOrdersCount',
            style: GoogleFonts.inter(
              color: const Color(0xFF00A3AD),
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (converted.isNotEmpty) ...[
          Text(
            'Pagos (${converted.length})',
            style: GoogleFonts.inter(
              color: const Color(0xFF00A3AD),
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ...converted.take(8).map((r) => _paymentRow(r, paid: true)),
          const SizedBox(height: 8),
        ],
        if (external.isNotEmpty) ...[
          Text(
            'Pagamento externo pendente',
            style: GoogleFonts.inter(
              color: const Color(0xFFFFB74D),
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ...external.take(6).map((r) => _paymentRow(r, paid: false)),
          const SizedBox(height: 8),
        ],
        if (accepted.isNotEmpty) ...[
          Text(
            'Aguardam pagamento (${accepted.length})',
            style: GoogleFonts.inter(
              color: const Color(0xFF6ED8DE),
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ...accepted.take(6).map((r) => _paymentRow(r, paid: false)),
          const SizedBox(height: 8),
        ],
        if (cancelledByBuyer.isNotEmpty) ...[
          _maestroHarnessSemantics(
            id: MaestroStudioDebugLog.enabled
                ? 'maestro_harness_cancelled_buyer'
                : null,
            label:
                'Cancelados pelo comprador (${cancelledByBuyer.length})',
            child: Text(
              'Cancelados pelo comprador (${cancelledByBuyer.length})',
              style: GoogleFonts.inter(
                color: const Color(0xFFE57373),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...cancelledByBuyer
              .take(6)
              .map((r) => _paymentRow(r, paid: false, cancelled: true)),
          const SizedBox(height: 8),
        ],
        if (pending.isNotEmpty &&
            pending.length > external.length) ...[
          Text(
            'Reservas a aguardar pagamento',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ...pending
              .where((r) => r.source == 'fleaber_live')
              .take(6)
              .map((r) => _paymentRow(r, paid: false)),
        ],
      ],
    );
  }

  Widget _tipPaymentRow(({String buyerLabel, double amountEur}) tip) {
    final amount =
        tip.amountEur.toStringAsFixed(2).replaceAll('.', ',');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        'Gorjeta recebida de ${tip.buyerLabel}: $amount €',
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 10,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _paymentRow(
    LiveReservationRequestsRow r, {
    required bool paid,
    bool cancelled = false,
  }) {
    LiveItemsRow? item;
    for (final row in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((row.id ?? '').trim() == (r.liveItemId ?? '').trim()) {
        item = row;
        break;
      }
    }
    final ref = item != null
        ? LiveVendorRefDisplay.itemDisplayName(
            title: item.title,
            refCode: item.refCode,
          )
        : 'Item';
    final awaitingConfirmation = !cancelled &&
        !paid &&
        _liveOrdersAwaitingConfirmationKeys.contains(
          '${(r.liveItemId ?? '').trim()}|${(r.buyerId ?? '').trim()}',
        );
    final iconData = cancelled
        ? Icons.close_rounded
        : (paid
            ? Icons.check_circle_outline_rounded
            : (awaitingConfirmation
                ? Icons.notifications_none_rounded
                : Icons.hourglass_empty_rounded));
    final suffix = cancelled
        ? ' · cancelado pelo comprador'
        : (paid
            ? ''
            : (awaitingConfirmation
                ? ' · pago fora da app · confirma'
                : ' · aguarda pagamento'));
    final color = cancelled
        ? const Color(0xFFE57373)
        : awaitingConfirmation
            ? const Color(0xFFFFB74D)
            : Colors.white.withValues(alpha: 0.88);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$ref${_qtySeg(r)}$suffix',
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogPanelContent({bool? dropdown}) {
    return _panelShell(
      title: 'Catálogo',
      dropdown: dropdown ?? widget.sellerOverlayLayout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCatalogQuickAddButton(),
          const SizedBox(height: 6),
          SizedBox(
            height: _kCatalogListBodyH,
            child: _buildCatalogList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanelViewport(LiveRoomService room) {
    if (_panel == SellerLiveActivePanel.catalog) {
      return _buildCatalogPanelContent(dropdown: widget.sellerOverlayLayout);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _kPanelMaxH),
      child: SingleChildScrollView(
        child: _buildExpandedPanelContent(room),
      ),
    );
  }

  Widget _buildExpandedPanelContent(LiveRoomService room) {
    final dropdown = widget.sellerOverlayLayout;

    switch (_panel) {
      case SellerLiveActivePanel.none:
        return const SizedBox.shrink();
      case SellerLiveActivePanel.chat:
        return _panelShell(
          title: 'Chat',
          dropdown: dropdown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChatHeaderRow(fullPanel: true),
              const SizedBox(height: 5),
              if (widget.privateChatMode)
                _buildPrivateChatInboxSection()
              else ...[
                _buildChatSection(room),
                const SizedBox(height: 5),
                _buildReplyRow(),
              ],
            ],
          ),
        );
      case SellerLiveActivePanel.catalog:
        return const SizedBox.shrink();
      case SellerLiveActivePanel.operation:
      case SellerLiveActivePanel.reservations:
      case SellerLiveActivePanel.payments:
      case SellerLiveActivePanel.operations:
        return _buildOperationPanel(room: room, dropdown: dropdown);
    }
  }

  Widget _buildOperationPanel({
    required LiveRoomService room,
    required bool dropdown,
  }) {
    final opsTotals = _computeOpsTotals();
    Widget sectionBody = switch (_operationSection) {
      SellerOperationSection.queue => _buildReservationsCategorizedPanel(
          includeSummary: false,
        ),
      SellerOperationSection.payments => _buildPaymentsPanel(),
      SellerOperationSection.history => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveVendorActivityTimeline(
              events: _activityEvents,
              height: 210,
              onEventAction: _onActivityEventAction,
            ),
          ],
        ),
    };

    return _panelShell(
      title: 'Operação',
      dropdown: dropdown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveVendorOperationKpiStrip(
            totals: opsTotals,
            onTapSales: () =>
                setOperationSection(SellerOperationSection.payments),
            onTapPending: () =>
                setOperationSection(SellerOperationSection.queue),
            onTapCheckout: () =>
                setOperationSection(SellerOperationSection.payments),
            onTapHelpers: () => unawaited(_openTeamSheet()),
            onTapUrgent: () =>
                setOperationSection(SellerOperationSection.queue),
          ),
          LiveRaffleSellerOpsBar(
            state: _raffleState,
            participantCount: _raffleParticipantCount,
            ticketTotal: _raffleTicketTotal,
            loading: _raffleActionLoading,
            onCreate: () => unawaited(_openRaffleSellerSheet()),
            onCloseEntries: () => unawaited(_closeRaffleEntries()),
            onDraw: () => unawaited(_drawRaffle()),
            onCancel: () => unawaited(_cancelRaffle()),
          ),
          LiveVendorOperationSectionTabs(
            selected: _operationSection,
            onSelected: setOperationSection,
            queueBadge: opsTotals.actionPendingCount,
            paymentsBadge: opsTotals.pendingCheckoutCount + opsTotals.salesCount,
          ),
          sectionBody,
        ],
      ),
    );
  }

  Future<void> _showItemReservationsDetailSheet() async {
    final active = _activeCatalogRow;
    if (active == null || !mounted) return;
    final itemId = active.id?.trim() ?? '';
    if (itemId.isEmpty) return;

    final rows = _reservationQueue
        .where((r) => (r.liveItemId ?? '').trim() == itemId)
        .where(
          (r) => LiveReservationQueueService.isOpenSellerTreatReservation(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList()
      ..sort((a, b) {
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

    await _resolveBuyerNames(rows.map((r) => r.buyerId ?? ''));

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reservas · ${_itemRefLabel(active)}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rows.isEmpty
                      ? 'Ninguém reservou este artigo neste momento.'
                      : LiveVendorSellerCopy.reservasAtivas(rows.length),
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                if (_isActiveItemRafflePrize(itemId) && rows.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Prémio da Rifa: as reservas deste artigo seguem a fila normal '
                    '(aceita ou lista de espera).',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF00A3AD),
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  Text(
                    'As reservas aparecem aqui quando alguém pede o artigo.',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: FleaberRadius.circularSm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _buyerNameLabel(r),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${LiveVendorSellerCopy.qtyLabel(qty)} · '
                                '${LiveVendorSellerCopy.reservationStatus(r.status, requestKind: r.requestKind)} · '
                                '${LiveVendorSellerCopy.reservationSource(r.source)} · '
                                '${LiveVendorSellerCopy.formatTime(r.createdAt)}'
                                '${_reservationDeadlineLabel(r)}',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                              if (LiveReservationQueueService
                                      .sellerCanActOnReservation(
                                    status: r.status,
                                    notes: r.notes,
                                    requestKind: r.requestKind,
                                  ) &&
                                  SellerStaffContext.instance.can(
                                    SellerStaffPermissions.canManageReservations,
                                  )) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _queueAction(
                                      'Aceitar',
                                      () => _processReservation(r, 'accept'),
                                    ),
                                    _queueAction(
                                      'Recusar',
                                      () => _processReservation(r, 'reject'),
                                    ),
                                  ],
                                ),
                              ],
                              ..._commerceTrustExtendActions(r),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _commerceTrustExtendActions(LiveReservationRequestsRow r) {
    final buyerId = (r.buyerId ?? '').trim();
    final canManage = SellerStaffContext.instance.can(
      SellerStaffPermissions.canManageReservations,
    );
    if (!canManage) return const [];
    final out = <Widget>[];
    // Guaranteed / accepted hold: one-time extend.
    // After accept from approval_pending, kind may still be approval_pending
    // until reconcile — still allow Prolongar when status is accepted.
    if (r.status == 'accepted' &&
        (r.requestKindOrDefault == 'guaranteed' ||
            r.requestKindOrDefault == 'approval_pending' ||
            r.requestKind == null ||
            r.requestKind!.isEmpty) &&
        !r.extendedOnce) {
      out.add(const SizedBox(height: 6));
      out.add(
        Row(
          children: [
            _queueAction('Prolongar', () => _extendGuaranteed(r)),
          ],
        ),
      );
    } else if (r.status == 'accepted' && r.extendedOnce) {
      out.add(const SizedBox(height: 4));
      out.add(
        Text(
          'Já prolongaste esta reserva',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    // Fleaber-identified buyer only — guest / Facebook unlinked cannot get
    // permanent manual trust (Phase 5 / F5-22).
    final hasGuest = (r.guestSessionId ?? '').trim().isNotEmpty;
    final hasFleaberBuyer = buyerId.isNotEmpty;
    final facebookUnlinked = (r.externalBuyerRef ?? '').trim().isNotEmpty &&
        !hasFleaberBuyer;
    if (hasFleaberBuyer && !hasGuest && !facebookUnlinked) {
      out.add(const SizedBox(height: 6));
      out.add(
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _queueAction(
              'Confiar',
              () => _trustBuyer(r, promote: true),
            ),
            _queueAction(
              'Não confiar',
              () => _distrustBuyer(r),
            ),
          ],
        ),
      );
    }
    return out;
  }

  Future<void> _extendGuaranteed(LiveReservationRequestsRow r) async {
    final id = r.id?.trim() ?? '';
    if (id.isEmpty) return;
    final policy = await SellerReservationPolicyService.fetchForCurrentSeller();
    final ttl = policy?.normalTtlSeconds ?? 86400;
    final label = SellerReservationPolicyService.formatTtl(ttl);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prolongar reserva?'),
        content: Text(
          'Só podes prolongar esta reserva uma vez. A partir de agora, '
          'fica reservada durante $label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton(
            label: 'Prolongar',
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await SellerCommerceTrustActions.extendGuaranteedOnce(
      requestId: id,
      ttlSeconds: ttl,
    );
    if (!mounted) return;
    if (res['ok'] != true) {
      final err = res['error']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == 'already_extended'
                ? 'Esta reserva já foi prolongada.'
                : 'Não foi possível prolongar.',
          ),
        ),
      );
      return;
    }
    await _loadReservationQueue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reserva prolongada.')),
    );
  }

  Future<void> _trustBuyer(
    LiveReservationRequestsRow r, {
    required bool promote,
  }) async {
    final buyerId = (r.buyerId ?? '').trim();
    if (buyerId.isEmpty) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como cliente de confiança?'),
        content: const Text(
          'Esta cliente passa a ser cliente de confiança. Os artigos que '
          'já tiver no saco podem ficar automaticamente reservados, se '
          'ainda houver stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton(
            label: 'Confiar',
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final liveId = (r.liveId ?? widget.liveId).trim();
    final res = promote
        ? await SellerCommerceTrustActions.trustAndPromote(
            buyerId: buyerId,
            liveId: liveId.isEmpty ? null : liveId,
          )
        : await SellerCommerceTrustActions.setTrust(
            buyerId: buyerId,
            mode: 'trusted',
          );
    if (!mounted) return;
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível actualizar a confiança.')),
      );
      return;
    }
    final promoted = (res['promoted'] as num?)?.toInt() ?? 0;
    final skipped = (res['skipped_no_stock'] as num?)?.toInt() ??
        (res['skipped'] as num?)?.toInt() ??
        0;
    await _loadReservationQueue();
    if (!mounted) return;
    final msg = skipped > 0 && promoted == 0
        ? 'Cliente marcada como de confiança. Nenhum artigo ficou '
            'reservado — não há stock suficiente.'
        : promoted > 0
            ? (promoted == 1
                ? 'Cliente marcada como de confiança. 1 artigo do saco '
                    'ficou reservado.'
                : 'Cliente marcada como de confiança. $promoted artigos '
                    'do saco ficaram reservados.')
            : 'Cliente marcada como de confiança.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _distrustBuyer(LiveReservationRequestsRow r) async {
    final buyerId = (r.buyerId ?? '').trim();
    if (buyerId.isEmpty) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar confiança?'),
        content: const Text(
          'Esta cliente deixa de ter benefício de confiança na tua loja. '
          'Não afecta outras lojas nem a reputação global.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton(
            label: 'Retirar',
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await SellerCommerceTrustActions.setTrust(
      buyerId: buyerId,
      mode: 'distrusted',
    );
    if (!mounted) return;
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível actualizar a confiança.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Confiança retirada nesta loja.')),
    );
  }

  Future<void> _showItemSoldDetailSheet() async {
    final active = _activeCatalogRow;
    if (active == null || !mounted) return;
    final itemId = active.id?.trim() ?? '';
    if (itemId.isEmpty) return;

    final rows = _reservationQueue
        .where((r) => (r.liveItemId ?? '').trim() == itemId)
        .where((r) => (r.status ?? '') == 'converted')
        .toList()
      ..sort((a, b) {
        final ta = a.updatedAt ?? a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.updatedAt ?? b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

    await _resolveBuyerNames(rows.map((r) => r.buyerId ?? ''));

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Vendidos · ${_itemRefLabel(active)}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rows.isEmpty
                      ? 'Ainda não há vendas registadas neste artigo.'
                      : LiveVendorSellerCopy.unidadesVendidas(
                          rows.fold<int>(
                            0,
                            (a, r) =>
                                a + (r.requestedQty < 1 ? 1 : r.requestedQty),
                          ),
                        ),
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  Text(
                    'Compras pagas ou marcadas como vendidas aparecem aqui.',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.4,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
                        final when = r.updatedAt ?? r.createdAt;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A3AD).withValues(alpha: 0.12),
                            borderRadius: FleaberRadius.circularSm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _buyerNameLabel(r),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${LiveVendorSellerCopy.qtyLabel(qty)} · '
                                '${LiveVendorSellerCopy.reservationStatus(r.status, requestKind: r.requestKind)} · '
                                '${LiveVendorSellerCopy.reservationSource(r.source)} · '
                                '${LiveVendorSellerCopy.formatTime(when)}',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  LiveReservationRequestsRow? _urgentReservationPrompt() {
    final open = _sellerOpenPendingReservations()
        .where(
          (r) =>
              r.source == 'fleaber_live' &&
              r.status == 'pending' &&
              LiveReservationQueueService.notesNeedQtyConfirm(r.notes) &&
              !_dismissedUrgentRequestIds.contains((r.id ?? '').trim()),
        )
        .where(_reservationNeedsUrgentQtyConfirm)
        .toList();
    if (open.isEmpty) return null;
    return _sortReservationsByUrgency(open).first;
  }

  bool _reservationNeedsUrgentQtyConfirm(LiveReservationRequestsRow r) {
    final itemId = (r.liveItemId ?? '').trim();
    final snap = itemId.isNotEmpty ? _stockByItemId[itemId] : null;
    LiveItemsRow? itemRow;
    for (final row in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((row.id ?? '').trim() == itemId) {
        itemRow = row;
        break;
      }
    }
    final freeQty = snap?.availableQty ?? itemRow?.quantity ?? 0;
    return LiveReservationQueueService.needsUrgentQtyConfirmCard(
      requestedQty: r.requestedQty,
      stock: snap,
      notesNeedQtyConfirm: true,
    );
  }

  Widget _buildUrgentReservationCard() {
    final req = _urgentReservationPrompt();
    if (req == null) return const SizedBox.shrink();
    final id = req.id?.trim() ?? '';
    if (id.isEmpty) return const SizedBox.shrink();
    final name = _buyerNameLabel(req);
    final itemId = (req.liveItemId ?? '').trim();
    LiveItemsRow? itemRow;
    for (final r in _catalogRows ?? const <LiveItemsRow>[]) {
      if ((r.id ?? '').trim() == itemId) {
        itemRow = r;
        break;
      }
    }
    final snap = itemId.isNotEmpty ? _stockByItemId[itemId] : null;
    final totalOnLive = snap?.totalQty ?? itemRow?.quantity ?? 1;
    final freeQty = snap?.availableQty ?? totalOnLive;
    final wantedQty = req.requestedQty < 1 ? 1 : req.requestedQty;
    final buyerId = (req.buyerId ?? '').trim();
    var reservedThisBuyer = 0;
    var reservedOthers = 0;
    for (final r in _reservationQueue) {
      if ((r.liveItemId ?? '').trim() != itemId) continue;
      if (!LiveReservationQueueService.isAcceptedAwaitingPayment(
        status: r.status,
        notes: r.notes,
      )) {
        continue;
      }
      final q = r.requestedQty < 1 ? 1 : r.requestedQty;
      if ((r.buyerId ?? '').trim() == buyerId) {
        reservedThisBuyer += q;
      } else {
        reservedOthers += q;
      }
    }
    final stockLines = <String>[
      'Na live: $totalOnLive un. · Livres: ${freeQty < 0 ? 0 : freeQty} un.',
      'Pedido total deste cliente: $wantedQty un.',
    ];
    if (reservedThisBuyer > 0) {
      stockLines.add(
        reservedThisBuyer == 1
            ? '1 un. já reservada para este cliente (aguarda pagamento)'
            : '$reservedThisBuyer un. já reservadas para este cliente (aguardam pagamento)',
      );
    }
    if (reservedOthers > 0) {
      stockLines.add(
        reservedOthers == 1
            ? '1 un. reservada para outro cliente (aguarda pagamento)'
            : '$reservedOthers un. reservadas para outros clientes (aguardam pagamento)',
      );
    }
    final ref = LiveVendorRefDisplay.formatRef(
      itemRow?.refCode ?? _refForLiveItem(req.liveItemId),
    );
    final title = itemRow == null
        ? ref
        : LiveVendorRefDisplay.itemDisplayName(
            title: itemRow.title,
            refCode: itemRow.refCode,
          );
    final price = itemRow?.price;
    final priceLabel = price != null && price > 0
        ? '${price.toStringAsFixed(2).replaceAll('.', ',')} €'
        : null;
    final size = itemRow?.clothingSize?.trim();
    final color = itemRow?.gender?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFB71C1C).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (itemRow?.photoUrl?.trim().isNotEmpty == true)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        itemRow!.photoUrl!.trim(),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (itemRow?.photoUrl?.trim().isNotEmpty == true)
                    const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirmar quantidade',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        if (priceLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            priceLabel,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (ref.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Ref. $ref',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (size != null && size.isNotEmpty)
                          Text(
                            'Tam: $size',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 9,
                            ),
                          ),
                        if (color != null && color.isNotEmpty)
                          Text(
                            'Cor: $color',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 9,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        ...stockLines.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              line,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 10,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          'Stock insuficiente — aceita ou recusa',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() => _dismissedUrgentRequestIds.add(id));
                    },
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                  ),
                ],
              ),
              if (itemRow != null &&
                  !LiveItemPriceGate.hasPayableUnitPrice(liveItemPrice: price))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          unawaited(_showCatalogQuickEditSheet(itemRow!)),
                      icon: const Icon(
                        Icons.euro_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      label: Text(
                        'Definir preço',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _processReservation(req, 'reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text(
                        'Recusar',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _processReservation(req, 'accept'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007782),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text(
                        'Aceitar',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomProductChrome() {
    final activeRow = _activeCatalogRow;
    if (activeRow == null) return const SizedBox.shrink();
    final itemId = activeRow.id?.trim() ?? '';
    final snap = itemId.isNotEmpty ? _stockByItemId[itemId] : null;
    final stats = _activeOpsSnapshot ??
        LiveItemOpsSnapshot(
          available: snap?.availableQty,
          sold: 0,
          interested: 0,
        );
    final totalQty = snap?.totalQty ?? 1;
    final avail = snap?.availableQty ?? stats.available ?? 0;
    final hasStock = avail > 0;
    final markedSold = LiveVendorSellerCopy.isMarkedSold(activeRow.status);
    final soldOut = markedSold ||
        (!hasStock &&
            ((snap != null && snap.soldConvertedQty >= totalQty) ||
                LiveVendorSellerCopy.isSoldOut(activeRow.status, stats)));
    // Barra sempre clicável (stock/show mesmo com artigo «vendido» — repor qty).
    final actionsEnabled = true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.sellerOverlayLayout) _buildUrgentReservationCard(),
        if (widget.sellerOverlayLayout) _buildActiveItemPendingReservationPrompt(),
        LiveVendorCompactProductCard(
          refLabel: _itemRefLabel(activeRow),
          title: _itemTitle(activeRow),
          attributesLine: _itemAttributes(activeRow),
          priceLabel: _itemPriceLabel(activeRow),
          photoUrl: activeRow.photoUrl,
          stats: stats,
          itemStatus: LiveVendorSellerCopy.displayItemStatus(
            rowStatus: activeRow.status,
            hasStock: hasStock,
          ),
          onReservationsTap: () => unawaited(_showItemReservationsDetailSheet()),
          onSoldTap: () => unawaited(_showItemSoldDetailSheet()),
        ),
        if (soldOut) ...[
          const SizedBox(height: 6),
          Material(
            color: const Color(0xFF007782),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => unawaited(_handleQuickAction('next')),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.skip_next_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Próximo artigo',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        LiveVendorProductActionsBar(
          onAction: _handleQuickAction,
          enabled: actionsEnabled,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _publicRoom;
    if (room == null) return const SizedBox.shrink();

    if (widget.sellerOverlayLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTopNav)
            LiveVendorOpsTopNavBar(
              activePanel: _panel,
              onPanelToggled: togglePanel,
              onMoreTap: widget.onMoreTap ?? showMoreMenu,
              queueBadge: queuePendingBadge,
              chatBadge: _chatNavBadge,
            ),
          if (_panelExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildExpandedPanelViewport(room),
            ),
          const Spacer(),
          _buildBottomProductChrome(),
        ],
      );
    }

    final opsTotals = _computeOpsTotals();
    final activeRow = _activeCatalogRow;
    final panelOpen = _panelExpanded;

    final sections = <Widget>[
      if (!widget.hideTopChrome) ...[
        _buildTopChromeRow(room),
        const SizedBox(height: 6),
      ],
      if (widget.showTopNav)
        LiveVendorOpsTopNavBar(
          activePanel: _panel,
          onPanelToggled: togglePanel,
          onMoreTap: widget.onMoreTap ?? showMoreMenu,
          queueBadge: queuePendingBadge,
          chatBadge: _chatNavBadge,
        ),
      if (widget.showTopNav && _panelExpanded)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _buildExpandedPanelViewport(room),
        ),
      if (!widget.showTopNav && activeRow != null) ...[
        LiveVendorCurrentProductPill(
          refLabel: _itemRefLabel(activeRow),
          title: _itemTitle(activeRow),
          attributesLine: _itemAttributes(activeRow),
          priceLabel: _itemPriceLabel(activeRow),
          onTap: panelOpen
              ? null
              : () => openOperationalQueue(section: SellerOperationSection.queue),
        ),
        const SizedBox(height: 6),
      ],
      if (!widget.showTopNav && !panelOpen) ...[
        if (opsTotals.hasAlerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: LiveVendorOpsStatusBar(
              totals: opsTotals,
              onTapQueue: () =>
                  openOperationalQueue(section: SellerOperationSection.queue),
              compact: true,
            ),
          ),
        _buildChatPreviewTap(room),
      ],
      if (!widget.showTopNav && panelOpen)
        _buildExpandedPanelViewport(room),
      if (!widget.showTopNav && activeRow != null) ...[
        const SizedBox(height: 6),
        _buildBottomProductChrome(),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: sections,
    );
  }

  String _reservationDeadlineLabel(LiveReservationRequestsRow r) {
    return LiveVendorSellerCopy.deadlineUntil(r.expiresAt);
  }

  /// Segmento de quantidade PT (« · 2 un.»); omite se qty==1.
  String _qtySeg(LiveReservationRequestsRow r, {bool omitWhenOne = true}) {
    return LiveVendorSellerCopy.qtySegment(
      r.requestedQty < 1 ? 1 : r.requestedQty,
      omitWhenOne: omitWhenOne,
    );
  }

  List<LiveReservationRequestsRow> _sellerOpenPendingReservations() {
    return _reservationQueue
        .where(
          (r) =>
              r.status == 'pending' &&
              LiveReservationQueueService.isOpenSellerTreatReservation(
                status: r.status,
                notes: r.notes,
              ),
        )
        .toList();
  }

  List<LiveReservationRequestsRow> _reservationsForCategory(
    _ReservationListCategory cat,
  ) {
    final pending = _sellerOpenPendingReservations();
    final accepted = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();
    switch (cat) {
      case _ReservationListCategory.inBag:
        return _sortReservationsByUrgency(
          pending
              .where(
                (r) =>
                    r.source == 'fleaber_live' &&
                    !LiveReservationQueueService.isBuyerCancelledReservation(
                      status: r.status,
                      notes: r.notes,
                    ) &&
                    LiveReservationQueueService.isOpenSellerTreatReservation(
                      status: r.status,
                      notes: r.notes,
                    ),
              )
              .toList(),
        );
      case _ReservationListCategory.accepted:
        return accepted
            .where(
              (r) => !LiveReservationQueueService.isBuyerCancelledReservation(
                status: r.status,
                notes: r.notes,
              ),
            )
            .toList();
      case _ReservationListCategory.external:
        return _sortReservationsByUrgency(
          pending
              .where(
                (r) =>
                    (r.source == 'facebook_manual' ||
                        r.source == 'helper_manual') &&
                    !LiveReservationQueueService.isBuyerCancelledReservation(
                      status: r.status,
                      notes: r.notes,
                    ),
              )
              .toList(),
        );
      case _ReservationListCategory.unpaid:
        return _sortReservationsByUrgency(
          pending.where((r) => _isReservationStale(r)).toList(),
        );
      case _ReservationListCategory.pending:
        return _sortReservationsByUrgency(
          pending
              .where(
                (r) =>
                    !LiveReservationQueueService.isBuyerCancelledReservation(
                      status: r.status,
                      notes: r.notes,
                    ) &&
                    LiveReservationQueueService.isOpenSellerTreatReservation(
                      status: r.status,
                      notes: r.notes,
                    ),
              )
              .toList(),
        );
    }
  }

  Widget _buildLiveSessionSummaryStrip() {
    final totals = _computeOpsTotals();
    final converted = _reservationQueue
        .where((r) => r.status == 'converted')
        .fold<int>(0, (a, r) => a + (r.requestedQty < 1 ? 1 : r.requestedQty));
    final accepted = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
            status: r.status,
            notes: r.notes,
          ),
        )
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo do directo',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _summaryChip('No saco', '${totals.bagCount}'),
              _summaryChip('Por pagar', '$accepted'),
              _summaryChip('Pagas', '$converted'),
              _summaryChip('Externos', '${totals.externalCount}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value) {
    return Text(
      '$label: $value',
      style: GoogleFonts.inter(
        color: Colors.white.withValues(alpha: 0.82),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildReservationsCategorizedPanel({bool includeSummary = true}) {
    // Spinner só na 1.ª carga (fila ainda vazia). Refresh em fundo: lista antiga.
    if (_reservationLoading && _reservationQueue.isEmpty) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final pending = _sellerOpenPendingReservations();
    final accepted = _reservationQueue
        .where(
          (r) => LiveReservationQueueService.isAcceptedAwaitingPayment(
            status: r.status,
            notes: r.notes,
          ),
        )
        .toList();

    const cats = <(_ReservationListCategory, String)>[
      (_ReservationListCategory.inBag, 'No saco'),
      (_ReservationListCategory.pending, 'Pendentes'),
      (_ReservationListCategory.accepted, 'Aguardam pagamento'),
      (_ReservationListCategory.external, 'Externos'),
      (_ReservationListCategory.unpaid, 'Sem pagamento'),
    ];

    final sections = <Widget>[
      for (final c in cats)
        if (_reservationsForCategory(c.$1).isNotEmpty)
          _buildReservationCategorySection(
            category: c.$1,
            title: c.$2,
            items: _reservationsForCategory(c.$1),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (includeSummary) _buildLiveSessionSummaryStrip(),
        if (sections.isEmpty)
          Text(
            pending.isEmpty && accepted.isEmpty
                ? 'Nada a tratar — continua a mostrar artigos no direto.'
                : 'Sem filas abertas neste momento.',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
          )
        else
          ...sections,
      ],
    );
  }

  Widget _buildReservationCategorySection({
    required _ReservationListCategory category,
    required String title,
    required List<LiveReservationRequestsRow> items,
  }) {
    final expanded = _expandedReservationCategory == category;
    final rowsById = {
      for (final r in _catalogRows ?? const <LiveItemsRow>[]) (r.id ?? ''): r,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularSm,
        child: InkWell(
          onTap: () => setState(() {
            _expandedReservationCategory =
                expanded ? null : category;
          }),
          borderRadius: FleaberRadius.circularSm,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _maestroHarnessSemantics(
                        id: _maestroHarnessCategoryId(category),
                        label: '$title (${items.length})',
                        child: Text(
                          '$title (${items.length})',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.white60,
                      size: 18,
                    ),
                  ],
                ),
                if (expanded && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Nada nesta categoria.',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                if (expanded)
                  for (final req in items.take(12))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          if (_isReservationStale(req))
                            Container(
                              margin: const EdgeInsets.only(right: 5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65100)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '>10m',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              '#${req.queuePosition ?? '?'} · '
                              '${_buyerNameLabel(req)} · '
                              '${LiveVendorRefDisplay.itemDisplayName(title: rowsById[req.liveItemId ?? '']?.title, refCode: rowsById[req.liveItemId ?? '']?.refCode)}'
                              '${_qtySeg(req)}'
                              '${_sellerWaitlistSuffix(req)}'
                              '${_sellerAwaitingConfirmationSuffix(req)}'
                              '${_reservationDeadlineLabel(req)}',
                              style: GoogleFonts.inter(
                                color: _sellerAwaitingConfirmationSuffix(req)
                                        .isNotEmpty
                                    ? const Color(0xFFFFB74D)
                                    : Colors.white70,
                                fontSize: 9.5,
                                fontWeight: _sellerAwaitingConfirmationSuffix(
                                          req,
                                        ).isNotEmpty
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (LiveReservationQueueService
                                  .sellerCanActOnReservation(
                                status: req.status,
                                notes: req.notes,
                                requestKind: req.requestKind,
                              ) &&
                              SellerStaffContext.instance.can(
                                SellerStaffPermissions.canManageReservations,
                              )) ...[
                            _queueAction(
                              'Aceitar',
                              () => _processReservation(req, 'accept'),
                            ),
                            _queueAction(
                              'Recusar',
                              () => _processReservation(req, 'reject'),
                            ),
                          ],
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogList() {
    if (_catalogLoading || _catalogRows == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_catalogRows!.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sem artigos no catálogo',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          _buildCatalogQuickAddButton(compact: true),
        ],
      );
    }

    return ListView.separated(
      controller: _catalogListScroll,
      padding: EdgeInsets.zero,
      itemCount: _catalogRows!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = _catalogRows![i];
        final active = row.isActive == true;
        final itemId = row.id?.trim() ?? '';
        final snap = itemId.isNotEmpty ? _stockByItemId[itemId] : null;
        final metrics = _metricsForLiveItem(row);
        final totalQty = snap?.totalQty ?? 1;
        final availQty = snap?.availableQty ?? metrics.quantity;
        final hasStock = (availQty ?? 0) > 0;
        final soldConverted = snap?.soldConvertedQty ?? metrics.sold;
        final markedSold = LiveVendorSellerCopy.isMarkedSold(row.status);
        final sold = markedSold ||
            (!hasStock &&
                (soldConverted >= totalQty ||
                    LiveVendorSellerCopy.isReservedFull(row.status)));
        final ref = LiveVendorRefDisplay.refLabel(row.refCode);
        final title = _itemTitle(row);
        final price = _itemPriceLabel(row);

        return LiveVendorCatalogQueueCard(
          title: title,
          refLabel: ref,
          attributesLine: _itemAttributes(row),
          priceLabel: price,
          photoUrl: row.photoUrl,
          metrics: metrics,
          itemStatus: LiveVendorSellerCopy.displayItemStatus(
            rowStatus: row.status,
            hasStock: hasStock,
          ),
          isActive: active,
          isSold: sold,
          onShow: () => _setActiveCatalogRow(row),
          onMenuSelected: (action) => _handleCatalogMenu(action, row),
        );
      },
    );
  }

  Widget _buildReservationQueuePanel() {
    if (_reservationLoading && _reservationQueue.isEmpty) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final pending = _reservationQueue
        .where(
          (r) =>
              r.status == 'pending' &&
              LiveReservationQueueService.isOpenSellerTreatReservation(
                status: r.status,
                notes: r.notes,
              ),
        )
        .toList();
    final stalePending = pending.where((r) {
      final c = r.createdAt;
      if (c == null) return false;
      return DateTime.now().difference(c.toLocal()) >= const Duration(minutes: 10);
    }).length;
    final conflicts = _reservationQueue
        .where((r) => r.status == 'rejected' || r.status == 'expired')
        .length;
    if (pending.isEmpty) {
      return Text(
        'Sem reservas pendentes neste directo.',
        style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
      );
    }

    final grouped = <String, List<LiveReservationRequestsRow>>{};
    for (final r in pending) {
      final key = r.liveItemId ?? 'unknown';
      grouped.putIfAbsent(key, () => <LiveReservationRequestsRow>[]).add(r);
    }
    for (final list in grouped.values) {
      list.sort(
        (a, b) => (a.queuePosition ?? 9999).compareTo(b.queuePosition ?? 9999),
      );
    }
    final rowsById = {for (final r in _catalogRows ?? const <LiveItemsRow>[]) (r.id ?? ''): r};

    return _vendorGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fila operacional de reservas',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showPsReaderTokenDialog,
                child: Text(
                  'PS Reader',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6ED8DE),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (stalePending > 0 || conflicts > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x33FF9800),
                borderRadius: FleaberRadius.circularSm,
              ),
              child: Text(
                'Alertas: '
                '${stalePending > 0 ? '$stalePending pendentes >10m · ' : ''}'
                '${conflicts > 0 ? '$conflicts conflitos/expiradas · ' : ''}'
                'Ações 1h: $_opsActionsLastHour',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFFD180),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final entry in grouped.entries) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: FleaberRadius.circularSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LiveVendorRefDisplay.refLabel(rowsById[entry.key]?.refCode),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final req in entry.value.take(6))
                    Row(
                      children: [
                        if (req.isPsNeedsReview)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65100)
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Rever',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            '#${req.queuePosition ?? '?'} · '
                            '${_buyerNameLabel(req)} · '
                            '${LiveVendorSellerCopy.reservationSource(req.source)}'
                            '${req.isPsOcrIngest ? ' · OCR' : ''}'
                            '${_qtySeg(req)}'
                            '${_sellerWaitlistSuffix(req)}',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (req.isPsNeedsReview &&
                            SellerStaffContext.instance.can(
                              SellerStaffPermissions.canManageReservations,
                            )) ...[
                          _queueAction(
                            'Confirmar',
                            () => _confirmPsReservation(req, 'confirm'),
                          ),
                          _queueAction(
                            'Ignorar',
                            () => _confirmPsReservation(req, 'reject'),
                          ),
                        ] else if (LiveReservationQueueService
                                .sellerCanActOnReservation(
                              status: req.status,
                              notes: req.notes,
                              requestKind: req.requestKind,
                            ) &&
                            SellerStaffContext.instance.can(
                              SellerStaffPermissions.canManageReservations,
                            )) ...[
                          _queueAction('Aceitar', () => _processReservation(req, 'accept')),
                          _queueAction('Recusar', () => _processReservation(req, 'reject')),
                          _queueAction('Ignorar', () => _processReservation(req, 'skip')),
                        ],
                      ],
                    ),
                  if (entry.value.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+${entry.value.length - 6} mais na fila deste artigo',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _queueAction(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, _VendorChatFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? FleaberColors.teal.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? FleaberColors.teal.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: selected ? 1 : 0.75),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuickEditSheetOutcome {
  const _QuickEditSheetOutcome({
    required this.updated,
    required this.qty,
    required this.andShow,
    required this.liveItemId,
  });

  final LiveCatalogStockSnapshot? updated;
  final int qty;
  final bool andShow;
  final String liveItemId;
}

class _StockAdjustSheetOutcome {
  const _StockAdjustSheetOutcome({
    required this.updated,
    required this.current,
    required this.amount,
    required this.remove,
    required this.change,
    required this.next,
  });

  final LiveCatalogStockSnapshot updated;
  final int current;
  final int amount;
  final bool remove;
  final int change;
  final int next;
}
