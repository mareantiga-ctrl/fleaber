import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_account_routes.dart';
import '/hub/hub_actions.dart';
import '/hub/hub_navigation.dart';
import '/hub/pages/how_it_works_body.dart';
import '/hub/seller/hub_seller_copy.dart';
import '/hub/seller/hub_seller_sheet.dart';
import '/hub/theme/hub_theme.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/index.dart';
import '/perfil/perfil_desktop_nav.dart';
import '/utils/fleaber_colors.dart';
import '/utils/profile_photo_picker.dart';
import '/utils/seller_professional.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/fleaber_create_sheet.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/widgets/helper_pending_invites_banner.dart';
import '/widgets/profile_avatar.dart';

/// Shell desktop H11 — header full-bleed + sidebar + painel de conteúdo real.
class PerfilAccountShell extends StatefulWidget {
  const PerfilAccountShell({
    super.key,
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.hasManualProfilePhoto,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    required this.isAdmin,
    required this.unreadMessagesFuture,
    required this.onRefreshProfile,
    this.profileFetchDegraded = false,
    this.initialPane = PerfilDesktopPane.resumo,
    this.initialLegalDoc,
    this.initialLiveId,
    this.initialOrderId,
  });

  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool hasManualProfilePhoto;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final bool isAdmin;
  final Future<List<ChatMessagesRow>> unreadMessagesFuture;
  final Future<void> Function() onRefreshProfile;
  final bool profileFetchDegraded;
  final PerfilDesktopPane initialPane;
  /// Documento legal inicial (`?doc=privacy`) — só com painel Informação legal.
  final String? initialLegalDoc;
  /// Sessão live aberta no painel Resultados (`?liveId=`).
  final String? initialLiveId;
  /// Encomenda concreta (`?orderId=`) — emails E1/E2/E3.
  final String? initialOrderId;

  @override
  State<PerfilAccountShell> createState() => _PerfilAccountShellState();
}

class _PerfilAccountShellState extends State<PerfilAccountShell> {
  late PerfilDesktopPane _pane;
  /// Documento legal aberto dentro do painel (null = lista Informação legal).
  String? _legalDocKind;
  /// Detalhe de sessão live no painel Resultados.
  String? _liveId;
  /// Deep link encomenda (emails).
  String? _orderId;
  final Set<String> _expanded = {
    PerfilDesktopNavGroups.conta,
    PerfilDesktopNavGroups.compras,
    PerfilDesktopNavGroups.vendas,
    PerfilDesktopNavGroups.ajuda,
  };

  @override
  void initState() {
    super.initState();
    _pane = widget.initialPane.embedsInShell
        ? widget.initialPane
        : PerfilDesktopPane.resumo;
    if (_pane == PerfilDesktopPane.infoLegal &&
        (widget.initialLegalDoc ?? '').trim().isNotEmpty) {
      _legalDocKind = widget.initialLegalDoc!.trim();
    }
    if (_pane == PerfilDesktopPane.resultadosLive &&
        (widget.initialLiveId ?? '').trim().isNotEmpty) {
      _liveId = widget.initialLiveId!.trim();
    }
    if (_pane == PerfilDesktopPane.encomendas &&
        (widget.initialOrderId ?? '').trim().isNotEmpty) {
      _orderId = widget.initialOrderId!.trim();
    }
  }

