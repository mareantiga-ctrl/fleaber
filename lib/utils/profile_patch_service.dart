import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Gravação segura em `profiles` — garante linha + upsert se UPDATE falhar.
class ProfilePatchService {
  ProfilePatchService._();

  static String friendlyError(Object e) {
    final msg = e.toString();
    if (e is PostgrestException) {
      if (e.code == 'PGRST116') {
        return 'Não foi possível guardar o perfil (linha em falta ou permissões). '
            'Executa supabase/sql/profiles_rls_batata.sql no Supabase e tenta outra vez.';
      }
      if (e.code == 'PGRST204') {
        return 'Faltam colunas na base de dados. Executa os ficheiros SQL em '
            'supabase/sql/ (profiles_shipping_payments_batata.sql, '
            'profiles_vacation_mode_batata.sql) no SQL Editor do Supabase.';
      }
    }
    if (msg.contains('shipping_') ||
        msg.contains('vacation_mode') ||
        msg.contains('external_payments_enabled') ||
        msg.contains('legal_full_name') ||
        msg.contains('iban') ||
        msg.contains('mb_way')) {
      return 'Faltam colunas na base de dados. Executa os ficheiros SQL em '
          'supabase/sql/ no SQL Editor do Supabase e volta a guardar.';
    }
    return msg.replaceFirst('Exception: ', '');
  }

  /// Garante que existe linha em `profiles` para o utilizador autenticado.
  static Future<void> ensureOwnProfileRow() async {
    if (currentUserUid.isEmpty) return;
    final uid = currentUserUid;
    try {
      final existing = await SupaFlow.client
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .limit(1);
      if (existing.isNotEmpty) return;

      final name = currentUserDisplayName.trim();
      await SupaFlow.client.from('profiles').insert({
        'id': uid,
        'full_name': name.isNotEmpty ? name : 'Utilizador',
        'user_type': 'vendedor',
      });
    } on PostgrestException catch (e) {
      // Concorrência ou linha criada entretanto.
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// UPDATE com fallback upsert; devolve a linha gravada ou null.
  static Future<Map<String, dynamic>?> patchOwnProfile(
    Map<String, dynamic> patch, {
    required String select,
  }) async {
    if (currentUserUid.isEmpty) return null;
    final uid = currentUserUid;
    final data = Map<String, dynamic>.from(patch)..remove('id');

    await ensureOwnProfileRow();

    List<dynamic> rows = await SupaFlow.client
        .from('profiles')
        .update(data)
        .eq('id', uid)
        .select(select);

    if (rows.isEmpty) {
      try {
        await SupaFlow.client.from('profiles').insert({
          'id': uid,
          'user_type': 'vendedor',
          ...data,
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
      rows = await SupaFlow.client
          .from('profiles')
          .update(data)
          .eq('id', uid)
          .select(select);
    }

    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }
}
