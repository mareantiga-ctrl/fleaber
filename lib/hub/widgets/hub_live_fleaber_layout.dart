import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/marketplace_product_card.dart';
import '/widgets/profile_avatar.dart';

import '/flutter_flow/nav/nav.dart';

import '../data/hub_models.dart';
import '../hub_actions.dart';
import '../hub_ps_claim.dart';
import '../hub_live_bag_hint_session.dart';
import '../hub_live_reservation_ui.dart';
import '../hub_player_diag.dart';
import '../hub_qa_diag.dart';
import '../hub_urls.dart';
import '../hub_navigation.dart';
import '../routing/hub_route_paths.dart';
import '../theme/hub_theme.dart';
import 'fleahub_site_chrome.dart';
import 'hub_facebook_reservations_entry.dart';
import 'hub_live_amazon_scan_button.dart';
import 'hub_live_bag_sheet.dart';
import 'hub_shared_widgets.dart';

/// Hub Live — ecrã Fleaber Live literal (1 viewport) + scroll Hub abaixo.
///
/// Desktop (≥ [HubTheme.liveDesktopShellBreakpoint]): shell B1+B2 — produtos à
/// esquerda, chat à direita, mesmo player/State (sem 2.ª LiveRoom / catálogo).
class HubLiveFleaberLayout extends StatefulWidget {
  const HubLiveFleaberLayout({
    super.key,
    required this.bundle,
    required this.handle,
    required this.onRefresh,
    this.psDemo = false,
  });

  final HubLiveBundle bundle;
  final String handle;
  final Future<void> Function() onRefresh;
  final bool psDemo;

  @override
  State<HubLiveFleaberLayout> createState() => _HubLiveFleaberLayoutState();
}

class _HubLiveFleaberLayoutState extends State<HubLiveFleaberLayout> {
  List<LiveReservationRequestsRow> _reservations = const [];
  Timer? _reservationPoll;
  Timer? _hintDismissTimer;
  bool _loadingReservations = false;
  bool _needsFacebookLogin = false;
  String? _trackedBuyerId;
  String? _lastLayoutDiagKey;
  bool? _followBusy;
  bool? _isFollowing;

  HubReservationSummary get _summary =>
      HubReservationSummary.fromRows(_reservations);

