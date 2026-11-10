import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Gravação segura em `profiles` — garante linha + upsert se UPDATE falhar.
class ProfilePatchService {
  ProfilePatchService._();

  /// Mensagens para a pessoa (sem SQL / códigos crus).
  static String friendlyError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();

    if (e is PostgrestException) {
      final code = (e.code ?? '').trim();
      final details =
          '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();

      if (code == '23505' ||
          details.contains('duplicate') ||
          details.contains('unique') ||
          details.contains('full_name')) {
        return 'Esse nome de utilizador já está em uso. Escolhe outro.';
      }
      if (code == '42501' ||
          details.contains('permission') ||
          details.contains('row-level security') ||
          details.contains('rls')) {
        return 'Não foi possível guardar (permissões). Termina sessão, volta a '
            'entrar e tenta outra vez.';
      }
      if (code == 'PGRST116') {
        return 'Não encontrámos o teu perfil. Volta a iniciar sessão e tenta guardar.';
      }
      if (code == 'PGRST204') {
        return 'A app está desactualizada face à base de dados. Contacta o suporte '
            'Fleaber (geral@fleaber.pt) se o problema continuar.';
      }
      if (code == '23514' || details.contains('check constraint')) {
        return 'Algum dado não é válido (nome, telefone ou morada). Confirma os '
            'campos assinalados e tenta outra vez.';
      }
      if (code == '22P02' || details.contains('invalid input')) {
        return 'Há um valor em formato incorrecto. Verifica o telefone, país (ex. PT) '
            'e código postal.';
      }
    }

    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed host') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection')) {
      return 'Sem ligação estável. Verifica a internet e tenta outra vez.';
    }

    if (lower.contains('jwt') ||
        lower.contains('not authenticated') ||
        lower.contains('session')) {
      return 'A sessão expirou. Volta a iniciar sessão e guarda outra vez.';
    }

    final clean = msg.replaceFirst('Exception: ', '').trim();
    if (clean.startsWith('O ') ||
        clean.startsWith('A ') ||
        clean.startsWith('Este ') ||
        clean.startsWith('Não ') ||
        clean.startsWith('Para ')) {
      if (clean.contains('supabase/sql') || clean.contains('SQL Editor')) {
        return 'Não foi possível guardar o perfil agora. Tenta outra vez daqui a '
            'um minuto. Se continuar, contacta geral@fleaber.pt.';
      }
      return clean;
    }

    if (clean.contains('supabase/sql') ||
        clean.contains('Postgrest') ||
        clean.contains('PGRST') ||
        RegExp(r'\b[A-Z]{2,}\d{2,}\b').hasMatch(clean)) {
      return 'Não foi possível guardar. Confirma os dados e tenta outra vez. '
          'Se o erro continuar, contacta geral@fleaber.pt.';
    }

    if (clean.length > 160) {
      return 'Não foi possível guardar o perfil. Verifica os campos e tenta outra vez.';
    }
    return clean.isEmpty
        ? 'Não foi possível guardar o perfil. Tenta outra vez.'
        : clean;
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
