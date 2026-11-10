import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/bundle_order_status_util.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/chat_page/chat_page_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_eligibility.dart';
import '/order_cancel_apply.dart';
import '/recolocar_ref_code.dart';
import '/utils/bundle_price_display.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_commercial_display.dart';
import '/utils/fleaber_h10_navigation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_typography.dart';
import '/utils/live_raffle_prize_copy.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_thumb_stack.dart';
import '/widgets/bundle_direct_payment_sheet.dart';
import '/utils/order_delivery_display.dart';
import '/widgets/dpd_tracking_sheet.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/order_post_purchase_panel.dart';

class MinhasEncomendasWidget extends StatefulWidget {
  const MinhasEncomendasWidget({
    super.key,
    this.embedded = false,
    this.initialOrderId,
  });

  /// H11 desktop shell: TabBar no corpo, sem AppBar duplicada.
  final bool embedded;

  /// Deep link email/Hub: abrir esta encomenda (tab + scroll + ACL).
  final String? initialOrderId;

  static const String routeName = 'MinhasEncomendas';
  static const String routePath = '/minhasEncomendas';

  @override
  State<MinhasEncomendasWidget> createState() => _MinhasEncomendasWidgetState();
}

class _MinhasEncomendasWidgetState extends State<MinhasEncomendasWidget>
    with SingleTickerProviderStateMixin {
  static const Color _kTeal = Color(0xFF007782);

  late TabController _tabController;
  String? _focusOrderId;
  String? _focusBanner;
  bool _focusReady = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final oid = (widget.initialOrderId ?? '').trim();
    if (oid.isNotEmpty) {
      _focusOrderId = oid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_resolveFocusOrder(oid));
      });
    } else {
      _focusReady = true;
    }
  }

  Future<void> _resolveFocusOrder(String orderId) async {
    if (currentUserUid.isEmpty) {
      if (mounted) setState(() => _focusReady = true);
      return;
    }
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => q.eq('id', orderId),
        limit: 1,
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() {
          _focusBanner =
              'Não encontrámos esta encomenda na tua conta.';
          _focusOrderId = null;
          _focusReady = true;
        });
        return;
      }
      final order = rows.first;
      final uid = currentUserUid;
      final sellerCtx = effectiveSellerId;
      final buyerId = (order.buyerId ?? '').trim();
      final sellerId = (order.sellerId ?? '').trim();
      final isBuyer = buyerId.isNotEmpty && buyerId == uid;
      final isSeller = sellerId.isNotEmpty &&
          (sellerId == uid || sellerId == sellerCtx);
      if (!isBuyer && !isSeller) {
        setState(() {
          _focusBanner =
              'Não tens permissão para ver esta encomenda.';
          _focusOrderId = null;
          _focusReady = true;
        });
        return;
      }
      // Comprador → Comprado; vendedor → Vendido (emails E1/E2).
      final tabIndex = isBuyer ? 1 : 0;
      if (_tabController.index != tabIndex) {
        _tabController.animateTo(tabIndex);
      }
      setState(() {
        _focusOrderId = orderId;
        _focusReady = true;
      });
    } catch (e) {
      print('MINHAS_ENCOMENDAS_BATATA focus order: $e');
      if (mounted) {
        setState(() {
          _focusBanner = 'Não foi possível abrir a encomenda pedida.';
          _focusOrderId = null;
          _focusReady = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusId = _focusOrderId;
    final tabs = TabBar(
      controller: _tabController,
      labelColor: _kTeal,
      unselectedLabelColor: const Color(0xFF57636C),
      indicatorColor: _kTeal,
      tabs: const [
        Tab(text: 'Vendido'),
        Tab(text: 'Comprado'),
      ],
    );
    final focusOnly = focusId != null &&
        focusId.isNotEmpty &&
        _focusReady &&
        _focusBanner == null;
    final views = TabBarView(
      controller: _tabController,
      children: [
        _OrdersListTab(
          key: const ValueKey<String>('encomendas_vendido_seller_id'),
          isVendasTab: true,
          highlightOrderId: focusId,
          focusOnly: focusOnly,
        ),
        _OrdersListTab(
          key: const ValueKey<String>('encomendas_comprado_buyer_id'),
          isVendasTab: false,
          highlightOrderId: focusId,
          focusOnly: focusOnly,
        ),
      ],
    );
    Widget body = views;
    if (_focusBanner != null || (!_focusReady && focusId != null)) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_focusBanner != null)
            Material(
              color: const Color(0xFFFFF4E5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  _focusBanner!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF8A5A00),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          Expanded(child: views),
        ],
      );
    }
    if (widget.embedded) {
      return ColoredBox(
        color: FleaberColors.bgTint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(color: FleaberColors.bgTint, child: tabs),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        backgroundColor: FleaberColors.bgTint,
        foregroundColor: const Color(0xFF101518),
        elevation: 0,
        title: Text(
          'As Minhas Encomendas',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: const Color(0xFF101518),
          ),
        ),
        bottom: tabs,
      ),
      body: body,
    );
  }
}

/// Pedidos + produtos num único passo (evita segundo Future recriado a cada frame).
class _TabOrdersPayload {
  _TabOrdersPayload(this.orders, this.productsById);

  final List<OrdersRow> orders;
  final Map<String, ProductsRow> productsById;
}

class _OrdersListTab extends StatefulWidget {
  const _OrdersListTab({
    super.key,
    required this.isVendasTab,
    this.highlightOrderId,
    this.focusOnly = false,
  });

  /// `true` → só encomendas em que sou **vendedor** (`seller_id`).
  /// `false` → só encomendas em que sou **comprador** (`buyer_id`).
  final bool isVendasTab;

  /// Deep link: destacar/scroll até esta encomenda nesta tab.
  final String? highlightOrderId;

  /// Email CTA: mostrar só a encomenda (ou conjunto) pedida — não só highlight.
  final bool focusOnly;

