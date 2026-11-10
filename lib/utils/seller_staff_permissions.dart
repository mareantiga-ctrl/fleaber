/// Permissões granulares para colaboradores (helpers) de uma loja Fleaber.
abstract final class SellerStaffPermissions {
  // Live
  static const canViewLiveDashboard = 'can_view_live_dashboard';
  static const canManageChat = 'can_manage_chat';
  static const canManageReservations = 'can_manage_reservations';
  static const canMarkItemsSold = 'can_mark_items_sold';
  static const canChangeCurrentItem = 'can_change_current_item';
  static const canEndLive = 'can_end_live';
  static const canManageRaffles = 'can_manage_raffles';

  // Loja
  static const canCreateProducts = 'can_create_products';
  static const canEditProducts = 'can_edit_products';
  static const canDeleteProducts = 'can_delete_products';
  static const canManageOrders = 'can_manage_orders';
  static const canManageShipping = 'can_manage_shipping';
  static const canReplyCustomers = 'can_reply_customers';
  static const canManageReturns = 'can_manage_returns';

  // Financeiro (restrito por defeito)
  static const canViewPayouts = 'can_view_payouts';
  static const canManagePayouts = 'can_manage_payouts';
  static const canIssueRefunds = 'can_issue_refunds';

  // Administrativo
  static const canManageHelpers = 'can_manage_helpers';
  static const canEditStoreProfile = 'can_edit_store_profile';
  static const canViewAnalytics = 'can_view_analytics';

  static const allKeys = <String>[
    canViewLiveDashboard,
    canManageChat,
    canManageReservations,
    canMarkItemsSold,
    canChangeCurrentItem,
    canEndLive,
    canManageRaffles,
    canCreateProducts,
    canEditProducts,
    canDeleteProducts,
    canManageOrders,
    canManageShipping,
    canReplyCustomers,
    canManageReturns,
    canViewPayouts,
    canManagePayouts,
    canIssueRefunds,
    canManageHelpers,
    canEditStoreProfile,
    canViewAnalytics,
  ];

  /// Permissões atribuídas por defeito a um novo colaborador (sem dinheiro).
  static Map<String, bool> defaultHelperPermissions() {
    return {
      canViewLiveDashboard: true,
      canManageChat: true,
      canManageReservations: true,
      canMarkItemsSold: true,
      canChangeCurrentItem: true,
      canEndLive: false,
      canManageRaffles: false,
      canCreateProducts: false,
      canEditProducts: false,
      canDeleteProducts: false,
      canManageOrders: true,
      canManageShipping: false,
      canReplyCustomers: true,
      canManageReturns: false,
      canViewPayouts: false,
      canManagePayouts: false,
      canIssueRefunds: false,
      canManageHelpers: false,
      canEditStoreProfile: false,
      canViewAnalytics: false,
    };
  }

  static Map<String, bool> ownerFullPermissions() {
    return {for (final k in allKeys) k: true};
  }

  static Map<String, bool> fromJson(Map<String, dynamic>? raw) {
    final base = defaultHelperPermissions();
    if (raw == null || raw.isEmpty) return base;
    for (final k in allKeys) {
      final v = raw[k];
      if (v is bool) base[k] = v;
    }
    return base;
  }

  static Map<String, dynamic> toJson(Map<String, bool> perms) {
    return {for (final k in allKeys) k: perms[k] == true};
  }

  static const categories = <StaffPermissionCategory>[
    StaffPermissionCategory(
      id: 'live',
      title: 'Directos e vendas ao vivo',
      subtitle: 'Operação durante o directo',
      keys: [
        canViewLiveDashboard,
        canManageChat,
        canManageReservations,
        canMarkItemsSold,
        canChangeCurrentItem,
        canEndLive,
        canManageRaffles,
      ],
    ),
    StaffPermissionCategory(
      id: 'store',
      title: 'Loja e encomendas',
      subtitle: 'Catálogo, envios e clientes',
      keys: [
        canCreateProducts,
        canEditProducts,
        canDeleteProducts,
        canManageOrders,
        canManageShipping,
        canReplyCustomers,
        canManageReturns,
      ],
    ),
    StaffPermissionCategory(
      id: 'financial',
      title: 'Financeiro',
      subtitle: 'Acesso sensível — usar com cuidado',
      keys: [
        canViewPayouts,
        canManagePayouts,
        canIssueRefunds,
      ],
    ),
    StaffPermissionCategory(
      id: 'admin',
      title: 'Administração',
      subtitle: 'Definições da loja e equipa',
      keys: [
        canManageHelpers,
        canEditStoreProfile,
        canViewAnalytics,
      ],
    ),
  ];

  static String label(String key) => _labels[key] ?? key;

  static String description(String key) => _descriptions[key] ?? '';

  static const _labels = <String, String>{
    canViewLiveDashboard: 'Ver painel do directo',
    canManageChat: 'Moderar chat público',
    canManageReservations: 'Gerir reservas',
    canMarkItemsSold: 'Marcar artigos como vendidos',
    canChangeCurrentItem: 'Mudar artigo «a mostrar»',
    canEndLive: 'Terminar directo',
    canManageRaffles: 'Gerir rifas do directo',
    canCreateProducts: 'Criar anúncios',
    canEditProducts: 'Editar anúncios',
    canDeleteProducts: 'Eliminar anúncios',
    canManageOrders: 'Gerir encomendas',
    canManageShipping: 'Gerir envios',
    canReplyCustomers: 'Responder clientes (chat)',
    canManageReturns: 'Gerir devoluções',
    canViewPayouts: 'Ver saldo e pagamentos',
    canManagePayouts: 'Gerir levantamentos',
    canIssueRefunds: 'Emitir reembolsos',
    canManageHelpers: 'Gerir colaboradores',
    canEditStoreProfile: 'Editar perfil da loja',
    canViewAnalytics: 'Ver estatísticas e histórico',
  };

  static const _descriptions = <String, String>{
    canViewLiveDashboard:
        'Acede ao ecrã de transmissão e ferramentas operacionais.',
    canManageChat: 'Responde e modera mensagens no chat do directo.',
    canManageReservations: 'Aceita ou gere pedidos de reserva durante a live.',
    canMarkItemsSold: 'Confirma vendas e atualiza stock em tempo real.',
    canChangeCurrentItem: 'Define qual artigo está «a mostrar» aos compradores.',
    canEndLive: 'Pode encerrar a transmissão (ação crítica).',
    canManageRaffles:
        'Cria, fecha e sorteia rifas; gera encomendas de prémio no catálogo.',
    canCreateProducts: 'Cria novos anúncios no marketplace.',
    canEditProducts: 'Altera preço, fotos e descrição dos anúncios.',
    canDeleteProducts: 'Remove anúncios da loja.',
    canManageOrders: 'Vê e trata encomendas como vendedor.',
    canManageShipping: 'Atualiza moradas e estado de envio.',
    canReplyCustomers: 'Usa mensagens e chat com compradores.',
    canManageReturns: 'Trata disputas e devoluções.',
    canViewPayouts: 'Vê saldo disponível e movimentos.',
    canManagePayouts: 'Solicita levantamentos e altera dados de pagamento.',
    canIssueRefunds: 'Pode reembolsar compradores.',
    canManageHelpers: 'Convida, remove e edita permissões de colaboradores.',
    canEditStoreProfile: 'Altera nome, foto e definições públicas da loja.',
    canViewAnalytics: 'Consulta histórico de ações da equipa.',
  };
}

class StaffPermissionCategory {
  const StaffPermissionCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.keys,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> keys;
}
