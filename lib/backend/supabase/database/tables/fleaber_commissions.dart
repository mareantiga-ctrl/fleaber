import '../database.dart';

class FleaberCommissionsTable extends SupabaseTable<FleaberCommissionsRow> {
  @override
  String get tableName => 'fleaber_commissions';

  @override
  FleaberCommissionsRow createRow(Map<String, dynamic> data) =>
      FleaberCommissionsRow(data);
}

class FleaberCommissionsRow extends SupabaseDataRow {
  FleaberCommissionsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => FleaberCommissionsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);

  double get amount {
    final v = data['amount'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  set amount(double value) => setField<double>('amount', value);

  String? get source => getField<String>('source');
  set source(String? value) => setField<String>('source', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
