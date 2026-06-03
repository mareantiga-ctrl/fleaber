import '../database.dart';

class OrderDisputesTable extends SupabaseTable<OrderDisputesRow> {
  @override
  String get tableName => 'order_disputes';

  @override
  OrderDisputesRow createRow(Map<String, dynamic> data) =>
      OrderDisputesRow(data);
}

class OrderDisputesRow extends SupabaseDataRow {
  OrderDisputesRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrderDisputesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  String? get reason => getField<String>('reason');
  set reason(String? value) => setField<String>('reason', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  List<String> get proofPhotos {
    final raw = data['proof_photos'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  set proofPhotos(List<String>? value) => data['proof_photos'] = value;

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String get currentTurn => getField<String>('current_turn') ?? 'vendedor';
  set currentTurn(String? value) => setField<String>('current_turn', value);

  DateTime? get nextDeadline => getField<DateTime>('next_deadline');
  set nextDeadline(DateTime? value) =>
      setField<DateTime>('next_deadline', value);

  String? get sellerOfferType => getField<String>('seller_offer_type');
  set sellerOfferType(String? value) =>
      setField<String>('seller_offer_type', value);

  bool get sellerPaysReturnShipping =>
      getField<bool>('seller_pays_return_shipping') == true;
  set sellerPaysReturnShipping(bool? value) =>
      setField<bool>('seller_pays_return_shipping', value);

  double? get sellerRefundPercent {
    final v = data['seller_refund_percent'];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  set sellerRefundPercent(double? value) =>
      setField<double>('seller_refund_percent', value);

  String? get buyerDecision => getField<String>('buyer_decision');
  set buyerDecision(String? value) => setField<String>('buyer_decision', value);

  DateTime? get returnLabelCreatedAt =>
      getField<DateTime>('return_label_created_at');
  set returnLabelCreatedAt(DateTime? value) =>
      setField<DateTime>('return_label_created_at', value);

  DateTime? get returnLabelDeadline =>
      getField<DateTime>('return_label_deadline');
  set returnLabelDeadline(DateTime? value) =>
      setField<DateTime>('return_label_deadline', value);

  String? get returnLabelUrl => getField<String>('return_label_url');
  set returnLabelUrl(String? value) => setField<String>('return_label_url', value);

  String? get adminResolution => getField<String>('admin_resolution');
  set adminResolution(String? value) =>
      setField<String>('admin_resolution', value);

  String? get adminResolutionNote => getField<String>('admin_resolution_note');
  set adminResolutionNote(String? value) =>
      setField<String>('admin_resolution_note', value);

  DateTime? get returnDeliveredAt => getField<DateTime>('return_delivered_at');
  set returnDeliveredAt(DateTime? value) =>
      setField<DateTime>('return_delivered_at', value);

  DateTime? get sellerInspectionDeadline =>
      getField<DateTime>('seller_inspection_deadline');
  set sellerInspectionDeadline(DateTime? value) =>
      setField<DateTime>('seller_inspection_deadline', value);

  DateTime? get sellerReturnIssueAt =>
      getField<DateTime>('seller_return_issue_at');
  set sellerReturnIssueAt(DateTime? value) =>
      setField<DateTime>('seller_return_issue_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
