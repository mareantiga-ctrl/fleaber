import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/favorites_util.dart';
import '/index.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_eligibility.dart';
import '/widgets/fleaber_refresh.dart';
import '/widgets/fleaber_create_sheet.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/home_live_feed_grid.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/utils/seller_vacation_mode.dart';
import '/widgets/marketplace_product_card.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/utils/fleaber_logger.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/helper_pending_invites_banner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

/// Create a high-fidelity mobile home page for a live shopping app.
///
/// Colors: Use the project's current theme colors. Top Bar: Fixed app bar
/// with 'Fleaber' logo, profile avatar, and a notification bell. Header Text:
/// Below the top bar, add a small text saying 'A decorrer agora'. Search: A
/// search bar with the hint 'Procurar vendedora...'. Feed: A vertical
/// Listview of large cards. Each card must contain: a large background image,
/// a red 'LIVE' badge, the seller's name, a star rating icon with a number
/// (e.g., 4.8), and a text showing the number of sales. Navbar: A fixed
/// bottom navigation bar with 4 items: 'Início', 'Mensagens', a large central
/// camera icon for 'LIVE', and 'Perfil'. Strict Instruction: Do NOT include a
/// 'Vender' button.
///
/// os 4 botoes de da barra de baixo devem estar bem centrados
class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with RouteAware, SingleTickerProviderStateMixin {
  late HomePageModel _model;
  late TabController _homeTabController;

  static const int _kInitialProfilesLimit = 12;
  static const int _kInitialMarketplaceLimit = 40;
  static const int _kHomeFavoritesLimit = 250;
  static const Duration _kHomeQueryTimeout = Duration(seconds: 20);

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _favoriteProductIds = <String>{};
  final Map<String, int> _favoriteCountsOverride = <String, int>{};
  final Set<String> _togglingFavorites = <String>{};
  Timer? _batataBellResyncTimer;
  Timer? _liveFeedSearchDebounce;
  Timer? _marketplaceSearchDebounce;
  Timer? _liveFeedRefreshDebounce;
  static const _kBellClearedPrefsKey = 'batata_home_bell_cleared_at_v1';

  DateTime? _notificationBellClearedAt;
  /// Esconde a bolinha logo ao tocar no sino (sem esperar a query).
  bool _suppressNotificationBellDot = false;
  DateTime? _newestUnreadAtWhenBellCleared;
  int _marketplaceSearchRevision = 0;
  bool _liveFeedReloadInFlight = false;
  final GlobalKey<HomeLiveFeedGridState> _liveFeedGridKey =
      GlobalKey<HomeLiveFeedGridState>();
  final Map<String, double> _ratingsBySellerId = <String, double>{};
  int _homeTabIndex = 0;
  Future<bool>? _unreadNotificationsFuture;
  int _unreadNotificationsFutureTick = -1;
  Future<List<ChatMessagesRow>>? _unreadMessagesFuture;
  int _unreadMessagesFutureTick = -1;
  late Future<ProfilesRow?> _headerProfileFuture;

  Future<ProfilesRow?> _loadHeaderProfile() async {
    if (currentUserUid.isEmpty) return null;
    try {
      final rows = await ProfilesTable()
          .queryRows(
            queryFn: (q) => q.eqOrNull('id', currentUserUid),
            limit: 1,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => const <ProfilesRow>[],
          );
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
    _homeTabController = TabController(length: 2, vsync: this);
    _homeTabController.addListener(() {
      if (!_homeTabController.indexIsChanging &&
          _homeTabController.index != _homeTabIndex) {
        setState(() => _homeTabIndex = _homeTabController.index);
      }
    });
    homeFavoritesUiRefreshTick.addListener(_onHomeFavoritesUiReload);
    favoritesUiRefreshTick.addListener(_onFavoritesCountUiReload);
    notificationBadgeRefreshTick.addListener(_onNotificationBadgeTick);
    liveFeedRefreshTick.addListener(_onLiveFeedRefreshTick);

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();
    _model.setupTextControllerListener(_onLiveFeedSearchChanged);

    _model.marketplaceSearchController ??= TextEditingController();
    _model.marketplaceSearchFocusNode ??= FocusNode();
    _model.setupMarketplaceSearchControllerListener(_onMarketplaceSearchChanged);

    _batataBellResyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      if (lastBatataReservationPingUtc != null) {
        setState(() {});
      }
    });

