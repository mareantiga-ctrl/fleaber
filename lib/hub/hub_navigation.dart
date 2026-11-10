import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/nav/nav.dart';
import '/index.dart';

import 'pages/fleahub_landing_page.dart';
import 'routing/hub_reserved_slugs.dart';
import 'routing/hub_route_paths.dart';
import 'theme/hub_theme.dart';
import 'widgets/hub_account_chrome.dart';

/// Navegação Hub — back interno vs entrada directa por URL.
abstract final class HubNavigation {
  /// Margens do overlay (alinhado ao fechar do player embed).
  static const overlayTop = 12.0;
  static const overlayLeft = 12.0;

  /// «Glass» do player live embed — círculo compacto.
  static const glassAlpha = 0.50;
  static const iconSize = 18.0;
  static const tapPadding = 6.0;

  /// Histórico interno (push app) — não confundir com URL directa.
  static bool hasInternalBack(BuildContext context) {
    if (!context.canPop()) return false;
    final route = ModalRoute.of(context);
    if (route == null || route.isFirst) return false;
    return true;
  }

  /// Voltar na topbar FleaHub (H02, info, …) — nunca na landing bare.
  /// Direct URL sem stack → [popOrLanding] vai para `#/fleahub`.
  static bool showSiteChromeBack(BuildContext context) {
    try {
      final path = GoRouterState.of(context).uri.path;
      final bare = path == HubRoutePaths.landing ||
          path == '${HubRoutePaths.landing}/';
      if (bare) return false;
      return true;
    } catch (_) {
      return hasInternalBack(context);
    }
  }

  /// Path que parece Hub mas não casou com rotas válidas → 404 Hub (B3).
  static bool isUnhandledHubPath(String path) {
    final segments =
        path.split('/').where((segment) => segment.trim().isNotEmpty).toList();
    if (segments.length < 2) return false;

    if (segments.length == 2) {
      final handle = segments[0];
      final suffix = segments[1].toLowerCase();
      if (HubReservedSlugs.blocksHubHandle(handle)) return false;
      const valid = {'live', 'shop', 'reviews'};
      return !valid.contains(suffix);
    }

    final suffix = segments[1].toLowerCase();
    return {'live', 'shop', 'reviews'}.contains(suffix);
  }

  static void pop(BuildContext context) {
    if (context.canPop()) context.pop();
  }

  /// Entrada directa sem histórico — raiz Fleaber (Home ou login).
  ///
  /// Web FleaHub: sempre a landing redesenhada (`/fleahub`).
  /// App nativa: Home clássica se autenticado; senão `/`.
  static void goFleaberHome(BuildContext context) {
    if (kIsWeb) {
      goFleahubLanding(context);
      return;
    }
    if (AppStateNotifier.instance.loggedIn) {
      context.goNamed(HomePageWidget.routeName);
      return;
    }
    context.go('/');
  }

  /// Destino «Início» / pós-login coerente com o canal.
  ///
  /// Em `fleaber.pt/fleahub` (web) a Home antiga (`/homePage`) não deve
  /// voltar a aparecer — a referência é [FleaHubLandingPage].
  static void goAppHome(BuildContext context, {bool replace = true}) {
    if (kIsWeb) {
      if (replace) {
        context.go(HubRoutePaths.landing);
      } else {
        context.push(HubRoutePaths.landing);
      }
      return;
    }
    if (replace) {
      context.goNamed(HomePageWidget.routeName);
    } else {
      context.pushNamed(HomePageWidget.routeName);
    }
  }

  /// Path da home no canal actual (`/fleahub` web · `/homePage` nativo).
  static String get appHomePath =>
      kIsWeb ? HubRoutePaths.landing : HomePageWidget.routePath;

  /// Nome de rota GoRouter da home no canal actual.
  static String get appHomeRouteName =>
      kIsWeb ? FleaHubLandingPage.routeName : HomePageWidget.routeName;

  /// Página inicial pública FleaHub (`/fleahub`) — acessível sem login.
  static void goFleahubLanding(BuildContext context) {
    context.go(HubRoutePaths.landing);
  }

  static void popOrLanding(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(HubRoutePaths.landing);
  }
}

/// Botão voltar Hub — mesmo «glass» que o fechar do player live.
class HubBackButton extends StatelessWidget {
  const HubBackButton({
    super.key,
    this.onPressed,
    this.icon = Icons.arrow_back_ios_new_rounded,
  });

  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!HubNavigation.hasInternalBack(context)) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.black.withValues(alpha: HubNavigation.glassAlpha),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed ?? () => context.pop(),
        child: Padding(
          padding: const EdgeInsets.all(HubNavigation.tapPadding),
          child: Icon(icon, color: Colors.white, size: HubNavigation.iconSize),
        ),
      ),
    );
  }

  static Widget topLeftOverlay(
    BuildContext context, {
    VoidCallback? onPressed,
  }) {
    if (!HubNavigation.hasInternalBack(context)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: HubNavigation.overlayTop,
      left: HubNavigation.overlayLeft,
      child: SafeArea(
        bottom: false,
        child: HubBackButton(onPressed: onPressed),
      ),
    );
  }

  /// Voltar integrado na topbar clara (H01 chrome partilhado) — sem círculo glass.
  static Widget? topBarLeading(BuildContext context) {
    if (!HubNavigation.showSiteChromeBack(context)) return null;
    return IconButton(
      tooltip: 'Voltar',
      onPressed: () => HubNavigation.popOrLanding(context),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: const Icon(
        Icons.arrow_back_ios_new_rounded,
        color: Color(0xFF007782),
        size: 18,
      ),
    );
  }
}

/// Página Hub — barra de conta (Entrar / sessão) + overlay voltar opcional.
class HubPageShell extends StatelessWidget {
  const HubPageShell({
    super.key,
    required this.child,
    this.showBack = true,
    this.showAccountChrome = true,
  });

  final Widget child;
  final bool showBack;

  /// Barra FleaHub + Entrar / nome + Sair. Desligar só se o ecrã já tiver
  /// chrome próprio (ex. landing) — não usar no player live.
  final bool showAccountChrome;

  static const _chromeBodyHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (showAccountChrome) {
      final topInset = MediaQuery.paddingOf(context).top;
      final chromeTotal = topInset + _chromeBodyHeight;
      // Stack+Positioned: fiável no web (Column+Expanded falhava em silêncio).
      content = SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: chromeTotal),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: HubAccountChromeBar(),
            ),
          ],
        ),
      );
    }
    if (!showBack || !HubNavigation.hasInternalBack(context)) {
      return content;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        HubBackButton.topLeftOverlay(context),
      ],
    );
  }
}

/// Loading Hub — back quando push interno.
class HubLoadingShell extends StatelessWidget {
  const HubLoadingShell({
    super.key,
    this.message = 'A carregar…',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return HubPageShell(
      child: Scaffold(
        backgroundColor: HubTheme.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: HubTheme.teal),
              const SizedBox(height: 16),
              Text(
                message,
                style: GoogleFonts.inter(
                  color: HubTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AppBar Hub — back só com histórico interno.
PreferredSizeWidget hubConditionalAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  VoidCallback? onBack,
}) {
  final hasBack = HubNavigation.hasInternalBack(context);
  return AppBar(
    backgroundColor: HubTheme.bg,
    foregroundColor: Colors.white,
    elevation: 0,
    automaticallyImplyLeading: false,
    leading: hasBack
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: onBack ?? () => context.pop(),
          )
        : null,
    title: Text(title),
    actions: actions,
  );
}
