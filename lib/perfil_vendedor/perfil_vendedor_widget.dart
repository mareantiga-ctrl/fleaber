import 'dart:async';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/chat_session_util.dart';
import '/widgets/batata_cached_image.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/widgets/marketplace_product_card.dart';
import '/widgets/profile_avatar.dart';
import '/utils/seller_vacation_mode.dart';
import '/utils/seller_professional.dart';
import '/widgets/professional_seller_badge.dart';
import '/widgets/profile_lives_tab.dart';
import '/widgets/fleaber_verification_badges.dart';
import '/hub/hub_account_routes.dart';
import '/hub/seller/hub_seller_sheet.dart';
import '/utils/profile_photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'perfil_vendedor_model.dart';
export 'perfil_vendedor_model.dart';

/// Create a high-fidelity mobile Seller Profile for Fleaber.
///
/// TOP HEADER: Perfectly centered circular avatar, seller name in bold, and
/// location with a pin icon.      NAVIGATION: A TabBar with 'Directos' and
/// 'Opiniões'.      VIDEO CONTENT: Under 'Directos', create a Container with
/// a strictly VERTICAL 9:16 Aspect Ratio to match mobile phone videos. This
/// container must be perfectly centered with 16px side margins and 20px
/// rounded corners.      OVERLAYS: Inside the video container, add a small
/// 'LIVE' pulsing red tag in the top-left.      PAST LIVES: Below the main
/// video, a horizontal scrolling row of small 9:16 vertical thumbnails.
/// STYLE: Primary color #007782, pure white background, and deep black text
/// for high contrast.
class PerfilVendedorWidget extends StatefulWidget {
  const PerfilVendedorWidget({
    super.key,
    required this.sellerID,
    this.initialTab,
  });

  final String? sellerID;

  /// Aba inicial: `diretos`, `marketplace` ou `opinioes` (query param, case-insensitive).
  final String? initialTab;

  static String routeName = 'PerfilVendedor';
  static String routePath = '/perfilVendedor';

  @override
  State<PerfilVendedorWidget> createState() => _PerfilVendedorWidgetState();
}

