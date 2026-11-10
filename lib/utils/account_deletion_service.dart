import '/backend/supabase/supabase.dart';

/// Eliminação de conta em produção (soft: anonimizar + ban Auth).
/// Staging wipe total: [TestAccountDeletionService].
abstract final class AccountDeletionService {
  static const confirmPhrase = 'ELIMINAR CONTA';

  /// Sempre disponível (produção e staging) — edge `request-account-deletion`.
  static bool get isAvailable => true;

  static Future<Map<String, dynamic>> requestDeletion({
    required String confirmation,
  }) async {
    if (confirmation.trim() != confirmPhrase) {
      throw ArgumentError('Confirmação incorrecta.');
    }

    final response = await SupaFlow.client.functions.invoke(
      'request-account-deletion',
      body: {'confirm': confirmation.trim()},
    );

    final data = response.data;
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'raw': data};

    if (response.status == 409) {
      return {
        ...map,
        'ok': false,
        'blocked': true,
      };
    }

    if (response.status != 200) {
      final msg = map['error']?.toString() ??
          'Não foi possível eliminar a conta (${response.status}).';
      throw Exception(msg);
    }

    return map;
  }
}
