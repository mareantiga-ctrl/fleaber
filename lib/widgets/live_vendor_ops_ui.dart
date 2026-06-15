import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';

/// Painel operacional activo (mutuamente exclusivo).
enum SellerLiveActivePanel {
  none,
  /// Centro de comando unificado (reservas + pagamentos + histórico).
  operation,
  chat,
  catalog,
  /// Legacy — redireccionam para [operation] com secção adequada.
  reservations,
  payments,
  operations,
}

/// Secções internas do painel Operação.
enum SellerOperationSection {
  queue,
  payments,
  history,
}

extension SellerLiveActivePanelOps on SellerLiveActivePanel {
  bool get isOperationFamily =>
      this == SellerLiveActivePanel.operation ||
      this == SellerLiveActivePanel.reservations ||
      this == SellerLiveActivePanel.payments ||
      this == SellerLiveActivePanel.operations;

  SellerLiveActivePanel get normalized =>
      isOperationFamily ? SellerLiveActivePanel.operation : this;

  SellerOperationSection get defaultOperationSection => switch (this) {
        SellerLiveActivePanel.payments => SellerOperationSection.payments,
        SellerLiveActivePanel.operations => SellerOperationSection.history,
        SellerLiveActivePanel.reservations => SellerOperationSection.queue,
        _ => SellerOperationSection.queue,
      };
}

/// Modos legados — preferir [SellerLiveActivePanel].
enum LiveSellerOpsMode { minimal, operation, catalog }

/// Formatação comercial de refs/preços (evita UUIDs técnicos na UI).
abstract final class LiveVendorRefDisplay {
  static bool looksLikeTechRef(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}$').hasMatch(t)) return true;
    if (RegExp(r'^[A-Z]{2,5}-[0-9a-fA-F]{8,}$').hasMatch(t)) return true;
    return false;
  }

  static String formatRef(String? refCode) {
    var ref = (refCode ?? '').trim();
    if (ref.isEmpty || looksLikeTechRef(ref)) return '';
    ref = ref.replaceFirst(RegExp(r'^#+'), '');
    ref = ref.replaceFirst(RegExp(r'^REF[-_]?', caseSensitive: false), '');
    if (looksLikeTechRef(ref)) return '';
    if (ref.length > 16) ref = ref.substring(0, 16);
    return ref;
  }

  static String refLabel(String? refCode) {
    final f = formatRef(refCode);
    return f.isEmpty ? '—' : 'Ref $f';
  }

  /// Título humano quando existir; senão referência formatada.
  static String itemDisplayName({String? title, String? refCode}) {
    final t = (title ?? '').trim();
    if (t.isNotEmpty && !looksLikeTechRef(t)) return t;
    final f = formatRef(refCode);
    if (f.isEmpty) return 'Artigo';
    return 'Ref $f';
  }

  static String formatPrice(double? price) {
    if (price == null) return '';
    if (price == price.roundToDouble()) return '${price.toInt()}€';
    return '${price.toStringAsFixed(2).replaceAll('.', ',')}€';
  }
}

/// Métricas derivadas da fila/catálogo — sem alterar backend.
class LiveItemOpsSnapshot {
  const LiveItemOpsSnapshot({
    this.available,
    this.sold = 0,
    this.inBag = 0,
    this.interested = 0,
    this.externalRequests = 0,
    this.pendingPayments = 0,
  });

  final int? available;
  final int sold;
  final int inBag;
  final int interested;
  final int externalRequests;
  final int pendingPayments;

  bool get lowStock => available != null && available! <= 2;

  /// Reservas activas (todas as origens) — usa [interested] já agregado no painel.
  int get reservations => interested;
}

/// Textos comerciais para a vendedora (sem termos internos).
abstract final class LiveVendorSellerCopy {
  static bool isMarkedSold(String? itemStatus) =>
      (itemStatus ?? '').trim().toLowerCase() == 'sold';

  static bool isReservedFull(String? itemStatus) =>
      (itemStatus ?? '').trim().toLowerCase() == 'reserved_full';

  /// Artigo indisponível para novas reservas (pago ou reservado aceite / stock esgotado).
  static bool isLiveItemUnavailable(String? itemStatus) =>
      isMarkedSold(itemStatus) || isReservedFull(itemStatus);

  static bool isSoldOut(String? itemStatus, LiveItemOpsSnapshot stats) {
    final st = (itemStatus ?? '').trim().toLowerCase();
    return st == 'sold' || st == 'reserved_full';
  }

