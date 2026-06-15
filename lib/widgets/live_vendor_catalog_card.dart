import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

/// Métricas comerciais por artigo no catálogo do directo.
class LiveVendorCatalogItemMetrics {
  const LiveVendorCatalogItemMetrics({
    this.quantity,
    this.available,
    this.sold = 0,
    this.reservations = 0,
  });

  /// Stock total na live (`live_items.quantity` / RPC `total_qty`).
  final int? quantity;
  /// Unidades livres para vender agora (RPC `available_qty`).
  final int? available;
  final int sold;
  final int reservations;

  String get quantityLabel =>
      quantity != null ? '$quantity' : '—';

  String get metricsLine {
    final total = quantity;
    final disp = available ?? quantity;
    final dispLabel = disp != null ? '$disp' : '—';
    if (total != null && disp != null && total != disp) {
      return 'Disp: $dispLabel · Total: $total · '
          'Vendidos: $sold · Reservas: $reservations';
    }
    return 'Disp: $dispLabel · '
        'Vendidos: $sold · Reservas: $reservations';
  }
}

/// Card da fila de catálogo (venda ao vivo).
class LiveVendorCatalogQueueCard extends StatelessWidget {
  const LiveVendorCatalogQueueCard({
    super.key,
    required this.title,
    required this.refLabel,
    this.attributesLine,
    this.priceLabel,
    this.photoUrl,
    required this.metrics,
    this.itemStatus,
    required this.isActive,
    required this.isSold,
    this.onShow,
    this.onMenuSelected,
  });

  final String title;
  final String refLabel;
  final String? attributesLine;
  final String? priceLabel;
  final String? photoUrl;
  final LiveVendorCatalogItemMetrics metrics;
  final String? itemStatus;
  final bool isActive;
  final bool isSold;
  final VoidCallback? onShow;
  final ValueChanged<String>? onMenuSelected;

  static const _liveGreen = Color(0xFF00C853);
  static const _soldRed = Color(0xFFEF5350);

  bool get _soldOut {
    if (isSold) return true;
    final st = (itemStatus ?? '').trim().toLowerCase();
    return st == 'sold' || st == 'reserved_full';
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? FleaberColors.teal.withValues(alpha: 0.85)
        : _soldOut
            ? _soldRed.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? FleaberColors.teal.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: borderColor, width: isActive ? 1.2 : 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: FleaberRadius.circularSm,
              child: SizedBox(
                width: 56,
                height: 56,
                child: photoUrl != null && photoUrl!.trim().isNotEmpty
                    ? Image.network(photoUrl!.trim(), fit: BoxFit.cover)
                    : const ColoredBox(color: Color(0xFF1A1A1A)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isActive && !_soldOut)
                    _badge('EM DIRETO', _liveGreen)
                  else if (_soldOut)
                    _badge(
                      isSold ? 'VENDIDO' : 'ESGOTADO',
                      _soldRed,
                    ),
                  if ((isActive && !_soldOut) || _soldOut) const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (attributesLine != null && attributesLine!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      attributesLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (priceLabel != null && priceLabel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      priceLabel!,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (refLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      refLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    metrics.metricsLine,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _compactActionButton(),
            if (onMenuSelected != null)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 20,
                ),
                color: const Color(0xFF1A2228),
                onSelected: onMenuSelected,
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Editar rápido'),
                  ),
                  PopupMenuItem(
                    value: 'stock',
                    child: Text('Adicionar stock'),
                  ),
                  PopupMenuItem(
                    value: 'sold',
                    child: Text('Marcar vendido'),
                  ),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicar'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('Arquivar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.85)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _compactActionButton() {
    if (_soldOut && !isActive) {
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text(
          isSold ? 'Vendido' : 'Esgotado',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (isActive) {
      return _actionChip(
        label: 'Na vitrine',
        enabled: false,
        bg: _liveGreen.withValues(alpha: 0.35),
        fg: Colors.white.withValues(alpha: 0.92),
      );
    }

    if (onShow == null) return const SizedBox.shrink();

    return _actionChip(
      label: 'Mostrar',
      enabled: true,
      bg: FleaberColors.teal,
      fg: Colors.white,
      onTap: onShow,
    );
  }

  Widget _actionChip({
    required String label,
    required bool enabled,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: FleaberRadius.circularSm,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: FleaberRadius.circularSm,
        child: Container(
          width: 58,
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 9,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
