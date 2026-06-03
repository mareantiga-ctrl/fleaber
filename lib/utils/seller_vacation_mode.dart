import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Modo de férias: ocultar anúncios/diretos no marketplace e bloquear compras novas.
class SellerVacationMode {
  SellerVacationMode._();

  static const vacationBannerMessage =
      'Este vendedor está de férias. Não é possível comprar ou fazer propostas '
      'até voltar a estar disponível. As mensagens sobre os artigos mantêm-se; '
      'encomendas já em curso continuam normalmente.';

  static Future<bool> isOnVacation(String? sellerId) async {
    final id = sellerId?.trim() ?? '';
    if (id.isEmpty) return false;
    try {
      final row = await SupaFlow.client
          .from('profiles')
          .select('vacation_mode')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return false;
      return row['vacation_mode'] == true;
    } catch (_) {
      return false;
    }
  }

  /// IDs de vendedores com `vacation_mode = true` (subconjunto de [sellerIds]).
  static Future<Set<String>> sellerIdsOnVacation(Iterable<String> sellerIds) async {
    final ids = sellerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};

    try {
      final rows = await SupaFlow.client
          .from('profiles')
          .select('id')
          .inFilter('id', ids)
          .eq('vacation_mode', true);
      return rows
          .map((r) => r['id']?.toString())
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static List<ProductsRow> hideProductsFromVacationSellers(
    List<ProductsRow> products,
    Set<String> vacationSellerIds,
  ) {
    if (vacationSellerIds.isEmpty) return products;
    return products
        .where((p) {
          final sid = p.sellerId?.trim() ?? '';
          if (sid.isEmpty) return true;
          if (sid == currentUserUid) return true;
          return !vacationSellerIds.contains(sid);
        })
        .toList();
  }

  /// Ocultar no feed público (Home / perfil de terceiros).
  static bool hideSellerFromPublicDiscovery({
    required bool sellerOnVacation,
    required String? sellerId,
  }) {
    if (!sellerOnVacation) return false;
    final sid = sellerId?.trim() ?? '';
    if (sid.isEmpty) return false;
    return sid != currentUserUid;
  }
}
