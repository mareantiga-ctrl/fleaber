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

  String? get bundleId => getField<String>('bundle_id');
  set bundleId(String? value) => setField<String>('bundle_id', value);

  String? get stripeCheckoutSessionId =>
      getField<String>('stripe_checkout_session_id');
  set stripeCheckoutSessionId(String? value) =>
      setField<String>('stripe_checkout_session_id', value);

  String? get stripePaymentIntentId =>
      getField<String>('stripe_payment_intent_id');
  set stripePaymentIntentId(String? value) =>
      setField<String>('stripe_payment_intent_id', value);

  String? get stripeRefundId => getField<String>('stripe_refund_id');
  set stripeRefundId(String? value) =>
      setField<String>('stripe_refund_id', value);

  DateTime? get stripeRefundedAt => getField<DateTime>('stripe_refunded_at');
  set stripeRefundedAt(DateTime? value) =>
      setField<DateTime>('stripe_refunded_at', value);

  /// ZIP 128 — c2c | b2c (snapshot)
  String? get commerceChannel => getField<String>('commerce_channel');
  set commerceChannel(String? value) =>
      setField<String>('commerce_channel', value);

  bool get sellerProfessionalAtPay =>
      getField<bool>('seller_professional_at_pay') == true;

  String? get withdrawalExceptionCode =>
      getField<String>('withdrawal_exception_code');

  DateTime? get consumerWithdrawalDeadlineAt =>
      getField<DateTime>('consumer_withdrawal_deadline_at');

  DateTime? get fundsHoldUntil => getField<DateTime>('funds_hold_until');

  String? get consumerWithdrawalStatus =>
      getField<String>('consumer_withdrawal_status');

  String? get stripeDisputeStatus =>
      getField<String>('stripe_dispute_status');

  bool get isB2cChannel =>
      (commerceChannel ?? '').trim().toLowerCase() == 'b2c';

  String? get deliveryPointRef => getField<String>('delivery_point_ref');
  String? get deliveryPointProvider =>
      getField<String>('delivery_point_provider');
  String? get deliveryPointLabel => getField<String>('delivery_point_label');

  String? get dpdService => getField<String>('dpd_service');
  String? get dpdExpeditionId => getField<String>('dpd_expedition_id');
  String? get dpdTrackingCode => getField<String>('dpd_tracking_code');
  String? get dpdLabelUrl => getField<String>('dpd_label_url');
  String? get dpdLastError => getField<String>('dpd_last_error');
  DateTime? get dpdCreatedAt => getField<DateTime>('dpd_created_at');
  DateTime? get dpdAcceptAt => getField<DateTime>('dpd_accept_at');
  DateTime? get dpdDeliveredAt => getField<DateTime>('dpd_delivered_at');
  double? get shippingWeightKg => getField<double>('shipping_weight_kg');
  String? get shippingWeightBand => getField<String>('shipping_weight_band');
  double? get shippingWeightChargedKg =>
      getField<double>('shipping_weight_charged_kg');
  String? get shippingWeightChargedBand =>
      getField<String>('shipping_weight_charged_band');
  double? get shippingWeightActualKg =>
      getField<double>('shipping_weight_actual_kg');
  String? get shippingWeightActualBand =>
      getField<String>('shipping_weight_actual_band');
  String? get shippingModality => getField<String>('shipping_modality');
  int? get shippingCentsCharged => getField<int>('shipping_cents_charged');
  String? get weightConfirmStatus => getField<String>('weight_confirm_status');
  String? get shippingDeltaStatus => getField<String>('shipping_delta_status');
  DateTime? get weightConfirmDeadlineAt =>
      getField<DateTime>('weight_confirm_deadline_at');
  DateTime? get shipByAt => getField<DateTime>('ship_by_at');
  DateTime? get shipClockPausedAt =>
      getField<DateTime>('ship_clock_paused_at');
  bool get shippingFreeBySeller =>
      getField<bool>('shipping_free_by_seller') == true;
  bool get shippingQuotePending =>
      getField<bool>('shipping_quote_pending') == true;
}
