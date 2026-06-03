import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/chat_session_util.dart';
import '/chat_page/chat_page_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_eligibility.dart';
import '/order_cancel_apply.dart';
import '/recolocar_ref_code.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_typography.dart';
import '/widgets/batata_cached_image.dart';

class MinhasEncomendasWidget extends StatefulWidget {
  const MinhasEncomendasWidget({super.key});

  static const String routeName = 'MinhasEncomendas';
  static const String routePath = '/minhasEncomendas';

  @override
  State<MinhasEncomendasWidget> createState() => _MinhasEncomendasWidgetState();
}

class _MinhasEncomendasWidgetState extends State<MinhasEncomendasWidget>
    with SingleTickerProviderStateMixin {
  static const Color _kTeal = Color(0xFF007782);

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kTeal,
          unselectedLabelColor: const Color(0xFF57636C),
          indicatorColor: _kTeal,
          tabs: const [
            Tab(text: 'Vendido'),
            Tab(text: 'Comprado'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OrdersListTab(
            key: ValueKey<String>('encomendas_vendido_seller_id'),
            isVendasTab: true,
          ),
          _OrdersListTab(
            key: ValueKey<String>('encomendas_comprado_buyer_id'),
            isVendasTab: false,
          ),
        ],
      ),
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
  });

  /// `true` → só encomendas em que sou **vendedor** (`seller_id`).
  /// `false` → só encomendas em que sou **comprador** (`buyer_id`).
  final bool isVendasTab;

  @override
  State<_OrdersListTab> createState() => _OrdersListTabState();
}

class _OrdersListTabState extends State<_OrdersListTab>
    with AutomaticKeepAliveClientMixin, RouteAware, WidgetsBindingObserver {
  Future<_TabOrdersPayload>? _payloadFuture;

  /// Força novo estado no [FutureBuilder] após recargas (evita snapshot antigo).
  int _payloadEpoch = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersRealtimeSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _payloadFuture = _loadPayload();
    _subscribeOrdersRealtime();
    ordersListRefreshTick.addListener(_onOrdersListRefreshTick);
  }

  void _onOrdersListRefreshTick() {
    if (!mounted) return;
    _reloadPayload();
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
              if (mounted) _reloadPayload();
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
    ordersListRefreshTick.removeListener(_onOrdersListRefreshTick);
    _ordersRealtimeSub?.cancel();
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

  Future<void> _reloadPayload() async {
    if (!mounted) return;
    setState(() {
      _payloadEpoch++;
      _payloadFuture = _loadPayload();
    });
    await _payloadFuture;
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
    if (currentUserUid.isEmpty) {
      return Center(
        child: Text(
          'Inicia sessão para veres as encomendas.',
          style: GoogleFonts.inter(color: const Color(0xFF57636C)),
        ),
      );
    }

    return FutureBuilder<_TabOrdersPayload>(
      key: ValueKey<int>(_payloadEpoch),
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

        return RefreshIndicator(
          color: const Color(0xFF007782),
          onRefresh: _reloadPayload,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              thickness: 0.5,
              color: Color(0xFFD9DEE3),
            ),
            itemBuilder: (context, index) {
              final order = orders[index];
              final product =
                  order.productId != null ? products[order.productId!] : null;
              return _OrderRowTile(
                key: ValueKey<String>(
                  '${order.id ?? index}_${widget.isVendasTab}',
                ),
                order: order,
                product: product,
                isVendasTab: widget.isVendasTab,
                onOrdersChanged: _reloadPayload,
                onSnackBar: (message, {bool error = false}) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                },
              );
            },
          ),
        );
      },
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
  });

  final OrdersRow order;
  final ProductsRow? product;
  final bool isVendasTab;

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
      requestOrdersListRefresh();
      pingBatataReservationForNotificationBell();
      onChanged?.call();
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
    final raw = orderStatusRawFromData(widget.order.data).trim();
    if (orderIsCancelled(raw)) return 'Cancelado';
    final st = normalizeOrderStatusKey(raw);

    // Prioridade explícita: cancelado > reserva > pago > enviado > restantes
    switch (st) {
      case 'reserva_pendente':
        return 'Pedido de Reserva';
      case 'reservado':
        return 'Reservado (Aguardando Pagamento)';
      case 'pendente':
        return 'Pagamento pendente';
      case 'aguarda_confirmacao':
        return 'Pagamento em Verificação';
      case 'pago':
        return 'Pago';
      case 'enviado':
        return 'Artigo Enviado';
      case 'concluido':
        return 'Concluída';
      case 'pedido_devolucao':
        return 'Pedido de Devolução';
      case 'em_devolucao':
        return 'Em Devolução';
      case 'devolvida':
        return 'Devolvida / Reembolsada';
      default:
        return raw.isNotEmpty ? raw : '—';
    }
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
      final chat = await ensureSellerChat(
        otherUserId: other,
        productId: pid,
      );
      if (!context.mounted) return;
      context.pushNamed(
        ChatPageWidget.routeName,
        queryParameters: <String, String?>{
          'chatId': serializeParam(chat.id, ParamType.String),
          'otherUserId': serializeParam(other, ParamType.String),
          if (requestCancelOnOpen)
            'requestCancelOnOpen': serializeParam(true, ParamType.bool),
        }.withoutNulls,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o chat.')),
      );
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
        await applyOrderCancelAndRelist(
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
              await ChatMessagesTable().insert({
                'sender_id': currentUserUid,
                'receiver_id': bid,
                'is_read': false,
                'text': 'O vendedor anulou a venda desta encomenda.',
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
    final title = widget.product?.title ?? 'Artigo removido';
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

    return Material(
      color: _kRowBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openChat(context),
                splashColor: const Color(0xFF007782).withValues(alpha: 0.08),
                highlightColor: const Color(0xFF007782).withValues(alpha: 0.04),
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
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: FleaberTypography.listTitle(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _priceLabel(),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showDuplicate) ...[
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFF007782),
                ),
                onPressed: _duplicateBusy ? null : _onVenderOutroIgual,
                child: _duplicateBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF007782),
                        ),
                      )
                    : Text(
                        'Vender outro igual',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.15,
                        ),
                      ),
              ),
              const SizedBox(width: 2),
            ],
            if (showCancelOnRow) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 2),
                child: OutlinedButton(
                  onPressed: (widget.isVendasTab && _sellerCancelBusy) ||
                          (!widget.isVendasTab && _buyerCancelReservaBusy)
                      ? null
                      : () {
                          if (widget.isVendasTab) {
                            _onVendedorCancelarComConfirmacao(context);
                          } else if (isReservaPendente) {
                            _onCompradorCancelarReservaPendenteComDialog(
                              context,
                            );
                          } else {
                            _openChat(
                              context,
                              requestCancelOnOpen: true,
                            );
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTealBatata,
                    side: const BorderSide(
                      color: _kTealBatata,
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: FleaberRadius.circularSm,
                    ),
                  ),
                  child: (widget.isVendasTab && _sellerCancelBusy) ||
                          (!widget.isVendasTab && _buyerCancelReservaBusy)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kTealBatata,
                          ),
                        )
                      : Text(
                          'Cancelar',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            height: 1.15,
                          ),
                        ),
                ),
              ),
            ],
            InkWell(
              onTap: () => _openChat(context),
              splashColor: const Color(0xFF007782).withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.only(left: 2, top: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: _kChevron,
                  size: 26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