  @override
  State<_OrdersListTab> createState() => _OrdersListTabState();
}

class _OrdersListTabState extends State<_OrdersListTab>
    with AutomaticKeepAliveClientMixin, RouteAware, WidgetsBindingObserver {
  Future<_TabOrdersPayload>? _payloadFuture;

  /// Força novo estado no [FutureBuilder] após recargas (evita snapshot antigo).
  int _payloadEpoch = 0;
  final ScrollController _listScrollController = ScrollController();
  double? _pendingScrollRestore;
  final Map<String, GlobalKey> _orderKeys = {};
  String? _scrolledHighlightId;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersRealtimeSub;

  @override
  bool get wantKeepAlive => true;

  String? _lastUidForLoad;

  GlobalKey _keyForOrder(String orderId) =>
      _orderKeys.putIfAbsent(orderId, GlobalKey.new);

  void _scrollToHighlightIfNeeded(List<List<OrdersRow>> entries) {
    final hid = (widget.highlightOrderId ?? '').trim();
    if (hid.isEmpty || hid == _scrolledHighlightId) return;
    var index = -1;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].any((o) => (o.id ?? '').trim() == hid)) {
        index = i;
        break;
      }
    }
    if (index < 0) return;
    _scrolledHighlightId = hid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _orderKeys[hid]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 380),
          alignment: 0.12,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastUidForLoad = currentUserUid;
    _payloadFuture = _loadPayload();
    _subscribeOrdersRealtime();
    ordersListRefreshTick.addListener(_onOrdersListRefreshTick);
    AppStateNotifier.instance.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final uid = currentUserUid;
    if (uid.isNotEmpty && uid != _lastUidForLoad) {
      _lastUidForLoad = uid;
      _subscribeOrdersRealtime();
      _reloadPayload(preserveScroll: false);
    }
  }

  void _onOrdersListRefreshTick() {
    if (!mounted) return;
    _reloadPayload(preserveScroll: true);
  }

  void _subscribeOrdersRealtime() {
    final uid = currentUserUid;
    if (uid.isEmpty) return;
    final column = widget.isVendasTab ? 'seller_id' : 'buyer_id';
    final filterId =
        widget.isVendasTab ? effectiveSellerId : currentUserUid;
    try {
      _ordersRealtimeSub?.cancel();
      _ordersRealtimeSub = SupaFlow.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq(column, filterId)
          .listen(
            (_) {
              if (mounted) _reloadPayload(preserveScroll: true);
            },
            onError: (Object e, StackTrace st) {
              print('MINHAS_ENCOMENDAS_BATATA stream orders: $e');
            },
          );
    } catch (e) {
      print('MINHAS_ENCOMENDAS_BATATA stream orders subscribe: $e');
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

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuthChanged);
    ordersListRefreshTick.removeListener(_onOrdersListRefreshTick);
    _ordersRealtimeSub?.cancel();
    _listScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadPayload();
    }
  }

  @override
  void didPush() {
    _reloadPayload();
  }

  @override
  void didPopNext() {
    _reloadPayload();
  }

  Future<void> _reloadPayload({bool preserveScroll = false}) async {
    if (!mounted) return;
    if (preserveScroll && _listScrollController.hasClients) {
      _pendingScrollRestore = _listScrollController.offset;
    }
    setState(() {
      _payloadEpoch++;
      _payloadFuture = _loadPayload();
    });
    await _payloadFuture;
    if (!mounted || _pendingScrollRestore == null) return;
    final target = _pendingScrollRestore!;
    _pendingScrollRestore = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScrollController.hasClients) return;
      final max = _listScrollController.position.maxScrollExtent;
      _listScrollController.jumpTo(target.clamp(0.0, max));
    });
  }

  static Future<Map<String, ProductsRow>> _productsForOrders(
    List<OrdersRow> orders,
  ) async {
    final ids =
        orders.map((o) => o.productId).whereType<String>().toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q.inFilter('id', ids),
      limit: ids.length,
    );
    return {for (final p in rows) if (p.id != null) p.id!: p};
  }

  Future<_TabOrdersPayload> _loadPayload() async {
    if (currentUserUid.isEmpty) {
      return _TabOrdersPayload(<OrdersRow>[], <String, ProductsRow>{});
    }
    final List<OrdersRow> orders;
    if (widget.isVendasTab) {
      orders = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eq('seller_id', effectiveSellerId)
            .order('created_at', ascending: false),
        limit: 100,
      );
    } else {
      orders = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eq('buyer_id', currentUserUid)
            .order('created_at', ascending: false),
        limit: 100,
      );
    }

    final tabLabel = widget.isVendasTab ? 'VENDIDO' : 'COMPRADO';
    final nCancel = orders
        .where((o) => orderIsCancelled(orderStatusRawFromData(o.data)))
        .length;
    print(
      'MINHAS_ENCOMENDAS_BATATA tab=$tabLabel total=${orders.length} '
      'cancelados=$nCancel',
    );

    final productsById = await _productsForOrders(orders);
    return _TabOrdersPayload(orders, productsById);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        if (currentUserUid.isEmpty) {
          // Sessão a restaurar OU login real em falta — nunca mensagem
          // enganadora dentro do shell Conta autenticado.
          final hasSession = AppStateNotifier.instance.loggedIn ||
              SupaFlow.client.auth.currentSession != null;
          if (hasSession) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF007782)),
            );
          }
          return Center(
            child: Text(
              'Inicia sessão para veres as encomendas.',
              style: GoogleFonts.inter(color: const Color(0xFF57636C)),
            ),
          );
        }

        // UID acabou de ficar disponível: garante reload se o future nasceu vazio.
        if (_lastUidForLoad != currentUserUid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _onAuthChanged();
          });
        }

        return FutureBuilder<_TabOrdersPayload>(
      future: _payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print('MINHAS_ENCOMENDAS_BATATA ERRO query: ${snapshot.error}');
          return _EmptyEncomendasIllustration(
            message:
                'Não foi possível carregar as encomendas. Verifica a ligação e tenta outra vez.',
          );
        }
        final payload = snapshot.data;
        if (payload == null || payload.orders.isEmpty) {
          return const _EmptyEncomendasIllustration(
            message: 'Ainda não tens encomendas.',
          );
        }

        final orders = payload.orders;
        final products = payload.productsById;
        var entries = _groupOrdersByBundle(orders);
        final highlightId = (widget.highlightOrderId ?? '').trim();
        if (widget.focusOnly && highlightId.isNotEmpty) {
          entries = entries
              .where(
                (g) => g.any((o) => (o.id ?? '').trim() == highlightId),
              )
              .toList();
          if (entries.isEmpty) {
            return _EmptyEncomendasIllustration(
              message:
                  'Esta encomenda não aparece neste separador. Confirma se és comprador ou vendedor.',
            );
          }
        }
        _scrollToHighlightIfNeeded(entries);

        void onSnack(String message, {bool error = false}) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }

        return RefreshIndicator(
          color: const Color(0xFF007782),
          onRefresh: _reloadPayload,
          child: ListView.separated(
            controller: _listScrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              thickness: 0.5,
              color: Color(0xFFD9DEE3),
            ),
            itemBuilder: (context, index) {
              final group = entries[index];
              final groupHasHighlight = highlightId.isNotEmpty &&
                  group.any((o) => (o.id ?? '').trim() == highlightId);
              final wrapHighlight = (Widget child) {
                if (!groupHasHighlight) return child;
                final anchorId = group
                        .map((o) => (o.id ?? '').trim())
                        .firstWhere(
                          (id) => id == highlightId,
                          orElse: () => (group.first.id ?? '').trim(),
                        );
                return KeyedSubtree(
                  key: _keyForOrder(anchorId.isEmpty ? highlightId : anchorId),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x14007782),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0x66007782),
                        width: 1.5,
                      ),
                    ),
                    child: child,
                  ),
                );
              };
              if (group.length >= 2) {
                return wrapHighlight(
                  _BundleOrderGroupTile(
                    key: ValueKey<String>(
                      'bundle_${group.first.bundleId}_${widget.isVendasTab}',
                    ),
                    orders: group,
                    productsById: products,
                    isVendasTab: widget.isVendasTab,
                    onOrdersChanged: () => _reloadPayload(preserveScroll: true),
                    onSnackBar: onSnack,
                  ),
                );
              }
              final order = group.first;
              final product =
                  order.productId != null ? products[order.productId!] : null;
              return wrapHighlight(
                _OrderRowTile(
                  key: ValueKey<String>(
                    '${order.id ?? index}_${widget.isVendasTab}',
                  ),
                  order: order,
                  product: product,
                  isVendasTab: widget.isVendasTab,
                  onOrdersChanged: () => _reloadPayload(preserveScroll: true),
                  onSnackBar: onSnack,
                ),
              );
            },
          ),
        );
      },
        );
      },
    );
  }
}

