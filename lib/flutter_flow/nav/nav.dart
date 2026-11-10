import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/chat_session_util.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

import '/hub/hub_actions.dart';
import '/utils/fleaber_oauth_redirect.dart';
import '/utils/fleaber_password_recovery.dart';
import '/index.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_h10_navigation.dart';
import '/utils/fleaber_paid_sale_chat.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_tip_context.dart';
import '/utils/live_reservation_queue_service.dart';

import '/hub/hub_account_routes.dart';
import '/hub/hub_navigation.dart';
import '/hub/hub_routes.dart';
import '/hub/pages/fleahub_landing_page.dart';
import '/hub/pages/hub_not_found_page.dart';
import '/hub/pages/hub_bag_visual_catalog_page.dart';
import '/hub/pages/hub_checkout_visual_catalog_page.dart';
import '/hub/pages/hub_messages_visual_catalog_page.dart';
import '/hub/pages/hub_messages_demo_thread_page.dart';
import '/hub/routing/hub_route_paths.dart';
import '/perfil/perfil_desktop_nav.dart';

export 'package:go_router/go_router.dart';
export 'serialization_util.dart';

const kTransitionInfoKey = '__transition_info__';

GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier._();

  static AppStateNotifier? _instance;
  static AppStateNotifier get instance => _instance ??= AppStateNotifier._();

  BaseAuthUser? initialUser;
  BaseAuthUser? user;
  bool showSplashImage = false;
  String? _redirectLocation;

  /// Determines whether the app will refresh and build again when a sign
  /// in or sign out happens. This is useful when the app is launched or
  /// on an unexpected logout. However, this must be turned off when we
  /// intend to sign in/out and then navigate or perform any actions after.
  /// Otherwise, this will trigger a refresh and interrupt the action(s).
  bool notifyOnAuthChange = true;

  bool get loading => showSplashImage;
  bool get loggedIn => user?.loggedIn ?? false;
  bool get initiallyLoggedIn => initialUser?.loggedIn ?? false;
  bool get shouldRedirect => loggedIn && _redirectLocation != null;

  String getRedirectLocation() => _redirectLocation!;
  bool hasRedirect() => _redirectLocation != null;
  void setRedirectLocationIfUnset(String loc) => _redirectLocation ??= loc;
  void setRedirectLocation(String loc) => _redirectLocation = loc;
  void clearRedirectLocation() => _redirectLocation = null;

  /// Mark as not needing to notify on a sign in / out when we intend
  /// to perform subsequent actions (such as navigation) afterwards.
  void updateNotifyOnAuthChange(bool notify) => notifyOnAuthChange = notify;

  void update(BaseAuthUser newUser) {
    final shouldUpdate =
        user?.uid == null || newUser.uid == null || user?.uid != newUser.uid;
    initialUser ??= newUser;
    user = newUser;
    // Refresh the app on auth change unless explicitly marked otherwise.
    // No need to update unless the user has changed.
    if (notifyOnAuthChange && shouldUpdate) {
      notifyListeners();
    }
    // Once again mark the notifier as needing to update on auth change
    // (in order to catch sign in / out events).
    updateNotifyOnAuthChange(true);
  }

  void stopShowingSplashImage() {
    showSplashImage = false;
    notifyListeners();
  }
}

