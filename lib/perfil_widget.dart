import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/index.dart';
import '/utils/fleaber_elevation.dart';
import '/widgets/fleaber_create_sheet.dart';
import '/widgets/fleaber_refresh.dart';
import '/widgets/profile_avatar.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/helper_pending_invites_banner.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  Future<List<ProfilesRow>> _loadProfile() {
    return ProfilesTable()
        .queryRows(
          queryFn: (q) => q.eqOrNull('id', currentUserUid),
          limit: 1,
        )
        .timeout(
          _kProfileQueryTimeout,
          onTimeout: () => const <ProfilesRow>[],
        )
        .catchError((_) => const <ProfilesRow>[]);
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
          _kProfileQueryTimeout,
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

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _unreadMessagesFuture = _loadUnreadMessages();
    unawaited(SellerStaffContext.instance.refresh());
  }

  Future<void> _showCreateBottomSheet() => FleaberCreateSheet.show(context);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0.0,
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Text(
            'Perfil',
            style: FlutterFlowTheme.of(context).headlineSmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                  ),
                  color: const Color(0xFF101518),
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                ),
          ),
        ),
        body: SafeArea(
          top: false,
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
                        FlutterFlowTheme.of(context).primary,
                      ),
                    ),
                  ),
                );
              }

              final profile =
                  snapshot.data!.isNotEmpty ? snapshot.data!.first : null;
              final fullName = profile?.fullName?.isNotEmpty == true
                  ? profile!.fullName!
                  : 'Utilizador Fleaber';
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
              final showVerificationBadges =
                  emailVerified || phoneVerified;

              return ListenableBuilder(
                listenable: SellerStaffContext.instance,
                builder: (context, _) {
                  final staff = SellerStaffContext.instance;
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
                  children: [
                  const AccountContextBadge(),
                  if (staff.myPendingInvitations.isNotEmpty) ...[
                    const SizedBox(height: 10.0),
                    const HelperPendingInvitesBanner(),
                  ],
                  const SizedBox(height: 10.0),
                  InkWell(
                    splashColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: () async {
                      context.pushNamed(
                        PerfilVendedorWidget.routeName,
                        queryParameters: {
                          'sellerID': serializeParam(
                            staff.effectiveSellerId,
                            ParamType.String,
                          ),
                          'initialTab': serializeParam(
                            'marketplace',
                            ParamType.String,
                          ),
                        }.withoutNulls,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: FleaberColors.bgTint,
                        borderRadius: FleaberRadius.circularMd,
                      ),
                      child: Row(
                        children: [
                          FleaberProfileAvatar(
                            userId: profile?.id ?? currentUserUid,
                            fullName: fullName,
                            photoUrl: photoUrl,
                            radius: 28.0,
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleMedium
                                                  .fontStyle,
                                        ),
                                        color: const Color(0xFF101518),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w700,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontStyle,
                                      ),
                                ),
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
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.w500,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: const Color(0xFF57636C),
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF57636C),
                            size: 22.0,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!hasManualProfilePhoto) ...[
                    const SizedBox(height: 10.0),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.pushNamed(ContaDefinicoesWidget.routeName),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const Text('Atualizar foto de perfil'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16.0),
                  if (staff.isOwnerContext)
                    _buildItem(
                      context,
                      'Definições de conta',
                      onTap: () =>
                          context.pushNamed(ContaDefinicoesWidget.routeName),
                    )
                  else if (staff.can(SellerStaffPermissions.canEditStoreProfile))
                    _buildItem(
                      context,
                      'Definições da loja',
                      onTap: () => context.pushNamed(
                        PerfilVendedorWidget.routeName,
                        queryParameters: {
                          'sellerID': serializeParam(
                            staff.effectiveSellerId,
                            ParamType.String,
                          ),
                        }.withoutNulls,
                      ),
                    ),
                  if (staff.can(SellerStaffPermissions.canCreateProducts))
                    _buildItem(
                      context,
                      'Novo anúncio',
                      onTap: () =>
                          context.pushNamed(SellerProductFormWidget.routeName),
                    ),
                  if (staff.isOwnerContext)
                    _buildItem(
                      context,
                      'Favoritos',
                      onTap: () =>
                          context.pushNamed(FavoritosPageWidget.routeName),
                    ),
                  if (staff.can(SellerStaffPermissions.canViewPayouts) ||
                      staff.can(SellerStaffPermissions.canManagePayouts))
                    _buildItem(
                      context,
                      'O meu Saldo',
                      onTap: () =>
                          context.pushNamed(WalletPageWidget.routeName),
                    ),
                  if (staff.can(SellerStaffPermissions.canManageOrders) ||
                      staff.isOwnerContext)
                    _buildItem(
                      context,
                      'Encomendas e Compras',
                      onTap: () => context.pushNamed(
                        MinhasEncomendasWidget.routeName,
                      ),
                    ),
                  if (staff.can(SellerStaffPermissions.canManageReservations))
                    _buildItem(
                      context,
                      'Resultados dos directos',
                      onTap: () => context.pushNamed(
                        LiveSalesSessionsPageWidget.routeName,
                      ),
                    ),
                  if (staff.isOwnerContext)
                    _buildItem(
                      context,
                      'Descontos de conjuntos',
                      onTap: () =>
                          context.pushNamed(DescontosConjuntosWidget.routeName),
                    ),
                  if (staff.isOwnerContext)
                    _buildItem(
                      context,
                      'Modo de férias',
                      onTap: () =>
                          context.pushNamed(ModoFeriasPageWidget.routeName),
                    ),
                  if (staff.isOwnerContext) ...[
                    _buildItem(
                      context,
                      'Equipa e colaboradores',
                      onTap: () =>
                          context.pushNamed(SellerHelpersPageWidget.routeName),
                    ),
                  ],
                  if (staff.myPendingInvitations.isNotEmpty)
                    _buildItem(
                      context,
                      staff.myPendingInvitations.length == 1
                          ? 'Convite de colaborador (pendente)'
                          : '${staff.myPendingInvitations.length} convites de colaborador',
                      onTap: () => HelperPendingInvitesBanner.openPendingInvites(
                        context,
                      ),
                    ),
                  if (staff.myHelperLinks.isNotEmpty ||
                      staff.myPendingInvitations.isNotEmpty)
                    _buildItem(
                      context,
                      staff.actingAsHelper
                          ? 'Acesso de colaborador (loja activa)'
                          : 'Acesso de colaborador',
                      onTap: () =>
                          context.pushNamed(HelperAccessPageWidget.routeName),
                    ),
                  _buildItem(
                    context,
                    'Como funciona o Fleaber',
                    onTap: () => context.pushNamed(
                      LegalDocumentPageWidget.routeName,
                      queryParameters: {'kind': 'how'},
                    ),
                  ),
                  _buildItem(
                    context,
                    'Perguntas Frequentes',
                    onTap: () => context.pushNamed(
                      LegalDocumentPageWidget.routeName,
                      queryParameters: {'kind': 'faq'},
                    ),
                  ),
                  _buildItem(
                    context,
                    'Informação legal',
                    onTap: () =>
                        context.pushNamed(LegalHubPageWidget.routeName),
                  ),
                  _buildItem(
                    context,
                    'Sobre a nossa plataforma',
                    onTap: () => context.pushNamed(
                      LegalDocumentPageWidget.routeName,
                      queryParameters: {'kind': 'about'},
                    ),
                  ),
                  if (isAdmin)
                    _buildItem(
                      context,
                      'Administração Fleaber',
                      onTap: () => context.pushNamed(AdminPageWidget.routeName),
                    ),
                  const SizedBox(height: 8.0),
                  InkWell(
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
                    child: Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(12.0, 14.0, 12.0, 14.0),
                      child: Text(
                        'Terminar Sessão',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              color: FleaberColors.danger,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              );
                },
              );
            },
          ),
        ),
        bottomNavigationBar: Container(
          width: double.infinity,
          height: 80.0,
          decoration: const BoxDecoration(
            color: FleaberColors.bgTint,
            boxShadow: const [FleaberElevation.smNav],
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
                    onTap: () => context.pushNamed(HomePageWidget.routeName),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.home_rounded,
                          color: Color(0xFF57636C),
                          size: 24.0,
                        ),
                        Text(
                          'Início',
                          style: FlutterFlowTheme.of(context).labelSmall.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                                color: const Color(0xFF57636C),
                                fontSize: 11.0,
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w500,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .labelSmall
                                    .fontStyle,
                              ),
                        ),
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
                        context.pushNamed(ListaConversasWidget.routeName),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Color(0xFF57636C),
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
                                    return SizedBox.shrink();
                                  }
                                  return Container(
                                    width: 8.0,
                                    height: 8.0,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF007782),
                                      shape: BoxShape.circle,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Mensagens',
                          style: FlutterFlowTheme.of(context).labelSmall.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                                color: const Color(0xFF57636C),
                                fontSize: 11.0,
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w500,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .labelSmall
                                    .fontStyle,
                              ),
                        ),
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
                            color: Color(0xFF007782),
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
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(0.0, 2.0, 0.0, 0.0),
                          child: Text(
                            'Vender',
                            style: FlutterFlowTheme.of(context).labelSmall.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF007782),
                                  fontSize: 11.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
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
                        const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFF007782),
                          size: 24.0,
                        ),
                        Text(
                          'Perfil',
                          style: FlutterFlowTheme.of(context).labelSmall.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                                color: const Color(0xFF007782),
                                fontSize: 11.0,
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .labelSmall
                                    .fontStyle,
                              ),
                        ),
                      ].divide(const SizedBox(height: 4.0)),
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

  Widget _buildItem(BuildContext context, String title, {VoidCallback? onTap}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FleaberColors.bgTint,
            width: 1.0,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(0.0, 2.0, 0.0, 2.0),
        title: Text(
          title,
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                color: const Color(0xFF101518),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w500,
                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF57636C),
          size: 20.0,
        ),
        onTap: onTap ?? () {},
      ),
    );
  }
}
