import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/index.dart';
import '/utils/fleaber_elevation.dart';
import '/widgets/fleaber_create_sheet.dart';
import '/widgets/fleaber_refresh.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/helper_pending_invites_banner.dart';
import '/hub/hub_account_routes.dart';
import '/hub/hub_actions.dart';
import '/hub/hub_navigation.dart';
import '/hub/seller/hub_seller_copy.dart';
import '/hub/seller/hub_seller_sheet.dart';
import '/hub/seo/hub_seo_meta.dart';
import '/hub/theme/hub_theme.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/hub/widgets/hub_seo_scope.dart';
import '/perfil/perfil_account_shell.dart';
import '/perfil/perfil_desktop_nav.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// Secções do menu Perfil (sidebar desktop + agrupamento).
enum _ProfileNavSection {
  resumo,
  conta,
  compras,
  vendas,
  ajuda,
}

class _ProfileMenuItem {
  const _ProfileMenuItem({
    required this.section,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.quickAccess = false,
  });

  final _ProfileNavSection section;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;
  final bool quickAccess;
}

class PerfilWidget extends StatefulWidget {
  const PerfilWidget({super.key});

  static String routeName = 'Perfil';
  static String routePath = '/perfil';

  @override
  State<PerfilWidget> createState() => _PerfilWidgetState();
}

