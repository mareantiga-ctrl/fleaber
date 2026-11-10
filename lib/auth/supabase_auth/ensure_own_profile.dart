import 'package:flutter/foundation.dart' show debugPrint;

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Garante linha em `profiles` após autenticação com sessão (insert-only).
/// Não sobrescreve perfil existente — o trigger Auth + registo tratam o resto.
Future<void> ensureOwnProfileRow({
  String? fullName,
  String? phone,
  String userType = 'vendedor',
}) async {
  final uid = currentUserUid;
  if (uid.isEmpty) return;

  final meta = SupaFlow.client.auth.currentUser?.userMetadata ?? const {};
  final nameFromMeta = meta['full_name']?.toString().trim();
  final nameFromAlt = meta['name']?.toString().trim();
  final name = (fullName != null && fullName.trim().isNotEmpty)
      ? fullName.trim()
      : (nameFromMeta != null && nameFromMeta.isNotEmpty
          ? nameFromMeta
          : (nameFromAlt != null && nameFromAlt.isNotEmpty
              ? nameFromAlt
              : (currentUserEmail.contains('@')
                  ? currentUserEmail.split('@').first
                  : 'Utilizador')));
  final phoneFromMeta = meta['phone']?.toString().trim() ?? '';
  final phoneVal = (phone != null && phone.trim().isNotEmpty)
      ? phone.trim()
      : phoneFromMeta;

  final payload = <String, dynamic>{
    'id': uid,
    'full_name': name,
    'user_type': userType,
    if (phoneVal.isNotEmpty) 'phone': phoneVal,
  };

  try {
    await ProfilesTable().insert(payload);
  } on PostgrestException catch (e) {
    if (e.code == '23505') return;
    debugPrint('ensureOwnProfileRow: ${e.message}');
  }
}
