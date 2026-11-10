import '/backend/supabase/supabase.dart';

/// Resultado normalizado de `batata_resolve_handle`.
class HubHandleResolveResult {
  const HubHandleResolveResult({
    required this.found,
    required this.httpStatus,
    this.handle,
    this.profileId,
    this.hubPublished,
    this.redirectTo,
    this.error,
  });

  final bool found;
  final int httpStatus;
  final String? handle;
  final String? profileId;
  final bool? hubPublished;
  final String? redirectTo;
  final String? error;

  bool get isPublished =>
      found && httpStatus == 200 && hubPublished == true && redirectTo == null;

  bool get needsRedirect =>
      found && redirectTo != null && redirectTo!.trim().isNotEmpty;

  factory HubHandleResolveResult.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const HubHandleResolveResult(
        found: false,
        httpStatus: 404,
        error: 'invalid_response',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    return HubHandleResolveResult(
      found: map['found'] == true,
      httpStatus: (map['http_status'] as num?)?.toInt() ?? 404,
      handle: map['handle']?.toString(),
      profileId: map['profile_id']?.toString(),
      hubPublished: map['hub_published'] as bool?,
      redirectTo: map['redirect_to']?.toString(),
      error: map['error']?.toString(),
    );
  }
}

/// Entrypoint Hub — única RPC de routing (anon OK).
class HubHandleResolver {
  HubHandleResolver._();

  static final Map<String, HubHandleResolveResult> _cache = {};

  static Future<HubHandleResolveResult> resolve(String rawHandle) async {
    final key = rawHandle.trim().toLowerCase();
    if (key.isEmpty) {
      return const HubHandleResolveResult(
        found: false,
        httpStatus: 404,
        error: 'empty_handle',
      );
    }
    final cached = _cache[key];
    if (cached != null) return cached;

    final raw = await SupaFlow.client.rpc(
      'batata_resolve_handle',
      params: {'p_handle': key},
    );
    final result = HubHandleResolveResult.fromRpc(raw);
    _cache[key] = result;
    return result;
  }

  static void clearCache() => _cache.clear();
}
