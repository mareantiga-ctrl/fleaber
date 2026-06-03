import '../database.dart';

class LiveItemShowEventsTable extends SupabaseTable<LiveItemShowEventsRow> {
  @override
  String get tableName => 'live_item_show_events';

  @override
  LiveItemShowEventsRow createRow(Map<String, dynamic> data) =>
      LiveItemShowEventsRow(data);
}

class LiveItemShowEventsRow extends SupabaseDataRow {
  LiveItemShowEventsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LiveItemShowEventsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get liveId => getField<String>('live_id');
  set liveId(String? value) => setField<String>('live_id', value);

  String? get liveItemId => getField<String>('live_item_id');
  set liveItemId(String? value) => setField<String>('live_item_id', value);

  DateTime? get shownAt => getField<DateTime>('shown_at');
  set shownAt(DateTime? value) => setField<DateTime>('shown_at', value);
}
