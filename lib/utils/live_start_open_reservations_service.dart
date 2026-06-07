import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/order_cancel_eligibility.dart';
import '/utils/live_reservation_queue_service.dart';

/// Resumo global do aviso V1 antes de iniciar directo.
class LiveStartOpenReservationsSummary {
  const LiveStartOpenReservationsSummary({
    required this.itemsWithOpen,
    required this.totalReservations,
    required this.totalUnits,
  });

  final int itemsWithOpen;
  final int totalReservations;
  final int totalUnits;

  bool get hasOpen => itemsWithOpen > 0;

  factory LiveStartOpenReservationsSummary.fromJson(Map<String, dynamic> json) {
    return LiveStartOpenReservationsSummary(
      itemsWithOpen: _asInt(json['items_with_open']),
      totalReservations: _asInt(json['total_reservations']),
      totalUnits: _asInt(json['total_units']),
    );
  }
}

/// Detalhe de uma reserva/pedido em aberto.
class LiveStartOpenReservationDetail {
  const LiveStartOpenReservationDetail({
    required this.kind,
    required this.id,
    this.buyerId,
    required this.buyerName,
    this.buyerPhotoUrl,
    required this.status,
    required this.statusLabel,
    required this.quantity,
    this.queuePosition,
    this.createdAt,
    required this.origin,
  });

  final String kind;
  final String id;
  final String? buyerId;
  final String buyerName;
  final String? buyerPhotoUrl;
  final String status;
  final String statusLabel;
  final int quantity;
  final int? queuePosition;
  final DateTime? createdAt;
  final String origin;

  bool get isLiveRequest => kind == 'live_request';

  factory LiveStartOpenReservationDetail.fromJson(Map<String, dynamic> json) {
    final status = (json['status']?.toString() ?? '').trim();
    final kind = (json['kind']?.toString() ?? '').trim();
    return LiveStartOpenReservationDetail(
      kind: kind,
      id: json['id']?.toString() ?? '',
      buyerId: json['buyer_id']?.toString(),
      buyerName: (json['buyer_name']?.toString() ?? 'Comprador').trim(),
      buyerPhotoUrl: json['buyer_photo_url']?.toString(),
      status: status,
      statusLabel: humanizeOpenReservationStatus(
        kind: kind,
        status: status,
      ),
      quantity: _asInt(json['quantity'], 1),
      queuePosition: _asNullableInt(json['queue_position']),
      createdAt: _parseDate(json['created_at']),
      origin: (json['origin']?.toString() ?? 'Marketplace').trim(),
    );
  }
}

/// Artigo do catálogo com pendências.
class LiveStartOpenReservationsItem {
  const LiveStartOpenReservationsItem({
    required this.liveItemId,
    required this.title,
    required this.refCode,
    this.photoUrl,
    required this.currentStock,
    required this.reservationCount,
    required this.reservedUnits,
    required this.stockWarning,
    required this.origins,
    required this.reservations,
  });

  final String liveItemId;
  final String title;
  final String refCode;
  final String? photoUrl;
  final int currentStock;
  final int reservationCount;
  final int reservedUnits;
  final bool stockWarning;
  final List<String> origins;
  final List<LiveStartOpenReservationDetail> reservations;

  String get originsLabel => origins.join(' · ');