  static String soldOutBadge(String? itemStatus) =>
      isMarkedSold(itemStatus) ? 'VENDIDO' : 'ESGOTADO';

  static String liveCatalogUnavailableBadge(String? itemStatus) =>
      soldOutBadge(itemStatus);

  static String liveCatalogUnavailableActionLabel(String? itemStatus) =>
      isMarkedSold(itemStatus) ? 'Vendido' : 'Esgotado';

  static String reservationStatus(String? status) => switch (status) {
        'pending' => 'Reservado',
        'converted' => 'Pago',
        'rejected' => 'Recusado',
        'expired' => 'Expirado',
        'accepted' => 'Aceite',
        _ => '—',
      };

  static String reservationSource(String? source) => switch (source) {
        'fleaber_live' => 'Fleaber',
        'facebook_manual' => 'Facebook',
        'helper_manual' => 'Manual',
        _ => 'Outro',
      };

  static String formatTime(DateTime? at) {
    if (at == null) return '—';
    final local = at.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Contadores do artigo em linguagem de vendedora.
class LiveVendorProductStatusCounters extends StatelessWidget {
  const LiveVendorProductStatusCounters({
    super.key,
    required this.stats,
    this.itemStatus,
    this.onReservationsTap,
    this.onSoldTap,
    this.compact = false,
    this.lightOnDark = true,
  });

  final LiveItemOpsSnapshot stats;
  final String? itemStatus;
  final VoidCallback? onReservationsTap;
  final VoidCallback? onSoldTap;
  final bool compact;
  final bool lightOnDark;

  static const _green = Color(0xFF4CAF50);
  static const _blue = Color(0xFF4DD0E1);
  static const _orange = Color(0xFFFFB74D);
  static const _red = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    final soldOut = LiveVendorSellerCopy.isSoldOut(itemStatus, stats);
    final avail = stats.available;
    final availLabel = soldOut
        ? null
        : avail != null
            ? '$avail'
            : '—';

    final soldCount = LiveVendorSellerCopy.isMarkedSold(itemStatus) &&
            stats.sold < 1
        ? 1
        : stats.sold;

    final counters = <Widget>[
      if (soldOut)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _red.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _red.withValues(alpha: 0.75)),
          ),
          child: Text(
            LiveVendorSellerCopy.soldOutBadge(itemStatus),
            style: GoogleFonts.inter(
              color: _red,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 9 : 10,
              letterSpacing: 0.4,
            ),
          ),
        )
      else if (availLabel != null)
        _chip(
          color: _green,
          text: availLabel == '—'
              ? '— disponíveis'
              : '$availLabel disponíveis',
          onTap: null,
        ),
      _chip(
        color: _blue,
        text: '$soldCount vendidos',
        onTap: onSoldTap,
      ),
      _chip(
        color: _orange,
        text: '${stats.reservations} reservas',
        onTap: onReservationsTap,
      ),
    ];

    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: counters,
    );
  }

  Widget _chip({
    required Color color,
    required String text,
    VoidCallback? onTap,
  }) {
    final fg = lightOnDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF101518);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            color: fg,
            fontSize: compact ? 9 : 9.5,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 12,
            color: fg.withValues(alpha: 0.55),
          ),
        ],
      ],
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: child,
        ),
      ),
    );
  }
}

class LiveOpsTotals {
  const LiveOpsTotals({
    this.bagCount = 0,
    this.externalCount = 0,
    this.pendingPaymentCount = 0,
    this.conflictCount = 0,
    this.lowStockCount = 0,
    this.activeHelpers = 0,
    this.queuePending = 0,
    this.salesCount = 0,
    this.salesValueEur = 0,
    this.pendingCheckoutCount = 0,
    this.actionPendingCount = 0,
    this.stalePendingCount = 0,
  });

  final int bagCount;
  final int externalCount;
  final int pendingPaymentCount;
  final int conflictCount;
  final int lowStockCount;
  final int activeHelpers;
  final int queuePending;
  /// Vendas confirmadas (convertidas) nesta live.
  final int salesCount;
  final double salesValueEur;
  /// Reservas aceites à espera de pagamento.
  final int pendingCheckoutCount;
  /// Itens que precisam acção (pendentes + aceites sem pagamento).
  final int actionPendingCount;
  /// Reservas pendentes há mais de 10 minutos.
  final int stalePendingCount;