GoRouter createRouter(AppStateNotifier appStateNotifier) => GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: false,
      // Restaura a última rota (URL + query) quando o Android recria o processo
      // (ex.: "Don't keep activities" / falta de memória) em vez de cair na Home.
      restorationScopeId: 'fleaber_router',
      refreshListenable: appStateNotifier,
      navigatorKey: appNavigatorKey,
      errorBuilder: (context, state) {
        if (HubNavigation.isUnhandledHubPath(state.uri.path)) {
          return const HubNotFoundPage();
        }
        // Web FleaHub: nunca cair na Home clássica (pré-H01).
        if (kIsWeb) return const FleaHubLandingPage();
        return appStateNotifier.loggedIn ? HomePageWidget() : LoginWidget();
      },
      routes: [
        FFRoute(
          name: '_initialize',
          path: '/',
          builder: (context, _) {
            if (kIsWeb) return const FleaHubLandingPage();
            return appStateNotifier.loggedIn
                ? HomePageWidget()
                : LoginWidget();
          },
        ),
        FFRoute(
          name: LoginWidget.routeName,
          path: LoginWidget.routePath,
          builder: (context, params) => LoginWidget(),
        ),
        FFRoute(
          name: RegistoWidget.routeName,
          path: RegistoWidget.routePath,
          builder: (context, params) => RegistoWidget(),
        ),
        FFRoute(
          name: HomePageWidget.routeName,
          path: HomePageWidget.routePath,
          builder: (context, params) {
            // Alias legado: `/homePage` no web → landing H01.
            if (kIsWeb) {
              return const _WebRedirectToFleahubLanding();
            }
            return HomePageWidget();
          },
        ),
        FFRoute(
          name: 'AuthCallback',
          path: '/auth-callback',
          builder: (context, params) => _OAuthCallbackResolver(
            uri: params.state.uri,
          ),
        ),
        FFRoute(
          name: 'StripeReturn',
          path: '/stripe-success',
          requireAuth: true,
          builder: (context, params) {
            return _StripeReturnResolver(
              sessionId: params.getParam(
                'session_id',
                ParamType.String,
              ),
              orderId: params.getParam(
                'order_id',
                ParamType.String,
              ),
              productId: params.getParam(
                'product_id',
                ParamType.String,
              ),
              liveId: _firstQueryParam(
                params,
                const ['liveId', 'live_id'],
              ),
              playbackId: params.getParam(
                'playbackId',
                ParamType.String,
              ),
              isLive: params.getParam(
                'isLive',
                ParamType.bool,
              ),
              sellerId: params.getParam(
                'sellerId',
                ParamType.String,
              ),
            );
          },
        ),
        FFRoute(
          name: EsqueciSenhaWidget.routeName,
          path: EsqueciSenhaWidget.routePath,
          builder: (context, params) => EsqueciSenhaWidget(),
        ),
        FFRoute(
          name: NovaSenhaWidget.routeName,
          path: NovaSenhaWidget.routePath,
          builder: (context, params) => NovaSenhaWidget(),
        ),
        FFRoute(
          name: 'Opinioes',
          path: '/opinioes',
          builder: (context, params) => PerfilVendedorWidget(
            sellerID: params.getParam(
              'sellerID',
              ParamType.String,
            ),
            initialTab: 'opinioes',
          ),
        ),
        FFRoute(
          name: PerfilVendedorWidget.routeName,
          path: PerfilVendedorWidget.routePath,
          builder: (context, params) => PerfilVendedorWidget(
            sellerID: params.getParam(
              'sellerID',
              ParamType.String,
            ),
            initialTab: params.getParam(
              'initialTab',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: LiveStreamVendorWidget.routeName,
          path: LiveStreamVendorWidget.routePath,
          builder: (context, params) => LiveStreamVendorWidget(),
        ),
        FFRoute(
          name: PrepararDirectoPageWidget.routeName,
          path: PrepararDirectoPageWidget.routePath,
          builder: (context, params) => const PrepararDirectoPageWidget(),
        ),
        FFRoute(
          name: CriarDirectoPageWidget.routeName,
          path: CriarDirectoPageWidget.routePath,
          builder: (context, params) => const CriarDirectoPageWidget(),
        ),
        FFRoute(
          name: FleaberLivePlayerWidget.routeName,
          path: FleaberLivePlayerWidget.routePath,
          builder: (context, params) => FleaberLivePlayerWidget(
            liveId: params.getParam(
              'liveId',
              ParamType.String,
            ),
            playbackId: params.getParam(
              'playbackId',
              ParamType.String,
            ),
            isLive: params.getParam(
              'isLive',
              ParamType.bool,
            ),
            sellerId: params.getParam(
              'sellerId',
              ParamType.String,
            ),
            raffleRef: params.getParam(
              'ref',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: ChatPageWidget.routeName,
          path: ChatPageWidget.routePath,
          builder: (context, params) => ChatPageWidget(
            otherUserId: params.getParam(
              'otherUserId',
              ParamType.String,
            ),
            chatId: params.getParam(
              'chatId',
              ParamType.String,
            ),
            orderId: params.getParam(
              'orderId',
              ParamType.String,
            ),
            requestCancelOnOpen:
                params.getParam('requestCancelOnOpen', ParamType.bool) ==
                    true,
          ),
        ),
        FFRoute(
          name: 'PerfilVendedorCopy',
          path: '/perfilVendedorCopy',
          builder: (context, params) => PerfilVendedorWidget(
            sellerID: params.getParam(
              'sellerID',
              ParamType.String,
            ),
            initialTab: params.getParam(
                  'initialTab',
                  ParamType.String,
                ) ??
                'marketplace',
          ),
        ),
        FFRoute(
          name: ListaConversasWidget.routeName,
          path: ListaConversasWidget.routePath,
          builder: (context, params) => ListaConversasWidget(
            initialTab: params.getParam(
              'initialTab',
              ParamType.String,
            ),
            initialChatId: params.getParam('chatId', ParamType.String),
            initialOtherUserId:
                params.getParam('otherUserId', ParamType.String),
            initialOrderId: params.getParam('orderId', ParamType.String),
            requestCancelOnOpen:
                params.getParam('requestCancelOnOpen', ParamType.bool) ==
                    true,
          ),
        ),
        FFRoute(
          name: HubMessagesVisualCatalogPage.routeName,
          path: HubMessagesVisualCatalogPage.routePath,
          builder: (context, params) => HubMessagesVisualCatalogPage(
            familyId: params.getParam('family', ParamType.String),
          ),
        ),
        FFRoute(
          name: HubBagVisualCatalogPage.routeName,
          path: HubBagVisualCatalogPage.routePath,
          builder: (context, params) => const HubBagVisualCatalogPage(),
        ),
        FFRoute(
          name: HubCheckoutVisualCatalogPage.routeName,
          path: HubCheckoutVisualCatalogPage.routePath,
          builder: (context, params) => const HubCheckoutVisualCatalogPage(),
        ),
        FFRoute(
          name: HubMessagesDemoThreadPage.routeName,
          path: HubMessagesDemoThreadPage.routePath,
          builder: (context, params) => const HubMessagesDemoThreadPage(),
        ),
        FFRoute(
          name: PerfilWidget.routeName,
          path: PerfilWidget.routePath,
          builder: (context, params) => PerfilWidget(),
        ),
        FFRoute(
          name: ContaDefinicoesWidget.routeName,
          path: ContaDefinicoesWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.contaDefinicoes,
                )
              : const ContaDefinicoesWidget(),
        ),
        FFRoute(
          name: DescontosConjuntosWidget.routeName,
          path: DescontosConjuntosWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.descontos,
                )
              : const DescontosConjuntosWidget(),
        ),
        FFRoute(
          name: CriarConjuntoPageWidget.routeName,
          path: CriarConjuntoPageWidget.routePath,
          // Preview P13 isolada: ver UI desktop sem login.
          // App Android / build sem define mantém requireAuth (paridade).
          requireAuth: !const bool.fromEnvironment(
            'FLEABER_P13_OPEN_BUNDLE',
            defaultValue: false,
          ),
          builder: (context, params) => CriarConjuntoPageWidget(
            sellerId: params.getParam('sellerId', ParamType.String) ?? '',
            initialProductId: params.getParam(
              'initialProductId',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: JuntarAoPremioPageWidget.routeName,
          path: JuntarAoPremioPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => JuntarAoPremioPageWidget(
            sellerId: params.getParam('sellerId', ParamType.String) ?? '',
            chatId: params.getParam('chatId', ParamType.String) ?? '',
            prizeOrderId:
                params.getParam('prizeOrderId', ParamType.String) ?? '',
            prizeProductId: params.getParam(
              'prizeProductId',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: VerConjuntoPageWidget.routeName,
          path: VerConjuntoPageWidget.routePath,
          requireAuth: !const bool.fromEnvironment(
            'FLEABER_P13_OPEN_BUNDLE',
            defaultValue: false,
          ),
          builder: (context, params) => VerConjuntoPageWidget(
            sellerId: params.getParam('sellerId', ParamType.String) ?? '',
            productIdsCsv: params.getParam('productIds', ParamType.String) ?? '',
            initialQuantitiesCsv:
                params.getParam('quantities', ParamType.String),
          ),
        ),
        FFRoute(
          name: FavoritosPageWidget.routeName,
          path: FavoritosPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.favoritos,
                )
              : const FavoritosPageWidget(),
        ),
        FFRoute(
          name: LegalHubPageWidget.routeName,
          path: LegalHubPageWidget.routePath,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.infoLegal,
                )
              : const LegalHubPageWidget(),
        ),
        FFRoute(
          name: LegalDocumentPageWidget.routeName,
          path: LegalDocumentPageWidget.routePath,
          builder: (context, params) {
            final kind = params.getParam('kind', ParamType.String);
            if (kIsWeb) {
              final t = HubAccountRoutes.legalDocumentTarget(kind);
              return HubAccountRoutes.webLegacyRedirect(
                t.pane,
                legalDoc: t.doc,
              );
            }
            return LegalDocumentPageWidget.fromKind(kind);
          },
        ),
        FFRoute(
          name: MinhasEncomendasWidget.routeName,
          path: MinhasEncomendasWidget.routePath,
          requireAuth: true,
          builder: (context, params) {
            final orderId = params.getParam('orderId', ParamType.String);
            if (kIsWeb) {
              return HubAccountRoutes.webLegacyRedirect(
                PerfilDesktopPane.encomendas,
                orderId: orderId,
              );
            }
            return MinhasEncomendasWidget(initialOrderId: orderId);
          },
        ),
        FFRoute(
          name: WalletPageWidget.routeName,
          path: WalletPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.saldo,
                )
              : const WalletPageWidget(),
        ),
        FFRoute(
          name: ModoFeriasPageWidget.routeName,
          path: ModoFeriasPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.ferias,
                )
              : const ModoFeriasPageWidget(),
        ),
        FFRoute(
          name: GestaoReferenciasPageWidget.routeName,
          path: GestaoReferenciasPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.referencias,
                )
              : const GestaoReferenciasPageWidget(),
        ),
        FFRoute(
          name: SellerHelpersPageWidget.routeName,
          path: SellerHelpersPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.equipa,
                )
              : const SellerHelpersPageWidget(),
        ),
        FFRoute(
          name: HelperAccessPageWidget.routeName,
          path: HelperAccessPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => const HelperAccessPageWidget(),
        ),
        FFRoute(
          name: HelperInvitationPageWidget.routeName,
          path: HelperInvitationPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => HelperInvitationPageWidget(
            helperLinkId: params.getParam(
              'helperLinkId',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: MaestroShowCreateSheetPageWidget.routeName,
          path: MaestroShowCreateSheetPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) =>
              const MaestroShowCreateSheetPageWidget(),
        ),
        FFRoute(
          name: MaestroAutologinPageWidget.routeName,
          path: MaestroAutologinPageWidget.routePath,
          builder: (context, params) => MaestroAutologinPageWidget(
            email: params.getParam(
              'email',
              ParamType.String,
            ),
            password: params.getParam(
              'password',
              ParamType.String,
            ),
            next: params.getParam(
              'next',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: MaestroSellerStudioPageWidget.routeName,
          path: MaestroSellerStudioPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => MaestroSellerStudioPageWidget(
            liveId: params.getParam(
              'liveId',
              ParamType.String,
            ),
            opsSection: params.getParam(
              'opsSection',
              ParamType.String,
            ),
            expandCategory: params.getParam(
              'expandCategory',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: HelperLiveOpsPageWidget.routeName,
          path: HelperLiveOpsPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => HelperLiveOpsPageWidget(
            liveId: params.getParam(
              'liveId',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: LiveSalesSessionsPageWidget.routeName,
          path: LiveSalesSessionsPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => kIsWeb
              ? HubAccountRoutes.webLegacyRedirect(
                  PerfilDesktopPane.resultadosLive,
                )
              : const LiveSalesSessionsPageWidget(),
        ),
        FFRoute(
          name: LiveSalesSessionDetailPageWidget.routeName,
          path: LiveSalesSessionDetailPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) {
            final liveId = params.getParam('liveId', ParamType.String);
            if (kIsWeb && (liveId ?? '').trim().isNotEmpty) {
              return HubAccountRoutes.webLiveDetailRedirect(liveId!.trim());
            }
            return LiveSalesSessionDetailPageWidget(liveId: liveId);
          },
        ),
        FFRoute(
          name: AdminPageWidget.routeName,
          path: AdminPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => const AdminPageWidget(),
        ),
        FFRoute(
          name: AmazonImporterHubPage.routeName,
          path: AmazonImporterHubPage.routePath,
          requireAuth: true,
          builder: (context, params) => const AmazonImporterHubPage(),
        ),
        FFRoute(
          name: AmazonImporterImportPage.routeName,
          path: AmazonImporterImportPage.routePath,
          requireAuth: true,
          builder: (context, params) => const AmazonImporterImportPage(),
        ),
        FFRoute(
          name: AmazonImporterCatalogPage.routeName,
          path: AmazonImporterCatalogPage.routePath,
          requireAuth: true,
          builder: (context, params) => const AmazonImporterCatalogPage(),
        ),
        FFRoute(
          name: AmazonImporterProductPage.routeName,
          path: AmazonImporterProductPage.routePath,
          requireAuth: true,
          builder: (context, params) => AmazonImporterProductPage(
            productId: params.getParam('productId', ParamType.String) ?? '',
          ),
        ),
        FFRoute(
          name: AmazonImporterResearchPage.routeName,
          path: AmazonImporterResearchPage.routePath,
          requireAuth: true,
          builder: (context, params) => AmazonImporterResearchPage(
            lotId: params.getParam('lotId', ParamType.String),
          ),
        ),
        FFRoute(
          name: AmazonImporterReviewPage.routeName,
          path: AmazonImporterReviewPage.routePath,
          requireAuth: true,
          builder: (context, params) => const AmazonImporterReviewPage(),
        ),
        FFRoute(
          name: AmazonImporterScanPage.routeName,
          path: AmazonImporterScanPage.routePath,
          requireAuth: true,
          builder: (context, params) => AmazonImporterScanPage(
            initialCode: params.getParam('code', ParamType.String),
          ),
        ),
        FFRoute(
          name: AdminLiveDirectorPageWidget.routeName,
          path: AdminLiveDirectorPageWidget.routePath,
          requireAuth: true,
          builder: (context, params) => const AdminLiveDirectorPageWidget(),
        ),
        FFRoute(
          name: LivesWebDashboardWidget.routeName,
          path: LivesWebDashboardWidget.routePath,
          requireAuth: true,
          builder: (context, params) => const LivesWebDashboardWidget(),
        ),
        FFRoute(
          name: SellerProductFormWidget.routeName,
          path: SellerProductFormWidget.routePath,
          requireAuth: true,
          builder: (context, params) => SellerProductFormWidget(
            editProductId: params.getParam(
              'editProductId',
              ParamType.String,
            ),
          ),
        ),
        FFRoute(
          name: ProductDetailsPageWidget.routeName,
          path: ProductDetailsPageWidget.routePath,
          builder: (context, params) {
            // Não usar GoRouterState.of(context) aqui: ao fazer push o context do
            // builder pode não ter rota modal e dispara GoError.
            // URL: #/productDetails?product_id=…&openCheckout=true|1 abre o sheet.
            final openCheckoutRaw = params.getParam(
                  'openCheckout',
                  ParamType.String,
                ) ??
                '';
            final openCheckoutQuery = openCheckoutRaw.toLowerCase() == 'true' ||
                openCheckoutRaw == '1' ||
                params.getParam('openCheckout', ParamType.bool) == true;
            return ProductDetailsPageWidget(
              product: ProductDetailsPageWidget.productFromRouteExtra(
                params.state.extra,
              ),
              productId: params.getParam(
                'product_id',
                ParamType.String,
              ) ??
                  params.getParam(
                    'productId',
                    ParamType.String,
                  ),
              openCheckoutSheetOnLoad: openCheckoutQuery ||
                  ProductDetailsPageWidget.openCheckoutFromRouteExtra(
                    params.state.extra,
                  ),
              agreedOfferPriceEur:
                  ProductDetailsPageWidget.agreedOfferPriceFromRouteExtra(
                params.state.extra,
              ),
              originLiveId: ProductDetailsPageWidget.originLiveIdFromRouteExtra(
                params.state.extra,
              ),
              originPlaybackId:
                  ProductDetailsPageWidget.originPlaybackIdFromRouteExtra(
                params.state.extra,
              ),
              originIsLive:
                  ProductDetailsPageWidget.originIsLiveFromRouteExtra(
                params.state.extra,
              ),
              originSellerId:
                  ProductDetailsPageWidget.originSellerIdFromRouteExtra(
                params.state.extra,
              ),
              originLiveItemId:
                  ProductDetailsPageWidget.originLiveItemIdFromRouteExtra(
                params.state.extra,
              ),
              originReservationRequestId:
                  ProductDetailsPageWidget
                      .originReservationRequestIdFromRouteExtra(
                params.state.extra,
              ),
              originPayQty: ProductDetailsPageWidget.originPayQtyFromRouteExtra(
                params.state.extra,
              ),
            );
          },
        ),
      ].map((r) => r.toRoute(appStateNotifier)).toList()
        ..addAll(buildHubGoRoutes().whereType<GoRoute>()),
      observers: [routeObserver],
    );

class _OAuthCallbackResolver extends StatefulWidget {
  const _OAuthCallbackResolver({required this.uri});

  final Uri uri;

  @override
  State<_OAuthCallbackResolver> createState() => _OAuthCallbackResolverState();
}

class _OAuthCallbackResolverState extends State<_OAuthCallbackResolver> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_resolve()));
  }

  Future<void> _resolve() async {
    if (!mounted) return;

    final uri = widget.uri;
    var isRecovery = FleaberOAuthRedirect.isPasswordRecoveryUri(uri);
    final tokenHash = (uri.queryParameters['token_hash'] ??
            uri.queryParameters['tokenHash'] ??
            '')
        .trim();
    final hasAuthParams = uri.queryParameters.containsKey('code') ||
        uri.fragment.contains('access_token');

    if (tokenHash.isNotEmpty) {
      try {
        await SupaFlow.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: OtpType.recovery,
        );
        await authManager.refreshUser();
        isRecovery = true;
        FleaberPasswordRecovery.markPending();
      } on AuthException catch (e) {
        lastFacebookLoginFailureMessage = e.message;
      } catch (_) {}
    } else if (hasAuthParams) {
      try {
        final response = await SupaFlow.client.auth.getSessionFromUrl(uri);
        await authManager.refreshUser();
        final redirectType = response.redirectType?.trim() ?? '';
        if (redirectType == AuthChangeEvent.passwordRecovery.name ||
            redirectType == 'passwordRecovery') {
          isRecovery = true;
        }
      } on AuthException catch (e) {
        lastFacebookLoginFailureMessage = 'Erro no Facebook: ${e.message}';
      } catch (_) {
        // SupabaseAuth pode já ter processado o mesmo deep link (detectSessionInUri).
      }
    }

    for (var i = 0; i < 40; i++) {
      if (!mounted) return;
      if (currentUserUid.isNotEmpty) {
        final appState = AppStateNotifier.instance;
        appState.updateNotifyOnAuthChange(true);
        await authManager.refreshUser();
        if (!mounted) return;

        if (isRecovery && !FleaberPasswordRecovery.completed) {
          appState.clearRedirectLocation();
          context.goNamed(NovaSenhaWidget.routeName);
          return;
        }

        final returnTo = uri.queryParameters['returnTo']?.trim() ??
            uri.queryParameters[FleaberOAuthRedirect.returnToQueryKey]?.trim() ??
            (appState.hasRedirect() ? appState.getRedirectLocation() : null);

        if (returnTo != null && returnTo.trim().isNotEmpty) {
          if (HubActions.isFleaHubReturnPath(returnTo)) {
            await HubActions.finishAuthWithHubWelcome(
              context,
              returnTo: returnTo.trim(),
            );
            return;
          }
          appState.clearRedirectLocation();
          context.go(returnTo.trim());
          return;
        }

        appState.clearRedirectLocation();
        HubNavigation.goAppHome(context);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (!mounted) return;
    context.goNamed(LoginWidget.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Redireciona `/homePage` → `/fleahub` no deploy web (consolidação H01+).
class _WebRedirectToFleahubLanding extends StatefulWidget {
  const _WebRedirectToFleahubLanding();

  @override
  State<_WebRedirectToFleahubLanding> createState() =>
      _WebRedirectToFleahubLandingState();
}

class _WebRedirectToFleahubLandingState
    extends State<_WebRedirectToFleahubLanding> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(HubRoutePaths.landing);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF007782))),
    );
  }
}

