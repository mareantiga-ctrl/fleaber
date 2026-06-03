import '../database.dart';

class WalletsTable extends SupabaseTable<WalletsRow> {
  @override
  String get tableName => 'wallets';

  @override
  WalletsRow createRow(Map<String, dynamic> data) => WalletsRow(data);
}

class WalletsRow extends SupabaseDataRow {
  WalletsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => WalletsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get stripeAccountId => getField<String>('stripe_account_id');
  set stripeAccountId(String? value) =>
      setField<String>('stripe_account_id', value);

  double get balance {
    final v = data['balance'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  set balance(double value) => setField<double>('balance', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
