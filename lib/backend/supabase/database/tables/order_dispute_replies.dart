import '../database.dart';

class OrderDisputeRepliesTable
    extends SupabaseTable<OrderDisputeRepliesRow> {
  @override
  String get tableName => 'order_dispute_replies';

  @override
  OrderDisputeRepliesRow createRow(Map<String, dynamic> data) =>
      OrderDisputeRepliesRow(data);
}

class OrderDisputeRepliesRow extends SupabaseDataRow {
  OrderDisputeRepliesRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => OrderDisputeRepliesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get disputeId => getField<String>('dispute_id');
  set disputeId(String? value) => setField<String>('dispute_id', value);

  String? get senderId => getField<String>('sender_id');
  set senderId(String? value) => setField<String>('sender_id', value);

  String? get message => getField<String>('message');
  set message(String? value) => setField<String>('message', value);

  List<String> get proofPhotos {
    final raw = data['proof_photos'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  set proofPhotos(List<String>? value) => data['proof_photos'] = value;

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
