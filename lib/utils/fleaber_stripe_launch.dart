import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_web_deploy.dart';
import '/utils/fleaber_web_nav.dart';

/// Base para `web_return_origin` (edge redireciona para `{base}/stripe-success?…`).
///
/// Em deploy `/fleahub/` o origin sozinho (`https://fleaber.pt`) aponta para fora
/// da SPA — o regresso após Stripe 404. Hash vs path conforme [FleaberWebDeploy].
String? fleaberWebStripeReturnOrigin() {
  if (!kIsWeb) return null;
  final base = Uri.base;
  final origin = base.origin.trim();
  if (origin.isEmpty) return null;

  final underFleahub = base.path.contains('/fleahub');
  final useHash = FleaberWebDeploy.useHashUrlOnWeb ||
      (underFleahub && base.fragment.isNotEmpty);

  if (useHash) {
    if (underFleahub) {
      // E85.3: NÃO usar index.html# — o regresso Stripe ficava em
      // #/stripe-success sem resolver (URL que o comprador via a falhar).
      // Forma estável comprovada: /fleahub/#/stripe-success?…
      return '$origin/fleahub/#';
    }
    return '$origin/#';
  }
  if (underFleahub) {
    return '$origin/fleahub';
  }
  return origin;
}

/// Campos a juntar ao body de `create-payment-intent` / tip no Chrome Hub.
Map<String, dynamic> fleaberStripeWebReturnFields() {
  final origin = fleaberWebStripeReturnOrigin();
  if (origin == null || origin.isEmpty) return const {};
  return {'web_return_origin': origin};
}

/// Abre o Checkout Stripe de forma fiável em web e mobile.
///
/// No Flutter web, `LaunchMode.inAppBrowserView` não existe. Abrir `_blank`
/// **depois** de `await` create-payment-intent é bloqueado pelo popup blocker
/// do Chrome (APP-SEC-005) — o `launchUrl` pode até devolver `true` sem abrir.
/// Por isso na web usamos o **mesmo separador** (`_self`).
///
/// Em mobile, gorjetas usam [preferExternalBrowser] (browser do sistema) —
/// mais fiável que in-app em alguns Android (APP-SEC-034-B).
Future<bool> fleaberLaunchStripeCheckout(
  String checkoutUrl, {
  Map<String, dynamic>? context,
  bool preferExternalBrowser = false,
}) async {
  final uri = Uri.parse(checkoutUrl.trim());
  final modeLabel = kIsWeb
      ? 'web_same_tab'
      : (preferExternalBrowser
          ? 'mobile_external_browser'
          : 'mobile_in_app_browser');
  await FleaberLogger.instance.logStripe(
    'launch_attempt',
    data: {
      'k_is_web': kIsWeb,
      'mode': modeLabel,
      'prefer_external': preferExternalBrowser,
      'url_host': uri.host,
      'web_return_origin': fleaberWebStripeReturnOrigin(),
      'url_path_prefix': uri.path.length > 24
          ? uri.path.substring(0, 24)
          : uri.path,
      if (context != null) ...context,
    },
  );

  try {
    var opened = false;
    var usedMode = modeLabel;
    if (kIsWeb) {
      // Preferir location.assign — launchUrl(_self) no Flutter web do Hub
      // devolve true sem navegar (popup/sandbox), e o Pagar fica a girar.
      try {
        fleaberWebAssignUrl(uri.toString());
        opened = true;
        usedMode = 'web_location_assign';
      } catch (_) {
        opened = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );
      }
    } else if (preferExternalBrowser) {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      try {
        opened = await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView,
          webViewConfiguration: const WebViewConfiguration(
            enableDomStorage: true,
          ),
        );
      } catch (_) {
        opened = false;
      }
      if (!opened) {
        usedMode = 'mobile_external_browser_fallback';
        opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    }
    await FleaberLogger.instance.logStripe(
      'launch_result',
      data: {
        'opened': opened,
        'mode': usedMode,
        if (context != null) ...context,
      },
    );
    return opened;
  } catch (e, st) {
    await FleaberLogger.instance.logStripe(
      'launch_error',
      data: {
        'mode': modeLabel,
        if (context != null) ...context,
      },
      error: e,
      stackTrace: st,
    );
    rethrow;
  }
}