/// Agrupa encomendas do mesmo conjunto (`bundle_id`) numa única entrada visual,
/// mantendo a ordem original (grupo fica na posição da 1.ª encomenda).
List<List<OrdersRow>> _groupOrdersByBundle(List<OrdersRow> orders) {
  final entries = <List<OrdersRow>>[];
  final indexByBundle = <String, int>{};
  for (final order in orders) {
    final bid = order.bundleId ?? '';
    if (bid.isNotEmpty) {
      final existing = indexByBundle[bid];
      if (existing != null) {
        entries[existing].add(order);
        continue;
      }
      indexByBundle[bid] = entries.length;
      entries.add(<OrdersRow>[order]);
    } else {
      entries.add(<OrdersRow>[order]);
    }
  }
  return entries;
}

/// Títulos de seed QA → apresentação comercial (H11 visual).
String _displayProductTitle(String? raw) => fleaberCommercialTitle(raw);

({Color color, IconData icon}) _orderRowStatusVisual(OrdersRow order) {
  var raw = orderStatusRawFromData(order.data).trim();
  if (orderIsCancelled(raw)) {
    return (color: FleaberColors.danger, icon: Icons.cancel_rounded);
  }
  switch (normalizeOrderStatusKey(raw)) {
    case 'reserva_pendente':
      return (
        color: const Color(0xFFD97706),
        icon: Icons.schedule_rounded,
      );
    case 'reservado':
      return (
        color: const Color(0xFF007782),
        icon: Icons.bookmark_added_rounded,
      );
    case 'pago':
      return (
        color: const Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
      );
    case 'premio_rifa':
      return (
        color: const Color(0xFFC9A227),
        icon: Icons.emoji_events_rounded,
      );
    case 'enviado':
      return (
        color: const Color(0xFF3949AB),
        icon: Icons.local_shipping_rounded,
      );
    default:
      return (
        color: const Color(0xFF57636C),
        icon: Icons.receipt_long_rounded,
      );
  }
}

String _orderRowStatusPhrase(OrdersRow order) {
  return bundleGroupAggregatedStatusPhrase([order]);
}

String _bundleGroupAggregatedStatusPhrase(List<OrdersRow> orders) {
  return bundleGroupAggregatedStatusPhrase(orders);
}

/// Linha compacta dentro de um conjunto expandido — tap imagem → detalhe; ⋮ acções.
class _BundleOrderSubRow extends StatefulWidget {
  const _BundleOrderSubRow({
    super.key,
    required this.order,
    required this.groupOrders,
    required this.product,
    required this.isVendasTab,
    this.onOrdersChanged,
    this.onSnackBar,
  });

