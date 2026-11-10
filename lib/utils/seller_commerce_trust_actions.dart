import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Phase 5 seller actions — thin wrappers over canonical RPCs (no second engine).
abstract final class SellerCommerceTrustActions {
  static Future<Map<String, dynamic>> setTrust({
    required String buyerId,
    required String mode, // trusted | distrusted | clear
  }) async {
    final sellerId = currentUserUid.trim();
    final bid = buyerId.trim();
    if (sellerId.isEmpty || bid.isEmpty) {
      return {'ok': false, 'error': 'missing_ids'};
    }
    if (bid == sellerId) {
      return {'ok': false, 'error': 'invalid_pair'};
    }
    final res = await SupaFlow.client.rpc(
      'batata_seller_buyer_trust_set',
      params: {
        'p_seller_id': sellerId,
        'p_buyer_id': bid,
        'p_mode': mode,
      },
    );
    return Map<String, dynamic>.from(res as Map? ?? {});
  }

  /// Manual trust + promote eligible pending lines with atomic stock checks.
  static Future<Map<String, dynamic>> trustAndPromote({
    required String buyerId,
    String? liveId,
  }) async {
    final sellerId = currentUserUid.trim();
    final bid = buyerId.trim();
    if (sellerId.isEmpty || bid.isEmpty) {
      return {'ok': false, 'error': 'missing_ids'};
    }
    final res = await SupaFlow.client.rpc(
      'batata_commerce_trust_and_promote',
      params: {
        'p_seller_id': sellerId,
        'p_buyer_id': bid,
        'p_live_id': (liveId ?? '').trim().isEmpty ? null : liveId!.trim(),
      },
    );
    return Map<String, dynamic>.from(res as Map? ?? {});
  }

  static Future<Map<String, dynamic>> extendGuaranteedOnce({
    required String requestId,
    required int ttlSeconds,
  }) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return {'ok': false, 'error': 'missing_request_id'};
    final res = await SupaFlow.client.rpc(
      'batata_commerce_extend_guaranteed_once',
      params: {
        'p_request_id': rid,
        'p_ttl_seconds': ttlSeconds,
      },
    );
    return Map<String, dynamic>.from(res as Map? ?? {});
  }

  /// Local override for this seller (null = auto / no row or clear).
  static Future<String?> fetchLocalTrustMode(String buyerId) async {
    final sellerId = currentUserUid.trim();
    final bid = buyerId.trim();
    if (sellerId.isEmpty || bid.isEmpty) return null;
    final rows = await SupaFlow.client
        .from('seller_buyer_trust')
        .select('mode')
        .eq('seller_id', sellerId)
        .eq('buyer_id', bid)
        .limit(1);
    if (rows.isEmpty) return null;
    return (rows.first as Map)['mode']?.toString();
  }
}
