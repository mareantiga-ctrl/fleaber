import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Encomenda com valor ainda retido na carteira (antes de libertação).
class WalletRetainedOrder {
  const WalletRetainedOrder({
    required this.order,
    this.product,
  });

  final OrdersRow order;
  final ProductsRow? product;

  double get amountEur => order.priceTotal ?? 0;

  String get statusLabel => _statusLabel(order.status);

  String get productTitle =>
      product?.title?.trim().isNotEmpty == true ? product!.title! : 'Artigo';

  String? get thumbUrl =>
      product != null && product!.imageUrls.isNotEmpty
          ? product!.imageUrls.first
          : null;

  static String _statusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'pago':
        return 'Aguarda envio';
      case 'enviado':
        return 'Aguarda confirmação do comprador';
      case 'em_devolucao':
        return 'Disputa em curso';
      default:
        return status ?? 'Em processamento';
    }
  }
}

Future<List<WalletRetainedOrder>> loadWalletRetainedOrders() async {
  if (currentUserUid.isEmpty) return const [];

  final orders = await OrdersTable().queryRows(
    queryFn: (q) => q
        .eqOrNull('seller_id', currentUserUid)
        .inFilter('status', ['pago', 'enviado', 'em_devolucao'])
        .order('created_at', ascending: false),
    limit: 200,
  );

  final retained = orders
      .where((o) => o.data['wallet_release_processed_at'] == null)
      .toList();
  if (retained.isEmpty) return const [];

  final productIds = retained
      .map((o) => o.productId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  final products = productIds.isEmpty
      ? const <ProductsRow>[]
      : await ProductsTable().queryRows(
          queryFn: (q) => q.inFilter('id', productIds),
          limit: productIds.length,
        );
  final productById = {for (final p in products) if (p.id != null) p.id!: p};

  return retained
      .map(
        (o) => WalletRetainedOrder(
          order: o,
          product: o.productId != null ? productById[o.productId] : null,
        ),
      )
      .toList();
}
