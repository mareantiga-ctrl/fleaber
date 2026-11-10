/// Textos do painel «Acesso de colaborador».
///
/// O dono da loja e o colaborador partilham a mesma rota; o copy tem de
/// reflectir o papel real para não parecer que o dono «trabalha para si».
class HelperAccessCopy {
  const HelperAccessCopy._();

  static String storeEyebrow({required bool isOwnerContext}) =>
      isOwnerContext ? 'A tua loja' : 'A trabalhar para';

  static String storeOwnerHint() =>
      'Não estás a trabalhar como colaborador. '
      'Esta página serve para lojas onde aceitares um convite.';

  static String associatedEmpty({required bool isOwnerContext}) =>
      isOwnerContext
          ? 'Ainda não és colaborador de outra loja.'
          : 'Não tens nenhuma loja aceite como colaborador.';

  static String ownerPermissionsTitle() => 'Modo pessoal';

  static String ownerPermissionsBody() =>
      'Como dono tens acesso completo à tua loja. '
      'As permissões de colaborador só aparecem aqui depois de aceitares um convite.';
}