  @override
  void didUpdateWidget(covariant PerfilAccountShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPane != widget.initialPane &&
        widget.initialPane.embedsInShell &&
        widget.initialPane != _pane) {
      _pane = widget.initialPane;
      _legalDocKind = (_pane == PerfilDesktopPane.infoLegal)
          ? widget.initialLegalDoc
          : null;
      _liveId = (_pane == PerfilDesktopPane.resultadosLive)
          ? widget.initialLiveId
          : null;
      _orderId = (_pane == PerfilDesktopPane.encomendas)
          ? widget.initialOrderId
          : null;
    } else if (oldWidget.initialLegalDoc != widget.initialLegalDoc &&
        _pane == PerfilDesktopPane.infoLegal) {
      _legalDocKind = widget.initialLegalDoc;
    } else if (oldWidget.initialLiveId != widget.initialLiveId &&
        _pane == PerfilDesktopPane.resultadosLive) {
      _liveId = widget.initialLiveId;
    } else if (oldWidget.initialOrderId != widget.initialOrderId &&
        _pane == PerfilDesktopPane.encomendas) {
      _orderId = widget.initialOrderId;
    }
  }

  Future<void> _showCreate([BuildContext? anchor]) =>
      FleaberCreateSheet.show(context, anchorContext: anchor ?? context);

  void _syncSecaoQuery(
    PerfilDesktopPane pane, {
    String? legalDoc,
    String? liveId,
    String? orderId,
  }) {
    if (!kIsWeb) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final params = <String, String>{};
    if (pane != PerfilDesktopPane.resumo) {
      params['secao'] = pane.name;
    }
    final doc = legalDoc ??
        (pane == PerfilDesktopPane.infoLegal ? _legalDocKind : null);
    if (doc != null && doc.isNotEmpty) {
      params['doc'] = doc;
    }
    final lid = liveId ??
        (pane == PerfilDesktopPane.resultadosLive ? _liveId : null);
    if (lid != null && lid.isNotEmpty) {
      params['liveId'] = lid;
    }
    final oid = orderId ??
        (pane == PerfilDesktopPane.encomendas ? _orderId : null);
    if (oid != null && oid.trim().isNotEmpty) {
      params['orderId'] = oid.trim();
    }
    router.replaceNamed('Perfil', queryParameters: params);
  }

  void _openLiveDetail(String liveId) {
    setState(() {
      _pane = PerfilDesktopPane.resultadosLive;
      _liveId = liveId.trim();
    });
    _syncSecaoQuery(PerfilDesktopPane.resultadosLive, liveId: liveId.trim());
  }

  void _closeLiveDetail() {
    setState(() => _liveId = null);
    _syncSecaoQuery(PerfilDesktopPane.resultadosLive, liveId: '');
  }

  void _select(PerfilDesktopPane pane) {
    final staff = SellerStaffContext.instance;
    switch (pane) {
      case PerfilDesktopPane.novoAnuncio:
        context.pushNamed(SellerProductFormWidget.routeName);
        return;
      case PerfilDesktopPane.explorarFleahub:
        HubActions.openFleaHubLanding(context);
        return;
      case PerfilDesktopPane.admin:
        context.pushNamed(AdminPageWidget.routeName);
        return;
      case PerfilDesktopPane.importadorAmazon:
        context.pushNamed(AmazonImporterHubPage.routeName);
        return;
      case PerfilDesktopPane.convites:
        HelperPendingInvitesBanner.openPendingInvites(context);
        return;
      case PerfilDesktopPane.definicoesLoja:
        context.pushNamed(
          PerfilVendedorWidget.routeName,
          queryParameters: {
            'sellerID': serializeParam(
              staff.effectiveSellerId,
              ParamType.String,
            ),
          }.withoutNulls,
        );
        return;
      default:
        setState(() {
          _pane = pane;
          if (pane != PerfilDesktopPane.infoLegal) {
            _legalDocKind = null;
          }
          if (pane != PerfilDesktopPane.resultadosLive) {
            _liveId = null;
          }
          if (pane != PerfilDesktopPane.encomendas) {
            _orderId = null;
          }
        });
        _syncSecaoQuery(pane);
    }
  }

  Map<String, List<PerfilNavEntry>> _groups(SellerStaffContext staff) {
    final conta = <PerfilNavEntry>[];
    if (staff.isOwnerContext) {
      conta.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.contaDefinicoes,
        title: 'Definições de conta',
        icon: Icons.settings_outlined,
      ));
    } else if (staff.can(SellerStaffPermissions.canEditStoreProfile)) {
      conta.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.definicoesLoja,
        title: 'Definições da loja',
        icon: Icons.storefront_outlined,
        external: true,
      ));
    }

    final compras = <PerfilNavEntry>[];
    if (staff.isOwnerContext) {
      compras.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.favoritos,
        title: 'Favoritos',
        icon: Icons.favorite_border_rounded,
      ));
    }
    if (staff.can(SellerStaffPermissions.canManageOrders) ||
        staff.isOwnerContext) {
      compras.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.encomendas,
        title: 'Encomendas e Compras',
        icon: Icons.local_shipping_outlined,
      ));
    }
    if (staff.can(SellerStaffPermissions.canManageReservations)) {
      compras.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.resultadosLive,
        title: 'Resultados dos diretos',
        icon: Icons.videocam_outlined,
      ));
    }

    final vendas = <PerfilNavEntry>[];
    if (staff.can(SellerStaffPermissions.canCreateProducts)) {
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.novoAnuncio,
        title: 'Novo anúncio',
        icon: Icons.add_box_outlined,
        external: true,
      ));
    }
    if (staff.can(SellerStaffPermissions.canViewPayouts) ||
        staff.can(SellerStaffPermissions.canManagePayouts)) {
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.saldo,
        title: 'O meu Saldo',
        icon: Icons.account_balance_wallet_outlined,
      ));
    }
    if (staff.isOwnerContext) {
      vendas.add(PerfilNavEntry(
        pane: PerfilDesktopPane.fleahub,
        title: HubSellerCopy.accountMenuTitle,
        subtitle: HubSellerCopy.accountMenuSubtitle,
        icon: Icons.store_mall_directory_outlined,
      ));
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.descontos,
        title: 'Descontos de conjuntos',
        icon: Icons.percent_rounded,
      ));
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.ferias,
        title: 'Modo de férias',
        icon: Icons.beach_access_outlined,
      ));
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.referencias,
        title: 'Gestão de referências',
        icon: Icons.qr_code_2_outlined,
      ));
      vendas.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.equipa,
        title: 'Equipa e colaboradores',
        icon: Icons.groups_outlined,
      ));
    }
    if (staff.myPendingInvitations.isNotEmpty) {
      vendas.add(PerfilNavEntry(
        pane: PerfilDesktopPane.convites,
        title: staff.myPendingInvitations.length == 1
            ? 'Convite de colaborador (pendente)'
            : '${staff.myPendingInvitations.length} convites de colaborador',
        icon: Icons.mail_outline_rounded,
        external: true,
      ));
    }
    if (staff.myHelperLinks.isNotEmpty ||
        staff.myPendingInvitations.isNotEmpty) {
      vendas.add(PerfilNavEntry(
        pane: PerfilDesktopPane.acessoColaborador,
        title: staff.actingAsHelper
            ? 'Acesso de colaborador (loja activa)'
            : 'Acesso de colaborador',
        icon: Icons.badge_outlined,
      ));
    }

    final ajuda = <PerfilNavEntry>[
      // Ordem H15–H19 + legais (sem «Explorar FleaHub» — redundante no Hub).
      const PerfilNavEntry(
        pane: PerfilDesktopPane.comoFunciona,
        title: 'Como funciona o Fleaber',
        icon: Icons.help_outline_rounded,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.comprarSeguro,
        title: 'Comprar com segurança',
        icon: Icons.verified_user_outlined,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.venderFleaber,
        title: 'Vender na Fleaber',
        icon: Icons.storefront_outlined,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.faq,
        title: 'Perguntas Frequentes',
        icon: Icons.question_answer_outlined,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.contactos,
        title: 'Contactos e identificação legal',
        icon: Icons.mail_outline_rounded,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.infoLegal,
        title: 'Informação legal',
        icon: Icons.gavel_outlined,
      ),
      const PerfilNavEntry(
        pane: PerfilDesktopPane.sobre,
        title: 'Sobre a nossa plataforma',
        icon: Icons.info_outline_rounded,
      ),
    ];
    if (widget.isAdmin) {
      ajuda.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.admin,
        title: 'Administração Fleaber',
        icon: Icons.admin_panel_settings_outlined,
        external: true,
      ));
      ajuda.add(const PerfilNavEntry(
        pane: PerfilDesktopPane.importadorAmazon,
        title: 'Importador Amazon',
        icon: Icons.inventory_2_outlined,
        external: true,
      ));
    }

    return {
      if (conta.isNotEmpty) PerfilDesktopNavGroups.conta: conta,
      if (compras.isNotEmpty) PerfilDesktopNavGroups.compras: compras,
      if (vendas.isNotEmpty) PerfilDesktopNavGroups.vendas: vendas,
      PerfilDesktopNavGroups.ajuda: ajuda,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SellerStaffContext.instance,
      builder: (context, _) {
        final staff = SellerStaffContext.instance;
        final groups = _groups(staff);
        final sideW = HubTheme.profileSidebarWidthFor(context);
        return Column(
          children: [
            _Header(
              unreadFuture: widget.unreadMessagesFuture,
              onCreate: _showCreate,
            ),
            const ColoredBox(
              color: FleaHubSiteLayout.topBarHairline,
              child: SizedBox(height: 1, width: double.infinity),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: sideW,
                    child: _Sidebar(
                      selected: _pane,
                      expanded: _expanded,
                      groups: groups,
                      onToggleGroup: (g) {
                        setState(() {
                          if (_expanded.contains(g)) {
                            _expanded.remove(g);
                          } else {
                            _expanded.add(g);
                          }
                        });
                      },
                      onSelect: _select,
                      onSignOut: () async {
                        GoRouter.of(context).prepareAuthEvent();
                        await authManager.signOut();
                        if (!context.mounted) return;
                        context.goNamedAuth(
                          LoginWidget.routeName,
                          context.mounted,
                        );
                      },
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: FleaberColors.alternate,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: FleaberColors.bgTint,
                      child: _PaneHost(
                        pane: _pane,
                        staff: staff,
                        fullName: widget.fullName,
                        photoUrl: widget.photoUrl,
                        profileId: widget.profileId,
                        hasManualProfilePhoto: widget.hasManualProfilePhoto,
                        showVerificationBadges: widget.showVerificationBadges,
                        emailVerified: widget.emailVerified,
                        phoneVerified: widget.phoneVerified,
                        profileFetchDegraded: widget.profileFetchDegraded,
                        onRefreshProfile: widget.onRefreshProfile,
                        onSelectPane: _select,
                        legalDocKind: _legalDocKind,
                        liveId: _liveId,
                        orderId: _orderId,
                        onOpenLiveId: _openLiveDetail,
                        onCloseLiveId: _closeLiveDetail,
                        onOpenLegalDoc: (kind) {
                          // Atalhos informativos → secções H11 (sem sair do shell).
                          if (kind == 'fleahub-account') {
                            _select(PerfilDesktopPane.fleahub);
                            return;
                          }
                          if (kind == 'how') {
                            _select(PerfilDesktopPane.comoFunciona);
                            return;
                          }
                          if (kind == 'faq') {
                            _select(PerfilDesktopPane.faq);
                            return;
                          }
                          if (kind == 'about') {
                            _select(PerfilDesktopPane.sobre);
                            return;
                          }
                          setState(() => _legalDocKind = kind);
                          _syncSecaoQuery(
                            PerfilDesktopPane.infoLegal,
                            legalDoc: kind,
                          );
                        },
                        onCloseLegalDoc: () {
                          setState(() => _legalDocKind = null);
                          _syncSecaoQuery(PerfilDesktopPane.infoLegal);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.unreadFuture,
    required this.onCreate,
  });

  final Future<List<ChatMessagesRow>> unreadFuture;
  final void Function([BuildContext? anchor]) onCreate;

  @override
  Widget build(BuildContext context) {
    final muted = FleaberColors.muted;
    final active = FleaberColors.teal;
    TextStyle linkStyle(bool on) => GoogleFonts.inter(
          color: on ? active : muted,
          fontSize: FleaHubSiteLayout.typeNav,
          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
        );

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
      Widget? badge,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: selected ? active : muted),
                  if (badge != null)
                    Positioned(right: -3, top: -3, child: badge),
                ],
              ),
              const SizedBox(width: 8),
              Text(label, style: linkStyle(selected)),
            ],
          ),
        ),
      );
    }

    final unreadDot = FutureBuilder<List<ChatMessagesRow>>(
      future: unreadFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: FleaberColors.teal,
            shape: BoxShape.circle,
          ),
        );
      },
    );

    return Material(
      color: FleaberColors.surface,
      child: SizedBox(
        height: FleaHubSiteLayout.topBarHeight,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              InkWell(
                onTap: () => HubNavigation.goAppHome(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    'Fleaber',
                    style: GoogleFonts.inter(
                      color: FleaberColors.teal,
                      fontSize: FleaHubSiteLayout.typeLogo,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Conta',
                style: GoogleFonts.inter(
                  color: FleaberColors.muted,
                  fontSize: FleaHubSiteLayout.typeSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              chip(
                icon: Icons.home_outlined,
                label: 'Início',
                onTap: () => HubNavigation.goAppHome(context),
              ),
              chip(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Mensagens',
                badge: unreadDot,
                onTap: () => HubAccountRoutes.openMensagens(context),
              ),
              Builder(
                builder: (btnCtx) => chip(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Criar',
                  onTap: () => onCreate(btnCtx),
                ),
              ),
              chip(
                icon: Icons.person_rounded,
                label: 'Perfil',
                selected: true,
                onTap: () => context.pushNamed(PerfilWidget.routeName),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.expanded,
    required this.groups,
    required this.onToggleGroup,
    required this.onSelect,
    required this.onSignOut,
  });

  final PerfilDesktopPane selected;
  final Set<String> expanded;
  final Map<String, List<PerfilNavEntry>> groups;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<PerfilDesktopPane> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FleaberColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              children: [
                _sideItem(
                  context,
                  pane: PerfilDesktopPane.resumo,
                  icon: Icons.dashboard_outlined,
                  label: 'Resumo',
                ),
                const SizedBox(height: 8),
                for (final e in groups.entries) ...[
                  _groupHeader(e.key),
                  if (expanded.contains(e.key))
                    for (final item in e.value)
                      _sideItem(
                        context,
                        pane: item.pane,
                        icon: item.icon,
                        label: item.title,
                        external: item.external,
                      ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: FleaberColors.alternate),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: TextButton(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: FleaberColors.danger,
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              child: Text(
                'Terminar Sessão',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String title) {
    final open = expanded.contains(title);
    return InkWell(
      onTap: () => onToggleGroup(title),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: FleaberColors.muted,
                ),
              ),
            ),
            Icon(
              open
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
              color: FleaberColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideItem(
    BuildContext context, {
    required PerfilDesktopPane pane,
    required IconData icon,
    required String label,
    bool external = false,
  }) {
    final on = selected == pane && !external;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        key: ValueKey<String>('perfil-nav-${pane.name}'),
        color: on
            ? FleaberColors.teal.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onSelect(pane),
          borderRadius: BorderRadius.circular(10),
          child: Semantics(
            button: true,
            selected: on,
            label: 'perfil-nav-${pane.name}',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: on ? FleaberColors.teal : FleaberColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? FleaberColors.teal : FleaberColors.text,
                      ),
                    ),
                  ),
                  if (external)
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: FleaberColors.muted.withValues(alpha: 0.7),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneHost extends StatelessWidget {
  const _PaneHost({
    required this.pane,
    required this.staff,
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.hasManualProfilePhoto,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    required this.profileFetchDegraded,
    required this.onRefreshProfile,
    required this.onSelectPane,
    this.legalDocKind,
    this.liveId,
    this.orderId,
    this.onOpenLiveId,
    this.onCloseLiveId,
    this.onOpenLegalDoc,
    this.onCloseLegalDoc,
  });

  final PerfilDesktopPane pane;
  final SellerStaffContext staff;
  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool hasManualProfilePhoto;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final bool profileFetchDegraded;
  final Future<void> Function() onRefreshProfile;
  final ValueChanged<PerfilDesktopPane> onSelectPane;
  final String? legalDocKind;
  final String? liveId;
  final String? orderId;
  final ValueChanged<String>? onOpenLiveId;
  final VoidCallback? onCloseLiveId;
  final ValueChanged<String>? onOpenLegalDoc;
  final VoidCallback? onCloseLegalDoc;

  String? get _paneTitle =>
      PerfilAccountPaneTitles.titleFor(pane, legalDocKind: legalDocKind);

  bool get _isReadingPane =>
      pane == PerfilDesktopPane.comoFunciona ||
      pane == PerfilDesktopPane.comprarSeguro ||
      pane == PerfilDesktopPane.venderFleaber ||
      pane == PerfilDesktopPane.faq ||
      pane == PerfilDesktopPane.contactos ||
      pane == PerfilDesktopPane.infoLegal ||
      pane == PerfilDesktopPane.sobre;

  bool get _hideShellTitleForLiveDetail =>
      pane == PerfilDesktopPane.resultadosLive &&
      (liveId ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final title = _paneTitle;
    final pad = _hideShellTitleForLiveDetail
        ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
        : const EdgeInsets.fromLTRB(24, 16, 24, 20);
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pane == PerfilDesktopPane.resumo) ...[
            Text(
              'A minha conta',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: FleaberColors.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: AccountContextBadge(compact: true, fitContent: true),
            ),
            if (staff.myPendingInvitations.isNotEmpty) ...[
              const SizedBox(height: 10),
              const HelperPendingInvitesBanner(),
            ],
            if (profileFetchDegraded) ...[
              const SizedBox(height: 10),
              _DegradeBanner(onRetry: onRefreshProfile),
            ],
            const SizedBox(height: 14),
          ] else if (title != null && !_hideShellTitleForLiveDetail) ...[
            Row(
              children: [
                if (pane == PerfilDesktopPane.infoLegal &&
                    legalDocKind != null) ...[
                  IconButton(
                    tooltip: 'Voltar à lista',
                    onPressed: onCloseLegalDoc,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: FleaberColors.teal,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: FleaberColors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: KeyedSubtree(
              key: ValueKey<String>(
                'perfil-pane-${pane.name}-${legalDocKind ?? 'root'}-${liveId ?? 'list'}-${orderId ?? 'none'}',
              ),
              child: _wrapPane(_buildPane(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapPane(Widget child) {
    if (_isReadingPane) {
      // Coluna de leitura à esquerda (≈ 760–900 px). Um único scroll do painel —
      // o conteúdo (FAQ, etc.) cresce; sem ListView interno com barra própria.
      return PrimaryScrollController.none(
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: child,
            ),
          ),
        ),
      );
    }
    return child;
  }

  Widget _buildPane(BuildContext context) {
    return PerfilAccountPaneBody(
      pane: pane,
      staff: staff,
      fullName: fullName,
      photoUrl: photoUrl,
      profileId: profileId,
      hasManualProfilePhoto: hasManualProfilePhoto,
      showVerificationBadges: showVerificationBadges,
      emailVerified: emailVerified,
      phoneVerified: phoneVerified,
      onSelectPane: onSelectPane,
      onRefreshProfile: onRefreshProfile,
      legalDocKind: legalDocKind,
      liveId: liveId,
      orderId: orderId,
      onOpenLiveId: onOpenLiveId,
      onCloseLiveId: onCloseLiveId,
      onOpenLegalDoc: onOpenLegalDoc,
    );
  }
}

/// Título humano da secção H11 (shell desktop + mobile).
abstract final class PerfilAccountPaneTitles {
  PerfilAccountPaneTitles._();

  static String? titleFor(PerfilDesktopPane pane, {String? legalDocKind}) {
    switch (pane) {
      case PerfilDesktopPane.resumo:
        return null;
      case PerfilDesktopPane.contaDefinicoes:
        return 'Definições de conta';
      case PerfilDesktopPane.favoritos:
        return 'Favoritos';
      case PerfilDesktopPane.encomendas:
        return 'Encomendas e Compras';
      case PerfilDesktopPane.resultadosLive:
        return 'Resultados dos diretos';
      case PerfilDesktopPane.saldo:
        return 'O meu Saldo';
      case PerfilDesktopPane.fleahub:
        return HubSellerCopy.accountMenuTitle;
      case PerfilDesktopPane.descontos:
        return 'Descontos de conjuntos';
      case PerfilDesktopPane.ferias:
        return 'Modo de férias';
      case PerfilDesktopPane.referencias:
        return 'Gestão de referências';
      case PerfilDesktopPane.equipa:
        return 'Equipa e colaboradores';
      case PerfilDesktopPane.acessoColaborador:
        return 'Acesso de colaborador';
      case PerfilDesktopPane.comoFunciona:
        return 'Como funciona o Fleaber';
      case PerfilDesktopPane.comprarSeguro:
        return 'Comprar com segurança';
      case PerfilDesktopPane.venderFleaber:
        return 'Vender na Fleaber';
      case PerfilDesktopPane.faq:
        return 'Perguntas Frequentes';
      case PerfilDesktopPane.contactos:
        return 'Contactos e identificação legal';
      case PerfilDesktopPane.infoLegal:
        if (legalDocKind != null && legalDocKind.isNotEmpty) {
          return LegalDocumentPageWidget.fromKind(legalDocKind).title;
        }
        return 'Informação legal';
      case PerfilDesktopPane.sobre:
        return 'Sobre a nossa plataforma';
      default:
        return null;
    }
  }
}

/// Conteúdo real de uma secção H11 (partilhado desktop shell + mobile).
class PerfilAccountPaneBody extends StatelessWidget {
  const PerfilAccountPaneBody({
    super.key,
    required this.pane,
    required this.staff,
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.hasManualProfilePhoto,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    required this.onSelectPane,
    this.onRefreshProfile,
    this.legalDocKind,
    this.liveId,
    this.orderId,
    this.onOpenLiveId,
    this.onCloseLiveId,
    this.onOpenLegalDoc,
  });

  final PerfilDesktopPane pane;
  final SellerStaffContext staff;
  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool hasManualProfilePhoto;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final ValueChanged<PerfilDesktopPane> onSelectPane;
  final Future<void> Function()? onRefreshProfile;
  final String? legalDocKind;
  final String? liveId;
  final String? orderId;
  final ValueChanged<String>? onOpenLiveId;
  final VoidCallback? onCloseLiveId;
  final ValueChanged<String>? onOpenLegalDoc;

  @override
  Widget build(BuildContext context) {
    switch (pane) {
      case PerfilDesktopPane.resumo:
        return _ResumoPane(
          staff: staff,
          fullName: fullName,
          photoUrl: photoUrl,
          profileId: profileId,
          hasManualProfilePhoto: hasManualProfilePhoto,
          showVerificationBadges: showVerificationBadges,
          emailVerified: emailVerified,
          phoneVerified: phoneVerified,
          onSelectPane: onSelectPane,
          onRefreshProfile: onRefreshProfile,
        );
      case PerfilDesktopPane.contaDefinicoes:
        return const ContaDefinicoesWidget(embedded: true);
      case PerfilDesktopPane.favoritos:
        return const FavoritosPageWidget(embedded: true);
      case PerfilDesktopPane.encomendas:
        return MinhasEncomendasWidget(
          embedded: true,
          initialOrderId: orderId,
        );
      case PerfilDesktopPane.resultadosLive:
        final lid = (liveId ?? '').trim();
        if (lid.isNotEmpty) {
          return LiveSalesSessionDetailPageWidget(
            liveId: lid,
            embedded: true,
            onBack: onCloseLiveId,
          );
        }
        return LiveSalesSessionsPageWidget(
          embedded: true,
          onOpenLiveId: onOpenLiveId,
        );
      case PerfilDesktopPane.saldo:
        return const WalletPageWidget(embedded: true);
      case PerfilDesktopPane.fleahub:
        return _FleahubManagePane();
      case PerfilDesktopPane.descontos:
        return const DescontosConjuntosWidget(embedded: true);
      case PerfilDesktopPane.ferias:
        return const ModoFeriasPageWidget(embedded: true);
      case PerfilDesktopPane.referencias:
        return const GestaoReferenciasPageWidget(embedded: true);
      case PerfilDesktopPane.equipa:
        return const SellerHelpersPageWidget(embedded: true);
      case PerfilDesktopPane.acessoColaborador:
        return const HelperAccessPageWidget(embedded: true);
      case PerfilDesktopPane.comoFunciona:
        return HowItWorksBody(
          embedded: true,
          compactPadding: true,
          onBuySafe: () => onSelectPane(PerfilDesktopPane.comprarSeguro),
          onSell: () => onSelectPane(PerfilDesktopPane.venderFleaber),
          onFaq: () => onSelectPane(PerfilDesktopPane.faq),
        );
      case PerfilDesktopPane.comprarSeguro:
        return LegalDocumentPageWidget.fromKind('buy-safe', embedded: true);
      case PerfilDesktopPane.venderFleaber:
        return LegalDocumentPageWidget.fromKind('sell', embedded: true);
      case PerfilDesktopPane.faq:
        return LegalDocumentPageWidget.fromKind('faq', embedded: true);
      case PerfilDesktopPane.contactos:
        return LegalDocumentPageWidget.fromKind('contacts', embedded: true);
      case PerfilDesktopPane.infoLegal:
        if (legalDocKind != null) {
          return LegalDocumentPageWidget.fromKind(
            legalDocKind,
            embedded: true,
          );
        }
        return LegalHubPageWidget(
          embedded: true,
          onOpenDocument: onOpenLegalDoc,
        );
      case PerfilDesktopPane.sobre:
        return LegalDocumentPageWidget.fromKind('about', embedded: true);
      case PerfilDesktopPane.novoAnuncio:
      case PerfilDesktopPane.explorarFleahub:
      case PerfilDesktopPane.admin:
      case PerfilDesktopPane.importadorAmazon:
      case PerfilDesktopPane.convites:
      case PerfilDesktopPane.definicoesLoja:
        return const SizedBox.shrink();
    }
  }
}

/// Mobile web (&lt;768): secção H11 a ecrã inteiro, sem sidebar comprimida.
class PerfilMobileSectionScaffold extends StatefulWidget {
  const PerfilMobileSectionScaffold({
    super.key,
    required this.pane,
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.hasManualProfilePhoto,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    this.onRefreshProfile,
    this.initialLegalDoc,
    this.initialLiveId,
    this.initialOrderId,
  });

  final PerfilDesktopPane pane;
  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool hasManualProfilePhoto;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final Future<void> Function()? onRefreshProfile;
  final String? initialLegalDoc;
  final String? initialLiveId;
  final String? initialOrderId;

  @override
  State<PerfilMobileSectionScaffold> createState() =>
      _PerfilMobileSectionScaffoldState();
}

class _PerfilMobileSectionScaffoldState
    extends State<PerfilMobileSectionScaffold> {
  late PerfilDesktopPane _pane;
  String? _legalDocKind;
  String? _liveId;
  String? _orderId;

  @override
  void initState() {
    super.initState();
    _pane = widget.pane.embedsInShell ? widget.pane : PerfilDesktopPane.resumo;
    if (_pane == PerfilDesktopPane.infoLegal &&
        (widget.initialLegalDoc ?? '').trim().isNotEmpty) {
      _legalDocKind = widget.initialLegalDoc!.trim();
    }
    if (_pane == PerfilDesktopPane.resultadosLive &&
        (widget.initialLiveId ?? '').trim().isNotEmpty) {
      _liveId = widget.initialLiveId!.trim();
    }
    if (_pane == PerfilDesktopPane.encomendas &&
        (widget.initialOrderId ?? '').trim().isNotEmpty) {
      _orderId = widget.initialOrderId!.trim();
    }
  }

  @override
  void didUpdateWidget(covariant PerfilMobileSectionScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pane != widget.pane && widget.pane.embedsInShell) {
      _pane = widget.pane;
      _legalDocKind = (_pane == PerfilDesktopPane.infoLegal)
          ? widget.initialLegalDoc
          : null;
      _liveId = (_pane == PerfilDesktopPane.resultadosLive)
          ? widget.initialLiveId
          : null;
      _orderId = (_pane == PerfilDesktopPane.encomendas)
          ? widget.initialOrderId
          : null;
    } else if (oldWidget.initialLegalDoc != widget.initialLegalDoc &&
        _pane == PerfilDesktopPane.infoLegal) {
      _legalDocKind = widget.initialLegalDoc;
    } else if (oldWidget.initialLiveId != widget.initialLiveId &&
        _pane == PerfilDesktopPane.resultadosLive) {
      _liveId = widget.initialLiveId;
    } else if (oldWidget.initialOrderId != widget.initialOrderId &&
        _pane == PerfilDesktopPane.encomendas) {
      _orderId = widget.initialOrderId;
    }
  }

  void _syncQuery({String? legalDoc, String? liveId, String? orderId}) {
    if (!kIsWeb) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final params = <String, String>{'secao': _pane.name};
    final doc = legalDoc ??
        (_pane == PerfilDesktopPane.infoLegal ? _legalDocKind : null);
    if (doc != null && doc.isNotEmpty) {
      params['doc'] = doc;
    }
    final lid = liveId ??
        (_pane == PerfilDesktopPane.resultadosLive ? _liveId : null);
    if (lid != null && lid.isNotEmpty) {
      params['liveId'] = lid;
    }
    final oid = orderId ??
        (_pane == PerfilDesktopPane.encomendas ? _orderId : null);
    if (oid != null && oid.trim().isNotEmpty) {
      params['orderId'] = oid.trim();
    }
    router.replaceNamed('Perfil', queryParameters: params);
  }

  void _select(PerfilDesktopPane pane) {
    switch (pane) {
      case PerfilDesktopPane.novoAnuncio:
        context.pushNamed(SellerProductFormWidget.routeName);
        return;
      case PerfilDesktopPane.explorarFleahub:
        HubActions.openFleaHubLanding(context);
        return;
      case PerfilDesktopPane.admin:
        context.pushNamed(AdminPageWidget.routeName);
        return;
      case PerfilDesktopPane.importadorAmazon:
        context.pushNamed(AmazonImporterHubPage.routeName);
        return;
      case PerfilDesktopPane.convites:
        HelperPendingInvitesBanner.openPendingInvites(context);
        return;
      case PerfilDesktopPane.definicoesLoja:
        context.pushNamed(
          PerfilVendedorWidget.routeName,
          queryParameters: {
            'sellerID': serializeParam(
              SellerStaffContext.instance.effectiveSellerId,
              ParamType.String,
            ),
          }.withoutNulls,
        );
        return;
      default:
        setState(() {
          _pane = pane;
          if (pane != PerfilDesktopPane.infoLegal) {
            _legalDocKind = null;
          }
          if (pane != PerfilDesktopPane.resultadosLive) {
            _liveId = null;
          }
          if (pane != PerfilDesktopPane.encomendas) {
            _orderId = null;
          }
        });
        _syncQuery();
    }
  }

  void _backToMenu() {
    if (_liveId != null && _pane == PerfilDesktopPane.resultadosLive) {
      setState(() => _liveId = null);
      _syncQuery(liveId: '');
      return;
    }
    context.go(PerfilWidget.routePath);
  }

  @override
  Widget build(BuildContext context) {
    final title = PerfilAccountPaneTitles.titleFor(
          _pane,
          legalDocKind: _legalDocKind,
        ) ??
        'Conta';
    return ListenableBuilder(
      listenable: SellerStaffContext.instance,
      builder: (context, _) {
        final staff = SellerStaffContext.instance;
        return Scaffold(
          backgroundColor: FleaberColors.bgTint,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: FleaberColors.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              tooltip: 'Voltar ao Perfil',
              icon: const Icon(Icons.arrow_back_rounded),
              color: FleaberColors.teal,
              onPressed: _legalDocKind != null &&
                      _pane == PerfilDesktopPane.infoLegal
                  ? () {
                      setState(() => _legalDocKind = null);
                      _syncQuery();
                    }
                  : _backToMenu,
            ),
            title: Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: FleaberColors.text,
                fontSize: 17,
              ),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Builder(
                builder: (context) {
                  final paneBody = PerfilAccountPaneBody(
                    pane: _pane,
                    staff: staff,
                    fullName: widget.fullName,
                    photoUrl: widget.photoUrl,
                    profileId: widget.profileId,
                    hasManualProfilePhoto: widget.hasManualProfilePhoto,
                    showVerificationBadges: widget.showVerificationBadges,
                    emailVerified: widget.emailVerified,
                    phoneVerified: widget.phoneVerified,
                    onSelectPane: _select,
                    onRefreshProfile: widget.onRefreshProfile,
                    legalDocKind: _legalDocKind,
                    liveId: _liveId,
                    orderId: _orderId,
                    onOpenLiveId: (id) {
                      setState(() {
                        _pane = PerfilDesktopPane.resultadosLive;
                        _liveId = id;
                      });
                      _syncQuery(liveId: id);
                    },
                    onCloseLiveId: () {
                      setState(() => _liveId = null);
                      _syncQuery(liveId: '');
                    },
                    onOpenLegalDoc: (kind) {
                      if (kind == 'fleahub-account') {
                        _select(PerfilDesktopPane.fleahub);
                        return;
                      }
                      if (kind == 'how') {
                        _select(PerfilDesktopPane.comoFunciona);
                        return;
                      }
                      if (kind == 'faq') {
                        _select(PerfilDesktopPane.faq);
                        return;
                      }
                      if (kind == 'about') {
                        _select(PerfilDesktopPane.sobre);
                        return;
                      }
                      setState(() => _legalDocKind = kind);
                      _syncQuery(legalDoc: kind);
                    },
                  );
                  // Páginas de leitura (FAQ, etc.): conteúdo em Column — um scroll
                  // de página, sem ListView interno.
                  final isReading = _pane == PerfilDesktopPane.comoFunciona ||
                      _pane == PerfilDesktopPane.comprarSeguro ||
                      _pane == PerfilDesktopPane.venderFleaber ||
                      _pane == PerfilDesktopPane.faq ||
                      _pane == PerfilDesktopPane.contactos ||
                      _pane == PerfilDesktopPane.infoLegal ||
                      _pane == PerfilDesktopPane.sobre;
                  if (!isReading) return paneBody;
                  return PrimaryScrollController.none(
                    child: SingleChildScrollView(child: paneBody),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResumoPane extends StatefulWidget {
  const _ResumoPane({
    required this.staff,
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.hasManualProfilePhoto,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    required this.onSelectPane,
    this.onRefreshProfile,
  });

  final SellerStaffContext staff;
  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool hasManualProfilePhoto;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final ValueChanged<PerfilDesktopPane> onSelectPane;
  final Future<void> Function()? onRefreshProfile;

  @override
  State<_ResumoPane> createState() => _ResumoPaneState();
}

class _ResumoPaneState extends State<_ResumoPane> {
  bool _proVerified = false;

  @override
  void initState() {
    super.initState();
    _loadProfessionalStatus();
  }

  @override
  void didUpdateWidget(covariant _ResumoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.staff.effectiveSellerId != widget.staff.effectiveSellerId) {
      _loadProfessionalStatus();
    }
  }

  Future<void> _loadProfessionalStatus() async {
    final id = widget.staff.effectiveSellerId.trim().isNotEmpty
        ? widget.staff.effectiveSellerId.trim()
        : widget.profileId.trim();
    if (id.isEmpty) return;
    final cached = SellerProfessionalCache.peek(id);
    if (cached != null) {
      if (!mounted) return;
      setState(() => _proVerified = cached.showProfessionalBadge);
      return;
    }
    final map = await SellerProfessionalCache.warm([id]);
    if (!mounted) return;
    setState(() => _proVerified = map[id]?.showProfessionalBadge == true);
  }

  void _openPublicProfile() {
    unawaited(
      HubActions.openPublicProfile(
        context,
        sellerId: widget.staff.effectiveSellerId,
      ),
    );
  }

  Future<void> _updatePhoto() async {
    final url = await ProfilePhotoPicker.pickAndSave(context);
    if (url == null || !mounted) return;
    await widget.onRefreshProfile?.call();
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.staff;
    final shortcuts =
        <({PerfilDesktopPane pane, IconData icon, String title, String desc})>[
      if (staff.isOwnerContext)
        (
          pane: PerfilDesktopPane.favoritos,
          icon: Icons.favorite_border_rounded,
          title: 'Favoritos',
          desc: 'Artigos e vendedores guardados',
        ),
      if (staff.isOwnerContext ||
          staff.can(SellerStaffPermissions.canManageOrders))
        (
          pane: PerfilDesktopPane.encomendas,
          icon: Icons.local_shipping_outlined,
          title: 'Encomendas e Compras',
          desc: 'Compras e vendas em curso',
        ),
      if (staff.can(SellerStaffPermissions.canViewPayouts) ||
          staff.can(SellerStaffPermissions.canManagePayouts))
        (
          pane: PerfilDesktopPane.saldo,
          icon: Icons.account_balance_wallet_outlined,
          title: 'O meu saldo',
          desc: 'Carteira e levantamentos',
        ),
      if (staff.isOwnerContext)
        (
          pane: PerfilDesktopPane.fleahub,
          icon: Icons.store_mall_directory_outlined,
          title: 'FleaHub',
          desc: 'Gerir e partilhar o teu Hub',
        ),
    ];

    return ListView(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _ResumoIdentityBlock(
              fullName: widget.fullName,
              photoUrl: widget.photoUrl,
              profileId: widget.profileId,
              showVerificationBadges: widget.showVerificationBadges,
              emailVerified: widget.emailVerified,
              phoneVerified: widget.phoneVerified,
              showProChip: _proVerified && staff.isOwnerContext,
              showEdit: staff.isOwnerContext,
              showUpdatePhoto:
                  staff.isOwnerContext && !widget.hasManualProfilePhoto,
              onOpenProfile: _openPublicProfile,
              onEdit: () =>
                  widget.onSelectPane(PerfilDesktopPane.contaDefinicoes),
              onUpdatePhoto: _updatePhoto,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Acessos rápidos',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: FleaberColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        if (shortcuts.isEmpty)
          Text(
            'Usa o menu à esquerda para navegar na tua conta.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: FleaberColors.muted,
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: _ResumoShortcutPanel(
              items: [
                for (final s in shortcuts)
                  (
                    icon: s.icon,
                    title: s.title,
                    description: s.desc,
                    onTap: () => widget.onSelectPane(s.pane),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Identidade da conta — sem cartão full-width; hierarquia tipográfica limpa.
class _ResumoIdentityBlock extends StatelessWidget {
  const _ResumoIdentityBlock({
    required this.fullName,
    required this.photoUrl,
    required this.profileId,
    required this.showVerificationBadges,
    required this.emailVerified,
    required this.phoneVerified,
    required this.showProChip,
    required this.showEdit,
    required this.showUpdatePhoto,
    required this.onOpenProfile,
    required this.onEdit,
    required this.onUpdatePhoto,
  });

  final String fullName;
  final String? photoUrl;
  final String profileId;
  final bool showVerificationBadges;
  final bool emailVerified;
  final bool phoneVerified;
  final bool showProChip;
  final bool showEdit;
  final bool showUpdatePhoto;
  final VoidCallback onOpenProfile;
  final VoidCallback onEdit;
  final VoidCallback onUpdatePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenProfile,
                customBorder: const CircleBorder(),
                child: FleaberProfileAvatar(
                  userId: profileId,
                  fullName: fullName,
                  photoUrl: photoUrl,
                  radius: 40,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.4,
                      color: FleaberColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if (showVerificationBadges)
                        FleaberVerificationBadges(
                          emailVerified: emailVerified,
                          phoneVerified: phoneVerified,
                          compact: true,
                        ),
                      if (showProChip)
                        Text(
                          'Vendedor profissional',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: FleaberColors.teal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onOpenProfile,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'Ver perfil público',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: FleaberColors.teal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showEdit || showUpdatePhoto) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showEdit)
                _ResumoSoftAction(
                  icon: Icons.edit_outlined,
                  label: 'Editar perfil',
                  emphasized: true,
                  onPressed: onEdit,
                ),
              if (showUpdatePhoto)
                _ResumoSoftAction(
                  icon: Icons.add_a_photo_outlined,
                  label: 'Atualizar fotografia',
                  emphasized: false,
                  onPressed: onUpdatePhoto,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ResumoSoftAction extends StatelessWidget {
  const _ResumoSoftAction({
    required this.icon,
    required this.label,
    required this.emphasized,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool emphasized;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = emphasized ? FleaberColors.teal : FleaberColors.text;
    final bg = emphasized
        ? FleaberColors.teal.withValues(alpha: 0.08)
        : const Color(0xFFF0F4F5);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um painel único com linhas — evita quatro caixas idênticas com sombra.
class _ResumoShortcutPanel extends StatelessWidget {
  const _ResumoShortcutPanel({required this.items});

  final List<
      ({
        IconData icon,
        String title,
        String description,
        VoidCallback onTap,
      })> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 560 && items.length > 1;
        if (!twoCol) {
          return _panel(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFE8ECEE)),
                _ResumoShortcutRow(
                  icon: items[i].icon,
                  title: items[i].title,
                  description: items[i].description,
                  onTap: items[i].onTap,
                ),
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += 2) {
          if (rows.isNotEmpty) {
            rows.add(const Divider(height: 1, color: Color(0xFFE8ECEE)));
          }
          final left = items[i];
          final hasRight = i + 1 < items.length;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ResumoShortcutRow(
                      icon: left.icon,
                      title: left.title,
                      description: left.description,
                      onTap: left.onTap,
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFFE8ECEE),
                  ),
                  Expanded(
                    child: hasRight
                        ? _ResumoShortcutRow(
                            icon: items[i + 1].icon,
                            title: items[i + 1].title,
                            description: items[i + 1].description,
                            onTap: items[i + 1].onTap,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }
        return _panel(children: rows);
      },
    );
  }

  Widget _panel({required List<Widget> children}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECEE)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _ResumoShortcutRow extends StatelessWidget {
  const _ResumoShortcutRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Icon(icon, color: FleaberColors.teal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        height: 1.2,
                        color: FleaberColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.3,
                        color: FleaberColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9AA5AB),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FleahubManagePane extends StatefulWidget {
  @override
  State<_FleahubManagePane> createState() => _FleahubManagePaneState();
}

class _FleahubManagePaneState extends State<_FleahubManagePane> {
  bool _managing = false;
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (_managing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _managing = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Voltar ao FleaHub'),
              style: TextButton.styleFrom(foregroundColor: FleaberColors.teal),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FleaberColors.alternate),
              ),
              child: HubSellerHubManageBody(
                lightChrome: true,
                onChanged: () {
                  // Recarrega cartão ao voltar.
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      children: [
        Text(
          HubSellerCopy.accountMenuTitle,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: FleaberColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          HubSellerCopy.accountMenuSubtitle,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: FleaberColors.muted,
          ),
        ),
        const SizedBox(height: 16),
        HubSellerHubCard(
          key: _cardKey,
          compact: false,
          onManage: () => setState(() => _managing = true),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => HubActions.openFleaHubLanding(context),
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Explorar FleaHub público'),
            style: TextButton.styleFrom(foregroundColor: FleaberColors.teal),
          ),
        ),
      ],
    );
  }
}

class _DegradeBanner extends StatelessWidget {
  const _DegradeBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Não foi possível atualizar os dados do perfil.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5D4037),
                ),
              ),
            ),
            TextButton(
              onPressed: () => onRetry(),
              child: Text(
                'Tentar novamente',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: FleaberColors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
