import '../database.dart';

class FollowsTable extends SupabaseTable<FollowsRow> {
  @override
  String get tableName => 'follows';

  @override
  FollowsRow createRow(Map<String, dynamic> data) => FollowsRow(data);
}

class FollowsRow extends SupabaseDataRow {
  FollowsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => FollowsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get followerId => getField<String>('follower_id');
  set followerId(String? value) => setField<String>('follower_id', value);

  String? get followingId => getField<String>('following_id');
  set followingId(String? value) => setField<String>('following_id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