  bool get hasAlerts =>
      actionPendingCount > 0 ||
      stalePendingCount > 0 ||
      externalCount > 0 ||
      conflictCount > 0 ||
      lowStockCount > 0;

  static String formatEuro(double value) {
    if (value <= 0) return '0€';
    if (value == value.roundToDouble()) return '${value.toInt()}€';
    return '${value.toStringAsFixed(2).replaceAll('.', ',')}€';
  }
}

enum LiveOpsActivityKind {
  bagAdd,
  purchase,
  stockLow,
  reservationAccepted,
  stockAdjust,
  soldOut,
  helperAction,
  externalPayment,
  system,
}

class LiveOpsActivityEvent {
  const LiveOpsActivityEvent({
    required this.id,
    required this.text,
    this.at,
    this.kind,
    this.liveItemId,
    this.requestId,
    this.actionLabel,
  });

  final String id;
  final String text;
  final DateTime? at;
  final LiveOpsActivityKind? kind;
  final String? liveItemId;
  final String? requestId;
  final String? actionLabel;

  bool get hasAction =>
      actionLabel != null && actionLabel!.trim().isNotEmpty;
}

/// Timeline operacional — seller/helper (não é FOMO do chat público).
class LiveVendorActivityTimeline extends StatelessWidget {
  const LiveVendorActivityTimeline({
    super.key,
    required this.events,
    this.height = 200,
    this.onEventAction,
  });

  final List<LiveOpsActivityEvent> events;
  final double height;
  final ValueChanged<LiveOpsActivityEvent>? onEventAction;

