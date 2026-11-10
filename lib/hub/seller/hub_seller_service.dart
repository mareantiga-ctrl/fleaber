import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

import 'hub_seller_state.dart';

/// RPCs handle/Hub seller — `batata_*` (authenticated).
class HubSellerService {
  HubSellerService({SupabaseClient? client})
      : _client = client ?? SupaFlow.client;

  final SupabaseClient _client;

  String get _authenticatedProfileId {
    final fromSession = _client.auth.currentUser?.id?.trim();
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;
    return currentUserUid.trim();
  }

  Future<HubSellerStatus?> fetchStatus([String? profileId]) async {
    final id = (profileId ?? _authenticatedProfileId).trim();
    if (id.isEmpty) return null;
    final row = await _client
        .from('profiles')
        .select(
          'id, full_name, handle, handle_suggested, hub_published, phone_verified_at',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return HubSellerStatus.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<String>> suggestHandles({String? seed, int limit = 5}) async {
    final uid = _authenticatedProfileId;
    if (uid.isEmpty) return const [];
    final raw = await _client.rpc(
      'batata_suggest_handles',
      params: {
        'p_seed': seed?.trim(),
        'p_profile_id': uid,
        'p_limit': limit,
      },
    );
    if (raw is! Map) return const [];
    final list = raw['suggestions'];
    if (list is! List) return const [];
    return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  Future<HubSellerActionResult> claimHandle(String handle) async {
    try {
      final normalized = _normalizeHandle(handle);
      if (normalized.length < 3) {
        return const HubSellerActionResult(
          ok: false,
          errorCode: 'handle_invalid',
          errorMessage: 'Mínimo 3 caracteres.',
        );
      }
      final raw = await _client.rpc(
        'batata_claim_handle',
        params: {'p_handle': normalized},
      );
      final result = HubSellerActionResult.fromRpc(raw);
      if (!result.ok && result.validationReasons.isNotEmpty) {
        return HubSellerActionResult(
          ok: false,
          errorCode: result.errorCode,
          errorMessage: HubSellerErrorMessages.fromCode(
            result.errorCode,
            validationReasons: result.validationReasons,
          ),
          validationReasons: result.validationReasons,
        );
      }
      return result;
    } catch (e) {
      return HubSellerActionResult.fromException(e);
    }
  }

  Future<HubSellerActionResult> changeHandle(String newHandle) async {
    try {
      final normalized = _normalizeHandle(newHandle);
      final raw = await _client.rpc(
        'batata_change_handle',
        params: {'p_new_handle': normalized},
      );
      final result = HubSellerActionResult.fromRpc(raw);
      if (!result.ok && result.validationReasons.isNotEmpty) {
        return HubSellerActionResult(
          ok: false,
          errorCode: result.errorCode,
          errorMessage: HubSellerErrorMessages.fromCode(
            result.errorCode,
            validationReasons: result.validationReasons,
          ),
          validationReasons: result.validationReasons,
        );
      }
      return result;
    } catch (e) {
      return HubSellerActionResult.fromException(e);
    }
  }

  Future<HubSellerActionResult> publishHub({required bool publish}) async {
    try {
      final raw = await _client.rpc(
        'batata_publish_hub',
        params: {'p_publish': publish},
      );
      return HubSellerActionResult.fromRpc(raw);
    } catch (e) {
      return HubSellerActionResult.fromException(e);
    }
  }

  static String _normalizeHandle(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'^@+'), '');
  }
}
