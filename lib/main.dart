import 'dart:async';

import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'auth/supabase_auth/supabase_user_provider.dart';
import 'auth/supabase_auth/auth_util.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_deep_link_service.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_tip_context.dart';
import '/utils/fleaber_user_notification_hub.dart';
import '/utils/seller_staff_service.dart';
import '/utils/live_publish_cleanup.dart';
import 'flutter_flow/flutter_flow_util.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FleaberLogger.install();

      GoRouter.optionURLReflectsImperativeAPIs = true;
      usePathUrlStrategy();

      await SupaFlow.initialize();
      FleaberLogger.markSupabaseReady();

      await FlutterFlowTheme.initialize();

      final appState = FFAppState();
      await appState.initializePersistedState();

      runApp(ChangeNotifierProvider(
        create: (context) => appState,
        child: MyApp(),
      ));
    },
    FleaberLogger.instance.recordZoneError,
  );
}

class MyApp extends StatefulWidget {
  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class MyAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // BATATA: a UI da app foi desenhada para tema claro. Forçar light evita
  // diferenças de contraste entre Android físico em dark mode e emulador.
  ThemeMode _themeMode = ThemeMode.light;

  late AppStateNotifier _appStateNotifier;
  late GoRouter _router;
  String getRoute([RouteMatch? routeMatch]) {
    final RouteMatch lastMatch =
        routeMatch ?? _router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : _router.routerDelegate.currentConfiguration;
    return matchList.uri.path;
  }

  List<String> getRouteStack() =>
      _router.routerDelegate.currentConfiguration.matches
          .map((e) => getRoute(e))
          .toList();
  late Stream<BaseAuthUser> userStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // App mobile 9:16 — evita landscape em OEMs (TCL/MTK) quando o vídeo não traz rotação.
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );

    _appStateNotifier = AppStateNotifier.instance;
    _router = createRouter(_appStateNotifier);
    unawaited(FleaberDeepLinkService.init(_router));
    FleaberLogger.instance.routeProvider = () {
      try {
        return getRoute();
      } catch (_) {
        return '/';
      }
    };
    userStream = fleaberSupabaseUserStream()
      ..listen((user) {
        _appStateNotifier.update(user);
        if (user.loggedIn) {
          FleaberUserNotificationHub.instance.syncSubscription();
          unawaited(SellerStaffContext.instance.refresh());
          unawaited(LivePublishCleanup.reconcileOnAppStart(fullSweep: true));
        } else {
          FleaberUserNotificationHub.instance.detach();
          SellerStaffContext.instance.switchToOwnStore();
        }
      });
    FleaberUserNotificationHub.instance.syncSubscription();
    jwtTokenStream.listen((_) {});
    Future.delayed(
      Duration(milliseconds: 1000),
      () => _appStateNotifier.stopShowingSplashImage(),
    );
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        _themeMode = ThemeMode.light;
        FlutterFlowTheme.saveThemeMode(ThemeMode.light);
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FleaberDeepLinkService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(FleaberStripeCheckoutContext.tryResumeOnAppResumed(_router));
      unawaited(FleaberStripeTipContext.tryResumeOnAppResumed(_router));
      unawaited(LivePublishCleanup.reconcileOnAppStart(fullSweep: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Fleaber',
      scrollBehavior: MyAppScrollBehavior(),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
        scaffoldBackgroundColor: FleaberColors.bgTint,
        colorScheme: FleaberColors.lightColorScheme,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
        scaffoldBackgroundColor: FleaberColors.bgTint,
        colorScheme: FleaberColors.lightColorScheme,
      ),
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
