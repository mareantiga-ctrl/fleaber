import '/backend/supabase/database/tables/orders.dart';
import '/utils/live_raffle_prize_copy.dart';

/// Resumo humano da modalidade de envio + ponto Pickup do **comprador**.
/// Não descreve o ponto onde o vendedor deposita o volume (fora do contrato UI).
List<String> orderBuyerDeliveryDetailLines(OrdersRow order) {
  final method = (order.shippingMethod ?? '').trim();
  if (method.isEmpty) return const [];

  if (LiveRafflePrizeCopy.isHandShippingMethod(method)) {
    return const ['Entrega: em mão'];
  }

  final isCarrier = method == 'carrier' ||
      method.toLowerCase().contains('dpd') ||
      method.toLowerCase().contains('transport');
  if (!isCarrier) return const [];

  final modality = (order.shippingModality ?? order.dpdService ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_');
  final point = (order.deliveryPointLabel ?? '').trim();
  final ref = (order.deliveryPointRef ?? '').trim();

  final isPickup = point.isNotEmpty ||
      modality == 'shop_to_shop' ||
      modality == 's2s' ||
      modality.contains('shop_to_shop') ||
      modality.contains('pickup');
  final isHome = modality == 'shop_to_home' ||
      modality == 's2h' ||
      modality.contains('shop_to_home') ||
      modality.contains('home');

  if (isPickup) {
    final lines = <String>['Envio: DPD Pickup (loja)'];
    if (point.isNotEmpty) lines.add('Ponto de levantamento: $point');
    if (ref.isNotEmpty) lines.add('Cód. ponto: $ref');
    return lines;
  }
  if (isHome || modality.isEmpty) {
    return const ['Envio: DPD para casa'];
  }
  return const ['Envio: DPD'];
}
