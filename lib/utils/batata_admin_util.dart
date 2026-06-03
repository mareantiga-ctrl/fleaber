/// Deteção de perfil admin (alinhado com `admin_batata.sql` / `AdminPageWidget`).
bool batataIsAdminUserType(String? userType) {
  final type = (userType ?? '').trim().toLowerCase();
  return const {
    'admin',
    'admim',
    'administrador',
    'administracao',
  }.contains(type);
}