class _PerfilVendedorWidgetState extends State<PerfilVendedorWidget>
    with TickerProviderStateMixin {
  late PerfilVendedorModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  int _profileDataVersion = 0;
  bool _photoUploading = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PerfilVendedorModel());
    final sid = widget.sellerID;
    if (sid != null && sid.isNotEmpty) {
      unawaited(SellerProfessionalCache.warm([sid]));
    }

    var tabIndex = 0;
    final rawTab = widget.initialTab?.trim().toLowerCase();
    if (rawTab == 'marketplace') {
      tabIndex = 1;
    } else if (rawTab == 'opinioes' ||
        rawTab == 'opiniões' ||
        rawTab == 'opiniones') {
      tabIndex = 2;
    }

    _model.tabBarController = TabController(
      vsync: this,
      length: 3,
      initialIndex: tabIndex.clamp(0, 2),
    )..addListener(() => safeSetState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  static String _formatPriceEur(ProductsRow row) {
    final p = row.price;
    if (p == null) return '—';
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String? _firstProductImageUrl(ProductsRow row) {
    final u = row.imageUrls;
    if (u.isEmpty) return null;
    return u.first;
  }

  Widget _buildSellerMarketplaceGrid() {
    final sid = widget.sellerID;
    if (sid == null || sid.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Perfil indisponível.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 15.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    final isOwnProfile = sid == currentUserUid;
    return FutureBuilder<bool>(
      future: SellerVacationMode.isOnVacation(sid),
      builder: (context, vacSnap) {
        final sellerOnVacation = vacSnap.data == true;
        if (sellerOnVacation && !isOwnProfile) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Este vendedor está de férias. Os anúncios estão temporariamente ocultos.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: const Color(0xFF57636C),
                  fontSize: 15.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }
        return FutureBuilder<List<ProductsRow>>(
          future: ProductsTable().queryRows(
            queryFn: (q) => q
                .eqOrNull('seller_id', sid)
                .eq('list_on_marketplace', true)
                .order('created_at', ascending: false),
            limit: 200,
          ),
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
            final rows = snapshot.data!
                .where((p) => !p.isSold && p.quantity > 0)
                .toList();
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Sem artigos no Marketplace.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF57636C),
                      fontSize: 15.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: kFleaberTwoColumnGridGap,
                      crossAxisSpacing: kFleaberTwoColumnGridGap,
                      childAspectRatio:
                          MarketplaceProductCard.gridChildAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = rows[index];
                        final sellerId =
                            product.sellerId ?? widget.sellerID ?? '';
                        final pro = SellerProfessionalCache.peek(sellerId);
                        return MarketplaceProductCard(
                          title:
                              valueOrDefault<String>(product.title, 'Artigo'),
                          stateLabel: product.state,
                          priceLabel: _formatPriceEur(product),
                          imageUrl: _firstProductImageUrl(product),
                          favoritesCount: product.favoritesCount,
                          isFavorited: false,
                          showProfessionalBadge:
                              pro?.showProfessionalBadge == true,
                          professionalVerified:
                              pro?.professionalVerified == true,
                          onTap: () {
                            context.push(
                              ProductDetailsPageWidget.routePath,
                              extra: ProductDetailsPageWidget
                                  .routeExtraForProduct(product),
                            );
                          },
                          onFavoriteTap: null,
                        );
                      },
                      childCount: rows.length,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickProfilePhoto() async {
    if (_photoUploading) return;
    setState(() => _photoUploading = true);
    final url = await ProfilePhotoPicker.pickAndSave(context);
    if (!mounted) return;
    setState(() {
      _photoUploading = false;
      if (url != null) _profileDataVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProfilesRow>>(
      key: ValueKey(_profileDataVersion),
      future: ProfilesDirectoryTable().querySingleRow(
        queryFn: (q) => q.eqOrNull(
          'id',
          widget.sellerID,
        ),
      ),
      builder: (context, snapshot) {
        // Customize what your widget looks like when it's loading.
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    FlutterFlowTheme.of(context).primary,
                  ),
                ),
              ),
            ),
          );
        }
        List<ProfilesRow> perfilVendedorProfilesRowList = snapshot.data!;

        // Return an empty Container when the item does not exist.
        if (snapshot.data!.isEmpty) {
          return Container();
        }
        final perfilVendedorProfilesRow =
            perfilVendedorProfilesRowList.isNotEmpty
                ? perfilVendedorProfilesRowList.first
                : null;
        final isOwnProfile = widget.sellerID == currentUserUid;
        final displayName = valueOrDefault<String>(
          perfilVendedorProfilesRow?.fullName,
          'Perfil de Membro',
        );
        final locationLabel = valueOrDefault<String>(
          perfilVendedorProfilesRow?.location,
          '',
        ).trim();

        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Scaffold(
            key: scaffoldKey,
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leading: FlutterFlowIconButton(
                borderColor: Colors.transparent,
                borderRadius: 22.0,
                borderWidth: 0.0,
                buttonSize: 44.0,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF007782),
                  size: 24.0,
                ),
                onPressed: () async {
                  context.safePop();
                },
              ),
              actions: [
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(8.0, 0.0, 8.0, 0.0),
                  child: FlutterFlowIconButton(
                    borderColor: Colors.transparent,
                    borderRadius: 22.0,
                    borderWidth: 0.0,
                    buttonSize: 44.0,
                    icon: Icon(
                      widget.sellerID == currentUserUid
                          ? Icons.settings_outlined
                          : Icons.more_vert_outlined,
                      color: Color(0xFF111111),
                      size: 24.0,
                    ),
                    onPressed: () {
                      if (widget.sellerID == currentUserUid) {
                        HubAccountRoutes.openContaDefinicoes(context);
                        return;
                      }
                      print('IconButton pressed ...');
                    },
                  ),
                ),
              ],
              centerTitle: true,
              elevation: 0.0,
            ),
            body: SafeArea(
              top: true,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16.0, 8.0, 16.0, 0.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isOwnProfile)
                                FleaberProfileAvatarEditable(
                                  userId: widget.sellerID,
                                  fullName: perfilVendedorProfilesRow?.fullName,
                                  photoUrl: perfilVendedorProfilesRow?.photoUrl,
                                  radius: 35.0,
                                  borderColor: const Color(0xFF007782),
                                  borderWidth: 1.5,
                                  uploading: _photoUploading,
                                  onTap: _pickProfilePhoto,
                                )
                              else
                                FleaberProfileAvatar(
                                  userId: widget.sellerID,
                                  fullName: perfilVendedorProfilesRow?.fullName,
                                  photoUrl: perfilVendedorProfilesRow?.photoUrl,
                                  radius: 35.0,
                                  borderColor: const Color(0xFF007782),
                                  borderWidth: 1.5,
                                ),
                              SizedBox(width: 12.0),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                              Text(
                                                displayName,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .titleMedium
                                                    .override(
                                                      font: GoogleFonts
                                                          .interTight(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleMedium
                                                                .fontStyle,
                                                      ),
                                                      color: const Color(
                                                          0xFF111111),
                                                      fontSize: 19.0,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleMedium
                                                              .fontStyle,
                                                    ),
                                              ),
                                              if (SellerProfessionalCache
                                                  .showBadge(
                                                widget.sellerID,
                                              ))
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 6.0,
                                                  ),
                                                  child:
                                                      ProfessionalSellerBadge(
                                                    compact: true,
                                                  ),
                                                ),
                                              if (isOwnProfile &&
                                                  locationLabel.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4.0),
                                                  child: Text(
                                                    locationLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 14.0,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: const Color(
                                                          0xFF777777),
                                                    ),
                                                  ),
                                                ),
                                              if (!isOwnProfile &&
                                                  locationLabel.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4.0),
                                                  child: Text(
                                                    locationLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 14.0,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: const Color(
                                                          0xFF777777),
                                                    ),
                                                  ),
                                                ),
                                              if (isOwnProfile) ...[
                                                Builder(
                                                  builder: (context) {
                                                    final phoneOk =
                                                        perfilVendedorProfilesRow
                                                                ?.phoneVerifiedAt !=
                                                            null;
                                                    final emailOk =
                                                        currentUserEmailVerified;
                                                    if (!emailOk && !phoneOk) {
                                                      return const SizedBox
                                                          .shrink();
                                                    }
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4.0),
                                                      child:
                                                          FleaberVerificationBadges(
                                                        emailVerified: emailOk,
                                                        phoneVerified: phoneOk,
                                                        ultraCompact: true,
                                                      ),
                                                    );
                                                  },
                                                ),
                                                HubSellerProfilePublicLine(
                                                  onChanged: () => setState(
                                                    () => _profileDataVersion++,
                                                  ),
                                                ),
                                              ] else if (widget.sellerID
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true) ...[
                                                HubVisitorFleaHubLine(
                                                  sellerId:
                                                      widget.sellerID!.trim(),
                                                ),
                                              ],
                                              if (widget.sellerID !=
                                                      currentUserUid &&
                                                  !isOwnProfile)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                      top: 8.0),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      FutureBuilder<List<FollowsRow>>(
                                                        future: FollowsTable()
                                                            .querySingleRow(
                                                          queryFn: (q) => q
                                                              .eqOrNull(
                                                                'follower_id',
                                                                currentUserUid,
                                                              )
                                                              .eqOrNull(
                                                                'following_id',
                                                                widget.sellerID,
                                                              ),
                                                        ),
                                                        builder:
                                                            (context, snapshot) {
                                                          if (!snapshot.hasData) {
                                                            return const SizedBox(
                                                              width: 88,
                                                              height: 30,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Color(
                                                                    0xFF007782),
                                                              ),
                                                            );
                                                          }
                                                          final rows =
                                                              snapshot.data!;
                                                          final follow =
                                                              rows.isNotEmpty
                                                                  ? rows.first
                                                                  : null;
                                                          return InkWell(
                                                            splashColor: Colors
                                                                .transparent,
                                                            focusColor: Colors
                                                                .transparent,
                                                            hoverColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            onTap: () async {
                                                              if (follow?.id !=
                                                                      null &&
                                                                  follow!
                                                                      .id!
                                                                      .isNotEmpty) {
                                                                await FollowsTable()
                                                                    .delete(
                                                                  matchingRows:
                                                                      (rows) =>
                                                                          rows
                                                                              .eqOrNull(
                                                                    'follower_id',
                                                                    currentUserUid,
                                                                  ).eqOrNull(
                                                                    'following_id',
                                                                    widget
                                                                        .sellerID,
                                                                  ),
                                                                );
                                                              } else {
                                                                await FollowsTable()
                                                                    .insert({
                                                                  'follower_id':
                                                                      currentUserUid,
                                                                  'following_id':
                                                                      widget
                                                                          .sellerID,
                                                                });
                                                              }
                                                              safeSetState(
                                                                  () {});
                                                            },
                                                            child: Container(
                                                              constraints:
                                                                  const BoxConstraints(
                                                                      minWidth:
                                                                          88),
                                                              height: 30.0,
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal:
                                                                    14.0,
                                                              ),
                                                              alignment: Alignment
                                                                  .center,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: const Color(
                                                                    0xFF007782),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            25.0),
                                                              ),
                                                              child: Text(
                                                                follow?.id !=
                                                                            null &&
                                                                        follow!
                                                                            .id!
                                                                            .isNotEmpty
                                                                    ? 'A Seguir'
                                                                    : 'Seguir',
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontStyle:
                                                                            FlutterFlowTheme.of(context)
                                                                                .labelMedium
                                                                                .fontStyle,
                                                                      ),
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          12.0,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontStyle:
                                                                          FlutterFlowTheme.of(context)
                                                                              .labelMedium
                                                                              .fontStyle,
                                                                    ),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        splashColor:
                                                            Colors.transparent,
                                                        focusColor:
                                                            Colors.transparent,
                                                        hoverColor:
                                                            Colors.transparent,
                                                        highlightColor:
                                                            Colors.transparent,
                                                        onTap: () async {
                                                          if (widget.sellerID ==
                                                                  null ||
                                                              widget.sellerID!
                                                                  .isEmpty) {
                                                            return;
                                                          }
                                                          if (currentUserUid
                                                              .isEmpty) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'Inicia sessão para enviar mensagem.',
                                                                ),
                                                              ),
                                                            );
                                                            return;
                                                          }
                                                          try {
                                                            final chat =
                                                                await ensureSellerChat(
                                                              otherUserId:
                                                                  widget
                                                                      .sellerID!,
                                                              productId: null,
                                                            );
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            context.pushNamed(
                                                              ChatPageWidget
                                                                  .routeName,
                                                              queryParameters: {
                                                                'chatId':
                                                                    serializeParam(
                                                                  chat.id,
                                                                  ParamType
                                                                      .String,
                                                                ),
                                                                'otherUserId':
                                                                    serializeParam(
                                                                  widget
                                                                      .sellerID,
                                                                  ParamType
                                                                      .String,
                                                                ),
                                                              }.withoutNulls,
                                                            );
                                                          } catch (_) {
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'Não foi possível abrir o chat.',
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                          safeSetState(() {});
                                                        },
                                                        child: Container(
                                                          constraints:
                                                              const BoxConstraints(
                                                                  minWidth: 88),
                                                          height: 30.0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 14.0,
                                                          ),
                                                          alignment:
                                                              Alignment.center,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFFF0F9FA),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        25.0),
                                                            border: Border.all(
                                                              color: const Color(
                                                                  0xFF007782),
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'Mensagem',
                                                            style:
                                                                FlutterFlowTheme
                                                                        .of(context)
                                                                    .labelMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontStyle:
                                                                            FlutterFlowTheme.of(context)
                                                                                .labelMedium
                                                                                .fontStyle,
                                                                      ),
                                                                      color: const Color(
                                                                          0xFF007782),
                                                                      fontSize:
                                                                          12.0,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontStyle:
                                                                          FlutterFlowTheme.of(context)
                                                                              .labelMedium
                                                                              .fontStyle,
                                                                    ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              16.0, 10.0, 16.0, 0.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  FutureBuilder<List<VSeguidoresStatsRow>>(
                                    future:
                                        VSeguidoresStatsTable().querySingleRow(
                                      queryFn: (q) => q.eqOrNull(
                                        'profile_id',
                                        widget.sellerID,
                                      ),
                                    ),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF007782),
                                          ),
                                        );
                                      }
                                      List<VSeguidoresStatsRow>
                                          textVSeguidoresStatsRowList =
                                          snapshot.data!;

                                      final textVSeguidoresStatsRow =
                                          textVSeguidoresStatsRowList.isNotEmpty
                                              ? textVSeguidoresStatsRowList
                                                  .first
                                              : null;

                                      return Text(
                                        valueOrDefault<String>(
                                          textVSeguidoresStatsRow
                                              ?.totalSeguidores
                                              ?.toString(),
                                          '0',
                                        ),
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111111),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Seguidores',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF57636C),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      valueOrDefault<String>(
                                        perfilVendedorProfilesRow?.totalLives
                                            ?.toString(),
                                        '0',
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111111),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Diretos',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF57636C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                  FutureBuilder<List<ReviewsPublicRatingsRow>>(
                                    future: ReviewsPublicRatingsTable().queryRows(
                                      queryFn: (q) => q.eqOrNull(
                                        'target_id',
                                        widget.sellerID,
                                      ),
                                    ),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF007782),
                                          ),
                                        );
                                      }
                                      List<ReviewsPublicRatingsRow> textReviewsRowList =
                                          snapshot.data!;

                                      return Text(
                                        valueOrDefault<String>(
                                          (List<int> notas) {
                                            return (notas.isEmpty)
                                                ? "0.0"
                                                : (notas.reduce(
                                                            (a, b) => a + b) /
                                                        notas.length)
                                                    .toStringAsFixed(1);
                                          }(textReviewsRowList
                                              .map((e) => valueOrDefault<int>(
                                                    e.stars,
                                                    0,
                                                  ))
                                              .toList()),
                                          '0.0',
                                        ),
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111111),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Estrelas',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF57636C),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        EdgeInsetsDirectional.fromSTEB(16.0, 14.0, 16.0, 0.0),
                    child: Divider(
                      height: 1.0,
                      thickness: 1.0,
                      color: Color(0xFFEEEEEE),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment(0.0, 0),
                          child: TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.center,
                            labelColor: const Color(0xFF007782),
                            unselectedLabelColor: const Color(0xFF656565),
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            labelStyle: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                            unselectedLabelStyle: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                            indicatorColor: const Color(0xFF007782),
                            tabs: const [
                              Tab(
                                text: 'Diretos',
                              ),
                              Tab(
                                text: 'Marketplace',
                              ),
                              Tab(
                                text: 'Opiniões',
                              ),
                            ],
                            controller: _model.tabBarController,
                            onTap: (i) async {
                              [() async {}, () async {}, () async {}][i]();
                            },
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _model.tabBarController,
                            children: [
                              ProfileLivesTab(
                                key: ValueKey(
                                  'lives-${widget.sellerID ?? ''}',
                                ),
                                sellerId: widget.sellerID ?? '',
                              ),
                              _buildSellerMarketplaceGrid(),
                              SingleChildScrollView(
                                padding: EdgeInsetsDirectional.fromSTEB(
                                    16.0, 12.0, 16.0, 24.0),
                                child: FutureBuilder<List<ReviewsPublicRatingsRow>>(
                                  future: ReviewsPublicRatingsTable().queryRows(
                                    queryFn: (q) => q
                                        .eqOrNull(
                                          'target_id',
                                          widget.sellerID,
                                        )
                                        .order('created_at', ascending: false),
                                  ),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return Padding(
                                        padding: EdgeInsets.all(32.0),
                                        child: Center(
                                          child: SizedBox(
                                            width: 44.0,
                                            height: 44.0,
                                            child: CircularProgressIndicator(
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                FlutterFlowTheme.of(context)
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final reviews = snapshot.data!;
                                    if (reviews.isEmpty) {
                                      return Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 32.0),
                                        child: Center(
                                          child: Text(
                                            'Ainda sem avaliações',
                                            textAlign: TextAlign.center,
                                            style: FlutterFlowTheme.of(context)
                                                .bodyLarge
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w500,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyLarge
                                                            .fontStyle,
                                                  ),
                                                  color: Color(0xFF57636C),
                                                  letterSpacing: 0.0,
                                                  fontWeight: FontWeight.w500,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(context)
                                                          .bodyLarge
                                                          .fontStyle,
                                                ),
                                          ),
                                        ),
                                      );
                                    }
                                    return ListView.separated(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: reviews.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 16.0,
                                        thickness: 1.0,
                                        color: Color(0xFFF0F0F0),
                                      ),
                                      itemBuilder: (context, listViewIndex) {
                                        final review = reviews[listViewIndex];
                                        // View pública sem buyer_id — autor anónimo.
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(12.0),
                                            boxShadow: const [
                                              BoxShadow(
                                                blurRadius: 8.0,
                                                color: Color(0x14000000),
                                                offset: Offset(0.0, 2.0),
                                              ),
                                            ],
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                FleaberProfileAvatar(
                                                  userId: null,
                                                  fullName: 'Comprador',
                                                  photoUrl: null,
                                                  radius: 20.0,
                                                ),
                                                SizedBox(width: 12.0),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Comprador',
                                                        style: FlutterFlowTheme
                                                                .of(context)
                                                            .bodyMedium
                                                            .override(
                                                              font: GoogleFonts
                                                                  .inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodyMedium
                                                                    .fontStyle,
                                                              ),
                                                              color: Color(
                                                                  0xFF111111),
                                                              letterSpacing:
                                                                  0.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontStyle: FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontStyle,
                                                            ),
                                                      ),
                                                      SizedBox(height: 4.0),
                                                      RatingBarIndicator(
                                                        itemBuilder: (context,
                                                                index) =>
                                                            Icon(
                                                          Icons.star_rounded,
                                                          color: Color(
                                                              0xFFFFC107),
                                                        ),
                                                        direction:
                                                            Axis.horizontal,
                                                        rating: valueOrDefault<
                                                            double>(
                                                          review.stars
                                                              ?.toDouble(),
                                                          0.0,
                                                        ),
                                                        unratedColor: Color(
                                                            0xFFE0E0E0),
                                                        itemCount: 5,
                                                        itemSize: 14.0,
                                                      ),
                                                      SizedBox(height: 6.0),
                                                      Text(
                                                        valueOrDefault<String>(
                                                          review.comment,
                                                          '',
                                                        ),
                                                        style: FlutterFlowTheme
                                                                .of(context)
                                                            .bodySmall
                                                            .override(
                                                              font: GoogleFonts
                                                                  .inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .normal,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                              ),
                                                              color: Color(
                                                                  0xFF555555),
                                                              letterSpacing:
                                                                  0.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .normal,
                                                              fontStyle: FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontStyle,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
