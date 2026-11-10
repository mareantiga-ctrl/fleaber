import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/nav/nav.dart';
import '/hub/hub_account_routes.dart';
import '/lista_conversas_widget.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_notifications_inbox.dart';

/// Push Android via FCM. No-op se Firebase não inicializar (sem `google-services.json`).
///
/// O Supabase continua a ser a fonte de verdade (`user_notifications`).
/// FCM só entrega; deep link usa `notification_id` / `chat_id` / `kind`.
abstract final class FleaberFcmService {
  FleaberFcmService._();

  static const _pushUi = MethodChannel('pt.fleaber.app/push_ui');

  static bool _started = false;
  static String? _token;
  static bool _firebaseReady = false;

  static bool get isAndroidPhone =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start() async {
    if (_started || !isAndroidPhone) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
    } catch (e) {
      debugPrint('FleaberFcmService: Firebase init skip ($e)');
      return;
    }

    try {
      await _pushUi.invokeMethod('ensureChannel');
    } catch (_) {}

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission();
    } catch (_) {}
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      unawaited(registerCurrentToken());
    });
    try {
      _token = await messaging.getToken();
      unawaited(registerCurrentToken());
    } catch (_) {}

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      notificationBadgeRefreshTick.value++;
      unawaited(_showForegroundLocal(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

    _pushUi.setMethodCallHandler((call) async {
      if (call.method == 'onPushTap') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        unawaited(
          _openFromData(
            chatId: (args['chat_id'] ?? '').toString(),
            kind: (args['kind'] ?? '').toString(),
            notificationId: (args['notification_id'] ?? '').toString(),
          ),
        );
      }
      return null;
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromMessage(initial);
      });
    } else {
      try {
        final launch = await _pushUi.invokeMethod<Map>('consumeLaunchPush');
        if (launch != null) {
          final chat = (launch['chat_id'] ?? '').toString();
          final kind = (launch['kind'] ?? '').toString();
          final nid = (launch['notification_id'] ?? '').toString();
          if (chat.isNotEmpty || kind.isNotEmpty || nid.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(
                _openFromData(
                  chatId: chat,
                  kind: kind,
                  notificationId: nid,
                ),
              );
            });
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> _showForegroundLocal(RemoteMessage message) async {
    final n = message.notification;
    final data = message.data;
    final title = (n?.title ?? data['title'] ?? 'Fleaber').toString();
    final body =
        (n?.body ?? data['body'] ?? 'Tens uma actualização.').toString();
    try {
      await _pushUi.invokeMethod('showLocal', {
        'title': title,
        'body': body,
        'chat_id': (data['chat_id'] ?? '').toString(),
        'kind': (data['kind'] ?? '').toString(),
        'notification_id': (data['notification_id'] ?? '').toString(),
      });
    } catch (_) {}
  }

  static Future<void> registerCurrentToken() async {
    if (!_firebaseReady) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    if (currentUserUid.isEmpty) return;
    try {
      await SupaFlow.client.rpc(
        'batata_register_push_token',
        params: {
          'p_token': token,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          'p_app_version': '1.0.0+1237',
        },
      );
    } catch (_) {}
  }

  static Future<void> onLogout() async {
    final t = _token;
    try {
      await SupaFlow.client.rpc(
        'batata_revoke_push_token',
        params: {'p_token': t},
      );
    } catch (_) {}
    if (_firebaseReady) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    _token = null;
  }

  static void _openFromMessage(RemoteMessage message) {
    final data = message.data;
    unawaited(
      _openFromData(
        chatId: (data['chat_id'] ?? '').toString(),
        kind: (data['kind'] ?? '').toString(),
        notificationId: (data['notification_id'] ?? '').toString(),
      ),
    );
  }

  static Future<void> _openFromData({
    required String chatId,
    required String kind,
    String notificationId = '',
  }) async {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final nid = notificationId.trim();
    if (nid.isNotEmpty) {
      try {
        final rows = await UserNotificationsTable().queryRows(
          queryFn: (q) => q.eqOrNull('id', nid),
          limit: 1,
        );
        if (rows.isNotEmpty && ctx.mounted) {
          await FleaberNotificationsInbox.openDestination(ctx, rows.first);
          return;
        }
      } catch (_) {}
    }

    final cid = chatId.trim();
    final k = kind.trim().toLowerCase();

    if (FleaberNotificationsInbox.isOrderLifecycleKind(k) ||
        k == 'seguro_fleaber_paid' ||
        k.contains('ship') ||
        k.contains('order') ||
        k.contains('paid')) {
      if (ctx.mounted) HubAccountRoutes.openEncomendas(ctx);
      return;
    }

    if (cid.isNotEmpty) {
      if (!ctx.mounted) return;
      // ListaConversas resolve otherUserId a partir do chat (initState).
      ctx.pushNamed(
        ListaConversasWidget.routeName,
        queryParameters: {
          'chatId': serializeParam(cid, ParamType.String),
        }.withoutNulls,
      );
      return;
    }

    if (ctx.mounted) {
      HubAccountRoutes.openNotificacoes(ctx);
    }
  }
}
