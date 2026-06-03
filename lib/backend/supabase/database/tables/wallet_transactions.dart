import '../database.dart';

class WalletTransactionsTable extends SupabaseTable<WalletTransactionsRow> {
  @override
  String get tableName => 'wallet_transactions';

  @override
  WalletTransactionsRow createRow(Map<String, dynamic> data) =>
      WalletTransactionsRow(data);
}

class WalletTransactionsRow extends SupabaseDataRow {
  WalletTransactionsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => WalletTransactionsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get walletId => getField<String>('wallet_id');
  set walletId(String? value) => setField<String>('wallet_id', value);

  double get amount {
    final v = data['amount'];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  set amount(double value) => setField<double>('amount', value);

  String? get type => getField<String>('type');
  set type(String? value) => setField<String>('type', value);

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get orderId => getField<String>('order_id');
  set orderId(String? value) => setField<String>('order_id', value);
}