  final OrdersRow order;
  final List<OrdersRow> groupOrders;
  final ProductsRow? product;
  final bool isVendasTab;
  final VoidCallback? onOrdersChanged;
  final _OrderRowSnackBar? onSnackBar;

  @override
  State<_BundleOrderSubRow> createState() => _BundleOrderSubRowState();
}

class _BundleOrderSubRowState extends State<_BundleOrderSubRow> {
  bool _duplicateBusy = false;
  bool _cancelBusy = false;

  String _priceLabel() {
    final t = widget.order.priceTotal;
    if (t == null) return '—';
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(t);
  }

  String? _imageUrl() {
    final urls = widget.product?.imageUrls ?? const [];
    if (urls.isEmpty) return null;
    return urls.first;
  }

  Future<void> _openProductDetails() async {
    final pid = (widget.product?.id ?? widget.order.productId)?.trim();
    if (pid == null || pid.isEmpty) {
      widget.onSnackBar?.call('Artigo não encontrado.', error: true);
      return;
    }
    // Sem import de ProductDetails (ciclos via HubAccountRoutes / index).
    await context.pushNamed(
      'ProductDetails',
      queryParameters: <String, String>{
        'product_id': pid,
      },
    );
  }

  Future<void> _onVenderOutroIgual() async {
    if (_duplicateBusy || !widget.isVendasTab) return;
    if (widget.order.sellerId != currentUserUid) return;
    final source = widget.product;
    if (source == null) return;

    setState(() => _duplicateBusy = true);
    try {
      final inserted = await insertRelistedProductFromSource(
        source: source,
        sellerId: currentUserUid,
      );
                  if (!mounted) return;
      widget.onSnackBar?.call('Artigo recolocado no marketplace!');
      requestMarketplaceFeedRefresh();
      widget.onOrdersChanged?.call();
      print('BATATA_DUPLICAR_LISTING bundle sub origem=${source.id} novo=${inserted.id}');
    } catch (e) {
      if (!mounted) return;
      widget.onSnackBar?.call('Erro ao duplicar: $e', error: true);
    } finally {
      if (mounted) setState(() => _duplicateBusy = false);
    }
  }

  Future<void> _onCancelarLinha() async {
    final oid = widget.order.id;
    if (oid == null || oid.isEmpty || _cancelBusy) return;
    if (!widget.isVendasTab || widget.order.sellerId != currentUserUid) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Anular esta linha?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Cancela só esta linha do conjunto. As outras encomendas do conjunto mantêm-se.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _cancelBusy = true);
    try {
      await applyOrderCancelAndRelist(
        orderId: oid,
        sellerUserId: currentUserUid,
      );
      widget.onSnackBar?.call('Linha do conjunto cancelada.');
      widget.onOrdersChanged?.call();
    } catch (e) {
      widget.onSnackBar?.call('Erro ao cancelar: $e', error: true);
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.product == null
        ? 'Artigo removido'
        : _displayProductTitle(widget.product!.title);
    final lineQty = widget.order.quantity ?? 1;
    final displayTitle =
        lineQty > 1 ? '$title ×$lineQty' : title;
    final url = _imageUrl();
    final phrase = bundleSubRowStatusPhrase(widget.order, widget.groupOrders);
    final statusVisual =
        bundleSubRowStatusVisual(widget.order, widget.groupOrders);
    final rowStatus = orderStatusRawFromData(widget.order.data);
    final showCancel = widget.isVendasTab &&
        !orderIsCancelled(rowStatus) &&
        orderAllowsBuyerCancelStatus(rowStatus) &&
        widget.order.sellerId == currentUserUid;
    final showDuplicate =
        widget.isVendasTab && widget.order.sellerId == currentUserUid;

    Widget thumbStack() {
      return SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: FleaberRadius.circularSm,
                child: url != null && url.isNotEmpty
                    ? BatataCachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholderColor: const Color(0xFFF1F4F8),
                      )
                    : ColoredBox(
                        color: const Color(0xFFF1F4F8),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.grey.shade500,
                        ),
                      ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: IgnorePointer(
                child: _OrderStatusThumbBadge(
                  color: statusVisual.color,
                  icon: statusVisual.icon,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: FleaberRadius.circularSm,
          border: Border.all(color: const Color(0xFFE8ECF0)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openProductDetails,
                child: thumbStack(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openProductDetails,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FleaberTypography.listTitle(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phrase,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FleaberTypography.orderStatus(statusVisual.color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: Text(
              _priceLabel(),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: const Color(0xFF007782),
              ),
            ),
          ),
          if (showCancel || showDuplicate)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF57636C)),
              onSelected: (v) {
                if (v == 'cancel') _onCancelarLinha();
                if (v == 'duplicate') _onVenderOutroIgual();
              },
              itemBuilder: (ctx) => [
                if (showCancel)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Cancelar'),
                  ),
                if (showDuplicate)
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Vender outro igual'),
                  ),
              ],
            ),
        ],
          ),
        ),
      ),
    );
  }
}

/// Cartão único «Conjunto · N artigos» com total pago; expande para as linhas.
class _BundleOrderGroupTile extends StatefulWidget {
  const _BundleOrderGroupTile({
    super.key,
    required this.orders,
    required this.productsById,
    required this.isVendasTab,
    required this.onOrdersChanged,
    required this.onSnackBar,
  });

  final List<OrdersRow> orders;
  final Map<String, ProductsRow> productsById;
  final bool isVendasTab;
  final VoidCallback onOrdersChanged;
  final _OrderRowSnackBar onSnackBar;

  @override
  State<_BundleOrderGroupTile> createState() => _BundleOrderGroupTileState();
}

class _BundleOrderGroupTileState extends State<_BundleOrderGroupTile> {
  bool _expanded = false;
  bool _groupActionBusy = false;

  double get _totalPaid {
    var sum = 0.0;
    for (final o in widget.orders) {
      sum += o.priceTotal ?? 0;
    }
    return sum;
  }

