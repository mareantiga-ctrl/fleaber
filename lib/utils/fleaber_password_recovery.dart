/// Estado da recuperação de senha — evita loop login → nova senha.
abstract final class FleaberPasswordRecovery {
  static bool completed = false;

  static void markPending() {
    completed = false;
  }

  static void markCompleted() {
    completed = true;
  }
}
