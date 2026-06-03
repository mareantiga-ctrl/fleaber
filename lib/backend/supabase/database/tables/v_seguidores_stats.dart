import '../database.dart';

class VSeguidoresStatsTable extends SupabaseTable<VSeguidoresStatsRow> {
  @override
  String get tableName => 'v_seguidores_stats';

  @override
  VSeguidoresStatsRow createRow(Map<String, dynamic> data) =>
      VSeguidoresStatsRow(data);
}

class VSeguidoresStatsRow extends SupabaseDataRow {
  VSeguidoresStatsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => VSeguidoresStatsTable();

  String? get profileId => getField<String>('profile_id');
  set profileId(String? value) => setField<String>('profile_id', value);

  int? get totalSeguidores => getField<int>('total_seguidores');
  set totalSeguidores(int? value) => setField<int>('total_seguidores', value);
}
