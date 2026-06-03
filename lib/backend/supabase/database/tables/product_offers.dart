import '../database.dart';

class ProductOffersTable extends SupabaseTable<ProductOffersRow> {
  @override
  String get tableName => 'product_offers';

  @override
  ProductOffersRow createRow(Map<String, dynamic> data) => ProductOffersRow(data);
}

class ProductOffersRow extends SupabaseDataRow {
  ProductOffersRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ProductOffersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get productId => getField<String>('product_id');
  set productId(String? value) => setField<String>('product_id', value);

  String? get chatId => getField<String>('chat_id');
  set chatId(String? value) => setField<String>('chat_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  double? get amount {
    final v = data['amount'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  set amount(double? value) => setField<double>('amount', value);

  double? get listPrice {
    final v = data['list_price'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  set listPrice(double? value) => setField<double>('list_price', value);

  String? get offeredBy => getField<String>('offered_by');
  set offeredBy(String? value) => setField<String>('offered_by', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get parentOfferId => getField<String>('parent_offer_id');
  set parentOfferId(String? value) => setField<String>('parent_offer_id', value);

  DateTime? get expiresAt => getField<DateTime>('expires_at');
  set expiresAt(DateTime? value) => setField<DateTime>('expires_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get respondedAt => getField<DateTime>('responded_at');
  set respondedAt(DateTime? value) => setField<DateTime>('responded_at', value);
}