    _headerProfileFuture = _loadHeaderProfile();
    unawaited(SellerStaffContext.instance.refresh());
    unawaited(_restoreNotificationBellClearedAt());
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
    _loadCurrentUserFavorites();
  }

  void _logBell(String message, [Map<String, Object?>? data]) {
    debugPrint('[FleaberBell] $message${data == null ? '' : ' $data'}');
    unawaited(
      FleaberLogger.instance.event('home.bell.$message', {
        if (data != null) ...data,
      }),
    );
  }

  Future<void> _restoreNotificationBellClearedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBellClearedPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final t = DateTime.tryParse(raw)?.toUtc();
      if (t == null) return;
      _notificationBellClearedAt = t;
      _logBell('restore_cleared_at', {'cleared_at': t.toIso8601String()});
    } catch (e) {
      _logBell('restore_cleared_at_error', {'error': e.toString()});
    }
  }

  Future<void> _persistNotificationBellClearedAt(DateTime clearedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBellClearedPrefsKey, clearedAt.toUtc().toIso8601String());
    } catch (e) {
      _logBell('persist_cleared_at_error', {'error': e.toString()});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.unsubscribe(this);
      routeObserver.subscribe(this, route);
    }
  }

  void _onLiveFeedSearchChanged() {
    _liveFeedSearchDebounce?.cancel();
    _liveFeedSearchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      // Atualiza a prop `search` do grid para aplicar o filtro por vendedora.
      setState(() {});
    });
  }

  void _onMarketplaceSearchChanged() {
    _marketplaceSearchDebounce?.cancel();
    _marketplaceSearchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _marketplaceSearchRevision++);
    });
  }

  @override
  void dispose() {
    _liveFeedSearchDebounce?.cancel();
    _marketplaceSearchDebounce?.cancel();
    _liveFeedRefreshDebounce?.cancel();
    _batataBellResyncTimer?.cancel();
    _homeTabController.dispose();
    homeFavoritesUiRefreshTick.removeListener(_onHomeFavoritesUiReload);
    favoritesUiRefreshTick.removeListener(_onFavoritesCountUiReload);
    notificationBadgeRefreshTick.removeListener(_onNotificationBadgeTick);
    liveFeedRefreshTick.removeListener(_onLiveFeedRefreshTick);
    routeObserver.unsubscribe(this);
    _model.dispose();

    super.dispose();
  }

  void _onLiveFeedRefreshTick() {
    if (!mounted) return;
    _liveFeedRefreshDebounce?.cancel();
    _liveFeedRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(_refreshLiveFeed());
    });
  }

  /// Recarrega grelha Diretos — sem voltar a incrementar [liveFeedRefreshTick].
  Future<void> _refreshLiveFeed() async {
    if (_liveFeedReloadInFlight) return;
    _liveFeedReloadInFlight = true;
    try {
      await _liveFeedGridKey.currentState?.reload();
    } finally {
      _liveFeedReloadInFlight = false;
    }
  }

  void _onNotificationBadgeTick() {
    if (!mounted) return;
    _unreadNotificationsFuture = null;
    _unreadMessagesFuture = null;
    unawaited(_syncNotificationBellDotAfterTick());
  }

  Future<void> _syncNotificationBellDotAfterTick() async {
    if (!_suppressNotificationBellDot) return;
    if (currentUserUid.isEmpty) return;
    final unread = await _homeFallback<List<UserNotificationsRow>>(
      UserNotificationsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('user_id', currentUserUid)
            .eqOrNull('is_read', false)
            .order('created_at', ascending: false)
            .limit(1),
      ),
      const <UserNotificationsRow>[],
    );
    if (!mounted) return;
    final newestUtc = unread.isEmpty ? null : unread.first.createdAt?.toUtc();
    final anchor = _newestUnreadAtWhenBellCleared;
    final hasNewerUnread = newestUtc != null &&
        anchor != null &&
        newestUtc.isAfter(anchor);
    _logBell('tick_while_suppressed', {
      'newest_unread_at': newestUtc?.toIso8601String(),
      'anchor_at_clear': anchor?.toIso8601String(),
      'has_newer_unread': hasNewerUnread,
      'batata_ping': batataReservationBellPingActive(),
    });
    if (!hasNewerUnread) return;
    setState(() => _suppressNotificationBellDot = false);
  }

  void _onNotificationBellTap() {
    final now = DateTime.now().toUtc();
    _logBell('tap', {
      'before_suppress': _suppressNotificationBellDot,
      'before_cleared_at': _notificationBellClearedAt?.toIso8601String(),
      'batata_ping': batataReservationBellPingActive(),
    });
    setState(() {
      _notificationBellClearedAt = now;
      _suppressNotificationBellDot = true;
      _unreadNotificationsFuture = Future<bool>.value(false);
      _unreadNotificationsFutureTick = notificationBadgeRefreshTick.value;
    });
    unawaited(_persistNotificationBellClearedAt(now));
    unawaited(() async {
      final unread = await _homeFallback<List<UserNotificationsRow>>(
        UserNotificationsTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('user_id', currentUserUid)
              .eqOrNull('is_read', false)
              .order('created_at', ascending: false)
              .limit(1),
        ),
        const <UserNotificationsRow>[],
      );
      _newestUnreadAtWhenBellCleared =
          unread.isEmpty ? null : unread.first.createdAt?.toUtc();
      _logBell('tap_anchor_saved', {
        'anchor_at_clear': _newestUnreadAtWhenBellCleared?.toIso8601String(),
      });
    }());
    clearBatataReservationNotificationBellPing();
    context.pushNamed(
      ListaConversasWidget.routeName,
      queryParameters: {
        'initialTab': serializeParam(
          'notificacoes',
          ParamType.String,
        ),
      }.withoutNulls,
    );
  }

  void _onHomeFavoritesUiReload() {
    if (!mounted) return;
    setState(() => _favoriteCountsOverride.clear());
    _loadCurrentUserFavorites();
    requestMarketplaceFeedRefresh();
  }

  void _onFavoritesCountUiReload() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didPopNext() {
    requestMarketplaceFeedRefresh();
    requestHomeFavoritesUiReload();
    requestLiveFeedRefresh();
    setState(() => _headerProfileFuture = _loadHeaderProfile());
  }

  Future<void> _showCreateBottomSheet() => FleaberCreateSheet.show(context);

  String _formatMarketplacePrice(ProductsRow row) {
    final p = row.price;
    if (p == null) return '—';
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String? _firstProductImageUrl(ProductsRow row) {
    final u = row.imageUrls;
    if (u.isEmpty) return null;
    return u.first;
  }

  Future<T> _homeFallback<T>(Future<T> future, T fallback) {
    return future.timeout(
      _kHomeQueryTimeout,
      onTimeout: () => fallback,
    ).catchError((_) => fallback);
  }

  Future<void> _loadCurrentUserFavorites() async {
    if (currentUserUid.isEmpty) {
      return;
    }
    final rows = await _homeFallback<List<FavoritesRow>>(
      FavoritesTable().queryRows(
        queryFn: (q) => q.eqOrNull('user_id', currentUserUid),
        limit: _kHomeFavoritesLimit,
      ),
      const <FavoritesRow>[],
    );
    if (!mounted) return;
    setState(() {
      _favoriteProductIds
        ..clear()
        ..addAll(rows.map((e) => e.productId));
    });
  }

  Future<bool> _hasUnreadNotifications() async {
    if (currentUserUid.isEmpty) {
      _logBell('check_skip_no_user');
      return false;
    }
    final unread = await _homeFallback<List<UserNotificationsRow>>(
      UserNotificationsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('user_id', currentUserUid)
            .eqOrNull('is_read', false)
            .order('created_at', ascending: false)
            .limit(1),
      ),
      const <UserNotificationsRow>[],
    );
    final batataPing = batataReservationBellPingActive();
    if (unread.isEmpty) {
      _logBell('check_no_db_unread', {'batata_ping': batataPing});
      return batataPing;
    }
    final newestUnreadAt = unread.first.createdAt?.toUtc();
    final clearedAt = _notificationBellClearedAt?.toUtc();
    final suppress = _suppressNotificationBellDot;
    final hiddenByClear = clearedAt != null &&
        newestUnreadAt != null &&
        !newestUnreadAt.isAfter(clearedAt);
    final show = !hiddenByClear;
    _logBell('check', {
      'suppress': suppress,
      'db_unread_count': unread.length,
      'newest_unread_at': newestUnreadAt?.toIso8601String(),
      'cleared_at': clearedAt?.toIso8601String(),
      'hidden_by_clear': hiddenByClear,
      'batata_ping': batataPing,
      'show_db_unread': show,
      'newest_id': unread.first.id,
    });
    if (hiddenByClear) return batataPing;
    return true;
  }

  Future<bool> _unreadNotificationsFutureForTick() {
    final tick = notificationBadgeRefreshTick.value;
    if (_unreadNotificationsFuture == null ||
        _unreadNotificationsFutureTick != tick) {
      _unreadNotificationsFutureTick = tick;
      _unreadNotificationsFuture = _hasUnreadNotifications();
    }
    return _unreadNotificationsFuture!;
  }

  Future<List<ChatMessagesRow>> _unreadMessagesFutureForTick() {
    if (currentUserUid.isEmpty) {
      return Future.value(const <ChatMessagesRow>[]);
    }
    final tick = notificationBadgeRefreshTick.value;
    if (_unreadMessagesFuture == null || _unreadMessagesFutureTick != tick) {
      _unreadMessagesFutureTick = tick;
      _unreadMessagesFuture = _homeFallback<List<ChatMessagesRow>>(
        ChatMessagesTable().queryRows(
          queryFn: (q) => q
              .eqOrNull('receiver_id', currentUserUid)
              .eqOrNull('is_read', false)
              .limit(1),
        ),
        const <ChatMessagesRow>[],
      );
    }
    return _unreadMessagesFuture!;
  }

  Future<Map<String, double>> _loadSellerRatings(List<String> sellerIds) async {
    if (sellerIds.isEmpty) return const {};
    final rows = await _homeFallback<List<ReviewsRow>>(
      ReviewsTable().queryRows(
        queryFn: (q) => q.inFilter('target_id', sellerIds),
        limit: 400,
      ),
      const <ReviewsRow>[],
    );
    final grouped = <String, List<int>>{};
    for (final row in rows) {
      final targetId = row.targetId;
      final stars = row.stars;
      if (targetId == null || stars == null) continue;
      grouped.putIfAbsent(targetId, () => []).add(stars);
    }
    return grouped.map(
      (id, stars) => MapEntry(
        id,
        stars.reduce((a, b) => a + b) / stars.length,
      ),
    );
  }

  String _ratingLabelForSeller(String? sellerId) {
    final rating = sellerId == null ? null : _ratingsBySellerId[sellerId];
    if (rating == null) return '5.0';
    return rating.toStringAsFixed(1);
  }

  Future<void> _toggleFavoriteForProduct(ProductsRow product) async {
    if (product.sellerId != null && product.sellerId == currentUserUid) return;
    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para guardar favoritos.')),
      );
      return;
    }
    final productId = product.id;
    if (productId == null || productId.isEmpty) return;
    if (_togglingFavorites.contains(productId)) return;
    final wasFavorited = _favoriteProductIds.contains(productId);
    final previousCount =
        _favoriteCountsOverride[productId] ?? product.favoritesCount;

    setState(() => _togglingFavorites.add(productId));
    try {
      final result = await toggleProductFavorite(
        userId: currentUserUid,
        product: product,
      );
      if (!mounted) return;
      if (result.didFail) {
        setState(() {
          if (wasFavorited) {
            _favoriteProductIds.add(productId);
          } else {
            _favoriteProductIds.remove(productId);
          }
          _favoriteCountsOverride[productId] = previousCount;
        });
        setFavoriteCountUiOverrideForProduct(productId, previousCount);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível atualizar favorito.')),
        );
        return;
      }
      setState(() {
        if (result.isFavorited) {
          _favoriteProductIds.add(productId);
        } else {
          _favoriteProductIds.remove(productId);
        }
        _favoriteCountsOverride[productId] = result.favoritesCount;
      });
      setFavoriteCountUiOverrideForProduct(productId, result.favoritesCount);
    } finally {
      if (!mounted) return;
      setState(() => _togglingFavorites.remove(productId));
    }
  }

  Future<List<ProductsRow>> _fetchMarketplaceProducts() async {
    final search = _model.marketplaceSearchController?.text.trim() ?? '';
    final rows = await _homeFallback<List<ProductsRow>>(
      ProductsTable().queryRows(
        queryFn: (q) {
          var query = q
              .eq('list_on_marketplace', true)
              .eq('is_sold', false);
          if (search.isNotEmpty) {
            query = query.ilike('title', '%$search%');
          }
          return query.order('created_at', ascending: false);
        },
        limit: _kInitialMarketplaceLimit,
      ),
      const <ProductsRow>[],
    );
    final ids = rows
        .map((p) => p.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return rows;
    final blockingOrders = await _homeFallback<List<OrdersRow>>(
      OrdersTable().queryRows(
        queryFn: (q) => q
            .inFilter('product_id', ids)
            .inFilter('status', [
              'reservado',
              'pago',
              'enviado',
              'pedido_devolucao',
              'em_devolucao',
            ]),
        limit: 120,
      ),
      const <OrdersRow>[],
    );
    final blocked = blockingOrders
        .where((o) => !orderIsCancelled(o.status))
        .map((o) => o.productId)
        .whereType<String>()
        .toSet();
    final visible = rows
        .where((p) => p.id != null && !blocked.contains(p.id))
        .toList();
    final sellerIds = visible.map((p) => p.sellerId).whereType<String>();
    final onVacation = await _homeFallback<Set<String>>(
      SellerVacationMode.sellerIdsOnVacation(sellerIds),
      {},
    );
    return SellerVacationMode.hideProductsFromVacationSellers(visible, onVacation);
  }

  Widget _buildHomeSearchField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    String? Function(String?)? validator,
  }) {
    return Container(
      width: double.infinity,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: false,
        obscureText: false,
        style: FlutterFlowTheme.of(context).bodyMedium.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.normal,
                fontStyle:
                    FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
              color: const Color(0xFF101518),
              fontSize: 13.0,
              letterSpacing: 0.0,
              fontWeight: FontWeight.normal,
              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
            ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.normal,
                  fontStyle:
                      FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                color: const Color(0xFF57636C),
                fontSize: 14.0,
                letterSpacing: 0.0,
                fontWeight: FontWeight.normal,
                fontStyle:
                    FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: FleaberColors.inputBorderIdle,
              width: 1.0,
            ),
            borderRadius: FleaberRadius.circularMd,
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: FleaberColors.teal.withValues(alpha: 0.45),
              width: 1.0,
            ),
            borderRadius: FleaberRadius.circularMd,
          ),
          errorBorder: OutlineInputBorder(
            borderSide: const BorderSide(
              color: FleaberColors.danger,
              width: 1.0,
            ),
            borderRadius: FleaberRadius.circularMd,
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: const BorderSide(
              color: FleaberColors.danger,
              width: 1.0,
            ),
            borderRadius: FleaberRadius.circularMd,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(
            14.0,
            8.0,
            14.0,
            8.0,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 34,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: FleaberColors.muted.withValues(alpha: 0.72),
            size: 18.0,
          ),
        ),
        cursorColor: FleaberColors.teal,
        validator: validator,
      ),
    );
  }

  Widget _buildMarketplaceTab(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: marketplaceFeedRefreshTick,
      builder: (context, tick, _) {
        final searchKey = '${tick}_$_marketplaceSearchRevision';
        return NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => const [],
          body: _HomeMarketplaceFutureHost(
          key: ValueKey<String>(searchKey),
          loadRows: _fetchMarketplaceProducts,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return FleaberRefresh(
                onRefresh: () async {
                  requestMarketplaceFeedRefresh();
                  await Future<void>.delayed(
                    const Duration(milliseconds: 500),
                  );
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                    Center(
                      child: SizedBox(
                        width: 40.0,
                        height: 40.0,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            FlutterFlowTheme.of(context).primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return FleaberRefresh(
                onRefresh: () async {
                  requestMarketplaceFeedRefresh();
                  await Future<void>.delayed(
                    const Duration(milliseconds: 500),
                  );
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Ainda sem artigos no Marketplace.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF57636C),
                          fontSize: 15.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return FleaberRefresh(
              onRefresh: () async {
                requestMarketplaceFeedRefresh();
                await Future<void>.delayed(const Duration(milliseconds: 500));
              },
              child: CustomScrollView(
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 100.0),
                    sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: kFleaberTwoColumnGridGap,
                      crossAxisSpacing: kFleaberTwoColumnGridGap,
                      childAspectRatio: MarketplaceProductCard.gridChildAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = rows[index];
                        final productId = product.id;
                        final isFavorited = productId != null &&
                            _favoriteProductIds.contains(productId);
                        final favoriteCount = productId != null
                            ? (favoriteCountUiOverrideForProduct(productId) ??
                                _favoriteCountsOverride[productId] ??
                                product.favoritesCount)
                            : product.favoritesCount;
                        final isOwnListing = product.sellerId != null &&
                            product.sellerId == currentUserUid;
                        return MarketplaceProductCard(
                          title: valueOrDefault<String>(product.title, 'Artigo'),
                          stateLabel: product.state,
                          priceLabel: _formatMarketplacePrice(product),
                          imageUrl: _firstProductImageUrl(product),
                          favoritesCount: favoriteCount,
                          isFavorited: isFavorited,
                          onFavoriteTap: isOwnListing
                              ? null
                              : () => _toggleFavoriteForProduct(product),
                          onTap: () {
                            context.push(
                              ProductDetailsPageWidget.routePath,
                              extra: ProductDetailsPageWidget.routeExtraForProduct(
                                product,
                              ),
                            );
                          },
                        );
                      },
                      childCount: rows.length,
                    ),
                  ),
                ),
                ],
              ),
            );
          },
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          backgroundColor: FleaberColors.bgTint,
          automaticallyImplyLeading: false,
          title: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Fleaber',
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.readexPro(
                        fontWeight: FontWeight.bold,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontStyle,
                      ),
                      color: Color(0xFF007782),
                      fontSize: 24.0,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.bold,
                      fontStyle:
                          FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: notificationBadgeRefreshTick,
                    builder: (context, _, __) {
                      return FutureBuilder<bool>(
                        key: ValueKey<int>(notificationBadgeRefreshTick.value),
                        future: _unreadNotificationsFutureForTick(),
                        builder: (context, notifSnapshot) {
                          final hasDbUnread = notifSnapshot.data == true;
                          final hasBatataPing = batataReservationBellPingActive();
                          final hasUnread = !_suppressNotificationBellDot &&
                              (hasDbUnread || hasBatataPing);
                          if (notifSnapshot.connectionState ==
                              ConnectionState.done) {
                            _logBell('ui_badge', {
                              'suppress': _suppressNotificationBellDot,
                              'has_db_unread': hasDbUnread,
                              'batata_ping': hasBatataPing,
                              'show_dot': hasUnread,
                              'cleared_at':
                                  _notificationBellClearedAt?.toIso8601String(),
                            });
                          }
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          FlutterFlowIconButton(
                            borderColor: Colors.transparent,
                            borderRadius: 20.0,
                            borderWidth: 1.0,
                            buttonSize: 40.0,
                            icon: const Icon(
                              Icons.notifications_none,
                              color: Color(0xFF101518),
                              size: 24.0,
                            ),
                            onPressed: _onNotificationBellTap,
                          ),
                          if (hasUnread)
                            const Positioned(
                              right: 8,
                              top: 7,
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: FleaberColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                        },
                      );
                    },
                  ),
                  FutureBuilder<ProfilesRow?>(
                    future: _headerProfileFuture,
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      return FleaberProfileAvatar(
                        userId: profile?.id ?? currentUserUid,
                        fullName: profile?.fullName,
                        photoUrl: profile?.photoUrl,
                        radius: 19.0,
                      );
                    },
                  ),
                ].divide(SizedBox(width: 12.0)),
              ),
            ].divide(SizedBox(width: 8.0)),
          ),
          actions: [],
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        16.0,
                        4.0,
                        16.0,
                        0.0,
                      ),
                      child: HelperPendingInvitesBanner(),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16.0,
                        2.0,
                        16.0,
                        2.0,
                      ),
                      child: IndexedStack(
                        index: _homeTabIndex,
                        sizing: StackFit.passthrough,
                        alignment: Alignment.topCenter,
                        children: [
                          _buildHomeSearchField(
                            controller: _model.textController!,
                            focusNode: _model.textFieldFocusNode!,
                            hintText: 'Procurar vendedora...',
                            validator: _model.textControllerValidator
                                ?.asValidator(context),
                          ),
                          _buildHomeSearchField(
                            controller: _model.marketplaceSearchController!,
                            focusNode: _model.marketplaceSearchFocusNode!,
                            hintText: 'Procurar artigo...',
                            validator: _model
                                .marketplaceSearchControllerValidator
                                ?.asValidator(context),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: FleaberColors.bgTint,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: TabBar(
                              controller: _homeTabController,
                              labelColor: const Color(0xFF007782),
                              unselectedLabelColor: const Color(0xFF57636C),
                              indicatorColor: const Color(0xFF007782),
                              indicatorWeight: 2.5,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              labelStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              unselectedLabelStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontSize: 13.5,
                              ),
                              tabs: const [
                                Tab(text: 'Diretos'),
                                Tab(text: 'Marketplace'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFE8ECF0),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _homeTabIndex,
                        children: [
                          FleaberRefresh(
                            onRefresh: _refreshLiveFeed,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  16.0,
                                  4.0,
                                  16.0,
                                  0.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'A decorrer agora',
                                      style: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelMedium
                                                      .fontStyle,
                                            ),
                                            color: const Color(0xFF007782),
                                            fontSize: 13.0,
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w600,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelMedium
                                                    .fontStyle,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    _buildLiveFeedSection(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _buildMarketplaceTab(context),
                        ],
                      ),
                    ),
                  ],
                ),
              Align(
                alignment: AlignmentDirectional(0.0, 1.0),
                child: Container(
                  width: double.infinity,
                  height: 80.0,
                  decoration: BoxDecoration(
                    color: FleaberColors.bgTint,
                    boxShadow: const [FleaberElevation.smNav],
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  context.pushNamed(HomePageWidget.routeName);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.home_rounded,
                                      color: Color(0xFF007782),
                                      size: 24.0,
                                    ),
                                    Text(
                                      'Início',
                                      style: FlutterFlowTheme.of(context)
                                          .labelSmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w500,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelSmall
                                                      .fontStyle,
                                            ),
                                            color: Color(0xFF007782),
                                            fontSize: 11.0,
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w500,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                  ].divide(SizedBox(height: 4.0)),
                                ),
                              ),
                              InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  context
                                      .pushNamed(ListaConversasWidget.routeName);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ValueListenableBuilder<int>(
                                      valueListenable:
                                          notificationBadgeRefreshTick,
                                      builder: (context, _, __) {
                                        return FutureBuilder<
                                            List<ChatMessagesRow>>(
                                          future:
                                              _unreadMessagesFutureForTick(),
                                          builder: (context, msgSnapshot) {
                                            final hasUnread =
                                                (msgSnapshot.data ?? const [])
                                                    .isNotEmpty;
                                            return Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Icon(
                                                  Icons.chat_bubble_outline,
                                                  color: Color(0xFF57636C),
                                                  size: 24.0,
                                                ),
                                                if (hasUnread)
                                                  const Positioned(
                                                    right: -2,
                                                    top: -2,
                                                    child: SizedBox(
                                                      width: 8,
                                                      height: 8,
                                                      child: DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              FleaberColors
                                                                  .danger,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    Text(
                                      'Mensagens',
                                      style: FlutterFlowTheme.of(context)
                                          .labelSmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w500,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelSmall
                                                      .fontStyle,
                                            ),
                                            color: Color(0xFF57636C),
                                            fontSize: 11.0,
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w500,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                  ].divide(SizedBox(height: 4.0)),
                                ),
                              ),
                              Semantics(
                                label: 'Fleaber criar',
                                button: true,
                                child: InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    await _showCreateBottomSheet();
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 52.0,
                                        height: 52.0,
                                        decoration: BoxDecoration(
                                          color: Color(0xFF007782),
                                          shape: BoxShape.circle,
                                          boxShadow: const [
                                            FleaberElevation.mdFab,
                                          ],
                                        ),
                                        child: Icon(
                                          _homeTabIndex == 1
                                              ? Icons.photo_camera_rounded
                                              : Icons.videocam_rounded,
                                          color: Colors.white,
                                          size: 28.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  context.pushNamed(PerfilWidget.routeName);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      color: Color(0xFF57636C),
                                      size: 24.0,
                                    ),
                                    Text(
                                      'Perfil',
                                      style: FlutterFlowTheme.of(context)
                                          .labelSmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w500,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .labelSmall
                                                      .fontStyle,
                                            ),
                                            color: Color(0xFF57636C),
                                            fontSize: 11.0,
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w500,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                  ].divide(SizedBox(height: 4.0)),
                                ),
                              ),
                            ],
                          ),
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
    );
  }


  Widget _buildLiveFeedSection(BuildContext context) {
    return HomeLiveFeedGrid(
      key: _liveFeedGridKey,
      search: _model.textController.text.trim(),
      ratingLabelForSeller: _ratingLabelForSeller,
    );
  }
}

/// Garante um único [Future] por «versão» do feed (evita refetch a cada setState da Home).
class _HomeMarketplaceFutureHost extends StatefulWidget {
  const _HomeMarketplaceFutureHost({
    super.key,
    required this.loadRows,
    required this.builder,
  });

  final Future<List<ProductsRow>> Function() loadRows;
  final Widget Function(
    BuildContext context,
    AsyncSnapshot<List<ProductsRow>> snapshot,
  ) builder;

  @override
  State<_HomeMarketplaceFutureHost> createState() =>
      _HomeMarketplaceFutureHostState();
}

class _HomeMarketplaceFutureHostState extends State<_HomeMarketplaceFutureHost> {
  late final Future<List<ProductsRow>> _future = widget.loadRows();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProductsRow>>(
      future: _future,
      builder: widget.builder,
    );
  }
}