/// Invoca `create-payment-intent` com logs em `stripe_checkout_events` /
/// `app_logs` em cada passo (para auditar FAIL Chrome sem print).
Future<({String checkoutUrl, String? checkoutSessionId})>
    fleaberInvokeCreatePaymentIntent({
  required Map<String, dynamic> body,
  Map<String, dynamic>? logContext,
}) async {
  final ctx = <String, dynamic>{
    if (logContext != null) ...logContext,
    'order_id': body['order_id']?.toString(),
    'product_id': body['product_id']?.toString(),
    'amount': body['amount'],
    'k_is_web': kIsWeb,
    'web_return_origin': fleaberWebStripeReturnOrigin(),
    'has_web_return_origin': body.containsKey('web_return_origin') ||
        fleaberWebStripeReturnOrigin() != null,
  };

  await FleaberLogger.instance.logStripe('invoke_start', data: ctx);

  Future<({String checkoutUrl, String? checkoutSessionId})> once({
    required int attempt,
  }) async {
    final response = await SupaFlow.client.functions.invoke(
      'create-payment-intent',
      body: {
        ...body,
        ...fleaberStripeWebReturnFields(),
      },
    );

    final data = response.data;
    final status = response.status;
    final checkoutUrl =
        data is Map ? data['checkoutUrl']?.toString() : null;
    final checkoutSessionId =
        data is Map ? data['checkoutSessionId']?.toString() : null;
    final error = data is Map ? data['error']?.toString() : null;

    await FleaberLogger.instance.logStripe(
      'invoke_done',
      data: {
        ...ctx,
        'attempt': attempt,
        'http_status': status,
        'has_checkout_url':
            checkoutUrl != null && checkoutUrl.trim().isNotEmpty,
        'session_id': checkoutSessionId,
        if (error != null && error.isNotEmpty) 'edge_error': error,
      },
    );

    if (status >= 400) {
      throw Exception(
        error == null || error.isEmpty
            ? 'Checkout Stripe falhou ($status).'
            : 'Stripe: $error',
      );
    }
    if (checkoutUrl == null || checkoutUrl.trim().isEmpty) {
      throw Exception(
        error == null || error.isEmpty
            ? 'A função Stripe não devolveu link de checkout.'
            : 'Stripe: $error',
      );
    }

    return (
      checkoutUrl: checkoutUrl.trim(),
      checkoutSessionId: checkoutSessionId,
    );
  }

  try {
    return await once(attempt: 1);
  } catch (e, st) {
    final msg = e.toString();
    final transient = msg.contains('Failed to fetch') ||
        msg.contains('ClientException') ||
        msg.contains('NetworkError') ||
        msg.contains('XMLHttpRequest');
    await FleaberLogger.instance.logStripe(
      'invoke_error',
      data: {
        ...ctx,
        'attempt': 1,
        'transient': transient,
      },
      error: e,
      stackTrace: st,
    );
    if (!transient) rethrow;
    await FleaberLogger.instance.logStripe(
      'invoke_retry',
      data: {...ctx, 'attempt': 2},
    );
    try {
      return await once(attempt: 2);
    } catch (e2, st2) {
      await FleaberLogger.instance.logStripe(
        'invoke_error',
        data: {...ctx, 'attempt': 2, 'after_retry': true},
        error: e2,
        stackTrace: st2,
      );
      throw Exception(
        'Não foi possível contactar o pagamento (rede/CORS). '
        'Atualiza a página (Ctrl+F5) e tenta de novo. Detalhe: $e2',
      );
    }
  }
}

/// Invoca `create-live-tip-checkout` com logs (APP-SEC-034-B).
Future<({String checkoutUrl, String? tipId, String? checkoutSessionId})>
    fleaberInvokeCreateLiveTipCheckout({
  required Map<String, dynamic> body,
  Map<String, dynamic>? logContext,
}) async {
  final ctx = <String, dynamic>{
    if (logContext != null) ...logContext,
    'source': logContext?['source'] ?? 'live_tip',
    'live_id': body['live_id']?.toString(),
    'seller_id': body['seller_id']?.toString(),
    'amount_eur': body['amount_eur'],
    'k_is_web': kIsWeb,
    'web_return_origin': fleaberWebStripeReturnOrigin(),
    'has_web_return_origin': body.containsKey('web_return_origin') ||
        fleaberWebStripeReturnOrigin() != null,
  };

  await FleaberLogger.instance.logStripe('tip_invoke_start', data: ctx);

  try {
    final response = await SupaFlow.client.functions.invoke(
      'create-live-tip-checkout',
      body: {
        ...body,
        ...fleaberStripeWebReturnFields(),
      },
    );

    final data = response.data;
    final status = response.status;
    final checkoutUrl =
        data is Map ? data['checkoutUrl']?.toString() : null;
    final tipId = data is Map ? data['tipId']?.toString() : null;
    final checkoutSessionId =
        data is Map ? data['checkoutSessionId']?.toString() : null;
    final error = data is Map ? data['error']?.toString() : null;

    await FleaberLogger.instance.logStripe(
      'tip_invoke_done',
      data: {
        ...ctx,
        'http_status': status,
        'has_checkout_url':
            checkoutUrl != null && checkoutUrl.trim().isNotEmpty,
        'tip_id': tipId,
        'session_id': checkoutSessionId,
        if (error != null && error.isNotEmpty) 'edge_error': error,
      },
    );

    if (status >= 400) {
      throw Exception(
        error == null || error.isEmpty
            ? 'Não foi possível iniciar o pagamento da gorjeta ($status).'
            : error,
      );
    }
    if (checkoutUrl == null || checkoutUrl.trim().isEmpty) {
      throw Exception(
        error == null || error.isEmpty
            ? 'Não foi possível iniciar o pagamento da gorjeta.'
            : error,
      );
    }

    return (
      checkoutUrl: checkoutUrl.trim(),
      tipId: tipId,
      checkoutSessionId: checkoutSessionId,
    );
  } catch (e, st) {
    await FleaberLogger.instance.logStripe(
      'tip_invoke_error',
      data: ctx,
      error: e,
      stackTrace: st,
    );
    rethrow;
  }
}
