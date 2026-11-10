import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/utils/live_raffle_share.dart';
import '/widgets/fleaber_primary_button.dart';

import 'data/hub_public_repository.dart';
import 'hub_public_access.dart';
import 'hub_urls.dart';
import 'routing/hub_reserved_slugs.dart';
import 'routing/hub_route_paths.dart';
import 'theme/hub_theme.dart';
import 'widgets/hub_auth_prompt.dart';

/// Login-on-action + partilha + funil app.
abstract final class HubActions {
  static const _loginPath = '/login';
  static const _registoPath = '/registo';

  /// Landing FleaHub na secção Explorar (diretos) — não o hero vazio.
  /// Se já estamos no Hub, substitui a rota (evita pilha duplicada).
  static void openFleaHubLanding(BuildContext context) {
    final dest = HubRoutePaths.landingExploreTab('diretos');
    final path = GoRouterState.of(context).uri.path;
    final onHub = path == HubRoutePaths.landing ||
        path.startsWith('${HubRoutePaths.landing}/') ||
        path == '/fleahub' ||
        path.startsWith('/fleahub/');
    if (onHub) {
      context.go(dest);
      return;
    }
    context.push(dest);
  }

  /// Perfil público canónico — [HubProfilePage] em `/{handle}` (H02).
  ///
  /// Resolve o handle via `hub_profiles_*`; não abre o legado
  /// `/perfilVendedor`. [initialTab]: `diretos` | `marketplace` | `opinioes`.
  static Future<void> openPublicProfile(
    BuildContext context, {
    required String sellerId,
    String? initialTab,
  }) async {
    final id = sellerId.trim();
    if (id.isEmpty) return;
    final profile = await HubPublicRepository().fetchProfileById(id);
    if (!context.mounted) return;
    final handle = profile?.handle.trim() ?? '';
    if (handle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil público ainda não disponível.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final tab = initialTab?.trim() ?? '';
    final path = tab.isEmpty
        ? HubRoutePaths.profileFor(handle)
        : HubRoutePaths.profileTabFor(handle, tab);
    context.push(path);
  }

  /// Guarda destino e abre login/registo (returnTo visível na URL).
  static void openLoginForReturn(
    BuildContext context, {
    String returnTo = HubRoutePaths.landing,
  }) {
    captureReturnTo(returnTo);
    context.push(
      '$_loginPath?returnTo=${Uri.encodeQueryComponent(returnTo)}',
    );
  }

  static void openRegistoForReturn(
    BuildContext context, {
    String returnTo = HubRoutePaths.landing,
  }) {
    // Nunca reabrir o login aqui: com returnTo do Hub isso fazia loop
    // («Registar-se» → login → «Registar-se» → login).
    if (!HubPublicAccess.registrationEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O registo público está temporariamente indisponível. '
            'Tenta mais tarde ou contacta a Fleaber.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    captureReturnTo(returnTo);
    context.push(
      '$_registoPath?returnTo=${Uri.encodeQueryComponent(returnTo)}',
    );
  }

  static void captureReturnTo(String returnTo) {
    final path = returnTo.trim();
    if (path.isEmpty) return;
    AppStateNotifier.instance.setRedirectLocation(path);
  }

  /// Path + query da URI actual (destino Hub após login).
  static String normalizeReturnTo(Uri uri) {
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.path}$q';
  }

  /// returnTo visível na URL ou redirect pendente em memória.
  static String? resolvePendingReturnTo(BuildContext context) {
    return resolveAuthDestination(context);
  }

  /// Destino pós-auth: query `returnTo`, memória, ou valor capturado antes do login.
  static String? resolveAuthDestination(
    BuildContext context, {
    String? captured,
  }) {
    final fromCapture = captured?.trim();
    if (fromCapture != null && fromCapture.isNotEmpty) return fromCapture;
    final fromQuery =
        GoRouterState.of(context).uri.queryParameters['returnTo']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final appState = AppStateNotifier.instance;
    if (appState.hasRedirect()) return appState.getRedirectLocation();
    return null;
  }

  /// Destino pós-auth pertence ao FleaHub (landing, perfil, live, shop, reviews).
  static bool isFleaHubReturnPath(String? location) {
    if (location == null || location.trim().isEmpty) return false;
    final Uri uri;
    try {
      final raw = location.trim();
      uri = Uri.parse(raw.startsWith('/') ? raw : '/$raw');
    } catch (_) {
      return false;
    }
    final path = uri.path;
    if (path == HubRoutePaths.landing ||
        path.startsWith('${HubRoutePaths.landing}/')) {
      return true;
    }
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    if (HubReservedSlugs.blocksHubHandle(segments.first)) return false;
    if (segments.length == 1) return true;
    if (segments.length >= 2) {
      return switch (segments[1].toLowerCase()) {
        'live' || 'shop' || 'reviews' => true,
        _ => false,
      };
    }
    return false;
  }

  static bool isFleaHubAuthContext(BuildContext context) {
    return isFleaHubReturnPath(resolvePendingReturnTo(context));
  }

  /// Breve ecrã «A regressar ao FleaHub…» antes do redirect.
  static Future<void> showFleaHubAuthWelcome(BuildContext context) async {
    if (!context.mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black26,
        builder: (ctx) => PopScope(
          canPop: false,
          child: Center(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              elevation: 8,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF007782),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bem-vindo.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF101518),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A regressar ao FleaHub...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF666666),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Pausa pós-auth + navegação explícita para [returnTo].
  static Future<bool> finishAuthWithHubWelcome(
    BuildContext context, {
    required String returnTo,
  }) async {
    if (isFleaHubReturnPath(returnTo)) {
      await showFleaHubAuthWelcome(context);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!context.mounted) return false;
    await publishAuthSession();
    if (!context.mounted) return false;
    return finishAuthRedirect(context, returnTo: returnTo);
  }

  /// Garante que widgets Hub veem sessão autenticada sem clique extra.
  static Future<void> publishAuthSession() async {
    await authManager.refreshUser();
    final appState = AppStateNotifier.instance;
    appState.updateNotifyOnAuthChange(true);
    final authUser = currentUser;
    if (authUser != null) {
      appState.update(authUser);
    }
    appState.notifyListeners();
  }

  /// Após auth OK — navega sempre para o destino (nunca pop silencioso).
  static bool finishAuthRedirect(
    BuildContext context, {
    String? returnTo,
  }) {
    final loc = resolveAuthDestination(context, captured: returnTo);
    if (loc == null || loc.isEmpty) return false;
    final appState = AppStateNotifier.instance;
    appState.clearRedirectLocation();
    appState.updateNotifyOnAuthChange(true);
    context.go(loc);
    return true;
  }
  static Future<bool> requireAuth(
    BuildContext context, {
    required String intentLabel,
    String? titleOverride,
    bool inLivePlayer = false,
  }) async {
    if (currentUserUid.isNotEmpty) return true;
    final proceed = await HubAuthPrompt.show(
      context,
      intentLabel: intentLabel,
      titleOverride: titleOverride,
      dismissLabel: inLivePlayer ? 'Voltar ao directo' : 'Agora não',
    );
    if (proceed != true || !context.mounted) return false;
    final returnTo = normalizeReturnTo(GoRouterState.of(context).uri);
    openLoginForReturn(context, returnTo: returnTo);
    return false;
  }

  /// Continua com Facebook OAuth existente (Hub claim `facebook_login_required`).
  /// Preserva [returnTo] da Live actual — sem OAuth paralelo.
  static Future<void> continueWithFacebook(BuildContext context) async {
    final returnTo = normalizeReturnTo(GoRouterState.of(context).uri);
    captureReturnTo(returnTo);
    GoRouter.of(context).prepareAuthEvent(true);
    await authManager.signInWithFacebook(context, returnTo: returnTo);
    if (!context.mounted) return;
    // Web: redirect completo para Facebook — recovery em main.dart.
    if (kIsWeb) return;
    if (currentUserUid.isEmpty) return;
    await finishAuthWithHubWelcome(context, returnTo: returnTo);
  }

  static Future<void> copyLink(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link copiado: $url'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> shareUrl(BuildContext context, String url) async {
    await copyLink(context, url);
  }

  /// Partilhar directo Hub — **mesmas regras de rifa** que o Player Fleaber
  /// (login + rifa activa → join se preciso + bónus de partilha).
  static Future<void> shareLiveWithRaffle(
    BuildContext context, {
    required String liveId,
    required String handle,
  }) async {
    final id = liveId.trim();
    if (id.isEmpty) {
      await shareUrl(context, HubUrls.live(handle));
      return;
    }
    final result = await LiveRaffleShare.shareLive(
      liveId: id,
      preferredLink: HubUrls.live(handle, liveId: id),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Perfil Hub: se a seller está AO VIVO, partilha o live (com rifa);
  /// senão, só o perfil.
  static Future<void> shareProfileOrLive(
    BuildContext context, {
    required String handle,
    String? activeLiveId,
  }) async {
    final liveId = activeLiveId?.trim() ?? '';
    if (liveId.isNotEmpty) {
      await shareLiveWithRaffle(
        context,
        liveId: liveId,
        handle: handle,
      );
      return;
    }
    await shareUrl(context, HubUrls.profile(handle));
  }

  static Future<void> openInstallApp() async {
    final uri = Uri.parse(HubUrls.installAndroid);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> toggleFollow(
    BuildContext context, {
    required String sellerId,
    required bool isFollowing,
  }) async {
    final ok = await requireAuth(context, intentLabel: 'seguir esta seller');
    if (!ok) return;
    if (currentUserUid.isNotEmpty && currentUserUid == sellerId.trim()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não podes seguir a tua própria conta.'),
        ),
      );
      return;
    }
    try {
      if (isFollowing) {
        await FollowsTable().delete(
          matchingRows: (q) => q
              .eqOrNull('follower_id', currentUserUid)
              .eqOrNull('following_id', sellerId),
        );
      } else {
        await FollowsTable().insert({
          'follower_id': currentUserUid,
          'following_id': sellerId,
        });
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFollowing ? 'Deixaste de seguir' : 'A seguir'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível actualizar.')),
      );
    }
  }

  static Future<bool?> queryIsFollowing(String sellerId) async {
    if (currentUserUid.isEmpty) return false;
    final rows = await FollowsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('follower_id', currentUserUid)
          .eqOrNull('following_id', sellerId),
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
