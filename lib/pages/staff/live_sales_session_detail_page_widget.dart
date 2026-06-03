import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/chat_session_util.dart';
import '/chat_page/chat_page_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_session_results_service.dart';
import '/utils/seller_staff_permissions.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/seller_staff_gate.dart';

class LiveSalesSessionDetailPageWidget extends StatefulWidget {
  const LiveSalesSessionDetailPageWidget({super.key, this.liveId});

  static String routeName = 'LiveSalesSessionDetail';
  static String routePath = '/resultadosLive';

  final String? liveId;

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
  }) async {
    final pid = productId?.trim() ?? '';
    if (buyerId.trim().isEmpty || pid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem encomenda associada para abrir.')),
      );
      return;
    }
    try {
      final chat = await ensureSellerChat(
        otherUserId: buyerId.trim(),
        productId: pid,
      );
      if (!mounted) return;
      context.pushNamed(
        ChatPageWidget.routeName,
        queryParameters: <String, String?>{
          'chatId': serializeParam(chat.id, ParamType.String),
          'otherUserId': serializeParam(buyerId.trim(), ParamType.String),
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a encomenda.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SellerStaffGate(
      permission: SellerStaffPermissions.canManageReservations,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_payload?.live.title ?? '').trim().isNotEmpty
                    ? _payload!.live.title!.trim()
                    : 'Resumo do directo',
                style: GoogleFonts.inter(
                  color: const Color(0xFF101518),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (_payload != null)
                Text(
                  _formatSessionDate(_payload!.live),
                  style: GoogleFonts.inter(
                    color: const Color(0xFF57636C),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: _kTeal,
            unselectedLabelColor: const Color(0xFF57636C),
            indicatorColor: _kTeal,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Vendas'),
              Tab(text: 'Reservas'),
              Tab(text: 'Pagamentos'),
              Tab(text: 'Artigos'),
              Tab(text: 'Atividade'),
              Tab(text: 'Estatísticas'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: const Color(0xFF57636C)),
                    ),
                  )
                : RefreshIndicator(
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
                  ),
      ),
    );
  }

  Widget _salesTab() {
    final sales = _payload?.sales ?? const [];
    if (sales.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Ainda não há vendas registadas nesta sessão.'),
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
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            row.articleLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
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
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(row.statusLabel),
              const Spacer(),
              Text(
                _formatDateTime(row.at),
                style: GoogleFonts.inter(
                  fontSize: 10,
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
                ),
                child: const Text('Abrir encomenda'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reservationsTab() {
    final reqs = _payload?.reservations ?? const [];
    final bag = reqs.where((r) => r.status == 'pending' && r.source == 'fleaber_live').toList();
    final accepted = reqs.where((r) => r.status == 'accepted').toList();
    final expired = reqs.where((r) => r.status == 'expired').toList();
    final converted = reqs.where((r) => r.status == 'converted').toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _reservationSection('Reservas do saco', bag),
        _reservationSection('Reservas aceites', accepted),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
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
    final buyer = _payload?.buyerNames[(r.buyerId ?? '').trim()] ?? 'Cliente';
    final item = _payload?.itemsById[(r.liveItemId ?? '').trim()];
    final ref = item == null
        ? '—'
        : LiveVendorRefDisplay.refLabel(item.refCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          buyer,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '$ref · Qty ${r.requestedQty} · '
          '${LiveVendorSellerCopy.reservationStatus(r.status)} · '
          '${LiveVendorSellerCopy.reservationSource(r.source)}',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF57636C)),
        ),
        Text(
          _formatDateTime(r.updatedAt ?? r.createdAt),
          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF8A96A0)),
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
              child: const Text('Abrir reserva'),
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
    final soon = pendingReqs.where((r) {
      final exp = r.expiresAt;
      if (exp == null) return false;
      return exp.difference(DateTime.now()).inHours <= 48;
    }).toList();

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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _paymentSection('Pagos', [
          ...paidReqs.map((r) => _PaymentLine.fromReservation(r, _payload!)),
          ...paidOrders.map((o) => _PaymentLine.fromOrder(o, _payload!)),
        ]),
        _paymentSection('Pendentes', [
          ...pendingReqs.map((r) => _PaymentLine.fromReservation(r, _payload!)),
          ...pendingOrders.map((o) => _PaymentLine.fromOrder(o, _payload!)),
        ]),
        _paymentSection(
          'Pagamento externo',
          external.map((r) => _PaymentLine.fromReservation(r, _payload!)).toList(),
        ),
        _paymentSection(
          'Expirações próximas (48h)',
          soon.map((r) => _PaymentLine.fromReservation(r, _payload!)).toList(),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
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
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${line.subtitle} · ${_formatMoney(line.amount)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF57636C),
                          ),
                        ),
                        Text(
                          _formatDateTime(line.at),
                          style: GoogleFonts.inter(
                            fontSize: 10,
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
        return _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.refLabel,
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _metricLine('Quantidade inicial', '${a.initialQty}'),
              _metricLine('Vendidos', '${a.soldQty}'),
              _metricLine('Reservas', '${a.reservedQty}'),
              _metricLine('Disponível', '${a.availableQty}'),
              const SizedBox(height: 6),
              Text(
                'Receita: ${_formatMoney(a.revenueEur)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: _kTeal,
                  fontSize: 13,
                ),
              ),
            ],
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
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final e = events[i];
        return _whiteCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  liveSessionSafeDisplayText(e.message),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF101518),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                e.at == null
                    ? '—'
                    : DateFormat('HH:mm').format(e.at!.toLocal()),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFF8A96A0),
                ),
              ),
            ],
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statRow('Receita total', _formatMoney(s.totalRevenueEur)),
              _statRow('Artigos vendidos', '${s.articlesSold}'),
              _statRow('Ticket médio', _formatMoney(s.avgTicketEur)),
              _statRow('Artigo mais vendido', s.topSoldRef ?? '—'),
              _statRow('Artigo mais reservado', s.topReservedRef ?? '—'),
              _statRow('Hora com mais vendas', hourLabel(s.peakSalesHour)),
              _statRow('Hora com mais actividade', hourLabel(s.peakActivityHour)),
              _statRow('Compradores únicos', '${s.uniqueBuyers}'),
              _statRow('Compradores repetidos', '${s.repeatBuyers}'),
              _statRow('Conversão reserva → compra', '$pct%'),
              _statRow('Artigos esgotados', '${s.soldOutCount}'),
            ],
          ),
        ),
      ],
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
                fontSize: 12,
                color: const Color(0xFF57636C),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF101518),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF3D4A55)),
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
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _whiteCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
      ),
      child: child,
    );
  }

  Widget _emptyCard(String message) {
    return _whiteCard(
      child: Text(
        message,
        style: GoogleFonts.inter(color: const Color(0xFF57636C), fontSize: 12),
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
    this.openLabel = 'Abrir',
  });

  final String label;
  final String subtitle;
  final double amount;
  final DateTime? at;
  final String? buyerId;
  final String? productId;
  final String openLabel;

  factory _PaymentLine.fromReservation(
    LiveReservationRequestsRow r,
    LiveSessionDetailPayload payload,
  ) {
    final buyer = payload.buyerNames[(r.buyerId ?? '').trim()] ?? 'Cliente';
    final item = payload.itemsById[(r.liveItemId ?? '').trim()];
    final ref = item == null
        ? '—'
        : LiveVendorRefDisplay.refLabel(item.refCode);
    final unit = item?.price ?? 0;
    final qty = r.requestedQty < 1 ? 1 : r.requestedQty;
    return _PaymentLine(
      label: buyer,
      subtitle: '$ref · ${LiveVendorSellerCopy.reservationStatus(r.status)}',
      amount: unit * qty,
      at: r.updatedAt ?? r.createdAt,
      buyerId: r.buyerId,
      productId: item?.checkoutProductIdOrPrimary ?? item?.productId,
      openLabel: r.status == 'converted' ? 'Abrir encomenda' : 'Abrir reserva',
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
      subtitle: product?.title ?? 'Artigo',
      amount: o.priceTotal ?? 0,
      at: o.createdAt,
      buyerId: o.buyerId,
      productId: o.productId,
      openLabel: 'Abrir encomenda',
    );
  }
}

extension _LiveItemCheckout on LiveItemsRow {
  String? get checkoutProductIdOrPrimary =>
      isMarketplaceProduct ? productId : (checkoutProductId ?? productId);
}