class _StripeReturnResolver extends StatefulWidget {
  const _StripeReturnResolver({
    required this.sessionId,
    required this.orderId,
    required this.productId,
    required this.liveId,
    required this.playbackId,
    required this.isLive,
    required this.sellerId,
  });

  final String? sessionId;
  final String? orderId;
  final String? productId;
  final String? liveId;
  final String? playbackId;
  final bool? isLive;
  final String? sellerId;

  @override
  State<_StripeReturnResolver> createState() => _StripeReturnResolverState();
}

class _StripeReturnResolverState extends State<_StripeReturnResolver> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    if (!mounted) return;
    final nav = GoRouter.of(context);

    // E85.3: após redirect index.html→/fleahub/# a sessão Auth pode
    // ainda estar a restaurar; sem UID o chat H10 não abre.
    for (var i = 0; i < 20 && currentUserUid.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }

    final saved = await FleaberStripeCheckoutContext.peek();
    final sessionId = widget.sessionId?.trim() ?? '';
    if (sessionId.isNotEmpty) {
      await FleaberStripeCheckoutContext.settleCheckoutSession(sessionId);
      await FleaberStripeTipContext.settleTipStripeSession(sessionId);
    }

    var liveId = widget.liveId?.trim() ?? '';
    var playbackId = widget.playbackId?.trim() ?? '';
    var isLive = widget.isLive;
    var sellerId = widget.sellerId?.trim() ?? '';
    var orderId = widget.orderId?.trim() ?? '';
    var productId = widget.productId?.trim() ?? '';

    if (saved != null) {
      liveId = liveId.isNotEmpty
          ? liveId
          : (saved['live_id']?.toString().trim() ?? '');
      playbackId = playbackId.isNotEmpty
          ? playbackId
          : (saved['playback_id']?.toString().trim() ?? '');
      sellerId = sellerId.isNotEmpty
          ? sellerId
          : (saved['seller_id']?.toString().trim() ?? '');
      orderId = orderId.isNotEmpty
          ? orderId
          : (saved['order_id']?.toString().trim() ?? '');
      productId = productId.isNotEmpty
          ? productId
          : (saved['product_id']?.toString().trim() ?? '');
      final savedLive = saved['is_live'];
      if (isLive == null) {
        if (savedLive is bool) {
          isLive = savedLive;
        } else if (savedLive is String) {
          isLive = savedLive == 'true';
        }
      }
      if (sessionId.isEmpty) {
        final savedSession =
            saved['checkout_session_id']?.toString().trim() ?? '';
        if (savedSession.isNotEmpty) {
          await FleaberStripeCheckoutContext.settleCheckoutSession(savedSession);
        }
      }
    }

    if (orderId.isNotEmpty) {
      final status = await FleaberStripeCheckoutContext.orderStatus(orderId);
      if (status == 'pago') {
        final bagJson = saved?['bag_orders_json']?.toString().trim() ?? '';
        if (bagJson.isNotEmpty) {
          await FleaberStripeCheckoutContext.reconcilePendingBagOrders(
            saved!,
            liveId: liveId,
          );
        } else {
          final reconcile =
              await LiveReservationQueueService().reconcileStripePaidOrder(
            orderId: orderId,
            reservationRequestId:
                saved?['reservation_request_id']?.toString(),
          );
          await FleaberLogger.instance.logStripe(
            'reconcile',
            data: {
              'order_id': orderId,
              'live_id': liveId,
              'result': reconcile,
            },
          );
        }
        if (liveId.isNotEmpty) {
          try {
            await SupaFlow.client.rpc(
              'batata_sync_live_item_for_order',
              params: {'p_order_id': orderId},
            );
          } catch (_) {}
        }
        await FleaberStripeCheckoutContext.loadAndClear();
      }
    }

    final tipCtx = await FleaberStripeTipContext.peek();
    if (tipCtx != null) {
      final tipId = tipCtx['tip_id']?.toString().trim() ?? '';
      if (tipId.isNotEmpty) {
        final tipStatus = await FleaberStripeTipContext.tipStatus(tipId);
        if (FleaberStripeTipContext.isTipSettled(tipStatus)) {
          await FleaberStripeTipContext.clear();
        }
      }
      if (liveId.isEmpty) {
        liveId = tipCtx['live_id']?.toString().trim() ?? '';
      }
      if (playbackId.isEmpty) {
        playbackId = tipCtx['playback_id']?.toString().trim() ?? '';
      }
      if (sellerId.isEmpty) {
        sellerId = tipCtx['seller_id']?.toString().trim() ?? '';
      }
      if (isLive == null) {
        isLive = tipCtx['is_live'] == true || tipCtx['is_live'] == 'true';
      }
    }

    FleaberLogger.instance.info(
      'stripe.return',
      'resolver liveId=${liveId.isEmpty ? "—" : liveId} orderId=${orderId.isEmpty ? "—" : orderId}',
    );

    // Compra no directo: voltar à página do directo (não chat/home).
    if (liveId.isNotEmpty && mounted) {
      FleaberStripeCheckoutContext.goToLivePlayer(nav, {
        'live_id': liveId,
        'playback_id': playbackId,
        'seller_id': sellerId,
        'is_live': isLive,
      });
      return;
    }

    if (orderId.isNotEmpty) {
      try {
        final rows = await OrdersTable().querySingleRow(
          queryFn: (q) => q.eqOrNull('id', orderId),
        );
        if (rows.isNotEmpty) {
          final order = rows.first;
          productId = order.productId ?? productId;
          final me = currentUserUid;
          final other = order.buyerId == me ? order.sellerId : order.buyerId;
          if (other != null && other.isNotEmpty) {
            // CHAT-MULTI: abrir o chat DESTA encomenda (com «Comprado!»),
            // nunca ensureSellerChat(preferNewest) que caía na thread antiga.
            String? chatId = await ensureSeguroFleaberPaidSaleChat(
              orderId: orderId,
              sellerId: order.sellerId,
              productId: productId,
            );
            chatId ??= (await findChatForOrderId(orderId))?.id;
            if (chatId == null || chatId.isEmpty) {
              chatId = (await ensureSellerChat(
                otherUserId: other,
                productId: productId,
                forceNew: true,
              ))
                  .id;
            }
            // Só abrir chat se a encomenda estiver paga no backend
            // (não basta o browser ter regressado do Stripe).
            // orderStatus já devolve chave normalizada (ex. «pago»).
            final paidStatus =
                await FleaberStripeCheckoutContext.orderStatus(orderId);
            final isPaid = paidStatus == 'pago';
            await FleaberLogger.instance.logStripe(
              'chat_multi_stripe_return_nav',
              data: {
                'order_id': orderId,
                'product_id': productId,
                'nav_chat_id': chatId,
                'order_status': paidStatus,
                'is_paid': isPaid,
              },
            );
            if (!isPaid) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'O pagamento ainda não está confirmado. '
                      'Se já pagaste, espera uns segundos e abre Mensagens.',
                    ),
                    duration: Duration(seconds: 6),
                  ),
                );
                HubNavigation.goAppHome(context);
              }
              return;
            }
            if (chatId != null && chatId.isNotEmpty && mounted) {
              // H10: desktop → ListaConversas split; mobile → ChatPage.
              await openH10Conversation(
                context,
                otherUserId: other,
                chatId: chatId,
                orderId: orderId,
                productId: productId.isEmpty ? null : productId,
              );
              return;
            }
          }
        }
      } catch (_) {}
    }

    if (productId.isNotEmpty && mounted) {
      nav.goNamed(
        ProductDetailsPageWidget.routeName,
        queryParameters: <String, String?>{
          'product_id': serializeParam(productId, ParamType.String),
        }.withoutNulls,
      );
      return;
    }

    if (mounted) {
      HubNavigation.goAppHome(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

extension NavParamExtensions on Map<String, String?> {
  Map<String, String> get withoutNulls => Map.fromEntries(
        entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );
}

extension NavigationExtensions on BuildContext {
  void goNamedAuth(
    String name,
    bool mounted, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    Object? extra,
    bool ignoreRedirect = false,
  }) =>
      !mounted || GoRouter.of(this).shouldRedirect(ignoreRedirect)
          ? null
          : goNamed(
              name,
              pathParameters: pathParameters,
              queryParameters: queryParameters,
              extra: extra,
            );

  void pushNamedAuth(
    String name,
    bool mounted, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String> queryParameters = const <String, String>{},
    Object? extra,
    bool ignoreRedirect = false,
  }) =>
      !mounted || GoRouter.of(this).shouldRedirect(ignoreRedirect)
          ? null
          : pushNamed(
              name,
              pathParameters: pathParameters,
              queryParameters: queryParameters,
              extra: extra,
            );

  void safePop() {
    final router = GoRouter.of(this);
    Navigator.maybePop(this).then((didPop) {
      if (!didPop) {
        router.go('/');
      }
    });
  }
}

