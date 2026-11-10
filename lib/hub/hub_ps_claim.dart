import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';

/// Resultado do claim PS/Facebook («São as minhas»).
class HubPsClaimResult {
  const HubPsClaimResult({
    required this.claimed,
    this.ok = true,
    this.error,
    this.claimedFb = 0,
    this.claimedLegacy = 0,
    this.hasFacebookIdentity = false,
    this.hint,
  });

  final bool ok;
  final int claimed;
  final int claimedFb;
  final int claimedLegacy;
  final bool hasFacebookIdentity;
  final String? error;
  final String? hint;

  bool get needsFacebookLogin => error == 'facebook_login_required';
}

/// Liga reservas PS/Facebook órfãs ao utilizador autenticado.
///
/// Binding seguro (SEC-013) — **só após GATE 1 = SIM** (DOM id ↔ OAuth provider_id):
/// - reservas `fb:{id}` → só se `auth.identities` Facebook `provider_id` coincidir;
/// - reservas legacy `sess:…` → ainda por nome;
/// - **nunca** claima `fb:` / `fb:u:` por igualdade de nome.
///
/// SQL definitivo: `sec_013_claim_fb_identity_batata.sql` (provisório até GATE 1).
/// Ver `14_AUDITOR_GATES_DOM_VS_OAUTH.md`.
abstract final class HubPsClaim {
  /// Evita esgotar rate limit (poll Hub 15s + saco 5s).
  static const _minInterval = Duration(seconds: 45);
  static final Map<String, DateTime> _lastClaimAt = {};

  static Future<int> claimForLive(
    String liveId, {
    bool force = false,
  }) async {
    final r = await claimForLiveDetailed(liveId, force: force);
    return r.claimed;
  }

  static Future<HubPsClaimResult> claimForLiveDetailed(
    String liveId, {
    bool force = false,
  }) async {
    if (currentUserUid.isEmpty || liveId.trim().isEmpty) {
      return const HubPsClaimResult(claimed: 0, ok: false, error: 'no_user');
    }
    final key = '${currentUserUid.trim()}:${liveId.trim()}';
    final last = _lastClaimAt[key];
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return const HubPsClaimResult(claimed: 0, ok: true);
    }
    try {
      final res = await SupaFlow.client.rpc(
        'batata_claim_external_reservations',
        params: {'p_live_id': liveId.trim()},
      );
      _lastClaimAt[key] = DateTime.now();
      if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        final ok = map['ok'] == true;
        final claimed = (map['claimed'] as num?)?.toInt() ?? 0;
        final err = map['error']?.toString();
        if (!ok) {
          FleaberLogger.instance.warning(
            'HubPsClaim',
            'claim rejected: $err',
          );
        }
        return HubPsClaimResult(
          ok: ok,
          claimed: claimed,
          claimedFb: (map['claimed_fb'] as num?)?.toInt() ?? 0,
          claimedLegacy: (map['claimed_legacy'] as num?)?.toInt() ?? 0,
          hasFacebookIdentity: map['has_facebook_identity'] == true,
          error: err,
          hint: map['hint']?.toString(),
        );
      }
    } catch (e) {
      FleaberLogger.instance.warning('HubPsClaim', 'claim failed: $e');
      return HubPsClaimResult(claimed: 0, ok: false, error: e.toString());
    }
    return const HubPsClaimResult(claimed: 0, ok: false, error: 'unknown');
  }
}
