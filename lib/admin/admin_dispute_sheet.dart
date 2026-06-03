import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/return_label.dart';

class AdminDisputeSheet extends StatefulWidget {
  const AdminDisputeSheet({
    super.key,
    required this.dispute,
    required this.order,
    required this.buyer,
    required this.seller,
    required this.onResolved,
  });

  final OrderDisputesRow dispute;
  final OrdersRow? order;
  final ProfilesRow? buyer;
  final ProfilesRow? seller;
  final VoidCallback onResolved;

  static Future<void> show(
    BuildContext context, {
    required OrderDisputesRow dispute,
    required OrdersRow? order,
    required ProfilesRow? buyer,
    required ProfilesRow? seller,
    required VoidCallback onResolved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdminDisputeSheet(
        dispute: dispute,
        order: order,
        buyer: buyer,
        seller: seller,
        onResolved: onResolved,
      ),
    );
  }

  @override
  State<AdminDisputeSheet> createState() => _AdminDisputeSheetState();
}

class _AdminDisputeSheetState extends State<AdminDisputeSheet> {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kMuted = Color(0xFF57636C);

  final _noteController = TextEditingController();
  bool _busy = false;
  late Future<List<OrderDisputeRepliesRow>> _repliesFuture;

  @override
  void initState() {
    super.initState();
    _repliesFuture = _loadReplies();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<List<OrderDisputeRepliesRow>> _loadReplies() async {
    final id = widget.dispute.id;
    if (id == null || id.isEmpty) return const [];
    return OrderDisputeRepliesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('dispute_id', id)
          .order('created_at', ascending: true),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'pt_PT').format(value.toLocal());
  }

  String _money(double? value) {
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€')
        .format(value ?? 0);
  }

  String _reasonLabel(String? reason) {
    switch (reason) {
      case 'danificado':
        return 'Artigo danificado';
      case 'nao_corresponde':
        return 'Não corresponde';
      case 'em_falta':
        return 'Em falta';
      case 'outro':
        return 'Outro';
      default:
        return reason ?? '-';
    }
  }

  Future<void> _resolve(String resolution) async {
    final disputeId = widget.dispute.id;
    if (disputeId == null || disputeId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await SupaFlow.client.rpc(
        'batata_admin_resolve_dispute',
        params: {
          'p_dispute_id': disputeId,
          'p_resolution': resolution,
          'p_note': _noteController.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onResolved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disputa atualizada pela administração.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível resolver: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _kMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF101518),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dispute = widget.dispute;
    final order = widget.order;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5FBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Intervir na disputa',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF101518),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (dispute.status == 'escalada_fleaber')
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(0xFFD8B4FE)),
                        ),
                        child: Text(
                          'Esta disputa está escalada e aguarda decisão do Fleaber.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B21A8),
                          ),
                        ),
                      ),
                    _infoRow('Estado', dispute.status ?? '-'),
                    _infoRow('Turno', dispute.currentTurn),
                    _infoRow('Motivo', _reasonLabel(dispute.reason)),
                    _infoRow('Descrição', dispute.description ?? '-'),
                    _infoRow('Prazo', _date(dispute.nextDeadline)),
                    _infoRow(
                      'Encomenda',
                      '${order?.status ?? '-'} | ${_money(order?.priceTotal)}',
                    ),
                    _infoRow(
                      'Comprador',
                      widget.buyer?.fullName ?? widget.buyer?.id ?? '-',
                    ),
                    _infoRow(
                      'Vendedor',
                      widget.seller?.fullName ?? widget.seller?.id ?? '-',
                    ),
                    if (dispute.sellerOfferType != null)
                      _infoRow(
                        'Proposta',
                        dispute.sellerOfferType == 'return_and_partial_refund'
                            ? 'Devolução + reembolso parcial ${(dispute.sellerRefundPercent ?? 0).toStringAsFixed(0)}%'
                            : dispute.sellerOfferType == 'partial_refund'
                                ? 'Reembolso parcial ${(dispute.sellerRefundPercent ?? 0).toStringAsFixed(0)}%'
                                : dispute.sellerOfferType == 'return'
                                    ? (dispute.sellerPaysReturnShipping
                                        ? 'Devolução (portes vendedor)'
                                        : 'Devolução (portes comprador)')
                                    : dispute.sellerOfferType!,
                      ),
                    if (dispute.adminResolution != null)
                      _infoRow('Decisão admin', dispute.adminResolution!),
                    const SizedBox(height: 8),
                    Text(
                      'Histórico',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<OrderDisputeRepliesRow>>(
                      future: _repliesFuture,
                      builder: (context, snapshot) {
                        final replies = snapshot.data ?? const [];
                        if (replies.isEmpty) {
                          return Text(
                            'Sem respostas registadas.',
                            style: GoogleFonts.inter(color: _kMuted),
                          );
                        }
                        return Column(
                          children: [
                            for (final reply in replies)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE6EEF0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reply.senderId == currentUserUid
                                          ? 'Administração'
                                          : 'Participante',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _kTeal,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(reply.message ?? ''),
                                    const SizedBox(height: 4),
                                    Text(
                                      _date(reply.createdAt),
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: _kMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Nota da decisão (opcional)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Resolver disputa',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _resolve('favor_buyer_refund'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                      ),
                      child: const Text('Dar razão ao comprador (reembolso)'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed:
                          _busy ? null : () => _resolve('favor_seller'),
                      style: FilledButton.styleFrom(backgroundColor: _kTeal),
                      child: const Text('Dar razão ao vendedor (libertar pagamento)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed:
                          _busy ? null : () => _resolve('approve_return'),
                      child: const Text('Aprovar devolução (gerar etiqueta)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