extension GoRouterExtensions on GoRouter {
  AppStateNotifier get appState => AppStateNotifier.instance;
  void prepareAuthEvent([bool ignoreRedirect = false]) =>
      appState.hasRedirect() && !ignoreRedirect
          ? null
          : appState.updateNotifyOnAuthChange(false);
  bool shouldRedirect(bool ignoreRedirect) =>
      !ignoreRedirect && appState.hasRedirect();
  void clearRedirectLocation() => appState.clearRedirectLocation();
  void setRedirectLocationIfUnset(String location) =>
      appState.updateNotifyOnAuthChange(false);
}

extension _GoRouterStateExtensions on GoRouterState {
  /// Só trata [extra] como mapa de parâmetros quando for de facto um [Map].
  /// Objetos não‑mapa (ex.: instâncias de row) ignoram‑se aqui — preferir mapa em `extra` na navegação.
  Map<String, dynamic> get extraMap {
    final e = extra;
    if (e == null) return {};
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return Map<String, dynamic>.from(e);
    return {};
  }
  Map<String, dynamic> get allParams => <String, dynamic>{}
    ..addAll(pathParameters)
    ..addAll(uri.queryParameters)
    ..addAll(extraMap);
  TransitionInfo get transitionInfo => extraMap.containsKey(kTransitionInfoKey)
      ? extraMap[kTransitionInfoKey] as TransitionInfo
      : TransitionInfo.appDefault();
}

