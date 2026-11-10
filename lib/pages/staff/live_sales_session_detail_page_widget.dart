import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/order_cancel_eligibility.dart';
import '/product_details/product_details_page_widget.dart';
import '/utils/fleaber_commercial_display.dart';
import '/utils/fleaber_h10_navigation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_session_results_service.dart';
import '/utils/seller_staff_permissions.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/seller_staff_gate.dart';

class LiveSalesSessionDetailPageWidget extends StatefulWidget {
  const LiveSalesSessionDetailPageWidget({
    super.key,
    this.liveId,
    this.embedded = false,
    this.onBack,
  });

  static String routeName = 'LiveSalesSessionDetail';
  static String routePath = '/resultadosLive';

  final String? liveId;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<LiveSalesSessionDetailPageWidget> createState() =>
      _LiveSalesSessionDetailPageWidgetState();
}

class _LiveSalesSessionDetailPageWidgetState
    extends State<LiveSalesSessionDetailPageWidget>
    with SingleTickerProviderStateMixin {
  static const Color _kTeal = Color(0xFF007782);

  late TabController _tabController;
  bool _loading = true;
  LiveSessionDetailPayload? _payload;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LiveSalesSessionDetailPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveId != widget.liveId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final liveId = widget.liveId?.trim() ?? '';
      if (liveId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Sessão inválida.';
        });
        return;
      }
      final payload = await LiveSessionResultsService.detailForLive(
        liveId: liveId,
        sellerId: effectiveSellerId,
      );
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
        _error = payload == null ? 'Sessão não encontrada.' : null;
      });
      if (payload != null &&
          payload.sales.isEmpty &&
          payload.reservations.isNotEmpty &&
          mounted) {
        _tabController.index = 1;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o resumo.';
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatSessionDate(LivesRow live) {
    final at = live.createdAt?.toLocal();
    if (at == null) return '—';
    final d = DateFormat('dd/MM/yyyy').format(at);
    final t = DateFormat('HH:mm').format(at);
    return '$d · $t';
  }

  String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return '${NumberFormat('#,##0', 'pt_PT').format(value.toInt())}€';
    }
    return '${NumberFormat('#,##0.00', 'pt_PT').format(value).replaceAll('.', ',')}€';
  }

  String _formatDateTime(DateTime? at) {
    if (at == null) return '—';
    final local = at.toLocal();
    return '${DateFormat('dd/MM/yyyy').format(local)} '
        '${DateFormat('HH:mm').format(local)}';
  }

  Future<void> _openOrderChat({
    required String buyerId,
    required String? productId,
    String? orderId,
  }) async {
    final pid = productId?.trim() ?? '';
    final bid = buyerId.trim();
    if (bid.isEmpty || pid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem encomenda associada para abrir.')),
      );
      return;
    }
    try {
      await openH10Conversation(
        context,
        otherUserId: bid,
        productId: pid,
        orderId: (orderId ?? '').trim().isEmpty ? null : orderId!.trim(),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a conversa.')),
      );
    }
  }

  Future<void> _openProduct(String? productId) async {
    final pid = (productId ?? '').trim();
    if (pid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artigo sem ficha associada.')),
      );
      return;
    }
    final cached = _payload?.productsById[pid];
    if (cached != null) {
      await context.push(
        ProductDetailsPageWidget.routePath,
        extra: ProductDetailsPageWidget.routeExtraForProduct(cached),
      );
      return;
    }
    await context.push(
      '${ProductDetailsPageWidget.routePath}?product_id=${Uri.encodeComponent(pid)}',
    );
  }

  Future<void> _onActivityTap(LiveSessionActivityEntry e) async {
    switch (e.kind) {
      case LiveSessionActivityKind.purchase:
      case LiveSessionActivityKind.reservation:
      case LiveSessionActivityKind.message:
        final bid = (e.buyerId ?? '').trim();
        final pid = (e.productId ?? '').trim();
        if (bid.isEmpty || pid.isEmpty) return;
        await _openOrderChat(
          buyerId: bid,
          productId: pid,
          orderId: e.orderId,
        );
        break;
      case LiveSessionActivityKind.article:
        await _openProduct(e.productId);
        break;
      case LiveSessionActivityKind.info:
        break;
    }
  }

  PreferredSizeWidget _tabBar() {
    final emb = widget.embedded;
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      labelColor: _kTeal,
      unselectedLabelColor: FleaberColors.muted,
      indicatorColor: _kTeal,
      indicatorWeight: emb ? 3 : 2,
      labelStyle: GoogleFonts.inter(
        fontSize: emb ? 14.5 : 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
      ),
      unselectedLabelStyle: GoogleFonts.inter(
        fontSize: emb ? 14 : 14.5,
        fontWeight: FontWeight.w600,
      ),
      labelPadding: EdgeInsets.symmetric(horizontal: emb ? 12 : 14),
      tabAlignment: TabAlignment.start,
      tabs: const [
        Tab(text: 'Vendas'),
        Tab(text: 'Reservas'),
        Tab(text: 'Pagamentos'),
        Tab(text: 'Artigos'),
        Tab(text: 'Atividade'),
        Tab(text: 'Estatísticas'),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.inter(
            fontSize: FleaHubSiteLayout.typeBody,
            color: FleaberColors.muted,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: TabBarView(
        controller: _tabController,
        children: [
          _salesTab(),
          _reservationsTab(),
          _paymentsTab(),
          _articlesTab(),
          _activityTab(),
          _statsTab(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_payload?.live.title ?? '').trim().isNotEmpty
        ? _payload!.live.title!.trim()
        : 'Resumo do directo';

    if (widget.embedded) {
      return SellerStaffGate(
        permission: SellerStaffPermissions.canManageReservations,
        child: ColoredBox(
          color: FleaberColors.bgTint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Voltar à lista',
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: FleaberColors.teal,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: FleaberColors.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: FleaHubSiteLayout.typeSection,
                                  ),
                                ),
                                if (_payload != null)
                                  Text(
                                    _formatSessionDate(_payload!.live),
                                    style: GoogleFonts.inter(
                                      color: FleaberColors.muted,
                                      fontSize:
                                          FleaHubSiteLayout.typeSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _tabBar(),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      );
    }

    return SellerStaffGate(
      permission: SellerStaffPermissions.canManageReservations,
      child: Scaffold(
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: FleaberColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeSection,
                ),
              ),
              if (_payload != null)
                Text(
                  _formatSessionDate(_payload!.live),
                  style: GoogleFonts.inter(
                    color: FleaberColors.muted,
                    fontSize: FleaHubSiteLayout.typeSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          bottom: _tabBar(),
        ),
        body: _body(),
      ),
    );
  }

  Widget _salesTab() {
    final sales = _payload?.sales ?? const [];
    final pending = (_payload?.reservations ?? const [])
        .where((r) => r.status == 'pending' || r.status == 'accepted')
        .length;
    if (sales.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard(
            pending > 0
                ? 'Ainda não há vendas concluídas nesta sessão.\n'
                    'Tens $pending reserva(s) pendente(s) — vê o separador Reservas.'
                : 'Ainda não há vendas registadas nesta sessão.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: sales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _saleCard(sales[i]),
    );
  }

  Widget _saleCard(LiveSessionSaleRow row) {
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row.buyerLabel,
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: FleaHubSiteLayout.typeBody),
          ),
          const SizedBox(height: 4),
          Text(
            row.articleLabel,
            style: GoogleFonts.inter(
              fontSize: FleaHubSiteLayout.typeSecondary,
              color: const Color(0xFF57636C),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _formatMoney(row.amountEur),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: _kTeal,
                  fontSize: FleaHubSiteLayout.typeBody,
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(row.statusLabel),
              const Spacer(),
              Text(
                _formatDateTime(row.at),
                style: GoogleFonts.inter(
                  fontSize: FleaHubSiteLayout.typeCaption,
                  color: const Color(0xFF57636C),
                ),
              ),
            ],
          ),
          if (row.orderId != null || row.productId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _openOrderChat(
                  buyerId: row.buyerId,
                  productId: row.productId,
                  orderId: row.orderId,
                ),
                child: const Text('Abrir conversa'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reservationsTab() {
    final reqs = _payload?.reservations ?? const [];
    // Pendentes / aceites abertas — nunca esconder PS/Facebook por filtro de source.
    final open = reqs
        .where((r) => r.status == 'pending' || r.status == 'accepted')
        .toList();
    final bag = open.where((r) => r.source == 'fleaber_live').toList();
    final fbPending = open
        .where(
          (r) =>
              r.source == 'facebook_manual' || r.source == 'helper_manual',
        )
        .toList();
    final shownIds = {...bag.map((r) => r.id), ...fbPending.map((r) => r.id)};
    final otherOpen =
        open.where((r) => !shownIds.contains(r.id)).toList();
    final expired = reqs.where((r) => r.status == 'expired').toList();
    final converted = reqs.where((r) => r.status == 'converted').toList();

    if (bag.isEmpty &&
        fbPending.isEmpty &&
        otherOpen.isEmpty &&
        expired.isEmpty &&
        converted.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Ainda não há reservas nesta sessão.'),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _reservationSection('Reservas do saco', bag),
        _reservationSection('Reservas Facebook / PS', fbPending),
        _reservationSection('Outras reservas', otherOpen),
        _reservationSection('Reservas expiradas', expired),
        _reservationSection('Convertidas em compra', converted),
      ],
    );
  }

  Widget _reservationSection(String title, List<LiveReservationRequestsRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _whiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$title (${rows.length})',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: FleaHubSiteLayout.typeBody),
            ),
            const SizedBox(height: 8),
            for (final r in rows) ...[
              _reservationRow(r),
              if (r != rows.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reservationRow(LiveReservationRequestsRow r) {
    final buyer = LiveSessionResultsService.reservationBuyerLabel(
      r,
      _payload?.buyerNames ?? const {},
    );
    final item = _payload?.itemsById[(r.liveItemId ?? '').trim()];
    final articleName = item == null
        ? 'Artigo'
        : fleaberCommercialTitle(
            (item.title ?? '').trim().isNotEmpty
                ? item.title
                : LiveVendorRefDisplay.refLabel(item.refCode),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          buyer,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$articleName · ${r.requestedQty} un. · '
          '${LiveVendorSellerCopy.reservationStatus(r.status, requestKind: r.requestKind)} · '
          '${LiveVendorSellerCopy.reservationSource(r.source)}',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF57636C),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _formatDateTime(r.updatedAt ?? r.createdAt),
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: const Color(0xFF8A96A0),
          ),
        ),
        if ((r.buyerId ?? '').isNotEmpty &&
            (item?.checkoutProductIdOrPrimary ?? item?.productId) != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _openOrderChat(
                buyerId: r.buyerId!,
                productId: item!.checkoutProductIdOrPrimary ?? item.productId,
              ),
              child: const Text('Abrir conversa'),
            ),
          ),
      ],
    );
  }

  Widget _paymentsTab() {
    final reqs = _payload?.reservations ?? const [];
    final orders = _payload?.orders ?? const [];

    final paidReqs = reqs.where((r) => r.status == 'converted').toList();
    final pendingReqs =
        reqs.where((r) => r.status == 'pending' || r.status == 'accepted').toList();
    final external = pendingReqs
        .where((r) => r.source == 'facebook_manual' || r.source == 'helper_manual')
        .toList();
    final externalIds = external.map((r) => r.id).toSet();
    final inAppPending = pendingReqs
        .where((r) => !externalIds.contains(r.id))
        .toList();
    final soon = pendingReqs.where((r) {
      if (externalIds.contains(r.id)) return false;
      final exp = r.expiresAt;
      if (exp == null) return false;
      return exp.difference(DateTime.now()).inHours <= 48;
    }).toList();
    final soonIds = soon.map((r) => r.id).toSet();
    final pendingNotSoon = inAppPending
        .where((r) => !soonIds.contains(r.id))
        .toList();

    final paidOrders = orders.where((o) {
      final k = normalizeOrderStatusKey(o.status);
      return k == 'pago' || k == 'enviado' || k == 'concluido';
    }).toList();
    final pendingOrders = orders.where((o) {
      final k = normalizeOrderStatusKey(o.status);
      return k == 'pendente' ||
          k == 'reserva_pendente' ||
          k == 'reservado' ||
          k == 'aguarda_confirmacao';
    }).toList();

    // Dedupe encomendas por live_item|buyer (evita 2 linhas do mesmo bot).
    final pendingOrdersByKey = <String, OrdersRow>{};
    for (final o in pendingOrders) {
      final iid = (o.liveItemId ?? '').trim();
      final bid = (o.buyerId ?? '').trim();
      final key = (iid.isNotEmpty && bid.isNotEmpty)
          ? '$iid|$bid'
          : 'order:${o.id?.trim() ?? ''}';
      if (key == 'order:') continue;
      final prev = pendingOrdersByKey[key];
      if (prev == null) {
        pendingOrdersByKey[key] = o;
      } else {
        final ta = o.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = prev.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (ta.isAfter(tb)) pendingOrdersByKey[key] = o;
      }
    }
    final pendingOrdersDeduped = pendingOrdersByKey.values.toList();
    final coveredByOrder = pendingOrdersByKey.keys
        .where((k) => !k.startsWith('order:'))
        .toSet();

    // Reservas só se ainda não houver encomenda pendente do mesmo par.
    final pendingReqsOnly = pendingNotSoon.where((r) {
      final iid = (r.liveItemId ?? '').trim();
      final bid = (r.buyerId ?? '').trim();
      if (iid.isEmpty || bid.isEmpty) return true;
      return !coveredByOrder.contains('$iid|$bid');
    }).toList();

    final paidOrdersDeduped = <String, OrdersRow>{};
    for (final o in paidOrders) {
      final iid = (o.liveItemId ?? '').trim();
      final bid = (o.buyerId ?? '').trim();
      final key = (iid.isNotEmpty && bid.isNotEmpty)
          ? '$iid|$bid'
          : 'order:${o.id?.trim() ?? ''}';
      if (key == 'order:') continue;
      paidOrdersDeduped.putIfAbsent(key, () => o);
    }
    final paidCovered = paidOrdersDeduped.keys
        .where((k) => !k.startsWith('order:'))
        .toSet();
    final paidReqsOnly = paidReqs.where((r) {
      final iid = (r.liveItemId ?? '').trim();
      final bid = (r.buyerId ?? '').trim();
      if (iid.isEmpty || bid.isEmpty) return true;
      return !paidCovered.contains('$iid|$bid');
    }).toList();

    // «Expirações» sem duplicar quem já está em Pendentes via encomenda.
    final soonOnly = soon.where((r) {
      final iid = (r.liveItemId ?? '').trim();
      final bid = (r.buyerId ?? '').trim();
      if (iid.isEmpty || bid.isEmpty) return true;
      return !coveredByOrder.contains('$iid|$bid');
    }).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _paymentSection('Pagos', [
          ...paidReqsOnly.map((r) => _PaymentLine.fromReservation(r, _payload!)),
          ...paidOrdersDeduped.values
              .map((o) => _PaymentLine.fromOrder(o, _payload!)),
        ]),
        _paymentSection('Pendentes', [
          ...pendingReqsOnly
              .map((r) => _PaymentLine.fromReservation(r, _payload!)),
          ...pendingOrdersDeduped
              .map((o) => _PaymentLine.fromOrder(o, _payload!)),
        ]),
        _paymentSection(
          'Pagamento externo',
          external.map((r) => _PaymentLine.fromReservation(r, _payload!)).toList(),
        ),
        _paymentSection(
          'Expirações próximas (48h)',
          soonOnly.map((r) => _PaymentLine.fromReservation(r, _payload!)).toList(),
        ),
      ],
    );
  }

  Widget _paymentSection(String title, List<_PaymentLine> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _whiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$title (${lines.length})',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: FleaHubSiteLayout.typeBody),
            ),
            const SizedBox(height: 8),
            for (final line in lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.label,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: FleaHubSiteLayout.typeSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${line.subtitle} · ${_formatMoney(line.amount)}',
                          style: GoogleFonts.inter(
                            fontSize: FleaHubSiteLayout.typeSecondary,
                            color: const Color(0xFF57636C),
                          ),
                        ),
                        Text(
                          _formatDateTime(line.at),
                          style: GoogleFonts.inter(
                            fontSize: FleaHubSiteLayout.typeCaption,
                            color: const Color(0xFF8A96A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (line.buyerId != null && line.productId != null)
                    TextButton(
                      onPressed: () => _openOrderChat(
                        buyerId: line.buyerId!,
                        productId: line.productId,
                        orderId: line.orderId,
                      ),
                      child: Text(line.openLabel),
                    ),
                ],
              ),
              if (line != lines.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _articlesTab() {
    final articles = _payload?.articles ?? const [];
    if (articles.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Sem artigos no catálogo desta sessão.'),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = articles[i];
        final itemTitle = fleaberCommercialTitle(a.liveItem.title);
        final displayTitle = itemTitle != 'Artigo' && itemTitle.isNotEmpty
            ? itemTitle
            : fleaberCommercialTitle(a.refLabel);
        final photo = (a.liveItem.photoUrl ?? '').trim();
        final productId =
            a.liveItem.checkoutProductIdOrPrimary ?? a.liveItem.productId;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: FleaberRadius.circularMd,
            onTap: () => _openProduct(productId),
            child: _whiteCard(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: photo.isNotEmpty
                          ? Image.network(
                              photo,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: FleaberColors.bgTint,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: FleaberColors.muted,
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: FleaberColors.bgTint,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: FleaberColors.muted,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: FleaberColors.text,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _qtyPill('Inicial', '${a.initialQty}'),
                            _qtyPill('Vendidos', '${a.soldQty}'),
                            _qtyPill('Reservas', '${a.reservedQty}'),
                            _qtyPill('Disponível', '${a.availableQty}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'Receita ${_formatMoney(a.revenueEur)}',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: _kTeal,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: FleaberColors.muted,
                              size: 22,
                            ),
                          ],
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
  }

  Widget _activityTab() {
    final events = _payload?.activity ?? const [];
    if (events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Sem actividade registada para esta sessão.'),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = events[i];
        final navigable = e.isNavigable;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: FleaberRadius.circularMd,
            onTap: navigable ? () => _onActivityTap(e) : null,
            child: _whiteCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fleaberCommercialLine(
                            liveSessionSafeDisplayText(e.message),
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF101518),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.at == null
                              ? '—'
                              : DateFormat('dd/MM/yyyy · HH:mm')
                                  .format(e.at!.toLocal()),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF8A96A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (navigable)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: FleaberColors.muted,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statsTab() {
    final s = _payload?.stats;
    if (s == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Sem estatísticas disponíveis.'),
        ],
      );
    }

    String hourLabel(int? hour) =>
        hour == null ? '—' : '${hour.toString().padLeft(2, '0')}:00';

    final pct = (s.reservationConversionRate * 100).toStringAsFixed(0);
    final highlight = <(String, String)>[
      ('Receita', _formatMoney(s.totalRevenueEur)),
      ('Vendidos', '${s.articlesSold}'),
      ('Conversão', '$pct%'),
      ('Compradores', '${s.uniqueBuyers}'),
    ];
    final rest = <(String, String)>[
      ('Ticket médio', _formatMoney(s.avgTicketEur)),
      ('Mais vendido', fleaberCommercialLine(s.topSoldRef ?? '—')),
      ('Mais reservado', fleaberCommercialLine(s.topReservedRef ?? '—')),
      ('Pico vendas', hourLabel(s.peakSalesHour)),
      ('Pico actividade', hourLabel(s.peakActivityHour)),
      ('Compradores repetidos', '${s.repeatBuyers}'),
      ('Esgotados', '${s.soldOutCount}'),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 720
                ? 4
                : (constraints.maxWidth >= 420 ? 2 : 2);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cols == 4 ? 2.35 : 2.1,
              children: [
                for (final e in highlight) _statTile(e.$1, e.$2),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _whiteCard(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              for (var i = 0; i < rest.length; i++) ...[
                _statRow(rest[i].$1, rest[i].$2),
                if (i != rest.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFE3EBEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _kTeal,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FleaberColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3EBEE)),
      ),
      child: Text(
        '$label $value',
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: FleaberColors.text,
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: FleaberColors.muted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              fleaberCommercialTitle(value),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: FleaberColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: FleaHubSiteLayout.typeCaption, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _whiteCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ??
          EdgeInsets.all(widget.embedded ? 16 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: widget.embedded
            ? Border.all(color: FleaberColors.alternate)
            : null,
      ),
      child: child,
    );
  }

  Widget _emptyCard(String message) {
    return _whiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: const Color(0xFF57636C),
          fontSize: FleaHubSiteLayout.typeBody,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}

class _PaymentLine {
  _PaymentLine({
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.at,
    this.buyerId,
    this.productId,
    this.orderId,
    this.openLabel = 'Abrir conversa',
  });

  final String label;
  final String subtitle;
  final double amount;
  final DateTime? at;
  final String? buyerId;
  final String? productId;
  final String? orderId;
  final String openLabel;

  factory _PaymentLine.fromReservation(
    LiveReservationRequestsRow r,
    LiveSessionDetailPayload payload,
  ) {
    final buyer = LiveSessionResultsService.reservationBuyerLabel(
      r,
      payload.buyerNames,
    );
    final item = payload.itemsById[(r.liveItemId ?? '').trim()];
    final article = item == null
        ? 'Artigo'
        : fleaberCommercialTitle(
            (item.title ?? '').trim().isNotEmpty
                ? item.title
                : LiveVendorRefDisplay.refLabel(item.refCode),
          );
    final unit = item?.price ?? 0;
    final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
    return _PaymentLine(
      label: buyer,
      subtitle:
          '$article · ${LiveVendorSellerCopy.reservationStatus(r.status, requestKind: r.requestKind)}',
      amount: unit * qty,
      at: r.updatedAt ?? r.createdAt,
      buyerId: r.buyerId,
      productId: item?.checkoutProductIdOrPrimary ?? item?.productId,
      openLabel: 'Abrir conversa',
    );
  }

  factory _PaymentLine.fromOrder(
    OrdersRow o,
    LiveSessionDetailPayload payload,
  ) {
    final buyer = payload.buyerNames[(o.buyerId ?? '').trim()] ?? 'Cliente';
    final product = payload.productsById[o.productId ?? ''];
    return _PaymentLine(
      label: buyer,
      subtitle: fleaberCommercialTitle(product?.title),
      amount: o.priceTotal ?? 0,
      at: o.createdAt,
      buyerId: o.buyerId,
      productId: o.productId,
      orderId: o.id,
      openLabel: 'Abrir conversa',
    );
  }
}

extension _LiveItemCheckout on LiveItemsRow {
  String? get checkoutProductIdOrPrimary =>
      isMarketplaceProduct ? productId : (checkoutProductId ?? productId);
}
