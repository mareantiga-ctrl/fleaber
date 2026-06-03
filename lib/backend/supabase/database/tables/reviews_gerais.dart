import '../database.dart';

class ReviewsGeraisTable extends SupabaseTable<ReviewsGeraisRow> {
  @override
  String get tableName => 'reviews_gerais';

  @override
  ReviewsGeraisRow createRow(Map<String, dynamic> data) =>
      ReviewsGeraisRow(data);
}

class ReviewsGeraisRow extends SupabaseDataRow {
  ReviewsGeraisRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ReviewsGeraisTable();

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
}