class FFParameters {
  FFParameters(this.state, [this.asyncParams = const {}]);

  final GoRouterState state;
  final Map<String, Future<dynamic> Function(String)> asyncParams;

  Map<String, dynamic> futureParamValues = {};

  // Parameters are empty if the params map is empty or if the only parameter
  // present is the special extra parameter reserved for the transition info.
  bool get isEmpty =>
      state.allParams.isEmpty ||
      (state.allParams.length == 1 &&
          state.extraMap.containsKey(kTransitionInfoKey));
  bool isAsyncParam(MapEntry<String, dynamic> param) =>
      asyncParams.containsKey(param.key) && param.value is String;
  bool get hasFutures => state.allParams.entries.any(isAsyncParam);
  Future<bool> completeFutures() => Future.wait(
        state.allParams.entries.where(isAsyncParam).map(
          (param) async {
            final doc = await asyncParams[param.key]!(param.value)
                .onError((_, __) => null);
            if (doc != null) {
              futureParamValues[param.key] = doc;
              return true;
            }
            return false;
          },
        ),
      ).onError((_, __) => [false]).then((v) => v.every((e) => e));

  dynamic getParam<T>(
    String paramName,
    ParamType type, {
    bool isList = false,
  }) {
    if (futureParamValues.containsKey(paramName)) {
      return futureParamValues[paramName];
    }
    if (!state.allParams.containsKey(paramName)) {
      return null;
    }
    final param = state.allParams[paramName];
    // Got parameter from `extras`, so just directly return it.
    if (param is! String) {
      return param;
    }
    // Return serialized value.
    return deserializeParam<T>(
      param,
      type,
      isList,
    );
  }
}

