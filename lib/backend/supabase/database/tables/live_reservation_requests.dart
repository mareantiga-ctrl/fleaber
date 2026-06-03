import '../database.dart';

class LiveReservationRequestsTable
    extends SupabaseTable<LiveReservationRequestsRow> {
  @override
  String get tableName => 'live_reservation_requests';

  @override
  LiveReservationRequestsRow createRow(Map<String, dynamic> data) =>
      LiveReservationRequestsRow(data);
}

class LiveReservationRequestsRow extends SupabaseDataRow {
  LiveReservationRequestsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LiveReservationRequestsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get liveId => getField<String>('live_id');
  set liveId(String? value) => setField<String>('live_id', value);

  String? get liveItemId => getField<String>('live_item_id');
  set liveItemId(String? value) => setField<String>('live_item_id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  int get requestedQty => getField<int>('requested_qty') ?? 1;
  set requestedQty(int value) => setField<int>('requested_qty', value);

  int? get queuePosition => getField<int>('queue_position');
  set queuePosition(int? value) => setField<int>('queue_position', value);

  String get source => getField<String>('source') ?? 'fleaber_live';
  set source(String? value) => setField<String>('source', value);

  String get status => getField<String>('status') ?? 'pending';
  set status(String? value) => setField<String>('status', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  String? get processedByUserId => getField<String>('processed_by_user_id');
  set processedByUserId(String? value) =>
      setField<String>('processed_by_user_id', value);

  DateTime? get expiresAt => getField<DateTime>('expires_at');
  set expiresAt(DateTime? value) => setField<DateTime>('expires_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
