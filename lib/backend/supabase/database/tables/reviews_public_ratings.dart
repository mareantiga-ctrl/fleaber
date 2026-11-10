import '../database.dart';

/// View pública de reputação (sem buyer_id / order_id).
class ReviewsPublicRatingsTable
    extends SupabaseTable<ReviewsPublicRatingsRow> {
  @override
  String get tableName => 'reviews_public_ratings';

  @override
  ReviewsPublicRatingsRow createRow(Map<String, dynamic> data) =>
      ReviewsPublicRatingsRow(data);
}

class ReviewsPublicRatingsRow extends SupabaseDataRow {
  ReviewsPublicRatingsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ReviewsPublicRatingsTable();

  String? get id => getField<String>('id');
  DateTime? get createdAt => getField<DateTime>('created_at');
  String? get targetId => getField<String>('target_id');
  int? get stars => getField<int>('stars');
  String? get comment => getField<String>('comment');
  bool? get isAutomatic => getField<bool>('is_automatic');
  String? get targetType => getField<String>('target_type');
  String? get authorRole => getField<String>('author_role');
}