class FFRoute {
  const FFRoute({
    required this.name,
    required this.path,
    required this.builder,
    this.requireAuth = false,
    this.asyncParams = const {},
    this.routes = const [],
  });

  final String name;
  final String path;
  final bool requireAuth;
  final Map<String, Future<dynamic> Function(String)> asyncParams;
  final Widget Function(BuildContext, FFParameters) builder;
  final List<GoRoute> routes;

  GoRoute toRoute(AppStateNotifier appStateNotifier) => GoRoute(
        name: name,
        path: path,
        redirect: (context, state) {
          if (appStateNotifier.shouldRedirect) {
            final redirectLocation = appStateNotifier.getRedirectLocation();
            appStateNotifier.clearRedirectLocation();
            return redirectLocation;
          }

          if (requireAuth && !appStateNotifier.loggedIn) {
            appStateNotifier.setRedirectLocationIfUnset(state.uri.toString());
            return '/login';
          }
          return null;
        },
        pageBuilder: (context, state) {
          fixStatusBarOniOS16AndBelow(context);
          final ffParams = FFParameters(state, asyncParams);
          final page = ffParams.hasFutures
              ? FutureBuilder(
                  future: ffParams.completeFutures(),
                  builder: (context, _) => builder(context, ffParams),
                )
              : builder(context, ffParams);
          final child = appStateNotifier.loading
              ? Center(
                  child: Text(
                    'Fleaber',
                    style: FlutterFlowTheme.of(context).headlineLarge.override(
                          color: const Color(0xFF007782),
                          fontSize: 32.0,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                )
              : page;

          final transitionInfo = state.transitionInfo;
          return transitionInfo.hasTransition
              ? CustomTransitionPage(
                  key: state.pageKey,
                  name: state.name,
                  child: child,
                  transitionDuration: transitionInfo.duration,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          PageTransition(
                    type: transitionInfo.transitionType,
                    duration: transitionInfo.duration,
                    reverseDuration: transitionInfo.duration,
                    alignment: transitionInfo.alignment,
                    child: child,
                  ).buildTransitions(
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ),
                )
              : MaterialPage(
                  key: state.pageKey, name: state.name, child: child);
        },
        routes: routes,
      );
}

class TransitionInfo {
  const TransitionInfo({
    required this.hasTransition,
    this.transitionType = PageTransitionType.fade,
    this.duration = const Duration(milliseconds: 300),
    this.alignment,
  });

  final bool hasTransition;
  final PageTransitionType transitionType;
  final Duration duration;
  final Alignment? alignment;

  static TransitionInfo appDefault() => TransitionInfo(hasTransition: false);
}

class RootPageContext {
  const RootPageContext(this.isRootPage, [this.errorRoute]);
  final bool isRootPage;
  final String? errorRoute;

  static bool isInactiveRootPage(BuildContext context) {
    final rootPageContext = context.read<RootPageContext?>();
    final isRootPage = rootPageContext?.isRootPage ?? false;
    final location = GoRouterState.of(context).uri.toString();
    return isRootPage &&
        location != '/' &&
        location != rootPageContext?.errorRoute;
  }

  static Widget wrap(Widget child, {String? errorRoute}) => Provider.value(
        value: RootPageContext(true, errorRoute),
        child: child,
      );
}

extension GoRouterLocationExtension on GoRouter {
  String getCurrentLocation() {
    final RouteMatch lastMatch = routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }
}

String? _firstQueryParam(FFParameters params, List<String> keys) {
  final qp = params.state.uri.queryParameters;
  for (final k in keys) {
    final raw = qp[k];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
  }
  for (final k in keys) {
    final v = params.getParam(k, ParamType.String);
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim();
    }
  }
  return null;
}
