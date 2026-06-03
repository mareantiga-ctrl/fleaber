import '../database.dart';

class ProductsTable extends SupabaseTable<ProductsRow> {
  @override
  String get tableName => 'products';

  @override
  ProductsRow createRow(Map<String, dynamic> data) => ProductsRow(data);
}

class ProductsRow extends SupabaseDataRow {
  ProductsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ProductsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  String? get refCode => data['ref_code'];
  set refCode(String? value) => data['ref_code'] = value;

  String? get clothingSize => data['clothing_size'];
  set clothingSize(String? value) => data['clothing_size'] = value;

  String? get gender => data['gender'];
  set gender(String? value) => data['gender'] = value;

  double? get price {
    final p = data['price'];
    if (p == null) return null;
    if (p is num) return p.toDouble();
    if (p is String) return double.tryParse(p);
    return null;
  }

  set price(double? value) => setField<double>('price', value);

  List<String> get imageUrls {
    final raw = data['image_urls'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  set imageUrls(List<String>? value) => data['image_urls'] = value;

  String? get category => getField<String>('category');
  set category(String? value) => setField<String>('category', value);

  String? get state => data['state'];
  set state(String? value) => data['state'] = value;

  int get favoritesCount {
    final v = data['favorites_count'];
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  set favoritesCount(int? value) => data['favorites_count'] = value;

  String? get description => getField<String>('description');
  set description(String? value) => setField<String>('description', value);

  bool? get listOnMarketplace => getField<bool>('list_on_marketplace');
  set listOnMarketplace(bool? value) => setField<bool>('list_on_marketplace', value);

  bool get isSold => getField<bool>('is_sold') == true;
  set isSold(bool? value) => setField<bool>('is_sold', value);

  bool? get availableForLive => getField<bool>('available_for_live');
  set availableForLive(bool? value) => setField<bool>('available_for_live', value);

  int get quantity {
    final v = data['quantity'];
    if (v == null) return 1;
    if (v is int) return v < 1 ? 1 : v;
    if (v is num) return v.toInt() < 1 ? 1 : v.toInt();
    final parsed = int.tryParse('$v') ?? 1;
    return parsed < 1 ? 1 : parsed;
  }
  set quantity(int? value) => data['quantity'] = value;

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);
}
