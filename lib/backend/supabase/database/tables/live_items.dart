import '../database.dart';

class LiveItemsTable extends SupabaseTable<LiveItemsRow> {
  @override
  String get tableName => 'live_items';

  @override
  LiveItemsRow createRow(Map<String, dynamic> data) => LiveItemsRow(data);
}

class LiveItemsRow extends SupabaseDataRow {
  LiveItemsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LiveItemsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get liveId => getField<String>('live_id');
  set liveId(String? value) => setField<String>('live_id', value);

  /// Código de referência (obrigatório na UI).
  String? get refCode => getField<String>('ref_code');
  set refCode(String? value) => setField<String>('ref_code', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  String? get photoUrl => getField<String>('photo_url');
  set photoUrl(String? value) => setField<String>('photo_url', value);

  bool? get isActive => getField<bool>('is_active');
  set isActive(bool? value) => setField<bool>('is_active', value);

  /// Estado operacional de reserva no contexto da live.
  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  double? get price {
    final p = data['price'];
    if (p == null) return null;
    if (p is num) return p.toDouble();
    if (p is String) return double.tryParse(p);
    return null;
  }

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get itemKind => getField<String>('item_kind');
  set itemKind(String? value) => setField<String>('item_kind', value);

  String? get productId => getField<String>('product_id');
  set productId(String? value) => setField<String>('product_id', value);

  String? get checkoutProductId => getField<String>('checkout_product_id');
  set checkoutProductId(String? value) =>
      setField<String>('checkout_product_id', value);

  int? get quantity {
    final v = data['quantity'];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  set quantity(int? value) => data['quantity'] = value;

  String? get clothingSize => getField<String>('clothing_size');
  set clothingSize(String? value) => setField<String>('clothing_size', value);

  String? get gender => getField<String>('gender');
  set gender(String? value) => setField<String>('gender', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  bool get isMarketplaceProduct =>
      (itemKind ?? '').trim() == 'marketplace_product' && productId != null;

  bool get isLiveOnly =>
      (itemKind ?? '').trim() == 'live_only' || productId == null;
}
