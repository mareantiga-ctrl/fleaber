import '/backend/supabase/supabase.dart';

/// Resultado do `signUp` por e-mail (sessão imediata vs confirmação pendente).
enum EmailAccountCreateStatus {
  /// Conta criada e sessão activa (confirmação desligada ou já confirmada).
  signedIn,

  /// Conta criada em Auth; falta confirmar o e-mail antes de entrar.
  pendingEmailConfirmation,

  /// Falha (duplicado, rate limit, rede, etc.).
  failed,
}

class EmailAccountCreateResult {
  const EmailAccountCreateResult({
    required this.status,
    this.user,
    this.errorMessage,
  });

  final EmailAccountCreateStatus status;
  final User? user;
  final String? errorMessage;

  bool get isSuccess =>
      status == EmailAccountCreateStatus.signedIn ||
      status == EmailAccountCreateStatus.pendingEmailConfirmation;

  factory EmailAccountCreateResult.signedIn(User user) =>
      EmailAccountCreateResult(
        status: EmailAccountCreateStatus.signedIn,
        user: user,
      );

  factory EmailAccountCreateResult.pendingEmailConfirmation(User user) =>
      EmailAccountCreateResult(
        status: EmailAccountCreateStatus.pendingEmailConfirmation,
        user: user,
      );

  factory EmailAccountCreateResult.failed(String message) =>
      EmailAccountCreateResult(
        status: EmailAccountCreateStatus.failed,
        errorMessage: message,
      );
}