  @override
  void initState() {
    super.initState();
    _reloadReservations();
    _reservationPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_reloadReservations(silent: true));
    });
    AppStateNotifier.instance.addListener(_onAuthSessionChanged);
    unawaited(_loadFollowState());
  }

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuthSessionChanged);
    _reservationPoll?.cancel();
    _hintDismissTimer?.cancel();
    super.dispose();
  }

  void _onAuthSessionChanged() {
    unawaited(_reloadReservations());
    unawaited(_loadFollowState());
    if (mounted) setState(() {});
  }

  Future<void> _loadFollowState() async {
    final sellerId = widget.bundle.profile.id.trim();
    final uid = currentUserUid.trim();
    if (uid.isEmpty || sellerId.isEmpty || uid == sellerId) {
      if (mounted) setState(() => _isFollowing = null);
      return;
    }
    final v = await HubActions.queryIsFollowing(sellerId);
    if (mounted) setState(() => _isFollowing = v);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = currentUserUid;
    if (uid != _trackedBuyerId) {
      _trackedBuyerId = uid;
      unawaited(_reloadReservations());
      unawaited(_loadFollowState());
    }
  }

  void _dismissBagHint() {
    final liveId = widget.bundle.live?.id;
    if (liveId == null || !HubLiveBagHintSession.shouldShow(liveId)) return;
    HubLiveBagHintSession.dismiss(liveId);
    _hintDismissTimer?.cancel();
    if (mounted) setState(() {});
  }

  void _scheduleBagHintDismiss(String liveId) {
    if (!HubLiveBagHintSession.shouldShow(liveId)) return;
    _hintDismissTimer?.cancel();
    _hintDismissTimer = Timer(const Duration(seconds: 12), _dismissBagHint);
  }

  bool _showBagHint(String liveId) =>
      currentUserUid.isNotEmpty &&
      _summary.hasAny &&
      HubLiveBagHintSession.shouldShow(liveId);

  Future<void> _reloadReservations({bool silent = false}) async {
    final liveId = widget.bundle.live?.id;
    if (liveId == null || currentUserUid.isEmpty) {
      if (mounted) {
        setState(() {
          _reservations = const [];
          _needsFacebookLogin = false;
        });
      }
      return;
    }
    if (!silent && mounted) setState(() => _loadingReservations = true);
    try {
      // Poll silencioso: sem claim (rate limit). Claim ao abrir / refresh forte.
      HubPsClaimResult? claimResult;
      if (!silent) {
        claimResult = await HubPsClaim.claimForLiveDetailed(
          liveId,
          force: true,
        );
      }
      final rows = await LiveReservationRequestsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('live_id', liveId)
            .eqOrNull('buyer_id', currentUserUid)
            .order('created_at', ascending: false),
        limit: 30,
      );
      if (!mounted) return;
      final needsFb = claimResult?.needsFacebookLogin == true;
      setState(() {
        _reservations = rows;
        _loadingReservations = false;
        if (claimResult != null) {
          _needsFacebookLogin = needsFb;
        }
      });
      if (claimResult != null &&
          claimResult.claimed > 0 &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              claimResult.claimed == 1
                  ? 'Reserva recuperada.'
                  : 'Reservas recuperadas.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      HubQaDiag.logC1(
        source: 'hub_scroll_panel',
        liveId: liveId,
        rows: rows,
        summary: _summary,
      );
      final fleaberOnly = rows
          .where((r) => (r.source ?? '').trim() == 'fleaber_live')
          .toList();
      if (fleaberOnly.length != rows.length) {
        HubQaDiag.logC1(
          source: 'hub_scroll_panel_fleaber_live_filter',
          liveId: liveId,
          rows: fleaberOnly,
          summary: HubReservationSummary.fromRows(fleaberOnly),
        );
      }
      if (_summary.hasAny && HubLiveBagHintSession.shouldShow(liveId)) {
        _scheduleBagHintDismiss(liveId);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReservations = false);
    }
  }

  Future<void> _openBagFromHub() async {
    if (currentUserUid.isEmpty) {
      final ok = await HubActions.requireAuth(
        context,
        intentLabel: 'ver o teu saco',
        inLivePlayer: true,
      );
      if (!ok || !mounted) return;
      await _reloadReservations();
    }
    if (!mounted) return;
    _dismissBagHint();

    final live = widget.bundle.live;
    final liveId = live?.id.trim() ?? '';
    if (liveId.isEmpty) return;

    // Saco Hub próprio (claim + mesmas linhas do banner) — não depender do
    // LiveEmbedHost/player, que por vezes abria sheet com 0 linhas.
    final claimOpen = await HubPsClaim.claimForLiveDetailed(
      liveId,
      force: true,
    );
    if (!mounted) return;
    if (claimOpen.needsFacebookLogin) {
      setState(() => _needsFacebookLogin = true);
    } else if (claimOpen.ok && claimOpen.claimed > 0) {
      setState(() => _needsFacebookLogin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimOpen.claimed == 1
                ? 'Reserva recuperada.'
                : 'Reservas recuperadas.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final itemsById = <String, HubLiveItem>{
      for (final i in widget.bundle.items)
        if ((i.id).trim().isNotEmpty) i.id.trim(): i,
    };

    await HubLiveBagSheet.show(
      context,
      liveId: liveId,
      sellerId: widget.bundle.profile.id,
      itemsById: itemsById,
      summary: _summary,
      psDemo: widget.psDemo,
      needsFacebookLogin: _needsFacebookLogin,
      onContinueWithFacebook: () =>
          unawaited(HubActions.continueWithFacebook(context)),
      loadRows: () async {
        // Throttle: não forçar a cada 5s do sheet.
        final claim = await HubPsClaim.claimForLiveDetailed(liveId);
        if (mounted && claim.needsFacebookLogin != _needsFacebookLogin) {
          setState(() => _needsFacebookLogin = claim.needsFacebookLogin);
        }
        final uid = currentUserUid.trim();
        if (uid.isEmpty) return const <LiveReservationRequestsRow>[];
        final sellerId = widget.bundle.profile.id.trim();
        if (sellerId.isEmpty) {
          return LiveReservationQueueService().liveBagDisplayRequests(
            liveId: liveId,
            buyerId: uid,
          );
        }
        return LiveReservationQueueService().sellerBagDisplayRequests(
          sellerId: sellerId,
          buyerId: uid,
        );
      },
      loadSellerBagMeta: () {
        final sellerId = widget.bundle.profile.id.trim();
        if (sellerId.isEmpty) return Future.value(null);
        return LiveReservationQueueService().loadSellerBag(sellerId: sellerId);
      },
      onChanged: () {
        unawaited(_reloadReservations(silent: true));
      },
    );
    if (mounted) await _reloadReservations(silent: true);
  }

  Future<void> _loginForBag() async {
    final ok = await HubActions.requireAuth(
      context,
      intentLabel: 'ver o teu saco',
      inLivePlayer: true,
    );
    if (ok && mounted) await _reloadReservations();
  }

  bool _hasInternalHistory(BuildContext context) =>
      HubNavigation.hasInternalBack(context);

  void _hubClose(BuildContext context) {
    if (_hasInternalHistory(context)) {
      context.pop();
    }
  }

  Future<void> _onToggleFollow() async {
    if (_followBusy == true) return;
    setState(() => _followBusy = true);
    try {
      await HubActions.toggleFollow(
        context,
        sellerId: widget.bundle.profile.id,
        isFollowing: _isFollowing == true,
      );
      await _loadFollowState();
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Widget _buildPlayer({
    required HubLive live,
    required bool isLive,
    required bool hasBack,
    required bool hubDesktopShell,
    Widget? hubTrailing,
  }) {
    return FleaberLivePlayerWidget(
      liveId: live.id,
      playbackId: live.effectivePlaybackId,
      sellerId: widget.bundle.profile.id,
      isLive: isLive,
      embedInHub: true,
      // Desktop: chat + produtos fora do vídeo; mobile: overlays originais Fleaber.
      hubExternalChat: hubDesktopShell,
      hubExternalProducts: hubDesktopShell,
      hubLightShell: hubDesktopShell,
      hubHideOverlaySideActions: hubDesktopShell,
      hubTrailing: hubTrailing,
      showEmbedClose: hasBack,
      hubShowBagReservationHint:
          !hubDesktopShell && _showBagHint(live.id),
      sharePreferredLink: HubUrls.live(
        widget.handle,
        liveId: live.id,
      ),
      onEmbedClose: () => _hubClose(context),
    );
  }


  /// Zona 1 desktop — vendedora compacta + acções + instalar.
  Widget _desktopSellerColumn({required HubLive live}) {
    final profile = widget.bundle.profile;
    final displayStatus = hubLiveDisplayStatus(live);
    final badge = switch (displayStatus) {
      HubLiveDisplayStatus.live => ('AO VIVO', HubTheme.liveRed),
      HubLiveDisplayStatus.preparing => (
          'A PREPARAR',
          const Color(0xFFB78103),
        ),
      HubLiveDisplayStatus.recorded => ('GRAVADO', FleaberColors.teal),
    };
    final name = profile.fullName.trim().isNotEmpty
        ? profile.fullName.trim()
        : '@${widget.handle}';
    final following = _isFollowing == true;
    final liveTitle = (live.title ?? '').trim().isNotEmpty
        ? live.title!.trim()
        : 'O meu directo';
    final published = HubUrls.installAndroidPublished;
    final isOwn = currentUserUid.trim() == profile.id.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FleaberProfileAvatar(
                  userId: profile.id,
                  fullName: profile.fullName,
                  photoUrl: profile.photoUrl,
                  radius: 24,
                  borderColor: FleaberColors.teal.withValues(alpha: 0.35),
                  borderWidth: 2,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: FleaberColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: FleaHubSiteLayout.typeSection,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        '@${widget.handle}',
                        style: GoogleFonts.inter(
                          color: FleaberColors.teal,
                          fontWeight: FontWeight.w700,
                          fontSize: FleaHubSiteLayout.typeSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badge.$2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge.$1,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: FleaHubSiteLayout.typeCaption,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              liveTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: FleaHubSiteLayout.typeBody,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (profile.followerCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${profile.followerCount} seguidores',
                style: GoogleFonts.inter(
                  color: FleaberColors.muted,
                  fontSize: FleaHubSiteLayout.typeCaption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!isOwn)
              FleaberPrimaryButton(
                label: following ? 'A seguir' : 'Seguir',
                height: 40,
                borderRadius: 14,
                fontSize: FleaHubSiteLayout.typeBody,
                onPressed: _followBusy == true ? null : _onToggleFollow,
              ),
            if (!isOwn) const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                HubActions.shareLiveWithRaffle(
                  context,
                  liveId: live.id,
                  handle: widget.handle,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: FleaberColors.teal,
                side: const BorderSide(color: FleaberColors.teal, width: 1.5),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Partilhar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeBody,
                ),
              ),
            ),
            if (isOwn) ...[
              const SizedBox(height: 8),
              HubLiveAmazonScanButton(
                liveId: live.id,
                sellerId: profile.id,
                onAdded: (_) async {
                  await widget.onRefresh();
                },
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: () =>
                  context.push(HubRoutePaths.profileFor(widget.handle)),
              child: Text(
                'Ver perfil',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: published ? 1 : 0.9,
              child: Material(
                color: const Color(0xFF101518),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: published ? () => HubActions.openInstallApp() : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                published ? 'DISPONÍVEL NO' : 'EM BREVE NO',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              Text(
                                'Google Play',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: FleaHubSiteLayout.typeSecondary,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _marketplaceEmptyCopy =
      'Esta loja ainda não tem artigos no Marketplace.';

  Widget _marketplaceEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          _marketplaceEmptyCopy,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: FleaberColors.muted,
            fontSize: FleaHubSiteLayout.typeSecondary,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _marketplaceProductCard(HubProduct p, NumberFormat priceFmt) {
    final price = p.price;
    return MarketplaceProductCard(
      title: p.title,
      stateLabel: p.isSold
          ? 'Vendido'
          : (p.state?.trim().isNotEmpty == true ? p.state!.trim() : null),
      priceLabel: price != null ? priceFmt.format(price) : '',
      imageUrl: p.primaryImage,
      favoritesCount: 0,
      isFavorited: false,
      onTap: () => context.push('/productDetails?product_id=${p.id}'),
    );
  }

  /// Zona Marketplace — coluna lateral; 2 artigos/linha quando largura ≥ 260.
  Widget _desktopMarketplaceColumn({bool twoColumn = true}) {
    final products = widget.bundle.products;
    final priceFmt = NumberFormat.currency(
        locale: 'pt_PT', symbol: '€', decimalDigits: 2);
    return SizedBox.expand(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: FleaberColors.surface,
          borderRadius: BorderRadius.circular(FleaberRadius.md),
          border: Border.all(color: FleaberColors.alternate),
          boxShadow: const [FleaberElevation.sm],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marketplace',
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: FleaHubSiteLayout.typeSection,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Mais desta loja',
              style: GoogleFonts.inter(
                color: FleaberColors.muted,
                fontSize: FleaHubSiteLayout.typeCaption,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: products.isEmpty
                  ? _marketplaceEmpty()
                  : LayoutBuilder(
                      builder: (context, box) {
                        final cols =
                            (twoColumn && box.maxWidth >= 260) ? 2 : 1;
                        if (cols == 2) {
                          return GridView.builder(
                            itemCount: products.length.clamp(0, 40),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio:
                                  MarketplaceProductCard.gridChildAspectRatio,
                            ),
                            itemBuilder: (context, i) =>
                                _marketplaceProductCard(products[i], priceFmt),
                          );
                        }
                        return ListView.separated(
                          itemCount: products.length.clamp(0, 40),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) => SizedBox(
                            width: box.maxWidth,
                            child: _marketplaceProductCard(
                                products[i], priceFmt),
                          ),
                        );
                      },
                    ),
            ),
            TextButton(
              onPressed: () =>
                  context.push(HubRoutePaths.reviewsFor(widget.handle)),
              child: Text(
                'Ver opiniões',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w700,
                  fontSize: FleaHubSiteLayout.typeSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  HubFacebookReservationsEntryKind _fbEntryKind({
    required bool isLoggedIn,
    required bool needsFacebookLogin,
  }) {
    if (!isLoggedIn) return HubFacebookReservationsEntryKind.guest;
    if (needsFacebookLogin) {
      return HubFacebookReservationsEntryKind.needsFacebookLogin;
    }
    return HubFacebookReservationsEntryKind.openBag;
  }

  Future<void> _onFacebookEntryTap({
    required HubFacebookReservationsEntryKind kind,
  }) async {
    switch (kind) {
      case HubFacebookReservationsEntryKind.guest:
        await _loginForBag();
      case HubFacebookReservationsEntryKind.needsFacebookLogin:
        await HubActions.continueWithFacebook(context);
      case HubFacebookReservationsEntryKind.openBag:
        await _openBagFromHub();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        final live = widget.bundle.live;
        final presentation = hubLivePresentation(live);
        final hasBack = _hasInternalHistory(context);

        if (presentation == HubLivePresentation.noLive ||
            presentation == HubLivePresentation.scheduledOnly ||
            live == null) {
          return _HubLiveUnavailable(
            handle: widget.handle,
            presentation: presentation,
            onRefresh: widget.onRefresh,
            showBack: hasBack,
            onBack: () => _hubClose(context),
          );
        }

        final isLive = presentation == HubLivePresentation.liveActive;
        final isLoggedIn = currentUserUid.isNotEmpty;
        final displayStatus = hubLiveDisplayStatus(live);
        final desktopShell = HubTheme.useLiveDesktopShell(context);
        final layoutDiagKey =
            '${live.id}|${live.status}|${live.isActive}|${displayStatus.name}|$isLive|desk:$desktopShell';
        if (_lastLayoutDiagKey != layoutDiagKey) {
          _lastLayoutDiagKey = layoutDiagKey;
          HubPlayerDiag.log('hub_layout', {
            'handle': widget.handle,
            'live_id': live.id,
            'status_raw': live.status ?? '',
            'is_active': live.isActive,
            'display_status': displayStatus.name,
            'is_live_prop': isLive,
            'desktop_shell_b1': desktopShell,
            'mux_playback_id': live.muxPlaybackId ?? '',
            'mux_vod_playback_id': live.muxVodPlaybackId ?? '',
          });
        }

        final fbKind = _fbEntryKind(
          isLoggedIn: isLoggedIn,
          needsFacebookLogin: _needsFacebookLogin,
        );

        // —— Mobile / tablet: experiência original do player Fleaber ——
        if (!desktopShell) {
          final mobilePlayer = _buildPlayer(
            live: live,
            isLive: isLive,
            hasBack: hasBack,
            hubDesktopShell: false,
          );
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: mobilePlayer),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 0,
                    child: ListenableBuilder(
                      listenable:
                          FleaberCookieConsentBanner.consentAccepted,
                      builder: (context, _) {
                        // Acima do aviso de cookies — chip FB + carrossel acessíveis.
                        final bottom =
                            FleaberCookieConsentBanner.consentAccepted.value
                                ? 12.0
                                : 156.0;
                        return Padding(
                          padding: EdgeInsets.only(bottom: bottom),
                          child: HubFacebookReservationsEntry(
                            kind: fbKind,
                            chip: true,
                            onPressed: () => unawaited(
                              _onFacebookEntryTap(kind: fbKind),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // —— Desktop: seller | (produtos·vídeo·rail·chat·MP na mesma Row) ——
        final pageW = MediaQuery.sizeOf(context).width;
        final stageMax = math.min(
          HubTheme.liveDesktopStageMaxWidth,
          pageW * 0.98,
        );
        final twoColMp = pageW >= 1280;
        final player = _buildPlayer(
          live: live,
          isLive: isLive,
          hasBack: hasBack,
          hubDesktopShell: true,
          hubTrailing: _desktopMarketplaceColumn(twoColumn: twoColMp),
        );

        final stage = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: (HubTheme.liveDesktopSellerFlex * 100).round(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: HubTheme.liveDesktopSellerMinWidth,
                ),
                child: _desktopSellerColumn(live: live),
              ),
            ),
            const SizedBox(width: HubTheme.liveDesktopColumnGap),
            Expanded(
              flex: ((HubTheme.liveDesktopProductsFlex +
                          HubTheme.liveDesktopChatFlex +
                          HubTheme.liveDesktopMarketplaceFlex) *
                      100)
                  .round() +
                  220,
              child: player,
            ),
          ],
        );

        return Scaffold(
          backgroundColor: FleaberColors.bgTint,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FleaHubSiteTopBar(),
                const FleaHubTopBarBleed(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: stageMax),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: stage,
                      ),
                    ),
                  ),
                ),
                const FleaHubSiteFooter(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HubLiveUnavailable extends StatelessWidget {
  const _HubLiveUnavailable({
    required this.handle,
    required this.presentation,
    required this.onRefresh,
    required this.showBack,
    required this.onBack,
  });

  final String handle;
  final HubLivePresentation presentation;
  final Future<void> Function() onRefresh;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      body: SafeArea(
        child: RefreshIndicator(
          color: FleaberColors.teal,
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: FleaHubSiteTopBar()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (showBack)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                size: 16),
                            label: const Text('Voltar'),
                          ),
                        ),
                      if (presentation == HubLivePresentation.noLive)
                        const HubEmptyState(
                          message:
                              'Não há directo activo agora. Segue a seller para saberes quando entra em directo.',
                          icon: Icons.schedule_outlined,
                        )
                      else
                        Text(
                          'Directo agendado — volta mais tarde.',
                          style: GoogleFonts.inter(
                            color: FleaberColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => HubActions.copyLink(
                          context,
                          HubUrls.live(handle),
                        ),
                        child: const Text('Copiar link'),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: FleaHubSiteFooter()),
            ],
          ),
        ),
      ),
    );
  }
}
