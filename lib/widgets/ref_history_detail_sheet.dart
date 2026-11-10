import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/chat_page/chat_page_widget.dart';
import '/chat_session_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:collection/collection.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/ref_history_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/ref_history_close_dialog.dart';

class RefHistoryDetailSheet extends StatefulWidget {
  const RefHistoryDetailSheet({
    super.key,
    required this.sellerId,
    required this.historyId,
    this.refCode,
    this.onChanged,
  });

  final String sellerId;
  final String historyId;
  final String? refCode;
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required String sellerId,
    required String historyId,
    String? refCode,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.9;
        return SizedBox(
          height: sheetH,
          child: RefHistoryDetailSheet(
            sellerId: sellerId,
            historyId: historyId,
            refCode: refCode,
            onChanged: onChanged,
          ),
        );
      },
    );
  }

  @override
  State<RefHistoryDetailSheet> createState() => _RefHistoryDetailSheetState();
}

class _RefHistoryDetailSheetState extends State<RefHistoryDetailSheet> {
  bool _loading = true;
  RefHistoryDetail? _detail;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final d = await RefHistoryService.detail(
      sellerId: widget.sellerId,
      historyId: widget.historyId,
    );
    if (!mounted) return;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = d;
      _error = d == null ? 'Histórico não encontrado.' : null;
    });
  }

  Future<String?> _resolveProductIdForPurchase(Map<String, dynamic> row) async {
    final direct = row['product_id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final kind = row['kind']?.toString() ?? '';
    final entryId = row['id']?.toString().trim() ?? '';
    if (entryId.isEmpty) return null;
    try {
      if (kind == 'order') {
        final orders = await OrdersTable().queryRows(
          queryFn: (q) => q.eq('id', entryId),
          limit: 1,
        );
        final pid = orders.firstOrNull?.productId?.trim();
        if (pid != null && pid.isNotEmpty) return pid;
      } else if (kind == 'live_request') {
        final reqs = await LiveReservationRequestsTable().queryRows(
          queryFn: (q) => q.eq('id', entryId),
          limit: 1,
        );
        final liveItemId = reqs.firstOrNull?.liveItemId?.trim();
        if (liveItemId != null && liveItemId.isNotEmpty) {
          final items = await LiveItemsTable().queryRows(
            queryFn: (q) => q.eq('id', liveItemId),
            limit: 1,
          );
          final item = items.firstOrNull;
          final pid = item?.checkoutProductId?.trim().isNotEmpty == true
              ? item!.checkoutProductId!.trim()
              : item?.productId?.trim();
          if (pid != null && pid.isNotEmpty) return pid;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _contactBuyer(
    String? buyerId, {
    String? productId,
    String? orderId,
  }) async {
    final bid = buyerId?.trim() ?? '';
    if (bid.isEmpty) return;
    final pid = productId?.trim();
    if (pid == null || pid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem artigo associado a esta venda para abrir o chat.'),
        ),
      );
      return;
    }
    try {
      final chat = await ensureSellerChat(
        otherUserId: bid,
        productId: pid,
      );
      if (!mounted) return;
      final oid = orderId?.trim() ?? '';
      context.pushNamed(
        ChatPageWidget.routeName,
        queryParameters: <String, String?>{
          'chatId': serializeParam(chat.id, ParamType.String),
          'otherUserId': serializeParam(bid, ParamType.String),
          if (oid.isNotEmpty) 'orderId': serializeParam(oid, ParamType.String),
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a conversa.')),
      );
    }
  }

  Future<void> _cancelReservation(Map<String, dynamic> row) async {
    final kind = row['kind']?.toString() ?? '';
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (kind == 'live_request') {
      final res = await LiveReservationQueueService().processRequest(
        requestId: id,
        action: 'reject',
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        widget.onChanged?.call();
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível cancelar a reserva.')),
        );
      }
    }
  }

  Future<void> _closeHistory() async {
    final d = _detail;
    if (d == null || !d.canClose) return;
    final ok = await RefHistoryCloseDialog.show(
      context,
      sellerId: widget.sellerId,
      historyId: d.historyId,
      displayTitle: d.displayTitle,
    );
    if (!mounted || ok != true) return;
    widget.onChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 12.0 + MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Histórico',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(color: Colors.white70),
                        ),
                      )
                    : _buildBody(_detail!, bottomPad),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(RefHistoryDetail d, double bottomPad) {
    final photo = d.displayPhotoUrl?.trim();
    final ref = d.refCode.isNotEmpty
        ? d.refCode
        : (widget.refCode?.trim().isNotEmpty == true ? widget.refCode! : '');

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo != null && photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: BatataCachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      placeholderColor: const Color(0xFF243038),
                    ),
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, color: Colors.white38),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ref.isNotEmpty)
                      Text(
                        ref,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF80DEEA),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      d.displayTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLabel(d.historyStatus),
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _statRow('Directos', '${d.liveCount}'),
          _statRow('Reservas abertas', '${d.openReservationCount}'),
          _statRow('Vendas concluídas', '${d.completedPurchaseCount}'),
          if (d.salesValueEur > 0)
            _statRow('Valor vendido', '${d.salesValueEur.toStringAsFixed(2)} €'),
          if (d.displayPrice != null)
            _statRow('Preço', '${d.displayPrice!.toStringAsFixed(2)} €'),
          if (d.displayQuantity != null)
            _statRow('Quantidade', '${d.displayQuantity}'),
          if (d.reservationsOpen.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Reservas em aberto',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final r in d.reservationsOpen)
              _reservationRow(r),
          ],
          if (d.purchasesCompleted.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Compras concluídas',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final p in d.purchasesCompleted.take(10))
              _purchaseRow(p),
          ],
          if (d.livesUsed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Directos onde apareceu',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final l in d.livesUsed)
              _listTile(
                l['title']?.toString() ?? 'Artigo',
                l['origin']?.toString() ?? '',
              ),
          ],
          if (d.canClose) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _closeHistory,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF8A80),
                side: const BorderSide(color: Color(0xFFFF8A80)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Encerrar histórico',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 8),
          FleaberPrimaryButton(
            label: 'Fechar',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reservationRow(Map<String, dynamic> r) {
    final title =
        '${r['buyer_name'] ?? 'Comprador'} · ${r['quantity'] ?? 1} un.';
    final subtitle = r['origin']?.toString() ?? '';
    final buyerId = r['buyer_id']?.toString();
    final isRequest = (r['kind']?.toString() ?? '') == 'live_request';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: buyerId == null || buyerId.isEmpty
                      ? null
                      : () => _contactBuyer(buyerId),
                  child: Text(
                    'Contactar',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF80DEEA),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (isRequest)
                  TextButton(
                    onPressed: () => _cancelReservation(r),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFF8A80),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _purchaseRow(Map<String, dynamic> p) {
    final title =
        '${p['buyer_name'] ?? 'Comprador'} · ${p['quantity'] ?? 1} un.';
    final subtitle = p['origin']?.toString() ?? '';
    final buyerId = p['buyer_id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: buyerId == null || buyerId.isEmpty
              ? null
              : () async {
                  final pid = await _resolveProductIdForPurchase(p);
                  final kind = p['kind']?.toString() ?? '';
                  final orderId = p['order_id']?.toString().trim().isNotEmpty ==
                          true
                      ? p['order_id']?.toString()
                      : (kind == 'order' ? p['id']?.toString() : null);
                  if (!context.mounted) return;
                  await _contactBuyer(
                    buyerId,
                    productId: pid,
                    orderId: orderId,
                  );
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                if (buyerId != null && buyerId.isNotEmpty)
                  const Icon(Icons.chat_bubble_outline, color: Color(0xFF80DEEA), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _listTile(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'closed':
        return 'Encerrado';
      case 'merged':
        return 'Juntado a outro histórico';
      default:
        return 'Ativo';
    }
  }
}
