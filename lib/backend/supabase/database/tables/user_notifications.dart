import '../database.dart';

class UserNotificationsTable extends SupabaseTable<UserNotificationsRow> {
  @override
  String get tableName => 'user_notifications';

  @override
  UserNotificationsRow createRow(Map<String, dynamic> data) =>
      UserNotificationsRow(data);
}

class UserNotificationsRow extends SupabaseDataRow {
  UserNotificationsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => UserNotificationsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get userId => getField<String>('user_id');
  set userId(String? value) => setField<String>('user_id', value);

  String? get kind => getField<String>('kind');
  set kind(String? value) => setField<String>('kind', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  String? get body => getField<String>('body');
  set body(String? value) => setField<String>('body', value);

  String? get chatId => getField<String>('chat_id');
  set chatId(String? value) => setField<String>('chat_id', value);

  String? get productId => getField<String>('product_id');
  set productId(String? value) => setField<String>('product_id', value);

  String? get offerId => getField<String>('offer_id');
  set offerId(String? value) => setField<String>('offer_id', value);

  String? get actorId => getField<String>('actor_id');
  set actorId(String? value) => setField<String>('actor_id', value);

  bool? get isRead => getField<bool>('is_read');
  set isRead(bool? value) => setField<bool>('is_read', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  /// Anti-duplicados (ponto 7). Null em rows antigas.
  String? get dedupeKey => getField<String>('dedupe_key');
  set dedupeKey(String? value) => setField<String>('dedupe_key', value);
}
