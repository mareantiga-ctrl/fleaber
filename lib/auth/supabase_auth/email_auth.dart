import '/backend/supabase/supabase.dart';

Future<User?> emailSignInFunc(
  String email,
  String password,
) async {
  final AuthResponse res = await SupaFlow.client.auth
      .signInWithPassword(email: email, password: password);
  return res.user;
}

Future<User?> emailCreateAccountFunc(
  String email,
  String password,
) async {
  final trimmed = email.trim();
  final AuthResponse res = await SupaFlow.client.auth.signUp(
    email: trimmed,
    password: password,
  );

  if (res.session != null && res.user != null) {
    return res.user;
  }

  final created = res.user;
  if (created == null) return null;

  // SignUp pode criar o user sem sessão no objeto (SDK); tentar login em seguida.
  try {
    final signIn = await SupaFlow.client.auth.signInWithPassword(
      email: trimmed,
      password: password,
    );
    return signIn.user ?? created;
  } catch (_) {
    return created.emailConfirmedAt != null ? created : null;
  }
}
