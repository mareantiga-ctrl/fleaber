import '/backend/supabase/supabase.dart';
import '/utils/seller_staff_service.dart';
import 'supabase_auth_manager.dart';

export 'supabase_auth_manager.dart';

final _authManager = SupabaseAuthManager();
SupabaseAuthManager get authManager => _authManager;

String get currentUserEmail =>
    currentUser?.email ?? SupaFlow.client.auth.currentUser?.email ?? '';

/// Prefer o utilizador FF; se ainda não sincronizou (race web), usa a sessão Supabase.
String get currentUserUid {
  final fromFf = currentUser?.uid?.trim() ?? '';
  if (fromFf.isNotEmpty) return fromFf;
  final fromUser = SupaFlow.client.auth.currentUser?.id?.trim() ?? '';
  if (fromUser.isNotEmpty) return fromUser;
  return SupaFlow.client.auth.currentSession?.user.id.trim() ?? '';
}

/// Loja em que o utilizador opera (dono ou colaborador activo).
String get effectiveSellerId => SellerStaffContext.instance.effectiveSellerId;

String get currentUserDisplayName => currentUser?.displayName ?? '';

String get currentUserPhoto => currentUser?.photoUrl ?? '';

String get currentPhoneNumber => currentUser?.phoneNumber ?? '';

String get currentJwtToken => _currentJwtToken ?? '';

bool get currentUserEmailVerified => currentUser?.emailVerified ?? false;

/// Create a Stream that listens to the current user's JWT Token.
String? _currentJwtToken;
final jwtTokenStream = SupaFlow.client.auth.onAuthStateChange
    .map(
      (authState) => _currentJwtToken = authState.session?.accessToken,
    )
    .asBroadcastStream();
