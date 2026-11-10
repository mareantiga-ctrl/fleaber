import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/utils/live_start_open_reservations_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/profile_avatar.dart';

/// Popup V1 antes de iniciar directo — reservas em aberto.
class LiveStartReservationsWarningSheet extends StatelessWidget {
  const LiveStartReservationsWarningSheet({
    super.key,
    required this.report,
  });

  final LiveStartOpenReservationsReport report;

  /// `true` = continuar directo; `false` = voltar ao catálogo.
  static Future<bool> show(
    BuildContext context, {
    required LiveStartOpenReservationsReport report,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LiveStartReservationsWarningSheet(report: report),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Reservas em aberto',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Alguns artigos deste direto já têm reservas ou pedidos em '
                'aberto de diretos anteriores, gravados ou marketplace.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _SummaryStrip(summary: summary),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: report.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _ItemTile(item: report.items[index]);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Podes iniciar o directo na mesma. Cancelar reservas individuais '
                'fica para uma versão futura.',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              FleaberPrimaryButton(
                label: 'Continuar directo',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Voltar ao catálogo',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF80DEEA),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});

  final LiveStartOpenReservationsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2329),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3A42)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryChip(
              value: '${summary.itemsWithOpen}',
              label: 'artigos',
            ),
          ),
          Expanded(
            child: _SummaryChip(
              value: '${summary.totalReservations}',
              label: 'reservas',
            ),
          ),
          Expanded(
            child: _SummaryChip(
              value: '${summary.totalUnits}',
              label: 'unidades',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            color: const Color(0xFF80DEEA),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final LiveStartOpenReservationsItem item;

  @override
  Widget build(BuildContext context) {
    final ref = LiveVendorRefDisplay.formatRef(item.refCode);
    final refBit = ref.isNotEmpty ? ' · $ref' : '';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151C21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.stockWarning
              ? const Color(0xFFFFB74D).withValues(alpha: 0.55)
              : const Color(0xFF243038),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: item.photoUrl != null && item.photoUrl!.trim().isNotEmpty
                  ? BatataCachedNetworkImage(
                      imageUrl: item.photoUrl!.trim(),
                      fit: BoxFit.cover,
                      placeholderColor: const Color(0xFF243038),
                    )
                  : ColoredBox(
                      color: const Color(0xFF243038),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white38,
                        size: 22,
                      ),
                    ),
            ),
          ),
          title: Text(
            '${item.title}$refBit',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'Stock ${item.currentStock} · '
                '${item.reservationCount} reserva${item.reservationCount == 1 ? '' : 's'} · '
                '${item.reservedUnits} un.',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
              ),
              if (item.originsLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.originsLabel,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF80DEEA).withValues(alpha: 0.85),
                    fontSize: 10.5,
                  ),
                ),
              ],
              if (item.stockWarning) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Unidades reservadas ≥ stock disponível',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFFB74D),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          children: [
            for (final r in item.reservations) _ReservationRow(detail: r),
          ],
        ),
      ),
    );
  }
}

class _ReservationRow extends StatelessWidget {
  const _ReservationRow({required this.detail});

  final LiveStartOpenReservationDetail detail;

  @override
  Widget build(BuildContext context) {
    final age = detail.createdAt != null
        ? dateTimeFormat('relative', detail.createdAt, locale: 'pt')
        : '';
    final queue = detail.queuePosition;
    final queueBit =
        queue != null && queue > 0 ? ' · Fila #$queue' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FleaberProfileAvatar(
            userId: detail.buyerId,
            fullName: detail.buyerName,
            photoUrl: detail.buyerPhotoUrl,
            radius: 14,
            backgroundColor: const Color(0xFF243038),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.buyerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${detail.statusLabel} · ${detail.quantity} un.$queueBit',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  '${detail.origin}${age.isNotEmpty ? ' · $age' : ''}',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
