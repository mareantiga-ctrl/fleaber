import '/backend/supabase/supabase.dart';
import '/hub/seo/hub_seo_policy.dart';

/// Apagar conta **com wipe total** — só staging (QA / testes Facebook, etc.).
///
/// Produção usará fluxo separado (soft delete + retenção legal) — ver
/// `supabase/sql/staging_nuke_user_account_batata.sql`.
abstract final class TestAccountDeletionService {
  static const confirmPhrase = 'APAGAR TUDO';

  /// Visível quando a app aponta ao projecto Supabase staging.
  static bool get isAvailable => HubSeoPolicy.isStagingSupabaseProject();

  /// Remove todos os dados do utilizador actual + conta Auth (edge function).
  static Future<Map<String, dynamic>> nukeCurrentAccount({
    required String confirmation,
  }) async {
    if (!isAvailable) {
      throw StateError('Apagar conta de testes só disponível em staging.');
    }
    if (confirmation.trim() != confirmPhrase) {
      throw ArgumentError('Confirmação incorrecta.');
    }

    final response = await SupaFlow.client.functions.invoke(
      'delete-test-account',
      body: {'confirm': confirmation.trim()},
    );

    final data = response.data;
    if (response.status != 200) {
      final msg = _errorMessage(data) ??
          'Não foi possível apagar a conta (${response.status}).';
      throw Exception(msg);
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ok': true};
  }

  static String? _errorMessage(Object? data) {
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return null;
  }
}
