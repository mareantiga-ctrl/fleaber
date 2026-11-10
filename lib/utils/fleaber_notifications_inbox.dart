import 'package:flutter/material.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/hub_account_routes.dart';
import '/hub/hub_navigation.dart';
import '/marketplace_feed_refresh.dart';
import '/pages/staff/helper_invitation_page_widget.dart';
import '/utils/fleaber_h10_navigation.dart';

/// Destino de navegação a partir de uma linha `user_notifications`.
enum FleaberNotificationDestination {
  chat,
  messagesInbox,
  orders,
  bag,
  product,
  helperInvite,
  wallet,
  none,
}

/// Inbox partilhada (app Home + FleaHub web) — só leitura/update próprios (RLS).
abstract final class FleaberNotificationsInbox {
  FleaberNotificationsInbox._();

  static Future<int> unreadCount({int limit = 100}) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return 0;
    try {
      final rows = await UserNotificationsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('user_id', uid)
            .eqOrNull('is_read', false)
            .order('created_at', ascending: false),
        limit: limit.clamp(1, 200),
      );
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<UserNotificationsRow>> listRecent({int limit = 40}) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return const [];
    try {
      return await UserNotificationsTable().queryRows(
        queryFn: (q) =>
            q.eqOrNull('user_id', uid).order('created_at', ascending: false),
        limit: limit.clamp(1, 80),
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<void> markRead(String? id) async {
    final nid = id?.trim() ?? '';
    if (nid.isEmpty) return;
    try {
      await UserNotificationsTable().update(
        data: {'is_read': true},
        matchingRows: (rows) => rows.eqOrNull('id', nid),
      );
    } catch (_) {
      // RLS / rede — badge actualiza na mesma
    } finally {
      notificationBadgeRefreshTick.value++;
    }
  }

  static Future<void> markAllRead() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return;
    try {
      await SupaFlow.client
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (_) {
    } finally {
      notificationBadgeRefreshTick.value++;
    }
  }

  static String? helperLinkIdFromKind(String? kind) {
    final raw = kind?.trim() ?? '';
    if (!raw.startsWith('helper_invitation')) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final id = parts[1].trim();
    return id.isEmpty ? null : id;
  }

  static final RegExp _orderUuidRe = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  );

  /// UUID da encomenda a partir de `dedupe_key` (ex. ship_delta:uuid:…).
  static String? orderIdFromNotification(UserNotificationsRow n) {
    final dedupe = (n.dedupeKey ?? '').trim();
    if (dedupe.isNotEmpty) {
      final m = _orderUuidRe.firstMatch(dedupe);
      if (m != null) return m.group(0);
    }
    for (final raw in [n.body, n.title]) {
      final m = _orderUuidRe.firstMatch((raw ?? '').trim());
      if (m != null) return m.group(0);
    }
    return null;
  }

  /// Kinds comerciais pós-compra → sempre a encomenda (não o chat).
  static bool isOrderLifecycleKind(String? kind) {
    final k = (kind ?? '').trim().toLowerCase();
    if (k.isEmpty) return false;
    if (k.startsWith('shipping_delta')) return true;
    if (k == 'ship_deadline_auto_cancelled') return true;
    if (k == 'reservation_order_shipped') return true;
    if (k == 'order_paid_buyer' || k == 'order_paid_seller') return true;
    if (k.contains('paid_sale')) return true;
    if (k.contains('encomenda') && k.contains('cancel')) return true;
    return false;
  }

  static FleaberNotificationDestination destinationFor(
    UserNotificationsRow n,
  ) {
    final kind = (n.kind ?? '').trim().toLowerCase();
    if (kind.startsWith('helper_invitation')) {
      return FleaberNotificationDestination.helperInvite;
    }
    if (isOrderLifecycleKind(kind)) {
      return FleaberNotificationDestination.orders;
    }
    // Favoritos / «gostou» → artigo quando há product_id.
    if ((kind.contains('favorite') ||
            kind.contains('gostou') ||
            kind == 'product_liked' ||
            kind.startsWith('like')) &&
        (n.productId ?? '').trim().isNotEmpty) {
      return FleaberNotificationDestination.product;
    }
    // Pagamento Seguro Fleaber / propostas → chat se existir thread.
    if (kind == 'seguro_fleaber_paid' ||
        kind.contains('offer') ||
        kind.contains('proposal') ||
        kind.contains('bundle')) {
      final chat = n.chatId?.trim() ?? '';
      if (chat.isNotEmpty) return FleaberNotificationDestination.chat;
      if ((n.productId ?? '').trim().isNotEmpty) {
        return FleaberNotificationDestination.product;
      }
      return FleaberNotificationDestination.messagesInbox;
    }
    if (kind.contains('reserv')) {
      final chat = n.chatId?.trim() ?? '';
      if (chat.isNotEmpty) return FleaberNotificationDestination.chat;
      return FleaberNotificationDestination.bag;
    }
    if (kind.startsWith('wallet_') ||
        kind == 'wallet_funds_released' ||
        kind == 'wallet_payout_sent' ||
        kind == 'wallet_payout_failed') {
      return FleaberNotificationDestination.wallet;
    }
    if (kind.contains('dispute') || kind.contains('encomenda')) {
      return FleaberNotificationDestination.orders;
    }
    final chat = n.chatId?.trim() ?? '';
    if (chat.isNotEmpty) return FleaberNotificationDestination.chat;
    if ((n.productId ?? '').trim().isNotEmpty &&
        (kind.contains('favorite') || kind.contains('product'))) {
      return FleaberNotificationDestination.product;
    }
    return FleaberNotificationDestination.messagesInbox;
  }

  /// Navega após marcar lida. [onOpenBag] = saco Hub (reservas sem chat).
  static Future<void> openDestination(
    BuildContext context,
    UserNotificationsRow n, {
    VoidCallback? onOpenBag,
  }) async {
    await markRead(n.id);
    if (!context.mounted) return;

    final dest = destinationFor(n);
    switch (dest) {
      case FleaberNotificationDestination.helperInvite:
        final linkId = helperLinkIdFromKind(n.kind);
        if (linkId == null || linkId.isEmpty) {
          HubAccountRoutes.openNotificacoes(context);
          return;
        }
        context.pushNamed(
          HelperInvitationPageWidget.routeName,
          queryParameters: {
            'helperLinkId': serializeParam(linkId, ParamType.String),
          }.withoutNulls,
        );
        return;
      case FleaberNotificationDestination.chat:
        final chatId = n.chatId?.trim() ?? '';
        if (chatId.isEmpty) {
          HubAccountRoutes.openMensagens(context);
          return;
        }
        var other = (n.actorId ?? '').trim();
        if (other.isEmpty) {
          other = await _otherUserIdForChat(chatId) ?? '';
        }
        if (other.isEmpty) {
          HubAccountRoutes.openMensagens(context);
          return;
        }
        if (!context.mounted) return;
        // Hub web: inbox H10 (split); app: ChatPage via openH10Conversation.
        try {
          await openH10Conversation(
            context,
            otherUserId: other,
            chatId: chatId,
            productId: (n.productId ?? '').trim().isEmpty
                ? null
                : n.productId!.trim(),
          );
        } catch (_) {
          if (!context.mounted) return;
          HubAccountRoutes.openMensagens(context);
        }
        return;
      case FleaberNotificationDestination.orders:
        HubAccountRoutes.openEncomendas(
          context,
          orderId: orderIdFromNotification(n),
        );
        return;
      case FleaberNotificationDestination.wallet:
        HubAccountRoutes.openSaldo(context);
        return;
      case FleaberNotificationDestination.bag:
        if (onOpenBag != null) {
          onOpenBag();
          return;
        }
        // Sem callback do Hub: Início (saco fica acessível na Home/Hub).
        HubNavigation.goAppHome(context);
        return;
      case FleaberNotificationDestination.product:
        final pid = (n.productId ?? '').trim();
        if (pid.isEmpty) {
          HubAccountRoutes.openMensagens(context);
          return;
        }
        context.pushNamed(
          'ProductDetails',
          queryParameters: {
            'productId': serializeParam(pid, ParamType.String),
          }.withoutNulls,
        );
        return;
      case FleaberNotificationDestination.messagesInbox:
        HubAccountRoutes.openNotificacoes(context);
        return;
      case FleaberNotificationDestination.none:
        return;
    }
  }

  static Future<String?> _otherUserIdForChat(String chatId) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty || chatId.trim().isEmpty) return null;
    try {
      final rows = await ChatsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', chatId.trim()),
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final c = rows.first;
      final a = (c.userA ?? '').trim();
      final b = (c.userB ?? '').trim();
      if (a == uid && b.isNotEmpty) return b;
      if (b == uid && a.isNotEmpty) return a;
      if (a.isNotEmpty && a != uid) return a;
      if (b.isNotEmpty && b != uid) return b;
    } catch (_) {}
    return null;
  }
}
