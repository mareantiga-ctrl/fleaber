import '../database.dart';

class AppLogsTable extends SupabaseTable<AppLogsRow> {
  @override
  String get tableName => 'app_logs';

  @override
  AppLogsRow createRow(Map<String, dynamic> data) => AppLogsRow(data);
}

class AppLogsRow extends SupabaseDataRow {
  AppLogsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => AppLogsTable();

  String? get id => getField<String>('id');
  DateTime? get createdAt => getField<DateTime>('created_at');
  Map<String, dynamic>? get deviceInfo =>
      getField<Map<String, dynamic>>('device_info');
  String? get errorMessage => getField<String>('error_message');
  String? get stackTrace => getField<String>('stack_trace');
  String? get category => getField<String>('category');
}