  factory LiveStartOpenReservationsItem.fromJson(Map<String, dynamic> json) {
    final originsRaw = json['origins'];
    final origins = <String>[];
    if (originsRaw is List) {
      for (final o in originsRaw) {
        final t = o?.toString().trim() ?? '';
        if (t.isNotEmpty) origins.add(t);
      }
    }
    final resRaw = json['reservations'];
    final reservations = <LiveStartOpenReservationDetail>[];
    if (resRaw is List) {
      for (final r in resRaw) {
        if (r is Map) {
          reservations.add(
            LiveStartOpenReservationDetail.fromJson(
              Map<String, dynamic>.from(r),
            ),
          );
        }
      }
    }
    return LiveStartOpenReservationsItem(
      liveItemId: json['live_item_id']?.toString() ?? '',
      title: (json['title']?.toString() ?? 'Artigo').trim(),
      refCode: (json['ref_code']?.toString() ?? '').trim(),
      photoUrl: json['photo_url']?.toString(),
      currentStock: _asInt(json['current_stock'], 1),
      reservationCount: _asInt(json['reservation_count']),
      reservedUnits: _asInt(json['reserved_units']),
      stockWarning: json['stock_warning'] == true,
      origins: origins,
      reservations: reservations,
    );
  }
}

/// Relatório completo devolvido pelo RPC.
class LiveStartOpenReservationsReport {
  const LiveStartOpenReservationsReport({
    required this.summary,
    required this.items,
  });

  final LiveStartOpenReservationsSummary summary;
  final List<LiveStartOpenReservationsItem> items;

  factory LiveStartOpenReservationsReport.fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw ArgumentError('Invalid RPC payload');
    }
    final m = Map<String, dynamic>.from(raw);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'open_reservations_unavailable');
    }
    final summaryJson = m['summary'];
    final itemsRaw = m['items'];
    final items = <LiveStartOpenReservationsItem>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map) {
          items.add(
            LiveStartOpenReservationsItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }
    return LiveStartOpenReservationsReport(
      summary: summaryJson is Map
          ? LiveStartOpenReservationsSummary.fromJson(
              Map<String, dynamic>.from(summaryJson),
            )
          : const LiveStartOpenReservationsSummary(
              itemsWithOpen: 0,
              totalReservations: 0,
              totalUnits: 0,
            ),
      items: items,
    );
  }
}

/// Estados de encomenda considerados «em aberto» na V1 (espelha o RPC).
bool orderStatusIsOpenForStartWarning(String? status) {
  if (orderIsCancelled(status)) return false;
  final s = normalizeOrderStatusKey(status);
  const open = {
    'reserva_pendente',
    'reservado',
    'aguarda_confirmacao',
    'pendente',
  };
  return open.contains(s);
}

/// Pedido de saco live considerado «em aberto» na V1 (espelha o RPC).
bool liveRequestIsOpenForStartWarning({
  required String? status,
  String? notes,
}) =>
    LiveReservationQueueService.isOpenSellerTreatReservation(
      status: status,
      notes: notes,
    );

String humanizeOpenReservationStatus({
  required String kind,
  required String status,
}) {
  if (kind == 'live_request') {
    return LiveReservationQueueService.statusLabel(status);
  }
  final s = normalizeOrderStatusKey(status);
  return switch (s) {
    'reserva_pendente' => 'Pedido de reserva',
    'reservado' => 'Reservado (aguarda pagamento)',
    'pendente' => 'Pagamento pendente',
    'aguarda_confirmacao' => 'Pagamento em verificação',
    _ => status.isNotEmpty ? status : 'Em aberto',
  };
}

/// Agrega contagens a partir de itens (útil em testes).
LiveStartOpenReservationsSummary summarizeOpenReservationItems(
  List<LiveStartOpenReservationsItem> items,
) {
  var reservations = 0;
  var units = 0;
  for (final item in items) {
    reservations += item.reservationCount;
    units += item.reservedUnits;
  }
  return LiveStartOpenReservationsSummary(
    itemsWithOpen: items.length,
    totalReservations: reservations,
    totalUnits: units,
  );
}

abstract final class LiveStartOpenReservationsService {
  static Future<LiveStartOpenReservationsReport?> fetch(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_start_open_reservations_check',
        params: {'p_live_id': id},
      );
      if (res == null) return null;
      return LiveStartOpenReservationsReport.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveStartOpenReservations] fetch failed: $e');
      return null;
    }
  }
}

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

int? _asNullableInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
