import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/fleahub_info_pages.dart';
import 'pages/fleahub_landing_page.dart';
import 'pages/hub_dev_launcher_page.dart';
import 'pages/hub_not_found_page.dart';
import 'routing/hub_handle_gate.dart';
import 'routing/hub_route_paths.dart';

/// Rotas FleaHub — **últimas** na lista GoRouter (catch-all `/:handle`).
/// App + browser: mesma experiência (`HubTheme`, widgets partilhados).
List<RouteBase> buildHubGoRoutes() {
  Widget gate(BuildContext context, GoRouterState state, HubSection section) {
    final handle = state.pathParameters['handle'] ?? '';
    return HubHandleGate(
      rawHandle: handle,
      uri: state.uri,
      section: section,
    );
  }

  return [
    GoRoute(
      path: HubDevLauncherPage.routePath,
      name: HubDevLauncherPage.routeName,
      builder: (context, state) => const HubDevLauncherPage(),
    ),
    GoRoute(
      path: FleaHubLandingPage.routePath,
      name: FleaHubLandingPage.routeName,
      builder: (context, state) => const FleaHubLandingPage(),
    ),
    GoRoute(
      path: FleaHubHowItWorksPage.routePath,
      name: FleaHubHowItWorksPage.routeName,
      builder: (context, state) => const FleaHubHowItWorksPage(),
    ),
    GoRoute(
      path: FleaHubBuySafePage.routePath,
      name: FleaHubBuySafePage.routeName,
      builder: (context, state) => const FleaHubBuySafePage(),
    ),
    GoRoute(
      path: FleaHubSellPage.routePath,
      name: FleaHubSellPage.routeName,
      builder: (context, state) => const FleaHubSellPage(),
    ),
    GoRoute(
      path: FleaHubHelpPage.routePath,
      name: FleaHubHelpPage.routeName,
      builder: (context, state) => const FleaHubHelpPage(),
    ),
    GoRoute(
      path: FleaHubContactsPage.routePath,
      name: FleaHubContactsPage.routeName,
      builder: (context, state) => const FleaHubContactsPage(),
    ),
    GoRoute(
      path: '/:handle',
      name: 'HubProfile',
      builder: (context, state) =>
          gate(context, state, HubSection.profile),
      routes: [
        GoRoute(
          path: 'live',
          name: 'HubLive',
          builder: (context, state) => gate(context, state, HubSection.live),
        ),
        GoRoute(
          path: 'shop',
          name: 'HubShop',
          builder: (context, state) => gate(context, state, HubSection.shop),
        ),
        GoRoute(
          path: 'reviews',
          name: 'HubReviews',
          builder: (context, state) =>
              gate(context, state, HubSection.reviews),
        ),
        GoRoute(
          path: ':invalidSection',
          builder: (context, state) => const HubNotFoundPage(),
        ),
      ],
    ),
  ];
}
