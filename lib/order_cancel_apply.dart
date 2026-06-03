import '/backend/supabase/supabase.dart';
import '/batata_reservation_actions.dart';
import '/order_cancel_eligibility.dart';
import '/recolocar_ref_code.dart';

/// Anula a encomenda, marca o artigo original como vendido e republica cópia no marketplace (ref base/N).
/// Só o `sellerId` da encomenda pode executar.
Future<void> applyOrderCancelAndRelist({
  required String orderId,
  required String sellerUserId,
}) async {
  final orderRows = await OrdersTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', orderId),
  );
  if (orderRows.isEmpty) {
    throw Exception('Encomenda não encontrada.');
  }
  final order = orderRows.first;
  if (order.sellerId != sellerUserId) {
    throw Exception('Sem permissão.');
  }
  if (orderIsCancelled(order.status)) {
    throw Exception('Esta encomenda já está cancelada.');
  }

  // Pedido de reserva pendente: só cancelar (sem republicar artigo no marketplace).
  if (normalizeOrderStatusKey(order.status) == 'reserva_pendente') {
    print('BATATA_CANCEL_RELIST reserva_pendente -> cancelado order=$orderId');
    await batataPatchOrderById(
      orderId: orderId,
      patch: {'status': 'cancelado'},
      requireStatusKey: 'reserva_pendente',
    );
    await assertOrderCancelled(orderId);
    return;
  }

  final productId = order.productId;
  if (productId == null || productId.isEmpty) {
    throw Exception('Encomenda sem artigo.');
  }
  final prows = await ProductsTable().querySingleRow(
    queryFn: (q) => q.eqOrNull('id', productId),
  );
  if (prows.isEmpty) throw Exception('Artigo não encontrado.');
  final source = prows.first;
  if (source.title == null ||
      source.title!.trim().isEmpty ||
      source.price == null) {
    throw Exception('Dados do artigo incompletos.');
  }
  final sellerId = order.sellerId;
  if (sellerId == null || sellerId.isEmpty) {
    throw Exception('Vendedor inválido.');
  }

  print('BATATA_CANCEL_RELIST cancel+relist order=$orderId');
  await batataPatchOrderById(
    orderId: orderId,
    patch: {'status': 'cancelado'},
  );
  await assertOrderCancelled(orderId);

  await insertRelistedProductFromSource(source: source, sellerId: sellerId);
  await ProductsTable().update(
    data: {'is_sold': true},
    matchingRows: (rows) => rows.eqOrNull('id', productId),
  );
}
