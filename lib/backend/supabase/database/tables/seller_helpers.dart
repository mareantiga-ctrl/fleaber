import '../database.dart';

class SellerHelpersTable extends SupabaseTable<SellerHelpersRow> {
  @override
  String get tableName => 'seller_helpers';

  @override
  SellerHelpersRow createRow(Map<String, dynamic> data) =>
      SellerHelpersRow(data);
}

class SellerHelpersRow extends SupabaseDataRow {
  SellerHelpersRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => SellerHelpersTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get helperUserId => getField<String>('helper_user_id');
  set helperUserId(String? value) =>
      setField<String>('helper_user_id', value);

  String? get invitedEmail => getField<String>('invited_email');
  set invitedEmail(String? value) => setField<String>('invited_email', value);

  String? get displayName => getField<String>('display_name');
  set displayName(String? value) => setField<String>('display_name', value);

  bool? get active => getField<bool>('active');
  set active(bool? value) => setField<bool>('active', value);

  String? get invitationStatus => getField<String>('invitation_status');
  set invitationStatus(String? value) =>
      setField<String>('invitation_status', value);

  String? get invitationNote => getField<String>('invitation_note');
  set invitationNote(String? value) =>
      setField<String>('invitation_note', value);

  Map<String, dynamic> get permissionsRaw =>
      Map<String, dynamic>.from(data['permissions'] as Map? ?? {});

  DateTime? get respondedAt => getField<DateTime>('responded_at');
  set respondedAt(DateTime? value) => setField<DateTime>('responded_at', value);

  DateTime? get lastActiveAt => getField<DateTime>('last_active_at');
  set lastActiveAt(DateTime? value) =>
      setField<DateTime>('last_active_at', value);

  String? get invitedBy => getField<String>('invited_by');
  set invitedBy(String? value) => setField<String>('invited_by', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);
}
