import '../database.dart';

class ReviewsTable extends SupabaseTable<ReviewsRow> {
  @override
  String get tableName => 'reviews';

  @override
  ReviewsRow createRow(Map<String, dynamic> data) => ReviewsRow(data);
}

class ReviewsRow extends SupabaseDataRow {
  ReviewsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ReviewsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get targetId => getField<String>('target_id');
  set targetId(String? value) => setField<String>('target_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  int? get stars => getField<int>('stars');
  set stars(int? value) => setField<int>('stars', value);

  String? get comment => getField<String>('comment');
  set comment(String? value) => setField<String>('comment', value);

  bool? get isAutomatic => getField<bool>('is_automatic');
  set isAutomatic(bool? value) => setField<bool>('is_automatic', value);

  String? get targetType => getField<String>('target_type');
  set targetType(String? value) => setField<String>('target_type', value);

  String? get authorRole => getField<String>('author_role');
  set authorRole(String? value) => setField<String>('author_role', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);
}
