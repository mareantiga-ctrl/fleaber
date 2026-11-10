import '../database.dart';

class LiveReservationRequestsTable
    extends SupabaseTable<LiveReservationRequestsRow> {
  @override
  String get tableName => 'live_reservation_requests';

  @override
  LiveReservationRequestsRow createRow(Map<String, dynamic> data) =>
      LiveReservationRequestsRow(data);
}

class LiveReservationRequestsRow extends SupabaseDataRow {
  LiveReservationRequestsRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LiveReservationRequestsTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  String? get liveId => getField<String>('live_id');
  set liveId(String? value) => setField<String>('live_id', value);

  String? get liveItemId => getField<String>('live_item_id');
  set liveItemId(String? value) => setField<String>('live_item_id', value);

  String? get sellerId => getField<String>('seller_id');
  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get buyerId => getField<String>('buyer_id');
  set buyerId(String? value) => setField<String>('buyer_id', value);

  int get requestedQty => getField<int>('requested_qty') ?? 1;
  set requestedQty(int value) => setField<int>('requested_qty', value);

  int? get queuePosition => getField<int>('queue_position');
  set queuePosition(int? value) => setField<int>('queue_position', value);

  String get source => getField<String>('source') ?? 'fleaber_live';
  set source(String? value) => setField<String>('source', value);

  String get status => getField<String>('status') ?? 'pending';
  set status(String? value) => setField<String>('status', value);

  String? get notes => getField<String>('notes');
  set notes(String? value) => setField<String>('notes', value);

  String? get processedByUserId => getField<String>('processed_by_user_id');
  set processedByUserId(String? value) =>
      setField<String>('processed_by_user_id', value);

  DateTime? get expiresAt => getField<DateTime>('expires_at');
  set expiresAt(DateTime? value) => setField<DateTime>('expires_at', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  DateTime? get updatedAt => getField<DateTime>('updated_at');
  set updatedAt(DateTime? value) => setField<DateTime>('updated_at', value);

  DateTime? get effectiveAt => getField<DateTime>('effective_at');
  DateTime? get detectedAt => getField<DateTime>('detected_at');
  String? get externalDisplayName =>
      getField<String>('external_display_name');
  String? get externalBuyerRef => getField<String>('external_buyer_ref');
  String? get ocrRawLine => getField<String>('ocr_raw_line');
  String? get ingestChannel => getField<String>('ingest_channel');
  String? get ingestStatus => getField<String>('ingest_status');
  double? get ingestConfidence {
    final v = getField<Object>('ingest_confidence');
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? get ocrConfidence => _numField('ocr_confidence');
  double? get parserConfidence => _numField('parser_confidence');
  double? get itemMatchConfidence => _numField('item_match_confidence');
  double? get identityConfidence => _numField('identity_confidence');
  String? get resolvedRefSlug => getField<String>('resolved_ref_slug');
  String? get resolvedMatchType => getField<String>('resolved_match_type');
  String? get parserIntent => getField<String>('parser_intent');
  String? get deviceId => getField<String>('device_id');

  double? _numField(String name) {
    final v = getField<Object>(name);
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  bool get isPsNeedsReview => (ingestStatus ?? '').trim() == 'needs_review';
  bool get isPsOcrIngest => (ingestChannel ?? '').trim() == 'ocr';

  /// Phase 1/2 commerce kind: approval_pending | bag_hold_none | guaranteed.
  String? get requestKind => getField<String>('request_kind');
  set requestKind(String? value) => setField<String>('request_kind', value);

  String get requestKindOrDefault =>
      (requestKind ?? '').trim().isEmpty ? 'approval_pending' : requestKind!.trim();

  int? get ttlSecondsSnapshot => getField<int>('ttl_seconds_snapshot');
  String? get policyModeSnapshot => getField<String>('policy_mode_snapshot');
  String? get trustDecisionSnapshot =>
      getField<String>('trust_decision_snapshot');
  String? get sourceChannel => getField<String>('source_channel');
  String? get guestSessionId => getField<String>('guest_session_id');

  /// One-time seller extension of a guaranteed hold (Phase 2+).
  bool get extendedOnce => getField<bool>('extended_once') ?? false;
}