  List<String> get _thumbUrls {
    final urls = <String>[];
    for (final o in widget.orders) {
      final p = o.productId != null ? widget.productsById[o.productId!] : null;
      final list = p?.imageUrls ?? const <String>[];
      if (list.isNotEmpty && list.first.isNotEmpty) urls.add(list.first);
    }
    return urls;
  }

  Future<void> _cancelBundleGroup() async {
    if (_groupActionBusy || !widget.isVendasTab) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Anular conjunto?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Cancela todas as linhas deste conjunto (${widget.orders.length} artigos).',
          style: GoogleFonts.inter(fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular conjunto'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _groupActionBusy = true);
    try {
      for (final o in widget.orders) {
        final oid = o.id;
        if (oid == null || oid.isEmpty) continue;
        if (orderIsCancelled(o.status)) continue;
        await applyOrderCancelAndRelist(
          orderId: oid,
          sellerUserId: currentUserUid,
        );
      }
      widget.onSnackBar('Conjunto cancelado.');
      widget.onOrdersChanged();
    } catch (e) {
      widget.onSnackBar('Erro ao cancelar conjunto: $e', error: true);
    } finally {
      if (mounted) setState(() => _groupActionBusy = false);
    }
  }

  Future<void> _relistBundleProducts() async {
    if (_groupActionBusy || !widget.isVendasTab) return;
    setState(() => _groupActionBusy = true);
    try {
      var count = 0;
      for (final o in widget.orders) {
        final p = o.productId != null
            ? widget.productsById[o.productId!]
            : null;
        if (p == null) continue;
        await insertRelistedProductFromSource(
          source: p,
          sellerId: currentUserUid,
        );
        count++;
      }
      requestMarketplaceFeedRefresh();
      widget.onSnackBar(
        count > 0
            ? 'Artigos recolocados no marketplace.'
            : 'Nenhum artigo recolocado.',
      );
      widget.onOrdersChanged();
    } catch (e) {
      widget.onSnackBar('Erro ao recolocar: $e', error: true);
    } finally {
      if (mounted) setState(() => _groupActionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.orders.fold<int>(
      0,
      (sum, o) => sum + (o.quantity ?? 1),
    );
    final thumbs = _thumbUrls.take(3).toList();
    final priceView = BundlePriceDisplay.forOrdersListBundle(
      isSellerTab: widget.isVendasTab,
      orders: widget.orders,
    );
    final statusPhrase = _bundleGroupAggregatedStatusPhrase(widget.orders);
    final statusVisual = bundleGroupAggregatedStatusVisual(widget.orders);
    final showPaymentDetails = !widget.isVendasTab &&
        (bundleOrdersDirectPaymentPending(widget.orders) ||
            widget.orders.any((o) {
              final st = normalizeOrderStatusKey(o.status);
              return st == 'aguarda_confirmacao' &&
                  bundlePaymentMethodIsDirect(o.paymentMethod);
            }));
    final bundleId = widget.orders.first.bundleId?.trim() ?? '';

    return Material(
      color: FleaberColors.bgTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  BundleThumbStack(imageUrls: thumbs),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conjunto · $count artigos',
                          style: FleaberTypography.listTitle(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusPhrase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FleaberTypography.orderStatus(statusVisual.color),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${priceView.primaryCaption}: ${priceView.primaryAmount}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: const Color(0xFF007782),
                          ),
                        ),
                        if (priceView.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            priceView.subtitle!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF57636C),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF57636C),
                  ),
                  if (widget.isVendasTab &&
                      widget.orders.first.sellerId == currentUserUid)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Color(0xFF57636C)),
                      enabled: !_groupActionBusy,
                      onSelected: (v) {
                        if (v == 'cancel') _cancelBundleGroup();
                        if (v == 'relist') _relistBundleProducts();
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancelar encomenda do conjunto'),
                        ),
                        PopupMenuItem(
                          value: 'relist',
                          child: Text('Recolocar artigos vendidos'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (showPaymentDetails && bundleId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FleaberPrimaryButton(
                width: double.infinity,
                height: 48,
                label: 'Ver dados de pagamento',
                fontSize: 15,
                onPressed: () async {
                  try {
                    final details = await buildBundleDirectPaymentDetails(
                      bundleId: bundleId,
                    );
                    if (!context.mounted) return;
                    await showBundleDirectPaymentDetailsSheet(
                      context,
                      details: details,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    widget.onSnackBar('$e', error: true);
                  }
                },
              ),
            ),
          if (_expanded) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F8),
                border: Border.all(color: FleaberColors.teal, width: 1.2),
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: widget.orders.map((o) {
                  final product = o.productId != null
                      ? widget.productsById[o.productId!]
                      : null;
                  return _BundleOrderSubRow(
                    key: ValueKey<String>('bundlerow_${o.id}'),
                    order: o,
                    groupOrders: widget.orders,
                    product: product,
                    isVendasTab: widget.isVendasTab,
                    onOrdersChanged: widget.onOrdersChanged,
                    onSnackBar: widget.onSnackBar,
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyEncomendasIllustration extends StatelessWidget {
  const _EmptyEncomendasIllustration({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: const Color(0xFF007782).withValues(alpha: 0.35),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF57636C),
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selo circular com ícone do estado, canto da miniatura na lista de encomendas.
class _OrderStatusThumbBadge extends StatelessWidget {
  const _OrderStatusThumbBadge({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }
}

typedef _OrderRowSnackBar = void Function(String message, {bool error});

class _OrderRowTile extends StatefulWidget {
  const _OrderRowTile({
    super.key,
    required this.order,
    required this.product,
    required this.isVendasTab,
    this.onOrdersChanged,
    this.onSnackBar,
    this.showBundleChip = true,
  });

  final OrdersRow order;
  final ProductsRow? product;
  final bool isVendasTab;

  /// Selo «Conjunto» na linha. Falso dentro do cartão de grupo (já tem no topo).
  final bool showBundleChip;

  /// Recarrega a lista de encomendas (ex.: após cancelamento pelo vendedor).
  final VoidCallback? onOrdersChanged;

  /// Snackbar no ecrã pai (sobrevive quando a linha é reconstruída).
  final _OrderRowSnackBar? onSnackBar;

  @override
  State<_OrderRowTile> createState() => _OrderRowTileState();
}

class _OrderRowTileState extends State<_OrderRowTile> {
  static const Color _kRowBg = FleaberColors.bgTint;
  static const Color _kChevron = Color(0xFFC7CDD4);
  static const Color _kTealBatata = Color(0xFF007782);

  bool _duplicateBusy = false;
  bool _sellerCancelBusy = false;
  bool _buyerCancelReservaBusy = false;

  /// Executa acção no servidor após o diálogo, mesmo que a linha seja desmontada
  /// (o [FutureBuilder] recarrega a lista enquanto o popup está aberto).
  Future<void> _afterConfirmRun({
    required bool? confirm,
    required Future<void> Function() run,
    required String okMessage,
    required void Function(bool busy) setBusyFlag,
  }) async {
    if (confirm != true) return;

    final onChanged = widget.onOrdersChanged;
    final snack = widget.onSnackBar;

    setBusyFlag(true);
    try {
      await run();
      requestMarketplaceFeedRefresh();
      pingBatataReservationForNotificationBell();
      if (onChanged != null) {
        onChanged();
      } else {
        requestOrdersListRefresh();
      }
      snack?.call(okMessage);
    } catch (e, st) {
      print('BATATA_ORDER_ACTION ERRO: $e\n$st');
      snack?.call('$e', error: true);
    } finally {
      setBusyFlag(false);
    }
  }

  Widget _confirmDialogTitle(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: _kTealBatata, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: const Color(0xFF101518),
            ),
          ),
        ),
      ],
    );
  }

  String _normalizedStatusKey() {
    final raw = orderStatusRawFromData(widget.order.data).trim();
    if (orderIsCancelled(raw)) return 'cancelado';
    return normalizeOrderStatusKey(raw);
  }

  ({Color color, IconData icon}) _statusVisual() {
    switch (_normalizedStatusKey()) {
      case 'cancelado':
        return (
          color: FleaberColors.danger,
          icon: Icons.cancel_rounded,
        );
      case 'reserva_pendente':
        return (
          color: const Color(0xFFD97706),
          icon: Icons.schedule_rounded,
        );
      case 'reservado':
        return (
          color: const Color(0xFF007782),
          icon: Icons.bookmark_added_rounded,
        );
      case 'pendente':
        return (
          color: const Color(0xFFE65100),
          icon: Icons.payments_outlined,
        );
      case 'aguarda_confirmacao':
        return (
          color: const Color(0xFF1565C0),
          icon: Icons.fact_check_rounded,
        );
      case 'pago':
        return (
          color: const Color(0xFF2E7D32),
          icon: Icons.check_circle_rounded,
        );
      case 'premio_rifa':
        return (
          color: const Color(0xFFC9A227),
          icon: Icons.emoji_events_rounded,
        );
      case 'enviado':
        return (
          color: const Color(0xFF3949AB),
          icon: Icons.local_shipping_rounded,
        );
      case 'pedido_devolucao':
        return (
          color: const Color(0xFFB45309),
          icon: Icons.report_problem_rounded,
        );
      case 'em_devolucao':
        return (
          color: const Color(0xFF7B1FA2),
          icon: Icons.assignment_return_rounded,
        );
      case 'devolucao_entregue':
        return (
          color: const Color(0xFF7B1FA2),
          icon: Icons.inventory_2_rounded,
        );
      case 'disputa_devolucao_vendedor':
        return (
          color: const Color(0xFFB45309),
          icon: Icons.report_problem_rounded,
        );
      case 'devolvida':
        return (
          color: const Color(0xFF007782),
          icon: Icons.keyboard_return_rounded,
        );
      default:
        return (
          color: const Color(0xFF57636C),
          icon: Icons.receipt_long_rounded,
        );
    }
  }

  String _statusPhrase() {
    return orderStatusDisplayPhrase(
      orderStatusRawFromData(widget.order.data),
      shippingMethod: widget.order.shippingMethod,
      paymentMethod: widget.order.paymentMethod,
    );
  }

  String _priceLabel() {
    final t = widget.order.priceTotal;
    if (t == null) return '—';
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(t);
  }

  String? _imageUrl() {
    final urls = widget.product?.imageUrls ?? const [];
    if (urls.isEmpty) return null;
    return urls.first;
  }

  Future<ProductsRow?> _resolveSourceProduct() async {
    if (widget.product != null) return widget.product;
    final pid = widget.order.productId;
    if (pid == null || pid.isEmpty) return null;
    final rows = await ProductsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', pid),
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> _onVenderOutroIgual() async {
    if (_duplicateBusy || !widget.isVendasTab) return;
    if (widget.order.sellerId != currentUserUid) {
      print(
        'BATATA_DUPLICAR_LISTING bloqueado: seller_id encomenda != utilizador.',
      );
      return;
    }

    setState(() => _duplicateBusy = true);
    try {
      final source = await _resolveSourceProduct();
      if (source == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artigo original não encontrado para duplicar.'),
          ),
        );
        return;
      }
      if (source.title == null || source.title!.trim().isEmpty ||
          source.price == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Faltam dados no artigo original (título ou preço).',
            ),
          ),
        );
        return;
      }

      final inserted = await insertRelistedProductFromSource(
        source: source,
        sellerId: currentUserUid,
      );

      print(
        'BATATA_DUPLICAR_LISTING origem=${source.id} novo=${inserted.id} '
        'seller=$currentUserUid',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artigo recolocado no marketplace!')),
      );
      requestMarketplaceFeedRefresh();
      widget.onOrdersChanged?.call();
    } catch (e) {
      print('BATATA_DUPLICAR_LISTING ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao duplicar: $e')),
      );
    } finally {
      if (mounted) setState(() => _duplicateBusy = false);
    }
  }

  Future<void> _openChat(
    BuildContext context, {
    bool requestCancelOnOpen = false,
  }) async {
    final pid = widget.order.productId;
    if (pid == null || pid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encomenda sem artigo associado.')),
      );
      return;
    }
    final other =
        widget.isVendasTab ? widget.order.buyerId : widget.order.sellerId;
    if (other == null || other.isEmpty) return;
    try {
      final oid = widget.order.id?.trim() ?? '';
      await openH10Conversation(
        context,
        otherUserId: other,
        orderId: oid.isEmpty ? null : oid,
        productId: pid,
        requestCancelOnOpen: requestCancelOnOpen,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a conversa.')),
      );
    }
  }

  bool _canShowDpdTracking() {
    final oid = widget.order.id?.trim() ?? '';
    if (oid.isEmpty) return false;
    if (LiveRafflePrizeCopy.isHandShippingMethod(widget.order.shippingMethod)) {
      return false;
    }
    final sm = (widget.order.shippingMethod ?? '').trim().toLowerCase();
    if (sm == 'hand' || sm.contains('entrega em mao') || sm.contains('entrega em mão')) {
      return false;
    }
    final key = normalizeOrderStatusKey(
      orderStatusRawFromData(widget.order.data),
    );
    final hasGuide = (widget.order.dpdTrackingCode ?? '').trim().isNotEmpty;
    return hasGuide ||
        key == 'pago' ||
        key == 'enviado' ||
        key == 'concluido' ||
        key == 'aguarda_confirmacao';
  }

  Future<void> _openDpdTracking() async {
    final oid = widget.order.id?.trim() ?? '';
    if (oid.isEmpty) return;
    await showDpdTrackingSheet(
      context,
      orderId: oid,
      knownGuide: widget.order.dpdTrackingCode,
    );
  }

  Future<void> _sellerAttachDpdGuide() async {
    if (!widget.isVendasTab || widget.order.sellerId != currentUserUid) return;
    final oid = widget.order.id?.trim() ?? '';
    if (oid.isEmpty) return;
    final ctrl = TextEditingController(
      text: (widget.order.dpdTrackingCode ?? '').trim(),
    );
    final guide = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Guia DPD',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Número da guia',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (guide == null || guide.isEmpty || !mounted) return;
    try {
      await OrdersTable().update(
        data: {'dpd_tracking_code': guide},
        matchingRows: (q) => q.eqOrNull('id', oid),
      );
      widget.onOrdersChanged?.call();
      if (!mounted) return;
      await showDpdTrackingSheet(
        context,
        orderId: oid,
        knownGuide: guide,
      );
    } catch (e) {
      widget.onSnackBar?.call('Não foi possível guardar a guia: $e', error: true);
    }
  }

  Future<void> _onCompradorCancelarReservaPendenteComDialog(
    BuildContext context,
  ) async {
    final oid = widget.order.id;
    final pid = widget.order.productId;
    final sid = widget.order.sellerId;
    if (oid == null ||
        oid.isEmpty ||
        _buyerCancelReservaBusy ||
        widget.order.buyerId != currentUserUid) {
      return;
    }
    final raw = orderStatusRawFromData(widget.order.data);
    if (normalizeOrderStatusKey(raw) != 'reserva_pendente') {
      await _openChat(context, requestCancelOnOpen: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularMd),
        title: _confirmDialogTitle('Cancelar pedido de reserva?'),
        content: Text(
          'Queres cancelar este pedido? Deixas de aguardar resposta do vendedor '
          'e a encomenda fica anulada. Esta ação não pode ser desfeita.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.4,
            color: const Color(0xFF3D4A55),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Voltar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF57636C),
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FleaberColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Cancelar reserva',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    await _afterConfirmRun(
      confirm: confirm,
      okMessage: 'Pedido de reserva cancelado.',
      setBusyFlag: (b) {
        if (mounted) setState(() => _buyerCancelReservaBusy = b);
      },
      run: () async {
        print('BATATA_COMPRADOR_CANCEL_RESERVA start oid=$oid');
        await batataBuyerCancelReservaPendente(
          orderId: oid,
          sellerId: sid ?? '',
          productId: pid ?? '',
        );
      },
    );
  }

  Future<void> _onVendedorCancelarComConfirmacao(BuildContext context) async {
    final oid = widget.order.id;
    if (oid == null || oid.isEmpty || _sellerCancelBusy) return;
    if (widget.order.sellerId != currentUserUid) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularMd),
        title: _confirmDialogTitle('Anular venda?'),
        content: Text(
          'Tens a certeza que queres anular esta venda? A encomenda será '
          'cancelada, o comprador deixa de ficar vinculado a ela e esta ação '
          'não tem volta atrás.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.4,
            color: const Color(0xFF3D4A55),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Voltar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF57636C),
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kTealBatata,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: FleaberRadius.circularSm,
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Anular venda',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    final bid = widget.order.buyerId;
    final pid = widget.order.productId;

    await _afterConfirmRun(
      confirm: confirm,
      okMessage: 'Encomenda cancelada.',
      setBusyFlag: (b) {
        if (mounted) setState(() => _sellerCancelBusy = b);
      },
      run: () async {
        print('BATATA_VENDEDOR_ANULAR_VENDA start oid=$oid');
        final refundResult = await applyOrderCancelAndRelist(
          orderId: oid,
          sellerUserId: currentUserUid,
        );

        if (bid != null &&
            bid.isNotEmpty &&
            pid != null &&
            pid.isNotEmpty) {
          try {
            final chat = await ensureSellerChat(
              otherUserId: bid,
              productId: pid,
            );
            final cid = chat.id;
            if (cid != null && cid.isNotEmpty) {
              var text = 'O vendedor anulou a venda desta encomenda.';
              if (refundResult.stripeRefundAttempted &&
                  (refundResult.stripeRefundOk ||
                      refundResult.stripeRefundAlready)) {
                text =
                    'O vendedor anulou a venda. Reembolso Stripe iniciado para o '
                    'método de pagamento original.';
              } else if (refundResult.stripeRefundAttempted &&
                  (refundResult.stripeRefundError ?? '').isNotEmpty) {
                text =
                    'O vendedor anulou a venda. Reembolso automático falhou — '
                    'contacte geral@fleaber.pt com o ID da encomenda.';
              }
              await ChatMessagesTable().insert({
                'sender_id': currentUserUid,
                'receiver_id': bid,
                'is_read': false,
                'text': text,
                'chat_id': cid,
                'is_reservation': false,
              });
              await ChatsTable().update(
                data: {
                  'last_message': 'Venda anulada pelo vendedor',
                  'last_message_time':
                      DateTime.now().toUtc().toIso8601String(),
                },
                matchingRows: (rows) => rows.eqOrNull('id', cid),
              );
            }
          } catch (_) {}
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusVisual = _statusVisual();
    final title = widget.product == null
        ? 'Artigo removido'
        : _displayProductTitle(widget.product!.title);
    final url = _imageUrl();
    final showDuplicate =
        widget.isVendasTab && widget.order.sellerId == currentUserUid;
    final rowStatus = orderStatusRawFromData(widget.order.data);
    final rowStatusKey = normalizeOrderStatusKey(rowStatus);
    final isReservaPendente = rowStatusKey == 'reserva_pendente';
    final showCancelOnRow = !orderIsCancelled(rowStatus) &&
        orderAllowsBuyerCancelStatus(rowStatus) &&
        (widget.isVendasTab
            ? widget.order.sellerId == currentUserUid
            : widget.order.buyerId == currentUserUid);
    final showTrack = _canShowDpdTracking();
    final showAttachGuide =
        widget.isVendasTab && widget.order.sellerId == currentUserUid && showTrack;

    return Material(
      color: _kRowBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openChat(context),
                    splashColor:
                        const Color(0xFF007782).withValues(alpha: 0.08),
                    highlightColor:
                        const Color(0xFF007782).withValues(alpha: 0.04),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: FleaberRadius.circularSm,
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: url != null && url.isNotEmpty
                                      ? BatataCachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.cover,
                                          placeholderColor:
                                              const Color(0xFFF1F4F8),
                                          errorWidget: ColoredBox(
                                            color: const Color(0xFFF1F4F8),
                                            child: Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        )
                                      : ColoredBox(
                                          color: const Color(0xFFF1F4F8),
                                          child: Icon(
                                            Icons.inventory_2_outlined,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                ),
                                Positioned(
                                  right: 3,
                                  bottom: 3,
                                  child: _OrderStatusThumbBadge(
                                    color: statusVisual.color,
                                    icon: statusVisual.icon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FleaberTypography.listTitle(),
                              ),
                              if ((widget.order.bundleId ?? '').isNotEmpty &&
                                  widget.showBundleChip) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2F1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Conjunto',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: const Color(0xFF007782),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _priceLabel(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: const Color(0xFF007782),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusPhrase(),
                                style: FleaberTypography.orderStatus(
                                  statusVisual.color,
                                ),
                              ),
                              ...[
                                for (final line in orderBuyerDeliveryDetailLines(
                                  widget.order,
                                ).take(2)) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    line,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      height: 1.25,
                                      color: const Color(0xFF57636C),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showDuplicate ||
                    showCancelOnRow ||
                    showTrack ||
                    showAttachGuide)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF57636C)),
                    enabled: !(widget.isVendasTab && _sellerCancelBusy) &&
                        !(!widget.isVendasTab && _buyerCancelReservaBusy),
                    onSelected: (v) {
                      if (v == 'duplicate') _onVenderOutroIgual();
                      if (v == 'track') unawaited(_openDpdTracking());
                      if (v == 'attach_guide') {
                        unawaited(_sellerAttachDpdGuide());
                      }
                      if (v == 'cancel') {
                        if (widget.isVendasTab) {
                          _onVendedorCancelarComConfirmacao(context);
                        } else if (isReservaPendente) {
                          _onCompradorCancelarReservaPendenteComDialog(context);
                        } else {
                          _openChat(context, requestCancelOnOpen: true);
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (showTrack)
                        PopupMenuItem(
                          value: 'track',
                          height: 44,
                          child: Text(
                            'Seguimento DPD',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF101518),
                            ),
                          ),
                        ),
                      if (showAttachGuide)
                        PopupMenuItem(
                          value: 'attach_guide',
                          height: 44,
                          child: Text(
                            'Associar guia DPD',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF101518),
                            ),
                          ),
                        ),
                      if (showDuplicate)
                        PopupMenuItem(
                          value: 'duplicate',
                          height: 44,
                          child: Text(
                            'Vender outro igual',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF101518),
                            ),
                          ),
                        ),
                      if (showCancelOnRow)
                        PopupMenuItem(
                          value: 'cancel',
                          height: 44,
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFC62828),
                            ),
                          ),
                        ),
                    ],
                  ),
                Tooltip(
                  message: 'Abrir conversa',
                  child: InkWell(
                    onTap: () => _openChat(context),
                    borderRadius: BorderRadius.circular(20),
                    splashColor:
                        const Color(0xFF007782).withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: _kChevron,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            OrderPostPurchasePanel(
              order: widget.order,
              isSellerView: widget.isVendasTab,
              onChanged: widget.onOrdersChanged,
            ),
          ],
        ),
      ),
    );
  }
}
