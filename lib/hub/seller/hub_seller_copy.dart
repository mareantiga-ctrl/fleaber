/// Copy user-facing FleaHub seller — fonte única (sheet + perfil + erros alinhados).
abstract final class HubSellerCopy {
  static const brand = 'FleaHub';
  static const profileLineCreate = 'Criar FleaHub';
  static const profileLineManage = 'FleaHub';

  /// Menu Perfil privado (conta seller — gestão).
  static const accountMenuTitle = 'FleaHub';
  static const accountMenuSubtitle = 'Gerir e partilhar o teu FleaHub';

  /// Perfil vendedor de outra seller (visitante — só navegação).
  static const visitorLineLabel = 'Ver FleaHub';

  static const sheetSubtitle = 'O teu espaço público na Fleaber.';
  static const setupPrompt = 'Escolhe o teu endereço.';
  static const confirmCreate = 'Confirmar';
  static const personalizeTitle = 'Personalizar endereço';
  static const hideFleaHub = 'Ocultar FleaHub';
  static const activateFleaHub = 'Activar FleaHub';
  static const inactiveHint = 'Activa o FleaHub para partilhares o endereço.';

  static const view = 'Ver';
  static const copy = 'Copiar';
  static const share = 'Partilhar';
  static const saveAddress = 'Guardar';

  /// Feedback inline na sheet (não snackbar atrás do modal).
  static const linkCopiedFeedback = 'Link copiado.';
  static const shareCopiedFeedback =
      'Link copiado — cola onde quiseres partilhar.';
  static const fleahubCreatedFeedback = 'FleaHub criado.';
  static const fleahubCreatedActivateHint =
      'Endereço guardado. Activa o FleaHub quando a loja estiver pronta.';

  static const addressFieldHint = 'ex.: maria-silva';
  static const updatedSnackbar = 'FleaHub actualizado.';
  static const personalizeFooter =
      'Se mudares o endereço, avisa quem já tinha o teu FleaHub guardado.';

  /// Cartão embed (Definições, Preparar directo, pós-live).
  static const embedPhaseNoFleaHub = 'Sem FleaHub';
  static const embedPhaseSuggested = 'Endereço sugerido';
  static const embedPhaseHidden = 'Oculto';
  static const embedPhaseActive = 'Activo';
  static const embedManage = 'Gerir FleaHub';
  static const embedViewLive = 'Ver directo';
  static const embedCopyLive = 'Copiar directo';
  static const settingsSectionBlurb =
      'O teu endereço público na Fleaber — diferente do nome de utilizador acima.';
  static const usernameHelperAvailable =
      'Disponível. Nome na app — o FleaHub (fleaber.pt/…) gere-se abaixo.';
  static const usernameHelperRequired =
      'Obrigatório. Nome na app ≠ endereço FleaHub.';
  static const postLiveBody =
      'Partilha o teu FleaHub para quem perdeu o directo.';
  static const liveLinkTooltip = 'Copiar endereço do directo';
  static const liveLinkSetupTooltip = 'Configura o FleaHub';
}
