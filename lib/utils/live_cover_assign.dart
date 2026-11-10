import '/backend/supabase/supabase.dart';
import '/utils/live_cover_catalog.dart';

/// Chama RPC de atribuição atómica; ignora falha se migração ainda não aplicada.
class LiveCoverAssign {
  LiveCoverAssign._();

  /// Cache de sessão (útil antes de `cover_id` estar no SELECT da tabela).
  static final Map<String, String> _sessionCovers = {};

  static Future<String?> assignForLive(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_assign_live_cover',
        params: {'p_live_id': id},
      );
      final cover = res?.toString().trim() ?? '';
      if (cover.isEmpty) return null;
      _sessionCovers[id] = cover;
      return cover;
    } catch (_) {
      // BD sem migração: UI usa provisionalCoverId(liveId).
      return null;
    }
  }

  static String resolveCoverId({
    required String liveId,
    String? persistedCoverId,
  }) {
    final p = persistedCoverId?.trim() ?? '';
    if (p.isNotEmpty) return p;
    final cached = _sessionCovers[liveId.trim()];
    if (cached != null && cached.isNotEmpty) return cached;
    return LiveCoverCatalog.provisionalCoverId(liveId);
  }
}
