import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import '/marketplace_feed_refresh.dart';

/// Alertas «push» in-app quando chega notificação (Realtime em user_notifications).
class FleaberUserNotificationHub {
  FleaberUserNotificationHub._();

  static final FleaberUserNotificationHub instance =
      FleaberUserNotificationHub._();

  RealtimeChannel? _channel;
  String? _subscribedUserId;

  void syncSubscription() {
    final uid = currentUserUid;
    if (uid.isEmpty) {
      detach();
      return;
    }
    if (_subscribedUserId == uid && _channel != null) return;
    detach();
    _subscribedUserId = uid;
    _channel = SupaFlow.client
        .channel('fleaber_user_notifications_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            _onNotificationInserted(row);
          },
        )
        .subscribe();
  }

  void detach() {
    final ch = _channel;
    _channel = null;
    _subscribedUserId = null;
    if (ch != null) {
      unawaited(SupaFlow.client.removeChannel(ch));
    }
  }

  void _onNotificationInserted(Map<String, dynamic> row) {
    notificationBadgeRefreshTick.value++;

    final kind = (row['kind'] as String?) ?? '';
    final isHelperInvite = kind.startsWith('helper_invitation');
    if (!kind.startsWith('price_offer') && !isHelperInvite) return;

    final title = (row['title'] as String?)?.trim();
    final body = (row['body'] as String?)?.trim();
    final chatId = row['chat_id'] as String?;
    final actorId = row['actor_id'] as String?;
    String? helperLinkId;
    if (isHelperInvite) {
      final parts = kind.split(':');
      if (parts.length >= 2) {
        helperLinkId = parts[1].trim();
      }
    }

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;

    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF101518),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null && title.isNotEmpty)
              Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            if (body != null && body.isNotEmpty)
              Text(
                body,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        action: isHelperInvite && helperLinkId != null && helperLinkId.isNotEmpty
            ? SnackBarAction(
                label: 'Ver convite',
                textColor: const Color(0xFF4DD0E1),
                onPressed: () {
                  final nav = appNavigatorKey.currentContext;
                  if (nav == null) return;
                  nav.pushNamed(
                    HelperInvitationPageWidget.routeName,
                    queryParameters: {
                      'helperLinkId': helperLinkId,
                    },
                  );
                },
              )
            : chatId != null && chatId.isNotEmpty
                ? SnackBarAction(
                    label: 'Ver',
                    textColor: const Color(0xFF4DD0E1),
                    onPressed: () {
                      final nav = appNavigatorKey.currentContext;
                      if (nav == null) return;
                      nav.pushNamed(
                        ChatPageWidget.routeName,
                        queryParameters: {
                          'chatId': chatId,
                          if (actorId != null && actorId.isNotEmpty)
                            'otherUserId': actorId,
                        },
                      );
                    },
                  )
                : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
