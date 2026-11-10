import '/backend/supabase/database/tables/profiles.dart';
import '/hub/data/hub_public_repository.dart';
import '/hub/data/hub_models.dart';

/// Nome público do vendedor para visitantes (anon) e autenticados.
///
/// Causa ZIP 161.1→162: `profiles_directory_public` **não** tem GRANT a `anon`,
/// por isso o Hub público caía no fallback «Vendedor». A view `hub_profiles_public`
/// é a fonte correcta para vitrinas publicadas (mesmo contrato do Hub perfil).
class SellerPublicDisplay {
  SellerPublicDisplay._();

  static final HubPublicRepository _hub = HubPublicRepository();

  /// Devolve nome + foto URL públicos, ou null se inexistente.
  static Future<({String name, String? photoUrl, String? handle})?> load(
    String? sellerId,
  ) async {
    final sid = (sellerId ?? '').trim();
    if (sid.isEmpty) return null;

    // 1) Hub público (anon + authenticated) — preferido na ficha de produto.
    try {
      final HubProfile? hub = await _hub.fetchProfileById(sid);
      if (hub != null) {
        final n = hub.fullName.trim();
        if (n.isNotEmpty) {
          return (name: n, photoUrl: hub.photoUrl, handle: hub.handle);
        }
        final h = hub.handle.trim();
        if (h.isNotEmpty) {
          return (name: '@$h', photoUrl: hub.photoUrl, handle: hub.handle);
        }
      }
    } catch (_) {}

    // 2) Directory (só authenticated / chats) — fallback app logada.
    try {
      final rows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eq('id', sid).limit(1),
      );
      if (rows.isNotEmpty) {
        final p = rows.first;
        final n = (p.fullName ?? '').trim();
        if (n.isNotEmpty) {
          return (name: n, photoUrl: p.photoUrl, handle: null);
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<String?> displayName(String? sellerId) async {
    final r = await load(sellerId);
    return r?.name;
  }
}
