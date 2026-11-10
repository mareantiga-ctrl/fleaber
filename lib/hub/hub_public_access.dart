/// Controlos de acesso público Hub / FleaHub.
abstract final class HubPublicAccess {
  /// Registo público **ligado** por defeito (lançamento).
  /// Desactivar só com `--dart-define=FLEABER_PUBLIC_REGISTRATION=false`.
  static bool get registrationEnabled {
    const flag = String.fromEnvironment(
      'FLEABER_PUBLIC_REGISTRATION',
      defaultValue: 'true',
    );
    return flag.toLowerCase() != 'false';
  }

  /// Entrada dev Hub no browser (launcher `/hub-dev`).
  static bool get devHubLauncherEnabled {
    const flag = String.fromEnvironment(
      'FLEABER_HUB_DEV',
      defaultValue: 'true',
    );
    return flag.toLowerCase() != 'false';
  }
}