class _PerfilWidgetState extends State<PerfilWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<ProfilesRow>> _profileFuture;
  late Future<List<ChatMessagesRow>> _unreadMessagesFuture;
  static const Duration _kProfileQueryTimeout = Duration(seconds: 5);

  /// Último nome de perfil OK neste State (mitiga flicker em timeouts).
  String? _lastKnownProfileName;

  /// Web: query vazia após retentativa (timeout/rede) — banner discreto + retry.
  bool _profileFetchDegraded = false;

  _ProfileNavSection _desktopSection = _ProfileNavSection.resumo;

  /// Web: timeout mais longo — capturas Playwright/CDN lentas devolvem [] e o
  /// UI mostra fallback; Android mantém 5s (sem mudança de comportamento).
  Duration get _profileQueryTimeout =>
      kIsWeb ? const Duration(seconds: 20) : _kProfileQueryTimeout;

  Future<List<ProfilesRow>> _queryProfileOnce() {
    return ProfilesTable()
        .queryRows(
          queryFn: (q) => q.eqOrNull('id', currentUserUid),
          limit: 1,
        )
        .timeout(
          _profileQueryTimeout,
          onTimeout: () => const <ProfilesRow>[],
        )
        .catchError((_) => const <ProfilesRow>[]);
  }

  Future<List<ProfilesRow>> _loadProfile() async {
    _profileFetchDegraded = false;
    final first = await _queryProfileOnce();
    if (first.isNotEmpty) return first;
    // Web: [] pode ser timeout/rede; uma segunda tentativa evita
    // «Utilizador Fleaber» falso quando o perfil existe (evidência E27/E28).
    if (!kIsWeb) return first;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final second = await _queryProfileOnce();
    if (second.isEmpty) {
      _profileFetchDegraded = true;
    }
    return second;
  }

  /// Nome: perfil → cache ecrã → sessão auth → e-mail → fallback genérico.
  String _resolveDisplayName(ProfilesRow? profile) {
    final fromProfile = profile?.fullName?.trim() ?? '';
    if (fromProfile.isNotEmpty) {
      _lastKnownProfileName = fromProfile;
      return fromProfile;
    }
    final cached = _lastKnownProfileName?.trim() ?? '';
    if (cached.isNotEmpty) return cached;
    final fromAuth = currentUserDisplayName.trim();
    if (fromAuth.isNotEmpty) return fromAuth;
    final email = currentUserEmail.trim();
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }
    return 'Utilizador Fleaber';
  }

  Future<List<ChatMessagesRow>> _loadUnreadMessages() {
    return ChatMessagesTable()
        .queryRows(
          queryFn: (q) => q
              .eqOrNull('receiver_id', currentUserUid)
              .eqOrNull('is_read', false)
              .limit(1),
        )
        .timeout(
          _profileQueryTimeout,
          onTimeout: () => const <ChatMessagesRow>[],
        )
        .catchError((_) => const <ChatMessagesRow>[]);
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _profileFuture = _loadProfile();
      _unreadMessagesFuture = _loadUnreadMessages();
    });
    await _profileFuture;
  }

  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _unreadMessagesFuture = _loadUnreadMessages();
    unawaited(SellerStaffContext.instance.refresh());
    // Quando a sessão Supabase restaura no web, reconstruímos o shell.
    _authSub = SupaFlow.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() {
        _profileFuture = _loadProfile();
        _unreadMessagesFuture = _loadUnreadMessages();
      });
      unawaited(SellerStaffContext.instance.refresh());
      AppStateNotifier.instance.notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _showCreateBottomSheet([BuildContext? anchor]) =>
      FleaberCreateSheet.show(context, anchorContext: anchor ?? context);

  /// Web tablet/desktop: shell conta clara. Mobile web e Android: lista.
  bool _isDesktopAccount(BuildContext context) =>
      kIsWeb && HubTheme.useProfileDesktopLayout(context);

  TextStyle get _titleMd => GoogleFonts.inter(
        color: FleaberColors.text,
        fontSize: FleaHubSiteLayout.typeNavTitle,
        fontWeight: FontWeight.w700,
      );

  TextStyle get _bodyMuted => GoogleFonts.inter(
        color: FleaberColors.muted,
        fontSize: FleaHubSiteLayout.typeSecondary,
        height: 1.4,
      );

  TextStyle get _sectionLabel => GoogleFonts.inter(
        color: FleaberColors.muted,
        fontSize: FleaHubSiteLayout.typeCaption,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  BoxDecoration get _cardDeco => BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      );

  @override
  Widget build(BuildContext context) {
    // Web: espera restauração da sessão antes de montar painéis
    // (evita «Inicia sessão» / carteira vazia com UID ainda vazio).
    // Title nativo Flutter + HubSeoScope: o Title evita que MaterialApp
    // reescreva document.title para «Fleaber» depois do SEO.
    // resetOnDispose:false — evita race GoRouter a limpar a meta seguinte.
    return Title(
      title: 'Perfil — Fleaber',
      color: FleaberColors.teal,
      child: HubSeoScope(
        meta: HubSeoMeta.forAccountPerfil(),
        resetOnDispose: false,
        child: ListenableBuilder(
          listenable: AppStateNotifier.instance,
          builder: (context, _) {
            if (kIsWeb && currentUserUid.isEmpty) {
              final hasSession =
                  SupaFlow.client.auth.currentSession != null ||
                      AppStateNotifier.instance.loggedIn;
              if (hasSession) {
                // Sessão a sincronizar → spinner até UID estar disponível.
                return const Scaffold(
                  backgroundColor: FleaberColors.bgTint,
                  body: Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  ),
                );
              }
              // Emails E1–E3 / Conta: sem sessão → login e regresso ao destino.
              final qp = GoRouterState.of(context).uri.queryParameters;
              final secao = PerfilDesktopPaneParsing.tryParse(qp['secao']);
              final orderId = (qp['orderId'] ?? '').trim();
              final needsAuth = orderId.isNotEmpty ||
                  secao == PerfilDesktopPane.encomendas ||
                  secao == PerfilDesktopPane.saldo ||
                  secao == PerfilDesktopPane.favoritos ||
                  secao == PerfilDesktopPane.contaDefinicoes ||
                  secao == PerfilDesktopPane.descontos ||
                  secao == PerfilDesktopPane.ferias ||
                  secao == PerfilDesktopPane.referencias ||
                  secao == PerfilDesktopPane.equipa ||
                  secao == PerfilDesktopPane.resultadosLive;
              if (needsAuth) {
                final returnTo =
                    HubActions.normalizeReturnTo(GoRouterState.of(context).uri);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  if (AppStateNotifier.instance.loggedIn ||
                      SupaFlow.client.auth.currentSession != null) {
                    return;
                  }
                  HubActions.openLoginForReturn(
                    context,
                    returnTo: returnTo,
                  );
                });
                return const Scaffold(
                  backgroundColor: FleaberColors.bgTint,
                  body: Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  ),
                );
              }
            }
            return _buildPerfilScaffold(context);
          },
        ),
      ),
    );
  }

  Widget _buildPerfilScaffold(BuildContext context) {
    final desktop = _isDesktopAccount(context);
    final qpEarly = GoRouterState.of(context).uri.queryParameters;
    final secaoEarly = PerfilDesktopPaneParsing.tryParse(qpEarly['secao']);
    // Secção mobile: o próprio PerfilMobileSectionScaffold traz AppBar.
    final mobileSectionChrome = !desktop &&
        kIsWeb &&
        secaoEarly != null &&
        secaoEarly != PerfilDesktopPane.resumo;
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FleaberColors.bgTint,
        appBar: (desktop || mobileSectionChrome)
            ? null
            : AppBar(
                elevation: 0.0,
                backgroundColor: FleaberColors.surface,
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                title: Text(
                  'Perfil',
                  style: FlutterFlowTheme.of(context).headlineSmall.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(context)
                              .headlineSmall
                              .fontStyle,
                        ),
                        color: FleaberColors.text,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineSmall
                            .fontStyle,
                      ),
                ),
              ),
        body: SafeArea(
          top: !desktop && !mobileSectionChrome,
          child: FutureBuilder<List<ProfilesRow>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                  child: SizedBox(
                    width: 40.0,
                    height: 40.0,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        FleaberColors.teal,
                      ),
                    ),
                  ),
                );
              }

              final profile =
                  snapshot.data!.isNotEmpty ? snapshot.data!.first : null;
              final fullName = _resolveDisplayName(profile);
              final photoUrl = profile?.photoUrl;
              final hasManualProfilePhoto =
                  hasUserUploadedProfilePhoto(photoUrl);
              final isAdmin = const {
                'admin',
                'admim',
                'administrador',
                'administracao',
              }.contains((profile?.userType ?? '').trim().toLowerCase());
              final phoneVerified = profile?.phoneVerifiedAt != null;
              final emailVerified = currentUserEmailVerified;
              final showVerificationBadges = emailVerified || phoneVerified;

              return ListenableBuilder(
                listenable: SellerStaffContext.instance,
                builder: (context, _) {
                  final staff = SellerStaffContext.instance;
                  final desktopLayout = _isDesktopAccount(context);
                  final items = _buildMenuItems(
                    context,
                    staff: staff,
                    isAdmin: isAdmin,
                  );

                  final qp = GoRouterState.of(context).uri.queryParameters;
                  final secao = qp['secao'];
                  final secaoPane = PerfilDesktopPaneParsing.tryParse(secao);
                  final doc = qp['doc']?.trim();
                  final legalDoc =
                      (doc != null && doc.isNotEmpty) ? doc : null;
                  final liveQ = qp['liveId']?.trim();
                  final liveId =
                      (liveQ != null && liveQ.isNotEmpty) ? liveQ : null;
                  final orderQ = qp['orderId']?.trim();
                  final orderId =
                      (orderQ != null && orderQ.isNotEmpty) ? orderQ : null;
                  // Shell com sidebar só em desktop web (≥768).
                  if (desktopLayout) {
                    return PerfilAccountShell(
                      fullName: fullName,
                      photoUrl: photoUrl,
                      profileId: profile?.id ?? currentUserUid,
                      hasManualProfilePhoto: hasManualProfilePhoto,
                      showVerificationBadges: showVerificationBadges,
                      emailVerified: emailVerified,
                      phoneVerified: phoneVerified,
                      isAdmin: isAdmin,
                      unreadMessagesFuture: _unreadMessagesFuture,
                      onRefreshProfile: _refreshProfile,
                      profileFetchDegraded: _profileFetchDegraded,
                      initialPane: secaoPane ?? PerfilDesktopPane.resumo,
                      initialLegalDoc: legalDoc,
                      initialLiveId: liveId,
                      initialOrderId: orderId,
                    );
                  }
                  // Mobile web com ?secao= → conteúdo a ecrã inteiro (sem sidebar).
                  if (kIsWeb &&
                      secaoPane != null &&
                      secaoPane != PerfilDesktopPane.resumo) {
                    return PerfilMobileSectionScaffold(
                      pane: secaoPane,
                      fullName: fullName,
                      photoUrl: photoUrl,
                      profileId: profile?.id ?? currentUserUid,
                      hasManualProfilePhoto: hasManualProfilePhoto,
                      showVerificationBadges: showVerificationBadges,
                      emailVerified: emailVerified,
                      phoneVerified: phoneVerified,
                      onRefreshProfile: _refreshProfile,
                      initialLegalDoc: legalDoc,
                      initialLiveId: liveId,
                      initialOrderId: orderId,
                    );
                  }

                  return FleaberRefresh(
                    onRefresh: () async {
                      await SellerStaffContext.instance.refresh();
                      await _refreshProfile();
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16.0,
                        12.0,
                        16.0,
                        20.0,
                      ),
                      children: _buildMobileChildren(
                        context,
                        staff: staff,
                        items: items,
                        fullName: fullName,
                        photoUrl: photoUrl,
                        profileId: profile?.id ?? currentUserUid,
                        hasManualProfilePhoto: hasManualProfilePhoto,
                        showVerificationBadges: showVerificationBadges,
                        emailVerified: emailVerified,
                        phoneVerified: phoneVerified,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        bottomNavigationBar: (desktop || mobileSectionChrome)
            ? null
            : _buildBottomNav(context),
      ),
    );
  }

  // ─── Inventário de opções (fonte única mobile + desktop) ───────────────

  List<_ProfileMenuItem> _buildMenuItems(
    BuildContext context, {
    required SellerStaffContext staff,
    required bool isAdmin,
  }) {
    final out = <_ProfileMenuItem>[];

    if (staff.isOwnerContext) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.conta,
        title: 'Definições de conta',
        icon: Icons.settings_outlined,
        onTap: () => HubAccountRoutes.openContaDefinicoes(context),
      ));
    } else if (staff.can(SellerStaffPermissions.canEditStoreProfile)) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.conta,
        title: 'Definições da loja',
        icon: Icons.storefront_outlined,
        onTap: () => context.pushNamed(
          PerfilVendedorWidget.routeName,
          queryParameters: {
            'sellerID': serializeParam(
              staff.effectiveSellerId,
              ParamType.String,
            ),
          }.withoutNulls,
        ),
      ));
    }

    if (staff.isOwnerContext) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.compras,
        title: 'Favoritos',
        icon: Icons.favorite_border_rounded,
        quickAccess: true,
        onTap: () => HubAccountRoutes.openFavoritos(context),
      ));
    }
    if (staff.can(SellerStaffPermissions.canManageOrders) ||
        staff.isOwnerContext) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.compras,
        title: 'Encomendas e Compras',
        icon: Icons.local_shipping_outlined,
        quickAccess: true,
        onTap: () => HubAccountRoutes.openEncomendas(context),
      ));
    }
    if (staff.can(SellerStaffPermissions.canManageReservations)) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.compras,
        title: 'Resultados dos diretos',
        icon: Icons.videocam_outlined,
        onTap: () => HubAccountRoutes.openResultadosLive(context),
      ));
    }

    if (staff.can(SellerStaffPermissions.canCreateProducts)) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'Novo anúncio',
        icon: Icons.add_box_outlined,
        onTap: () => context.pushNamed(SellerProductFormWidget.routeName),
      ));
    }
    if (staff.can(SellerStaffPermissions.canViewPayouts) ||
        staff.can(SellerStaffPermissions.canManagePayouts)) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'O meu Saldo',
        icon: Icons.account_balance_wallet_outlined,
        quickAccess: true,
        onTap: () => HubAccountRoutes.openSaldo(context),
      ));
    }
    if (staff.isOwnerContext) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: HubSellerCopy.accountMenuTitle,
        subtitle: HubSellerCopy.accountMenuSubtitle,
        icon: Icons.store_mall_directory_outlined,
        quickAccess: true,
        onTap: () => HubSellerHubSheet.show(context),
      ));
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'Descontos de conjuntos',
        icon: Icons.percent_rounded,
        onTap: () => HubAccountRoutes.openDescontos(context),
      ));
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'Modo de férias',
        icon: Icons.beach_access_outlined,
        onTap: () => HubAccountRoutes.openFerias(context),
      ));
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'Gestão de referências',
        icon: Icons.qr_code_2_outlined,
        onTap: () => HubAccountRoutes.openReferencias(context),
      ));
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: 'Equipa e colaboradores',
        icon: Icons.groups_outlined,
        onTap: () => HubAccountRoutes.openEquipa(context),
      ));
    }
    if (staff.myPendingInvitations.isNotEmpty) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: staff.myPendingInvitations.length == 1
            ? 'Convite de colaborador (pendente)'
            : '${staff.myPendingInvitations.length} convites de colaborador',
        icon: Icons.mail_outline_rounded,
        onTap: () =>
            HelperPendingInvitesBanner.openPendingInvites(context),
      ));
    }
    if (staff.myHelperLinks.isNotEmpty ||
        staff.myPendingInvitations.isNotEmpty) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.vendas,
        title: staff.actingAsHelper
            ? 'Acesso de colaborador (loja activa)'
            : 'Acesso de colaborador',
        icon: Icons.badge_outlined,
        onTap: () => context.pushNamed(HelperAccessPageWidget.routeName),
      ));
    }

    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Como funciona o Fleaber',
      icon: Icons.help_outline_rounded,
      onTap: () => HubAccountRoutes.openComoFunciona(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Comprar com segurança',
      icon: Icons.verified_user_outlined,
      onTap: () => HubAccountRoutes.openComprarSeguro(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Vender na Fleaber',
      icon: Icons.storefront_outlined,
      onTap: () => HubAccountRoutes.openVenderFleaber(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Perguntas Frequentes',
      icon: Icons.question_answer_outlined,
      onTap: () => HubAccountRoutes.openFaq(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Contactos e identificação legal',
      icon: Icons.mail_outline_rounded,
      onTap: () => HubAccountRoutes.openContactos(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Informação legal',
      icon: Icons.gavel_outlined,
      onTap: () => HubAccountRoutes.openInfoLegal(context),
    ));
    out.add(_ProfileMenuItem(
      section: _ProfileNavSection.ajuda,
      title: 'Sobre a nossa plataforma',
      icon: Icons.info_outline_rounded,
      onTap: () => HubAccountRoutes.openSobre(context),
    ));
    if (isAdmin) {
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.ajuda,
        title: 'Administração Fleaber',
        icon: Icons.admin_panel_settings_outlined,
        onTap: () => context.pushNamed(AdminPageWidget.routeName),
      ));
      out.add(_ProfileMenuItem(
        section: _ProfileNavSection.ajuda,
        title: 'Importador Amazon',
        icon: Icons.inventory_2_outlined,
        onTap: () => context.pushNamed(AmazonImporterHubPage.routeName),
      ));
    }

    return out;
  }

  String _sectionTitle(_ProfileNavSection s) {
    switch (s) {
      case _ProfileNavSection.resumo:
        return 'Resumo';
      case _ProfileNavSection.conta:
        return 'Conta pessoal';
      case _ProfileNavSection.compras:
        return 'Compras e atividade';
      case _ProfileNavSection.vendas:
        return 'Vendas e FleaHub';
      case _ProfileNavSection.ajuda:
        return 'Ajuda e informação';
    }
  }

  // ─── Desktop shell ─────────────────────────────────────────────────────

  Widget _buildDesktopShell(
    BuildContext context, {
    required SellerStaffContext staff,
    required List<_ProfileMenuItem> items,
    required String fullName,
    required String? photoUrl,
    required String profileId,
    required bool hasManualProfilePhoto,
    required bool showVerificationBadges,
    required bool emailVerified,
    required bool phoneVerified,
  }) {
    return Column(
      children: [
        _buildDesktopHeader(context),
        const ColoredBox(
          color: FleaHubSiteLayout.topBarHairline,
          child: SizedBox(height: 1, width: double.infinity),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: HubTheme.profileContentMaxWidthFor(context),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: HubTheme.profileSidebarWidth,
                      child: SingleChildScrollView(
                        child: _buildDesktopSidebar(context, items: items),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FleaberRefresh(
                        onRefresh: () async {
                          await SellerStaffContext.instance.refresh();
                          await _refreshProfile();
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 32),
                          children: _buildDesktopMain(
                            context,
                            staff: staff,
                            items: items,
                            fullName: fullName,
                            photoUrl: photoUrl,
                            profileId: profileId,
                            hasManualProfilePhoto: hasManualProfilePhoto,
                            showVerificationBadges: showVerificationBadges,
                            emailVerified: emailVerified,
                            phoneVerified: phoneVerified,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHeader(BuildContext context) {
    final muted = FleaberColors.muted;
    final active = FleaberColors.teal;
    TextStyle linkStyle(bool on) => GoogleFonts.inter(
          color: on ? active : muted,
          fontSize: FleaHubSiteLayout.typeNav,
          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
        );

    Widget navChip({
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
      future: _unreadMessagesFuture,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
              navChip(
                icon: Icons.home_outlined,
                label: 'Início',
                onTap: () => HubNavigation.goAppHome(context),
              ),
              navChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Mensagens',
                badge: unreadDot,
                onTap: () =>
                    HubAccountRoutes.openMensagens(context),
              ),
              Builder(
                builder: (btnCtx) => navChip(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Criar',
                  onTap: () => _showCreateBottomSheet(btnCtx),
                ),
              ),
              navChip(
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

  Widget _buildDesktopSidebar(
    BuildContext context, {
    required List<_ProfileMenuItem> items,
  }) {
    final present = <_ProfileNavSection>{
      _ProfileNavSection.resumo,
      for (final i in items) i.section,
    };

    Widget sideItem({
      required _ProfileNavSection section,
      required IconData icon,
      required String label,
    }) {
      if (!present.contains(section) &&
          section != _ProfileNavSection.resumo) {
        return const SizedBox.shrink();
      }
      final on = _desktopSection == section;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on
              ? FleaberColors.teal.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => setState(() => _desktopSection = section),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: on ? FleaberColors.teal : FleaberColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeNav,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? FleaberColors.teal : FleaberColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: _cardDeco,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text('A minha conta', style: _sectionLabel),
          ),
          sideItem(
            section: _ProfileNavSection.resumo,
            icon: Icons.dashboard_outlined,
            label: 'Resumo',
          ),
          sideItem(
            section: _ProfileNavSection.conta,
            icon: Icons.manage_accounts_outlined,
            label: 'Conta',
          ),
          sideItem(
            section: _ProfileNavSection.compras,
            icon: Icons.shopping_bag_outlined,
            label: 'Compras',
          ),
          sideItem(
            section: _ProfileNavSection.vendas,
            icon: Icons.storefront_outlined,
            label: 'Vendas',
          ),
          sideItem(
            section: _ProfileNavSection.ajuda,
            icon: Icons.support_outlined,
            label: 'Ajuda',
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: FleaberColors.alternate),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text('Atalhos', style: _sectionLabel),
          ),
          _sidebarLink(
            icon: Icons.home_outlined,
            label: 'Início',
            onTap: () => HubNavigation.goAppHome(context),
          ),
          _sidebarLink(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Mensagens',
            onTap: () => HubAccountRoutes.openMensagens(context),
          ),
          Builder(
            builder: (btnCtx) => _sidebarLink(
              icon: Icons.add_circle_outline_rounded,
              label: 'Criar anúncio ou directo',
              onTap: () => _showCreateBottomSheet(btnCtx),
            ),
          ),
          _sidebarLink(
            icon: Icons.explore_outlined,
            label: 'Explorar FleaHub',
            onTap: () => HubActions.openFleaHubLanding(context),
          ),
        ],
      ),
    );
  }

  Widget _sidebarLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: FleaberColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: FleaberColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDesktopMain(
    BuildContext context, {
    required SellerStaffContext staff,
    required List<_ProfileMenuItem> items,
    required String fullName,
    required String? photoUrl,
    required String profileId,
    required bool hasManualProfilePhoto,
    required bool showVerificationBadges,
    required bool emailVerified,
    required bool phoneVerified,
  }) {
    final degrade = _degradeBanner(light: true);
    final out = <Widget>[
      const AccountContextBadge(),
      if (staff.myPendingInvitations.isNotEmpty) ...[
        const SizedBox(height: 12),
        const HelperPendingInvitesBanner(),
      ],
      if (degrade != null) ...[
        const SizedBox(height: 12),
        degrade,
      ],
      const SizedBox(height: 14),
      _buildIdentityCard(
        context,
        staff: staff,
        fullName: fullName,
        photoUrl: photoUrl,
        profileId: profileId,
        showVerificationBadges: showVerificationBadges,
        emailVerified: emailVerified,
        phoneVerified: phoneVerified,
        hasManualProfilePhoto: hasManualProfilePhoto,
        desktop: true,
      ),
    ];

    final showResumo = _desktopSection == _ProfileNavSection.resumo;
    final sectionFilter = showResumo ? null : _desktopSection;

    if (showResumo) {
      final quick = items.where((e) => e.quickAccess).toList();
      if (quick.isNotEmpty) {
        out.add(const SizedBox(height: 20));
        out.add(Text('Acesso rápido', style: _sectionLabel));
        out.add(const SizedBox(height: 10));
        out.add(_buildQuickAccessGrid(quick));
      }
    }

    final sections = <_ProfileNavSection>[
      _ProfileNavSection.conta,
      _ProfileNavSection.compras,
      _ProfileNavSection.vendas,
      _ProfileNavSection.ajuda,
    ];

    for (final sec in sections) {
      if (sectionFilter != null && sectionFilter != sec) continue;
      final children = items.where((e) => e.section == sec).toList();
      if (children.isEmpty) continue;
      out.add(const SizedBox(height: 20));
      out.add(_buildLightSection(
        title: _sectionTitle(sec),
        children: children
            .map((e) => _buildItem(
                  context,
                  e.title,
                  subtitle: e.subtitle,
                  icon: e.icon,
                  onTap: e.onTap,
                  card: false,
                ))
            .toList(),
      ));
    }

    out.add(const SizedBox(height: 20));
    out.add(_buildSignOut(desktop: true));
    return out;
  }

  Widget _buildQuickAccessGrid(List<_ProfileMenuItem> quick) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 720 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 4 ? 1.55 : 1.7,
          children: [
            for (final item in quick)
              Material(
                color: FleaberColors.surface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: item.onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: _cardDeco,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon ?? Icons.chevron_right_rounded,
                          color: FleaberColors.teal,
                          size: 26,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: FleaberColors.text,
                          ),
                        ),
                        if (item.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _bodyMuted.copyWith(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── Mobile ────────────────────────────────────────────────────────────

  List<Widget> _buildMobileChildren(
    BuildContext context, {
    required SellerStaffContext staff,
    required List<_ProfileMenuItem> items,
    required String fullName,
    required String? photoUrl,
    required String profileId,
    required bool hasManualProfilePhoto,
    required bool showVerificationBadges,
    required bool emailVerified,
    required bool phoneVerified,
  }) {
    final degrade = _degradeBanner(light: true);
    return [
      const AccountContextBadge(),
      if (staff.myPendingInvitations.isNotEmpty) ...[
        const SizedBox(height: 10.0),
        const HelperPendingInvitesBanner(),
      ],
      if (degrade != null) degrade,
      const SizedBox(height: 10.0),
      _buildIdentityCard(
        context,
        staff: staff,
        fullName: fullName,
        photoUrl: photoUrl,
        profileId: profileId,
        showVerificationBadges: showVerificationBadges,
        emailVerified: emailVerified,
        phoneVerified: phoneVerified,
        hasManualProfilePhoto: hasManualProfilePhoto,
        desktop: false,
      ),
      const SizedBox(height: 16.0),
      ..._mobileGroupedMenu(context, items),
      const SizedBox(height: 8.0),
      _buildSignOut(desktop: false),
    ];
  }

  /// Mobile: mesma ordem lógica, agrupada em cartões brancos (tema H01–H06).
  List<Widget> _mobileGroupedMenu(
    BuildContext context,
    List<_ProfileMenuItem> items,
  ) {
    final out = <Widget>[];
    final order = <_ProfileNavSection>[
      _ProfileNavSection.conta,
      _ProfileNavSection.compras,
      _ProfileNavSection.vendas,
      _ProfileNavSection.ajuda,
    ];
    for (final sec in order) {
      final children = items.where((e) => e.section == sec).toList();
      if (children.isEmpty) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(_buildLightSection(
        title: _sectionTitle(sec),
        children: children
            .map((e) => _buildItem(
                  context,
                  e.title,
                  subtitle: e.subtitle,
                  icon: e.icon,
                  onTap: e.onTap,
                  card: false,
                ))
            .toList(),
      ));
    }
    return out;
  }

  // ─── Shared pieces ─────────────────────────────────────────────────────

  Widget _buildIdentityCard(
    BuildContext context, {
    required SellerStaffContext staff,
    required String fullName,
    required String? photoUrl,
    required String profileId,
    required bool showVerificationBadges,
    required bool emailVerified,
    required bool phoneVerified,
    required bool hasManualProfilePhoto,
    required bool desktop,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          splashColor: Colors.transparent,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            unawaited(
              HubActions.openPublicProfile(
                context,
                sellerId: staff.effectiveSellerId,
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(desktop ? 20.0 : 14.0),
            decoration: _cardDeco,
            child: Row(
              children: [
                FleaberProfileAvatar(
                  userId: profileId,
                  fullName: fullName,
                  photoUrl: photoUrl,
                  radius: desktop ? 36.0 : 28.0,
                ),
                const SizedBox(width: 14.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName, style: _titleMd),
                      if (showVerificationBadges) ...[
                        const SizedBox(height: 6.0),
                        FleaberVerificationBadges(
                          emailVerified: emailVerified,
                          phoneVerified: phoneVerified,
                          compact: true,
                        ),
                      ],
                      const SizedBox(height: 4.0),
                      Text(
                        'Os meus anúncios e diretos',
                        style: _bodyMuted,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: FleaberColors.muted,
                  size: 22.0,
                ),
              ],
            ),
          ),
        ),
        if (desktop && staff.isOwnerContext) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => HubAccountRoutes.openContaDefinicoes(context),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar perfil e dados pessoais'),
              style: TextButton.styleFrom(
                foregroundColor: FleaberColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
        if (!hasManualProfilePhoto) ...[
          SizedBox(height: desktop ? 12.0 : 10.0),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => HubAccountRoutes.openContaDefinicoes(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: FleaberColors.teal,
                side: BorderSide(
                  color: FleaberColors.teal.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Atualizar foto de perfil'),
            ),
          ),
        ],
      ],
    );
  }

  Widget? _degradeBanner({required bool light}) {
    if (!(kIsWeb && _profileFetchDegraded)) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xFFE65100),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Não foi possível actualizar os dados do perfil.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5D4037),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_refreshProfile()),
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
      ),
    );
  }

  Widget _buildSignOut({required bool desktop}) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () async {
        GoRouter.of(context).prepareAuthEvent();
        await authManager.signOut();
        if (!mounted) return;
        context.goNamedAuth(LoginWidget.routeName, context.mounted);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: EdgeInsetsDirectional.fromSTEB(
          desktop ? 16.0 : 12.0,
          14.0,
          desktop ? 16.0 : 12.0,
          14.0,
        ),
        decoration: desktop
            ? _cardDeco.copyWith(
                border: Border.all(
                  color: FleaberColors.danger.withValues(alpha: 0.25),
                ),
              )
            : null,
        child: Text(
          'Terminar Sessão',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: FleaberColors.danger,
          ),
        ),
      ),
    );
  }

  Widget _buildLightSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: Text(title, style: _sectionLabel),
        ),
        Container(
          decoration: _cardDeco,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: FleaberColors.alternate,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    String title, {
    String? subtitle,
    IconData? icon,
    VoidCallback? onTap,
    bool card = true,
  }) {
    final titleStyle = GoogleFonts.inter(
      fontWeight: FontWeight.w500,
      fontSize: 14.5,
      color: FleaberColors.text,
    );
    final subStyle = GoogleFonts.inter(
      fontWeight: FontWeight.w400,
      fontSize: 12.5,
      color: FleaberColors.muted,
    );
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
      leading: icon == null
          ? null
          : Icon(icon, size: 22, color: FleaberColors.teal),
      title: Text(title, style: titleStyle),
      subtitle: subtitle == null ? null : Text(subtitle, style: subStyle),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: FleaberColors.muted,
        size: 20.0,
      ),
      onTap: onTap ?? () {},
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final muted = FleaberColors.muted;
    final active = FleaberColors.teal;
    final labelStyle = (Color c, {FontWeight w = FontWeight.w500}) =>
        FlutterFlowTheme.of(context).labelSmall.override(
              font: GoogleFonts.inter(
                fontWeight: w,
                fontStyle: FlutterFlowTheme.of(context).labelSmall.fontStyle,
              ),
              color: c,
              fontSize: 11.0,
              letterSpacing: 0.0,
              fontWeight: w,
              fontStyle: FlutterFlowTheme.of(context).labelSmall.fontStyle,
            );
    return Container(
      width: double.infinity,
      height: 80.0,
      decoration: const BoxDecoration(
        color: FleaberColors.bgTint,
        boxShadow: [FleaberElevation.smNav],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () => HubNavigation.goAppHome(context),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.home_rounded, color: muted, size: 24.0),
                    Text('Início', style: labelStyle(muted)),
                  ].divide(const SizedBox(height: 4.0)),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () =>
                    HubAccountRoutes.openMensagens(context),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: muted,
                          size: 24.0,
                        ),
                        Positioned(
                          right: -2.0,
                          top: -2.0,
                          child: FutureBuilder<List<ChatMessagesRow>>(
                            future: _unreadMessagesFuture,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData ||
                                  snapshot.data!.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                width: 8.0,
                                height: 8.0,
                                decoration: const BoxDecoration(
                                  color: FleaberColors.teal,
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    Text('Mensagens', style: labelStyle(muted)),
                  ].divide(const SizedBox(height: 4.0)),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: _showCreateBottomSheet,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 53.0,
                      height: 53.0,
                      decoration: const BoxDecoration(
                        color: FleaberColors.teal,
                        shape: BoxShape.circle,
                      ),
                      child: const Align(
                        alignment: AlignmentDirectional(0.0, 0.0),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28.0,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 2.0, 0.0, 0.0),
                      child: Text(
                        'Vender',
                        style: labelStyle(active, w: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () => context.pushNamed(PerfilWidget.routeName),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      color: active,
                      size: 24.0,
                    ),
                    Text(
                      'Perfil',
                      style: labelStyle(active, w: FontWeight.w700),
                    ),
                  ].divide(const SizedBox(height: 4.0)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
