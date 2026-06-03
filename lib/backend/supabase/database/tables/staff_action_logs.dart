import '../database.dart';

class StaffActionLogsTable extends SupabaseTable<StaffActionLogsRow> {
  @override
  String get tableName => 'staff_action_logs';

  @override
  StaffActionLogsRow createRow(Map<String, dynamic> data) =>
      StaffActionLogsRow(data);
}

class StaffActionLogsRow extends SupabaseDataRow {
  StaffActionLogsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => StaffActionLogsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get performedByUserId => getField<String>('performed_by_user_id');
  set performedByUserId(String? value) =>
      setField<String>('performed_by_user_id', value);

  String? get targetEntity => getField<String>('target_entity');
  set targetEntity(String? value) => setField<String>('target_entity', value);

  String? get targetId => getField<String>('target_id');
  set targetId(String? value) => setField<String>('target_id', value);

  String? get actionType => getField<String>('action_type');
  set actionType(String? value) => setField<String>('action_type', value);

  Map<String, dynamic> get metadataRaw =>
      Map<String, dynamic>.from(data['metadata'] as Map? ?? {});

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
