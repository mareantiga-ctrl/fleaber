import '../database.dart';

class ProfilesTable extends SupabaseTable<ProfilesRow> {
  @override
  String get tableName => 'profiles';

  @override
  ProfilesRow createRow(Map<String, dynamic> data) => ProfilesRow(data);
}

class ProfilesRow extends SupabaseDataRow {
  ProfilesRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => ProfilesTable();

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get fullName => getField<String>('full_name');
  set fullName(String? value) => setField<String>('full_name', value);

  /// Nome legal completo (etiquetas, pagamentos). Distinto de [fullName] (nome na app).
  String? get legalFullName => getField<String>('legal_full_name');
  set legalFullName(String? value) =>
      setField<String>('legal_full_name', value);

  String? get userType => getField<String>('user_type');
  set userType(String? value) => setField<String>('user_type', value);

  String? get phone => getField<String>('phone');
  set phone(String? value) => setField<String>('phone', value);

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get photoUrl => getField<String>('photo_url');
  set photoUrl(String? value) => setField<String>('photo_url', value);

  bool? get isLive => getField<bool>('is_live');
  set isLive(bool? value) => setField<bool>('is_live', value);

  DateTime? get nextLive => getField<DateTime>('next_live');
  set nextLive(DateTime? value) => setField<DateTime>('next_live', value);

  DateTime? get lastLive => getField<DateTime>('last_live');
  set lastLive(DateTime? value) => setField<DateTime>('last_live', value);

  String? get location => getField<String>('location');
  set location(String? value) => setField<String>('location', value);

  int? get totalLives => getField<int>('total_lives');
  set totalLives(int? value) => setField<int>('total_lives', value);

  /// Opcional: colunas `mb_way` / `iban` na tabela `profiles` (Supabase).
  String? get mbWay => getField<String>('mb_way');
  set mbWay(String? value) => setField<String>('mb_way', value);

  String? get iban => getField<String>('iban');
  set iban(String? value) => setField<String>('iban', value);

  bool get externalPaymentsEnabled =>
      getField<bool>('external_payments_enabled') == true;
  set externalPaymentsEnabled(bool? value) =>
      setField<bool>('external_payments_enabled', value);

  String? get shippingLine1 => getField<String>('shipping_line1');
  set shippingLine1(String? value) =>
      setField<String>('shipping_line1', value);

  String? get shippingLine2 => getField<String>('shipping_line2');
  set shippingLine2(String? value) =>
      setField<String>('shipping_line2', value);

  String? get shippingPostalCode => getField<String>('shipping_postal_code');
  set shippingPostalCode(String? value) =>
      setField<String>('shipping_postal_code', value);

  String? get shippingCity => getField<String>('shipping_city');
  set shippingCity(String? value) => setField<String>('shipping_city', value);

  String? get shippingCountry => getField<String>('shipping_country');
  set shippingCountry(String? value) =>
      setField<String>('shipping_country', value);

  DateTime? get phoneVerifiedAt => getField<DateTime>('phone_verified_at');
  set phoneVerifiedAt(DateTime? value) =>
      setField<DateTime>('phone_verified_at', value);

  bool? get vacationMode => getField<bool>('vacation_mode');
  set vacationMode(bool? value) => setField<bool>('vacation_mode', value);
}
