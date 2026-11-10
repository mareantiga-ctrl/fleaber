import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hub_urls.dart';
import '../routing/hub_route_paths.dart';
import 'hub_seller_copy.dart';

/// Copiar / abrir / partilhar links Hub (`fleaber.pt`) — sem App Links (#22).
abstract final class HubSellerShare {
  static String profileUrl(String handle) => HubUrls.profile(handle);

  static String liveUrl(String handle) => HubUrls.live(handle);

  static Future<void> copyUrl(
    BuildContext context,
    String url, {
    bool showSnackBar = true,
  }) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(HubSellerCopy.linkCopiedFeedback)),
      );
    }
  }

  /// Partilha = copiar link (sem `share_plus` — colar em WhatsApp/IG).
  static Future<void> shareUrl(
    BuildContext context,
    String url, {
    bool showSnackBar = true,
  }) async {
    await copyUrl(context, url, showSnackBar: showSnackBar);
  }

  static Future<void> openInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Path sem query — `/perfilVendedor?sellerID=` → `/perfilVendedor`.
  static String locationPath(String location) {
    final uri = Uri.tryParse(location);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    final q = location.indexOf('?');
    return q <= 0 ? location : location.substring(0, q);
  }

  /// Ecrã onde o Hub deve assentar: **1 voltar** regressa aqui (Z1 / NAV-004).
  ///
  /// Não se parte o Perfil nem a Home — um `pop` cego extra era o que
  /// mandava o utilizador para o Início.
  static bool isHubReturnAnchor(String location) {
    final path = locationPath(location);
    return path == '/perfil' ||
        path == '/homePage' ||
        path == '/' ||
        path == '/login';
  }

  /// Abre FleaHub **in-app** (push — permite voltar à origem Fleaber).
  ///
  /// [closeModalFirst]: usar a `true` a partir do bottom sheet FleaHub («Ver»),
  /// para 1 back regressar ao Perfil sem o sheet ficar por cima (Z1).
  static void viewPublicHub(
    BuildContext context, {
    required String handle,
    bool live = false,
    bool closeModalFirst = false,
  }) {
    final h = handle.trim();
    if (h.isEmpty) return;
    final path =
        live ? HubRoutePaths.liveFor(h) : HubRoutePaths.profileFor(h);
    final router = GoRouter.of(context);
    final route = ModalRoute.of(context);
    final inPopup = route is PopupRoute;
    if (closeModalFirst || inPopup) {
      final sheetNav = Navigator.of(context, rootNavigator: true);
      if (sheetNav.canPop()) {
        sheetNav.pop();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popUntilHubAnchor(router);
        router.push(path);
      });
      return;
    }
    router.push(path);
  }

  static String _routerLocation(GoRouter router) {
    final lastMatch = router.routerDelegate.currentConfiguration.last;
    final matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }

  /// Fecha «anúncios» (PerfilVendedor) mas **para** no Perfil. Nunca no Início.
  static void _popUntilHubAnchor(GoRouter router) {
    var guard = 0;
    while (router.canPop() && guard < 8) {
      if (isHubReturnAnchor(_routerLocation(router))) {
        break;
      }
      router.pop();
      guard++;
    }
  }
}