  static final _timeFmt = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'A actividade do directo aparece aqui em tempo real.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
        ),
      );
    }

    final sorted = List<LiveOpsActivityEvent>.from(events)
      ..sort((a, b) {
        final ta = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sorted.length.clamp(0, 50),
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final e = sorted[i];
          final time = e.at != null ? _timeFmt.format(e.at!.toLocal()) : '--:--';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  time,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.text,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (e.hasAction && onEventAction != null) ...[
                      const SizedBox(height: 3),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: FleaberColors.teal,
                        ),
                        onPressed: () => onEventAction!(e),
                        child: Text(
                          e.actionLabel!,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Feed legado — preferir [LiveVendorActivityTimeline].
class LiveVendorOpsActivityFeed extends StatelessWidget {
  const LiveVendorOpsActivityFeed({
    super.key,
    required this.events,
    this.height = 68,
    this.onEventAction,
  });

  final List<LiveOpsActivityEvent> events;
  final double height;
  final ValueChanged<LiveOpsActivityEvent>? onEventAction;

  @override
  Widget build(BuildContext context) {
    return LiveVendorActivityTimeline(
      events: events,
      height: height,
      onEventAction: onEventAction,
    );
  }
}

/// Barra de modos: Minimal / Operação / Catálogo.
class LiveVendorOpsModeBar extends StatelessWidget {
  const LiveVendorOpsModeBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final LiveSellerOpsMode mode;
  final ValueChanged<LiveSellerOpsMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip('Minimal', LiveSellerOpsMode.minimal, Icons.videocam_outlined),
        const SizedBox(width: 5),
        _chip('Atividade', LiveSellerOpsMode.operation, Icons.dashboard_customize_outlined),
        const SizedBox(width: 5),
        _chip('Catálogo', LiveSellerOpsMode.catalog, Icons.view_carousel_outlined),
      ],
    );
  }

  Widget _chip(String label, LiveSellerOpsMode value, IconData icon) {
    final selected = mode == value;
    return Expanded(
      child: Material(
        color: selected
            ? FleaberColors.teal.withValues(alpha: 0.78)
            : Colors.black.withValues(alpha: 0.32),
        borderRadius: FleaberRadius.circularSm,
        child: InkWell(
          onTap: () => onModeChanged(value),
          borderRadius: FleaberRadius.circularSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.7),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: selected ? 1 : 0.78),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// KPIs do centro de comando — sempre visível no topo de Operação.
class LiveVendorOperationKpiStrip extends StatelessWidget {
  const LiveVendorOperationKpiStrip({
    super.key,
    required this.totals,
    this.onTapSales,
    this.onTapPending,
    this.onTapCheckout,
    this.onTapHelpers,
    this.onTapUrgent,
  });

  final LiveOpsTotals totals;
  final VoidCallback? onTapSales;
  final VoidCallback? onTapPending;
  final VoidCallback? onTapCheckout;
  final VoidCallback? onTapHelpers;
  final VoidCallback? onTapUrgent;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            LiveOpsTotals.formatEuro(totals.salesValueEur),
            style: GoogleFonts.inter(
              color: totals.salesValueEur > 0
                  ? FleaberColors.teal
                  : Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Ganhos desta live',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _kpiChip(
                label: 'Vendas',
                value: '${totals.salesCount}',
                highlight: totals.salesCount > 0,
                onTap: onTapSales,
              ),
              _kpiChip(
                label: 'Pendentes',
                value: '${totals.actionPendingCount}',
                highlight: totals.actionPendingCount > 0,
                onTap: onTapPending,
              ),
              _kpiChip(
                label: 'A receber',
                value: '${totals.pendingCheckoutCount}',
                highlight: totals.pendingCheckoutCount > 0,
                onTap: onTapCheckout,
              ),
              _kpiChip(
                label: 'Equipa',
                value: '${totals.activeHelpers}',
                highlight: false,
                onTap: onTapHelpers,
              ),
              if (totals.stalePendingCount > 0)
                _kpiChip(
                  label: 'Urgentes',
                  value: '${totals.stalePendingCount}',
                  highlight: true,
                  onTap: onTapUrgent ?? onTapPending,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiChip({
    required String label,
    required String value,
    required bool highlight,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? FleaberColors.teal.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.28),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(
          color: highlight
              ? FleaberColors.teal.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularSm,
        child: child,
      ),
    );
  }
}

/// Sub-navegação do painel Operação.
class LiveVendorOperationSectionTabs extends StatelessWidget {
  const LiveVendorOperationSectionTabs({
    super.key,
    required this.selected,
    required this.onSelected,
    this.queueBadge = 0,
    this.paymentsBadge = 0,
  });

  final SellerOperationSection selected;
  final ValueChanged<SellerOperationSection> onSelected;
  final int queueBadge;
  final int paymentsBadge;

  static const _tabs = <(SellerOperationSection, String)>[
    (SellerOperationSection.queue, 'Pendentes'),
    (SellerOperationSection.payments, 'A receber'),
    (SellerOperationSection.history, 'Histórico'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _segChip(
                label: _tabs[i].$2,
                selected: selected == _tabs[i].$1,
                badge: switch (_tabs[i].$1) {
                  SellerOperationSection.queue => queueBadge,
                  SellerOperationSection.payments => paymentsBadge,
                  _ => 0,
                },
                onTap: () => onSelected(_tabs[i].$1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.black.withValues(alpha: 0.25),
      borderRadius: FleaberRadius.circularSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.62),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FleaberColors.teal,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
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
}

/// Barra de estado operacional compacta.
class LiveVendorOpsStatusBar extends StatelessWidget {
  const LiveVendorOpsStatusBar({
    super.key,
    required this.totals,
    this.onTapQueue,
    this.compact = false,
  });

  final LiveOpsTotals totals;
  final VoidCallback? onTapQueue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!totals.hasAlerts && compact) return const SizedBox.shrink();

    final chips = <Widget>[
      if (totals.actionPendingCount > 0)
        _statusChip('🔴', '${totals.actionPendingCount} a tratar', true)
      else if (totals.bagCount > 0)
        _statusChip('🟢', '${totals.bagCount} saco', true),
      if (totals.stalePendingCount > 0)
        _statusChip('⏱', '${totals.stalePendingCount} >10m', true),
      if (totals.externalCount > 0)
        _statusChip('🟡', '${totals.externalCount} ext.', true),
      if (totals.pendingPaymentCount > 0)
        _statusChip('🔴', '${totals.pendingPaymentCount} pend.', true),
      if (totals.activeHelpers > 0)
        _statusChip('👥', '${totals.activeHelpers} help.', false),
      if (totals.lowStockCount > 0)
        _statusChip('🔥', 'quase esgotado', true),
      if (totals.conflictCount > 0)
        _statusChip('⚠️', '${totals.conflictCount} confl.', true),
    ];

    if (chips.isEmpty) {
      chips.add(_statusChip('⚪', 'Sem pendências', false));
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapQueue,
        borderRadius: FleaberRadius.circularSm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: FleaberRadius.circularSm,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String emoji, String label, bool highlight) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        '$emoji $label',
        style: GoogleFonts.inter(
          color: highlight
              ? Colors.white.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.65),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Indicador mínimo do artigo em direto (modo apresentação).
class LiveVendorCurrentProductPill extends StatelessWidget {
  const LiveVendorCurrentProductPill({
    super.key,
    required this.refLabel,
    required this.title,
    this.attributesLine,
    this.priceLabel,
    this.onTap,
  });

  final String refLabel;
  final String title;
  final String? attributesLine;
  final String? priceLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularSm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(
              color: FleaberColors.teal.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FleaberColors.teal.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      refLabel,
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (attributesLine != null &&
                        attributesLine!.isNotEmpty) ...[
                      Text(
                        attributesLine!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (priceLabel != null && priceLabel!.isNotEmpty)
                Text(
                  priceLabel!,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card destacado do artigo «A MOSTRAR».
class LiveVendorActiveItemHero extends StatelessWidget {
  const LiveVendorActiveItemHero({
    super.key,
    required this.refLabel,
    required this.title,
    this.priceLabel,
    this.photoUrl,
    required this.stats,
    this.onShowCatalog,
    this.compact = false,
  });

  final String refLabel;
  final String title;
  final String? priceLabel;
  final String? photoUrl;
  final LiveItemOpsSnapshot stats;
  final VoidCallback? onShowCatalog;
  final bool compact;

  static const double heroHeight = 104;
  static const double compactHeight = 76;

  @override
  Widget build(BuildContext context) {
    final h = compact ? compactHeight : heroHeight;
    return Container(
      height: h,
      decoration: BoxDecoration(
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.7)),
        boxShadow: compact ? null : [FleaberElevation.smAccent(FleaberColors.teal)],
      ),
      child: ClipRRect(
        borderRadius: FleaberRadius.circularMd,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Row(
            children: [
              if (!compact)
                SizedBox(
                  width: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (photoUrl != null && photoUrl!.trim().isNotEmpty)
                        Image.network(photoUrl!.trim(), fit: BoxFit.cover)
                      else
                        const ColoredBox(color: Color(0xFF1A1A1A)),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 10 : 8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            refLabel,
                            style: GoogleFonts.inter(
                              color: FleaberColors.teal,
                              fontWeight: FontWeight.w900,
                              fontSize: compact ? 11 : 13,
                            ),
                          ),
                          if (priceLabel != null && priceLabel!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              priceLabel!,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 11 : 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 10 : 11,
                          height: 1.15,
                        ),
                      ),
                      const Spacer(),
                      LiveVendorProductStatusCounters(
                        stats: stats,
                        compact: true,
                        lightOnDark: true,
                      ),
                    ],
                  ),
                ),
              ),
              if (onShowCatalog != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onShowCatalog,
                  icon: const Icon(Icons.view_carousel_outlined,
                      color: Colors.white60, size: 18),
                  tooltip: 'Fila catálogo',
                ),
            ],
          ),
        ),
      ),
    );
  }

}

typedef LiveVendorQuickAction = void Function(String id);

/// Acções rápidas horizontais durante o directo.
class LiveVendorQuickActionsStrip extends StatelessWidget {
  const LiveVendorQuickActionsStrip({
    super.key,
    required this.onAction,
    this.enabled = true,
  });

  final LiveVendorQuickAction onAction;
  final bool enabled;

  static const _actions = <(String id, String label, IconData icon)>[
    ('show', 'Mostrar', Icons.push_pin_outlined),
    ('sold', 'Vendido', Icons.check_circle_outline),
    ('last_unit', 'Última un.', Icons.local_fire_department_outlined),
    ('stock', '+ Stock', Icons.add_box_outlined),
    ('external', 'Pedido ext.', Icons.payments_outlined),
    ('queue', 'Fila', Icons.inbox_outlined),
    ('conflict', 'Conflito', Icons.warning_amber_outlined),
    ('helper', 'Helper', Icons.groups_outlined),
    ('bundle', 'Bundle', Icons.card_giftcard_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, i) {
          final a = _actions[i];
          return Material(
            color: Colors.black.withValues(alpha: enabled ? 0.42 : 0.25),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: enabled ? () => onAction(a.$1) : null,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.$3, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                    const SizedBox(width: 3),
                    Text(
                      a.$2,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Topbar secundária sob o LIVE — navegação principal dos painéis.
class LiveVendorOpsTopNavBar extends StatelessWidget {
  const LiveVendorOpsTopNavBar({
    super.key,
    required this.activePanel,
    required this.onPanelToggled,
    required this.onMoreTap,
    this.queueBadge = 0,
    this.chatBadge = 0,
  });

  final SellerLiveActivePanel activePanel;
  final ValueChanged<SellerLiveActivePanel> onPanelToggled;
  final VoidCallback onMoreTap;
  final int queueBadge;
  final int chatBadge;

  static const _tabs = <(SellerLiveActivePanel, String, IconData)>[
    (SellerLiveActivePanel.operation, 'Operação', Icons.dashboard_customize_outlined),
    (SellerLiveActivePanel.chat, 'Chat', Icons.chat_bubble_outline_rounded),
    (SellerLiveActivePanel.catalog, 'Catálogo', Icons.inventory_2_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _navChip(
                icon: _tabs[i].$3,
                label: _tabs[i].$2,
                selected: switch (_tabs[i].$1) {
                  SellerLiveActivePanel.operation =>
                    activePanel.isOperationFamily,
                  _ => activePanel == _tabs[i].$1,
                },
                badge: switch (_tabs[i].$1) {
                  SellerLiveActivePanel.operation => queueBadge,
                  SellerLiveActivePanel.chat => chatBadge,
                  _ => 0,
                },
                onTap: () => onPanelToggled(_tabs[i].$1),
              ),
            ),
          ],
          const SizedBox(width: 4),
          _navChip(
            icon: Icons.more_horiz_rounded,
            label: '···',
            selected: false,
            onTap: onMoreTap,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _navChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badge = 0,
    bool compact = false,
  }) {
    final fg = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.62);

    return Material(
      color: selected
          ? FleaberColors.teal.withValues(alpha: 0.82)
          : Colors.black.withValues(alpha: 0.38),
      borderRadius: FleaberRadius.circularSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularSm,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 4 : 5,
            horizontal: compact ? 4 : 2,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: compact ? 14 : 15,
                    color: fg,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: fg,
                      fontSize: compact ? 7.5 : 8,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
              if (badge > 0)
                Positioned(
                  right: compact ? -4 : -2,
                  top: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FleaberColors.teal,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 0.8),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
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
}

/// Card compacto do artigo em direto (sem acções internas).
class LiveVendorCompactProductCard extends StatelessWidget {
  const LiveVendorCompactProductCard({
    super.key,
    required this.refLabel,
    required this.title,
    this.attributesLine,
    this.priceLabel,
    this.photoUrl,
    required this.stats,
    this.itemStatus,
    this.onReservationsTap,
    this.onSoldTap,
  });

  final String refLabel;
  final String title;
  final String? attributesLine;
  final String? priceLabel;
  final String? photoUrl;
  final LiveItemOpsSnapshot stats;
  final String? itemStatus;
  final VoidCallback? onReservationsTap;
  final VoidCallback? onSoldTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = LiveVendorSellerCopy.isSoldOut(itemStatus, stats);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: soldOut
              ? const Color(0xFFEF5350).withValues(alpha: 0.65)
              : FleaberColors.teal.withValues(alpha: 0.55),
          width: soldOut ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: FleaberRadius.circularSm,
            child: SizedBox(
              width: 52,
              height: 52,
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
                Text(
                  refLabel,
                  style: GoogleFonts.inter(
                    color: FleaberColors.teal,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
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
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                LiveVendorProductStatusCounters(
                  stats: stats,
                  itemStatus: itemStatus,
                  onReservationsTap: onReservationsTap,
                  onSoldTap: onSoldTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Acções rápidas do artigo seleccionado (barra dedicada).
class LiveVendorProductActionsBar extends StatelessWidget {
  const LiveVendorProductActionsBar({
    super.key,
    required this.onAction,
    this.enabled = true,
  });

  final LiveVendorQuickAction onAction;
  final bool enabled;

  static const _actions = <(String id, String label)>[
    ('show', 'Mostrar'),
    ('sold', 'Vendido'),
    ('last_unit', 'Última Unidade'),
    ('stock', '+Stock'),
    ('external', 'Reserva Facebook'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, i) {
          final a = _actions[i];
          return Material(
            color: Colors.black.withValues(alpha: enabled ? 0.42 : 0.22),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: enabled ? () => onAction(a.$1) : null,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  a.$2,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
