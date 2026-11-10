import '../database.dart';

class LivesTable extends SupabaseTable<LivesRow> {
  @override
  String get tableName => 'lives';

  /// SEC-003: stream keys revoked — never `select=*` (PostgREST 401).
  @override
  String? get selectColumns =>
      'id,created_at,vendedor_id,playback_id,is_active,title,status,'
      'seller_id,mux_playback_id,publish_backend,livekit_room_name,'
      'mux_asset_id,mux_vod_playback_id,viewer_count,went_live_at,ended_at,'
      'cover_id';

  @override
  LivesRow createRow(Map<String, dynamic> data) => LivesRow(data);
}

class LivesRow extends SupabaseDataRow {
  LivesRow(Map<String, dynamic> data) : super(data);

  @override
  SupabaseTable get table => LivesTable();

  String? get id => getField<String>('id');
  set id(String? value) => setField<String>('id', value);

  DateTime? get createdAt => getField<DateTime>('created_at');
  set createdAt(DateTime? value) => setField<DateTime>('created_at', value);

  String? get vendedorId => getField<String>('vendedor_id');
  set vendedorId(String? value) => setField<String>('vendedor_id', value);

  String? get sellerId {
    final seller = getField<String>('seller_id');
    if (seller != null && seller.isNotEmpty) return seller;
    return vendedorId;
  }

  set sellerId(String? value) => setField<String>('seller_id', value);

  String? get muxLiveId => getField<String>('mux_live_id');
  set muxLiveId(String? value) => setField<String>('mux_live_id', value);

  String? get streamKey => getField<String>('stream_key');
  set streamKey(String? value) => setField<String>('stream_key', value);

  String? get muxStreamKey {
    final key = getField<String>('mux_stream_key');
    if (key != null && key.isNotEmpty) return key;
    return streamKey;
  }

  set muxStreamKey(String? value) => setField<String>('mux_stream_key', value);

  String? get playbackId => getField<String>('playback_id');
  set playbackId(String? value) => setField<String>('playback_id', value);

  String? get muxPlaybackId {
    final id = getField<String>('mux_playback_id');
    if (id != null && id.isNotEmpty) return id;
    return playbackId;
  }

  set muxPlaybackId(String? value) => setField<String>('mux_playback_id', value);

  bool? get isActive => getField<bool>('is_active');
  set isActive(bool? value) => setField<bool>('is_active', value);

  String? get title => getField<String>('title');
  set title(String? value) => setField<String>('title', value);

  String? get status => getField<String>('status');
  set status(String? value) => setField<String>('status', value);

  String? get publishBackend => getField<String>('publish_backend');
  set publishBackend(String? value) =>
      setField<String>('publish_backend', value);

  String? get livekitRoomName => getField<String>('livekit_room_name');
  set livekitRoomName(String? value) =>
      setField<String>('livekit_room_name', value);

  String? get livekitEgressId => getField<String>('livekit_egress_id');
  set livekitEgressId(String? value) =>
      setField<String>('livekit_egress_id', value);

  String? get muxAssetId => getField<String>('mux_asset_id');
  set muxAssetId(String? value) => setField<String>('mux_asset_id', value);

  String? get muxVodPlaybackId => getField<String>('mux_vod_playback_id');
  set muxVodPlaybackId(String? value) =>
      setField<String>('mux_vod_playback_id', value);

  DateTime? get wentLiveAt => getField<DateTime>('went_live_at');
  set wentLiveAt(DateTime? value) => setField<DateTime>('went_live_at', value);

  /// Capa Fleaber estável (`fleaber_capa_NN`). Null se coluna ainda não migrada.
  String? get coverId => getField<String>('cover_id');
  set coverId(String? value) => setField<String>('cover_id', value);
}
