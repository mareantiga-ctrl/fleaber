import '../database.dart';

class OrdersTable extends SupabaseTable<OrdersRow> {
  @override
  String get tableName => 'orders';

  @override
  OrdersRow createRow(Map<String, dynamic> data) => OrdersRow(data);
}

class OrdersRow extends SupabaseDataRow {
  OrdersRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrdersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get productId => getField<String>('product_id');
  set productId(String? value) => setField<String>('product_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  double? get priceTotal {
    final p = data['price_total'];
    if (p == null) return null;
    if (p is num) return p.toDouble();
    if (p is String) return double.tryParse(p);
    return null;
  }

  set priceTotal(double? value) => setField<double>('price_total', value);

  String? get shippingMethod => getField<String>('shipping_method');
  set shippingMethod(String? value) => setField<String>('shipping_method', value);

  String? get paymentMethod => getField<String>('payment_method');
  set paymentMethod(String? value) => setField<String>('payment_method', value);

  String? get proofUrl => getField<String>('proof_url');
  set proofUrl(String? value) => setField<String>('proof_url', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  DateTime? get reservationExpiresAt =>
      getField<DateTime>('reservation_expires_at');
  set reservationExpiresAt(DateTime? value) =>
      setField<DateTime>('reservation_expires_at', value);

  bool get isReservation => getField<bool>('is_reservation') == true;
  set isReservation(bool? value) => setField<bool>('is_reservation', value);

  int get quantity {
    final q = data['quantity'];
    if (q == null) return 1;
    if (q is int) return q < 1 ? 1 : q;
    if (q is num) return q.toInt() < 1 ? 1 : q.toInt();
    final parsed = int.tryParse('$q') ?? 1;
    return parsed < 1 ? 1 : parsed;
  }
  set quantity(int? value) => data['quantity'] = value;

  String? get productOfferId => getField<String>('product_offer_id');
  set productOfferId(String? value) =>
      setField<String>('product_offer_id', value);

  String? get liveId => getField<String>('live_id');
  set liveId(String? value) => setField<String>('live_id', value);

  String? get liveItemId => getField<String>('live_item_id');
  set liveItemId(String? value) => setField<String>('live_item_id', value);
}
