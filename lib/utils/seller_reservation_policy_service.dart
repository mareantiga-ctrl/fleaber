import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Canonical seller reservation policy (Phase 1 table + Phase 5 UX).
///
/// No row ⇒ seller has not configured yet (first-live gate).
class SellerReservationPolicy {
  const SellerReservationPolicy({
    required this.sellerId,
    required this.policyMode,
    required this.untrustedMode,
    required this.normalTtlSeconds,
    required this.trustedTtlSeconds,
    required this.acceptFleaberGlobalTrust,
    required this.policyVersion,
    required this.configuredAt,
  });

  final String sellerId;
  final String policyMode;
  final String untrustedMode;
  final int normalTtlSeconds;
  final int trustedTtlSeconds;
  final bool acceptFleaberGlobalTrust;
  final int policyVersion;
  final DateTime? configuredAt;

  bool get isAskSeller => untrustedMode == 'approval';
  bool get isPayGuarantees => untrustedMode == 'pay_required';

  static SellerReservationPolicy? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final sid = m['seller_id']?.toString().trim() ?? '';
    if (sid.isEmpty) return null;
    return SellerReservationPolicy(
      sellerId: sid,
      policyMode: (m['policy_mode'] ?? 'trust').toString(),
      untrustedMode: (m['untrusted_mode'] ?? 'approval').toString(),
      normalTtlSeconds: (m['normal_ttl_seconds'] as num?)?.toInt() ?? 432000,
      trustedTtlSeconds: (m['trusted_ttl_seconds'] as num?)?.toInt() ?? 432000,
      acceptFleaberGlobalTrust: m['accept_fleaber_global_trust'] != false,
      policyVersion: (m['policy_version'] as num?)?.toInt() ?? 1,
      configuredAt: m['configured_at'] == null
          ? null
          : DateTime.tryParse(m['configured_at'].toString()),
    );
  }
}

/// Reads/writes `seller_reservation_settings` via authenticated client (RLS).
abstract final class SellerReservationPolicyService {
  static const int minTtlSeconds = 900; // 15 min
  static const int maxTtlSeconds = 432000; // 5 days

  static int clampTtl(int seconds) {
    if (seconds < minTtlSeconds) return minTtlSeconds;
    if (seconds > maxTtlSeconds) return maxTtlSeconds;
    return seconds;
  }

  static Future<SellerReservationPolicy?> fetchForCurrentSeller() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return null;
    final rows = await SupaFlow.client
        .from('seller_reservation_settings')
        .select()
        .eq('seller_id', uid)
        .limit(1);
    if (rows.isEmpty) return null;
    return SellerReservationPolicy.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  static Future<bool> hasConfiguredPolicy() async {
    final p = await fetchForCurrentSeller();
    return p != null;
  }

  /// Upsert policy. Snapshots on existing reservations are never rewritten here.
  static Future<Map<String, dynamic>> save({
    required String untrustedMode,
    required int normalTtlSeconds,
    required int trustedTtlSeconds,
    bool acceptFleaberGlobalTrust = true,
    String policyMode = 'trust',
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      return {'ok': false, 'error': 'not_authenticated'};
    }
    final mode = untrustedMode.trim();
    if (mode != 'approval' && mode != 'pay_required') {
      return {'ok': false, 'error': 'invalid_untrusted_mode'};
    }
    final normal = clampTtl(normalTtlSeconds);
    final trusted = clampTtl(trustedTtlSeconds);
    final pm = policyMode.trim().isEmpty ? 'trust' : policyMode.trim();

    final existing = await fetchForCurrentSeller();
    final payload = <String, dynamic>{
      'seller_id': uid,
      'policy_mode': pm,
      'untrusted_mode': mode,
      'normal_ttl_seconds': normal,
      'trusted_ttl_seconds': trusted,
      'accept_fleaber_global_trust': acceptFleaberGlobalTrust,
      'configured_at':
          (existing?.configuredAt ?? DateTime.now().toUtc()).toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      if (existing == null) {
        await SupaFlow.client.from('seller_reservation_settings').insert(payload);
      } else {
        await SupaFlow.client
            .from('seller_reservation_settings')
            .update({
              'policy_mode': pm,
              'untrusted_mode': mode,
              'normal_ttl_seconds': normal,
              'trusted_ttl_seconds': trusted,
              'accept_fleaber_global_trust': acceptFleaberGlobalTrust,
              'updated_at': payload['updated_at'],
            })
            .eq('seller_id', uid);
      }
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Human duration for PT-PT labels (seller settings).
  static String formatTtl(int seconds) {
    final s = clampTtl(seconds);
    if (s < 3600) {
      final m = (s / 60).round();
      return m == 1 ? '1 minuto' : '$m minutos';
    }
    if (s < 86400) {
      final h = (s / 3600).round();
      return h == 1 ? '1 hora' : '$h horas';
    }
    final d = (s / 86400);
    if ((d - d.round()).abs() < 0.05) {
      final days = d.round();
      return days == 1 ? '1 dia' : '$days dias';
    }
    final days = d.toStringAsFixed(1).replaceAll('.', ',');
    return '$days dias';
  }

  static const List<int> ttlPresetsSeconds = [
    900, // 15 min
    1800, // 30 min
    3600, // 1 h
    7200, // 2 h
    14400, // 4 h
    28800, // 8 h
    86400, // 1 day
    172800, // 2 days
    259200, // 3 days
    432000, // 5 days
  ];
}
