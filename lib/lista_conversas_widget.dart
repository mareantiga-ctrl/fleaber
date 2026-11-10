import 'dart:async';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_offer_pending.dart';
import '/chat_session_util.dart';
import '/marketplace_feed_refresh.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/theme/hub_theme.dart';
import '/hub/theme/hub_messages_theme.dart';
import '/hub/hub_navigation.dart';
import '/chat_page/chat_page_widget.dart';
import '/perfil_widget.dart';
import '/widgets/batata_cached_image.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_notification_copy.dart';
import '/utils/fleaber_notifications_inbox.dart';
import '/utils/fleaber_chat_system_copy.dart';
import '/widgets/fleaber_create_sheet.dart';
import '/widgets/fleaber_refresh.dart';
import '/widgets/profile_avatar.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ListaConversasWidget extends StatefulWidget {
  const ListaConversasWidget({
    super.key,
    this.initialTab,
    this.initialChatId,
    this.initialOtherUserId,
    this.initialOrderId,
    this.requestCancelOnOpen = false,
  });

  static String routeName = 'ListaConversas';
  static String routePath = '/listaConversas';
  final String? initialTab;

  /// Pré-seleccionar conversa no painel H10 (web desktop split).
  final String? initialChatId;
  final String? initialOtherUserId;
  final String? initialOrderId;
  final bool requestCancelOnOpen;

  @override
  State<ListaConversasWidget> createState() => _ListaConversasWidgetState();
}

class _ListaConversasWidgetState extends State<ListaConversasWidget>
    with TickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  String? _notificationsErrorHint;
  final Set<String> _locallyReadNotificationIds = <String>{};
  late TabController _tabController;
  int _listRefreshTick = 0;

  /// Web P10 desktop split — conversa activa no painel direito.
  String? _hubSelectedChatId;
  String? _hubSelectedOtherUserId;
  String? _hubSelectedOrderId;
  bool _hubRequestCancelOnOpen = false;

  bool get _hubWeb => kIsWeb;

  void _openConversation(String chatId, String otherUserId) {
    if (_hubWeb && HubTheme.useMessagesDesktopSplit(context)) {
      setState(() {
        _hubSelectedChatId = chatId;
        _hubSelectedOtherUserId = otherUserId;
        _hubSelectedOrderId = null;
        _hubRequestCancelOnOpen = false;
      });
      return;
    }
    context.pushNamed(
      ChatPageWidget.routeName,
      queryParameters: {
        'chatId': serializeParam(chatId, ParamType.String),
        'otherUserId': serializeParam(otherUserId, ParamType.String),
      }.withoutNulls,
    );
  }

  void _clearHubPanelSelection() {
    setState(() {
      _hubSelectedChatId = null;
      _hubSelectedOtherUserId = null;
      _hubSelectedOrderId = null;
      _hubRequestCancelOnOpen = false;
    });
  }

  Widget _hubEmptyChatPane() {
    // Estado vazio discreto — ligeiramente acima do centro para não «flutuar»
    // no painel largo (E26). Sem estatísticas nem CTAs inventados.
    return ColoredBox(
      color: HubMessagesTheme.bg,
      child: Align(
        alignment: const Alignment(0, -0.18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: HubMessagesTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: HubMessagesTheme.borderSoft),
                    boxShadow: HubMessagesTheme.cardShadow,
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 34,
                    color: HubMessagesTheme.teal,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'As tuas mensagens',
                  textAlign: TextAlign.center,
                  style: HubMessagesTheme.titleMd.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  'Seleciona uma conversa para veres as mensagens.',
                  textAlign: TextAlign.center,
                  style: HubMessagesTheme.body.copyWith(fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Notificações: no Mockup B desktop a lista vive na coluna esquerda (sem teto estreito).
  Widget _hubNotifShell({required Widget child}) => child;

  /// Mockup B — título + pills compactos (só desktop split).
  Widget _buildMockupBInboxChrome() {
    final i = _tabController.index;
    Widget pill(String label, int index) {
      final active = i == index;
      return Expanded(
        child: Material(
          color: active
              ? const Color(0x1A007782)
              : HubMessagesTheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (_tabController.index != index) {
                _tabController.animateTo(index);
                setState(() {});
              }
            },
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? HubMessagesTheme.selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? HubMessagesTheme.teal.withValues(alpha: 0.45)
                      : HubMessagesTheme.border,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active
                      ? HubMessagesTheme.teal
                      : HubMessagesTheme.textMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: HubMessagesTheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caixa de entrada',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: HubMessagesTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                pill('Mensagens', 0),
                const SizedBox(width: 8),
                pill('Notificações', 1),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshLists() async {
    setState(() => _listRefreshTick++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  int _initialTabIndex() {
    final tab = widget.initialTab?.trim().toLowerCase();
    if (tab == 'notificacoes' || tab == 'notificações') return 1;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    final chatId = (widget.initialChatId ?? '').trim();
    final other = (widget.initialOtherUserId ?? '').trim();
    if (chatId.isNotEmpty && other.isNotEmpty) {
      _hubSelectedChatId = chatId;
      _hubSelectedOtherUserId = other;
      final oid = (widget.initialOrderId ?? '').trim();
      _hubSelectedOrderId = oid.isEmpty ? null : oid;
      _hubRequestCancelOnOpen = widget.requestCancelOnOpen;
    } else if (chatId.isNotEmpty) {
      _hubSelectedChatId = chatId;
      final oid = (widget.initialOrderId ?? '').trim();
      _hubSelectedOrderId = oid.isEmpty ? null : oid;
      _hubRequestCancelOnOpen = widget.requestCancelOnOpen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_resolveOtherUserForSelectedChat());
      });
    }
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _initialTabIndex(),
    )..addListener(() {
        if (_tabController.indexIsChanging) return;
        if (mounted) setState(() {});
        if (_tabController.index == 1) {
          unawaited(_markNotificationsAsRead());
        }
      });

    if (_tabController.index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_markNotificationsAsRead());
      });
    }
  }

  Future<void> _resolveOtherUserForSelectedChat() async {
    final chatId = (_hubSelectedChatId ?? '').trim();
    if (chatId.isEmpty || currentUserUid.isEmpty) return;
    try {
      final rows = await ChatsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', chatId),
        limit: 1,
      );
      if (!mounted || rows.isEmpty) return;
      final c = rows.first;
      final a = (c.userA ?? '').trim();
      final b = (c.userB ?? '').trim();
      String? other;
      if (a == currentUserUid && b.isNotEmpty) {
        other = b;
      } else if (b == currentUserUid && a.isNotEmpty) {
        other = a;
      } else if (a.isNotEmpty && a != currentUserUid) {
        other = a;
      } else if (b.isNotEmpty && b != currentUserUid) {
        other = b;
      }
      if (other == null || other.isEmpty) return;
      setState(() => _hubSelectedOtherUserId = other);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatLastMessageTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (messageDay == today) {
      return DateFormat('HH:mm').format(dateTime);
    }
    if (messageDay == yesterday) {
      return 'Ontem';
    }
    return DateFormat('dd/MM').format(dateTime);
  }

  String _otherUserIdForChat(ChatsRow chat) {
    return chat.userA == currentUserUid ? chat.userB : chat.userA;
  }

  Future<bool> _hasAnyUnreadMessages() async {
    final unreadRows = await ChatMessagesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('receiver_id', currentUserUid)
          .eqOrNull('is_read', false)
          .limit(1),
    );
    return unreadRows.isNotEmpty;
  }

  Future<List<_FavoriteNotificationItem>> _loadFavoriteNotifications() async {
    if (currentUserUid.isEmpty) return const <_FavoriteNotificationItem>[];
    final favorites = await _loadFavoriteNotificationsManual();
    final offers = await _loadOfferNotifications();
    return [...offers, ...favorites]
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(1970))
            .compareTo(a.createdAt ?? DateTime(1970)),
      );
  }

  Future<List<_FavoriteNotificationItem>> _loadOfferNotifications() async {
    try {
      final rows = await UserNotificationsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('user_id', currentUserUid)
            .order('created_at', ascending: false),
        limit: 80,
      );
      if (rows.isEmpty) return const [];

      final actorIds = rows
          .map((r) => r.actorId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final actors = actorIds.isEmpty
          ? const <ProfilesRow>[]
          : await ProfilesDirectoryTable().queryRows(
              queryFn: (q) => q.inFilter('id', actorIds),
              limit: actorIds.length,
            );
      final actorById = {for (final p in actors) if (p.id != null) p.id!: p};

      return rows.map((n) {
        final actor = actorById[n.actorId ?? ''];
        final isCounter = n.kind == 'price_offer_counter';
        final helperLinkId = _helperLinkIdFromNotificationKind(n.kind);
        return _FavoriteNotificationItem(
          notificationId: n.id,
          likerId: n.actorId ?? '',
          likerName: actor?.fullName ?? 'Utilizador',
          likerPhotoUrl: actor?.photoUrl,
          productId: n.productId,
          productTitle: n.body ?? (isCounter ? 'Contra-proposta' : 'Proposta'),
          createdAt: n.createdAt,
          kind: n.kind ?? 'price_offer',
          helperLinkId: helperLinkId,
          chatId: n.chatId,
          inboxTitle: n.title,
          isRead: n.isRead == true,
          dedupeKey: n.dedupeKey,
        );
      }).toList(growable: false);
    } catch (e) {
      print('ERRO NOTIFICACOES_OFERTA: $e');
      return const [];
    }
  }

  Future<void> _markOfferNotificationRead(String? id) async {
    if (id == null || id.isEmpty) return;
    try {
      await UserNotificationsTable().update(
        data: {'is_read': true},
        matchingRows: (rows) => rows.eqOrNull('id', id),
      );
      notificationBadgeRefreshTick.value++;
    } catch (e) {
      print('ERRO NOTIFICACOES_OFERTA_READ: $e');
    }
  }

  String? _helperLinkIdFromNotificationKind(String? kind) {
    final raw = kind?.trim() ?? '';
    if (!raw.startsWith('helper_invitation')) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final id = parts[1].trim();
    return id.isEmpty ? null : id;
  }

  Future<List<_FavoriteNotificationItem>> _loadFavoriteNotificationsManual() async {
    try {
      final myProducts = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', currentUserUid),
        limit: 300,
      );
      if (myProducts.isEmpty) {
        _notificationsErrorHint = null;
        return const <_FavoriteNotificationItem>[];
      }

      final productById = <String, ProductsRow>{
        for (final p in myProducts)
          if (p.id != null && p.id!.isNotEmpty) p.id!: p,
      };
      if (productById.isEmpty) {
        _notificationsErrorHint = null;
        return const <_FavoriteNotificationItem>[];
      }

      final favoriteRows = await FavoritesTable().queryRows(
        queryFn: (q) => q
            .neq('user_id', currentUserUid)
            .order('created_at', ascending: false),
        limit: 500,
      );

      final relevant = favoriteRows
          .where((f) => productById.containsKey(f.productId))
          .toList(growable: false);
      if (relevant.isEmpty) {
        _notificationsErrorHint = null;
        return const <_FavoriteNotificationItem>[];
      }

      final likerIds =
          relevant.map((e) => e.userId).toSet().toList(growable: false);
      final likers = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.inFilter('id', likerIds),
        limit: likerIds.length,
      );
      final likerById = <String, ProfilesRow>{
        for (final p in likers)
          if (p.id != null && p.id!.isNotEmpty) p.id!: p,
      };

      _notificationsErrorHint = null;
      return relevant.map((fav) {
        final product = productById[fav.productId];
        final liker = likerById[fav.userId];
        return _FavoriteNotificationItem(
          notificationId: fav.id,
          likerId: fav.userId,
          likerName: liker?.fullName ?? 'Um utilizador',
          likerPhotoUrl: liker?.photoUrl,
          productId: product?.id,
          productTitle: product?.title ?? 'um artigo',
          createdAt: fav.createdAt,
        );
      }).toList(growable: false);
    } catch (e) {
      print('ERRO NOTIFICACOES: $e');
      final raw = e.toString().toLowerCase();
      final isPermissionIssue =
          raw.contains('jwt') || raw.contains('permission denied');
      _notificationsErrorHint = isPermissionIssue
          ? 'Permissão/JWT no Supabase. Ajusta as políticas RLS para favorites/products/profiles.'
          : null;
      return const <_FavoriteNotificationItem>[];
    }
  }

  Future<void> _markNotificationsAsRead() async {
    if (currentUserUid.isEmpty) return;
    // Badge Hub/Home lê `user_notifications` — marcar aí (não só notifications_view).
    await FleaberNotificationsInbox.markAllRead();
    try {
      await SupaFlow.client
          .from('notifications_view')
          .update({'is_read': true})
          .eq('target_user_id', currentUserUid)
          .eq('is_read', false);
    } catch (e) {
      // Favoritos legados na view — best-effort.
      print('ERRO NOTIFICACOES_VIEW_READ: $e');
    } finally {
      clearBatataReservationNotificationBellPing();
    }
  }

  Future<void> _markNotificationAsRead(_FavoriteNotificationItem item) async {
    final id = item.notificationId?.trim() ?? '';
    if (id.isEmpty) {
      await _markNotificationsAsRead();
      return;
    }
    try {
      await SupaFlow.client
          .from('notifications_view')
          .update({'is_read': true})
          .eq('target_user_id', currentUserUid)
          .eq('favorite_id', id);
    } catch (e) {
      try {
        await SupaFlow.client
            .from('notifications_view')
            .update({'is_read': true})
            .eq('target_user_id', currentUserUid)
            .eq('notification_id', id);
      } catch (e2) {
        print('ERRO NOTIFICACOES_READ_ONE: $e | $e2');
        await _markNotificationsAsRead();
      }
    }
    clearBatataReservationNotificationBellPing();
    notificationBadgeRefreshTick.value++;
  }

  Future<void> _showCreateBottomSheet([BuildContext? anchor]) =>
      FleaberCreateSheet.show(context, anchorContext: anchor ?? context);

  @override
  Widget build(BuildContext context) {
    final hub = _hubWeb;
    final hubSplit = hub && HubTheme.useMessagesDesktopSplit(context);
    final scaffoldBg = hub ? HubMessagesTheme.bg : FleaberColors.bgTint;
    final appBarBg = hub ? HubMessagesTheme.surface : Colors.white;
    final tabSelected = hub ? HubMessagesTheme.teal : const Color(0xFF007782);
    final tabUnselected =
        hub ? HubMessagesTheme.textMuted : const Color(0xFF57636C);
    final dividerColor =
        hub ? HubMessagesTheme.divider : const Color(0xFFF1F4F8);

    final tabViews = TabBarView(
              controller: _tabController,
              children: [
                FutureBuilder<List<ChatsRow>>(
                  key: ValueKey<int>(_listRefreshTick),
                  future: ChatsTable().queryRows(
                    queryFn: (q) => q
                        .or('user_a.eq.$currentUserUid,user_b.eq.$currentUserUid')
                        .order('last_message_time', ascending: false),
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: SizedBox(
                          width: 40.0,
                          height: 40.0,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              hub ? HubMessagesTheme.accent : FlutterFlowTheme.of(context).primary,
                            ),
                          ),
                        ),
                      );
                    }

                    final chats = snapshot.data!;
                    final uniqueChatsById = <String, ChatsRow>{};
                    for (final chat in chats) {
                      if (chat.id != null) {
                        uniqueChatsById[chat.id!] = chat;
                      }
                    }
                    final uniqueChats = uniqueChatsById.values.toList()
                      ..sort((a, b) => (b.lastMessageTime ?? DateTime(1970))
                          .compareTo(a.lastMessageTime ?? DateTime(1970)));
                    if (uniqueChats.isEmpty) {
                      final emptyListBody = Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forum_outlined,
                                size: hubSplit ? 48.0 : 80.0,
                                color: hub
                                    ? HubMessagesTheme.accent
                                    : const Color(0xFF007782),
                              ),
                              const SizedBox(height: 14.0),
                              Text(
                                'Ainda não tens conversas.',
                                textAlign: TextAlign.center,
                                style: hub
                                    ? HubMessagesTheme.titleMd
                                    : FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyLarge
                                                    .fontStyle,
                                          ),
                                          letterSpacing: 0.0,
                                          fontWeight: FontWeight.w600,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyLarge
                                                  .fontStyle,
                                        ),
                              ),
                            ],
                          ),
                        ),
                      );
                      // Desktop Mockup B: empty só na coluna esquerda.
                      return emptyListBody;
                    }

                    return FutureBuilder<Set<String>>(
                      future: fetchChatIdsWithPendingOfferForMe(),
                      builder: (context, pendingSnap) {
                        final pendingOfferChatIds =
                            pendingSnap.data ?? const {};
                        final listPane = FleaberRefresh(
                      onRefresh: _refreshLists,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        itemCount: uniqueChats.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1.0,
                        thickness: 1.0,
                        color: dividerColor,
                      ),
                      itemBuilder: (context, index) {
                        final chat = uniqueChats[index];
                        final hasPendingOffer = chatHasPendingOfferForMe(
                          pendingOfferChatIds,
                          chat.id,
                        );
                        final otherUserId = _otherUserIdForChat(chat);
                        final isSelected = hubSplit &&
                            chat.id != null &&
                            chat.id == _hubSelectedChatId;

                        final productId = chat.productId;
                        final hasProductContext =
                            productId != null && productId.isNotEmpty;

                        return FutureBuilder<List<ProfilesRow>>(
                          future: ProfilesDirectoryTable().queryRows(
                            queryFn: (q) => q.eqOrNull('id', otherUserId),
                          ),
                          builder: (context, profileSnapshot) {
                            final profile = profileSnapshot.hasData &&
                                    profileSnapshot.data!.isNotEmpty
                                ? profileSnapshot.data!.first
                                : null;

                            return FutureBuilder<List<ProductsRow>>(
                              future: hasProductContext
                                  ? ProductsTable().querySingleRow(
                                      queryFn: (q) =>
                                          q.eqOrNull('id', productId),
                                    )
                                  : Future<List<ProductsRow>>.value(
                                      const <ProductsRow>[],
                                    ),
                              builder: (context, productSnapshot) {
                                final ProductsRow? productRow =
                                    hasProductContext &&
                                            productSnapshot.hasData &&
                                            productSnapshot.data!.isNotEmpty
                                        ? productSnapshot.data!.first
                                        : null;
                                final String? productThumbUrl =
                                    productRow != null &&
                                            productRow.imageUrls.isNotEmpty
                                        ? productRow.imageUrls.first
                                        : null;

                            return FutureBuilder<List<ChatMessagesRow>>(
                              future: ChatMessagesTable().queryRows(
                                queryFn: (q) => q
                                    .eqOrNull('chat_id', chat.id)
                                    .eqOrNull('receiver_id', currentUserUid)
                                    .eqOrNull('is_read', false)
                                    .limit(1),
                              ),
                              builder: (context, messageSnapshot) {
                                final hasUnread = messageSnapshot.hasData &&
                                    messageSnapshot.data!.isNotEmpty;
                                final isUnread = hasUnread;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                  splashColor: HubMessagesTheme.teal
                                      .withValues(alpha: 0.08),
                                  hoverColor: HubMessagesTheme.hoverBg,
                                  onTap: () {
                                    final id = chat.id;
                                    if (id == null || id.isEmpty) return;
                                    _openConversation(id, otherUserId);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: hub
                                          ? (isSelected
                                              ? HubMessagesTheme.selectedBg
                                              : (isUnread
                                                  ? HubMessagesTheme.unreadBg
                                                  : HubMessagesTheme.surface))
                                          : (isUnread
                                              ? const Color(0xFFEFF9FA)
                                              : Colors.white),
                                      border: Border(
                                        left: BorderSide(
                                          color: (isSelected || isUnread)
                                              ? (hub
                                                  ? HubMessagesTheme.teal
                                                  : const Color(0xFF007782))
                                              : Colors.transparent,
                                          width: isSelected ? 3 : 2,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        14.0, 12.0, 12.0, 12.0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        FleaberProfileAvatar(
                                          userId: otherUserId,
                                          fullName: profile?.fullName,
                                          photoUrl: profile?.photoUrl,
                                          radius: 22.0,
                                        ),
                                        const SizedBox(width: 12.0),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                profile?.fullName ?? 'Utilizador',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodyLarge
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight: isUnread ||
                                                                isSelected
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .fontStyle,
                                                      ),
                                                      color: hub
                                                          ? HubMessagesTheme
                                                              .textPrimary
                                                          : const Color(
                                                              0xFF101518),
                                                      letterSpacing: 0.0,
                                                      fontWeight: isUnread ||
                                                              isSelected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyLarge
                                                              .fontStyle,
                                                    ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                // Âncora product_id mantém-se no chat; o assunto
                                                // visual de conjunto vem do last_message (Android).
                                                fleaberChatInboxSubject(
                                                  lastMessage: chat.lastMessage,
                                                  productTitle: hasProductContext
                                                      ? productRow?.title
                                                      : null,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodyMedium
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight: isUnread
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontStyle,
                                                      ),
                                                      color: hub
                                                          ? HubMessagesTheme.textSecondary
                                                          : const Color(
                                                              0xFF3F4A53),
                                                      letterSpacing: 0.0,
                                                      fontWeight: isUnread
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodyMedium
                                                              .fontStyle,
                                                    ),
                                              ),
                                              if (hasPendingOffer) ...[
                                                const SizedBox(height: 6.0),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8.0,
                                                    vertical: 4.0,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFFF3E0),
                                                    borderRadius:
                                                        BorderRadius.circular(6.0),
                                                    border: Border.all(
                                                      color: const Color(0xFFFFB74D),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Proposta pendente',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11.0,
                                                      fontWeight: FontWeight.w700,
                                                      color: const Color(0xFFE65100),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (hasProductContext) ...[
                                                const SizedBox(height: 8.0),
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8.0),
                                                    child: SizedBox(
                                                      width: 40.0,
                                                      height: 40.0,
                                                      child: productThumbUrl !=
                                                                  null &&
                                                              productThumbUrl
                                                                  .isNotEmpty
                                                          ? BatataCachedNetworkImage(
                                                              imageUrl:
                                                                  productThumbUrl,
                                                              fit: BoxFit.cover,
                                                              placeholderColor:
                                                                  const Color(
                                                                      0xFFF1F4F8),
                                                              errorWidget:
                                                                  ColoredBox(
                                                                color: const Color(
                                                                    0xFFF1F4F8),
                                                                child: Icon(
                                                                  Icons
                                                                      .image_not_supported_outlined,
                                                                  size: 18.0,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade500,
                                                                ),
                                                              ),
                                                            )
                                                          : const ColoredBox(
                                                              color: Color(
                                                                  0xFFF1F4F8),
                                                              child: Icon(
                                                                Icons
                                                                    .inventory_2_outlined,
                                                                size: 18.0,
                                                                color: Color(
                                                                    0xFF8A8D93),
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8.0),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatLastMessageTime(
                                                  chat.lastMessageTime),
                                              style: FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .override(
                                                    font: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .labelMedium
                                                              .fontStyle,
                                                    ),
                                                    color: hub
                                                        ? HubMessagesTheme.textMuted
                                                        : const Color(
                                                            0xFF57636C),
                                                    letterSpacing: 0.0,
                                                    fontWeight: FontWeight.w500,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .labelMedium
                                                            .fontStyle,
                                                  ),
                                            ),
                                            const SizedBox(height: 8.0),
                                            if (isUnread)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: hub
                                                      ? HubMessagesTheme.teal
                                                      : const Color(0xFF007782),
                                                  borderRadius: BorderRadius.circular(
                                                    999,
                                                  ),
                                                ),
                                                child: Text(
                                                  'Nova',
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              );

                        // Desktop Mockup B: lista só na coluna esquerda (chat à direita no shell).
                        return ColoredBox(
                          color: hub ? HubMessagesTheme.surface : FleaberColors.bgTint,
                          child: listPane,
                        );
                      },
                    );
                  },
                ),
                FutureBuilder<List<_FavoriteNotificationItem>>(
                  key: ValueKey<String>('notif_$_listRefreshTick'),
                  future: _loadFavoriteNotifications(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: hub ? HubMessagesTheme.accent : null,
                          ),
                        ),
                      );
                    }
                    final notifications = snapshot.data!;
                    if (notifications.isEmpty) {
                      final emptyNotif = Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: hub && hubSplit ? 48.0 : 24.0,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: hub ? 64.0 : 84.0,
                                  color: hub
                                      ? HubMessagesTheme.accent
                                      : const Color(0xFF007782),
                                ),
                                const SizedBox(height: 14.0),
                                Text(
                                  'Ainda não tens notificações',
                                  textAlign: TextAlign.center,
                                  style: hub
                                      ? HubMessagesTheme.titleMd
                                      : FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyLarge
                                                      .fontStyle,
                                            ),
                                            color: const Color(0xFF57636C),
                                            letterSpacing: 0.0,
                                            fontWeight: FontWeight.w600,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyLarge
                                                    .fontStyle,
                                          ),
                                ),
                                if (_notificationsErrorHint != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _notificationsErrorHint!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: hub
                                          ? const Color(0xFFFF8A80)
                                          : const Color(0xFFB00020),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                      return ColoredBox(
                        color: hub ? HubMessagesTheme.bg : FleaberColors.bgTint,
                        child: _hubNotifShell(child: emptyNotif),
                      );
                    }
                    final notifList = FleaberRefresh(
                      onRefresh: _refreshLists,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          vertical: hub && hubSplit ? 16 : 8,
                          horizontal: hub && hubSplit ? 4 : 0,
                        ),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                        final when = _formatLastMessageTime(n.createdAt);
                          final localRead = n.notificationId != null &&
                              _locallyReadNotificationIds.contains(n.notificationId);
                          final isUnread = n.isRead != true && !localRead;
                        return Container(
                          decoration: BoxDecoration(
                            color: hub
                                ? (isUnread
                                    ? HubMessagesTheme.unreadBg
                                    : HubMessagesTheme.surface)
                                : (isUnread
                                    ? const Color(0xFFEFF9FA)
                                    : Colors.white),
                            border: Border(
                              left: BorderSide(
                                color: isUnread
                                    ? (hub
                                        ? HubMessagesTheme.teal
                                        : const Color(0xFF007782))
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: FleaberProfileAvatar(
                              userId: n.likerId,
                              fullName: n.likerName,
                              photoUrl: n.likerPhotoUrl,
                              radius: 20,
                            ),
                            title: Text(
                              fleaberNotificationInboxTitle(
                                kind: n.kind,
                                inboxTitle: n.inboxTitle,
                                likerName: n.likerName,
                                productTitle: n.productTitle,
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight:
                                    isUnread ? FontWeight.w700 : FontWeight.w600,
                                color: hub
                                    ? HubMessagesTheme.textPrimary
                                    : const Color(0xFF101518),
                              ),
                            ),
                            subtitle: n.usesInboxTitle
                                ? Text(
                                    n.isBundleNotif
                                        ? (n.productTitle.isNotEmpty
                                            ? '${n.likerName} · ${n.productTitle}'
                                            : n.likerName)
                                        : '${n.likerName} · ${n.productTitle}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: hub
                                          ? HubMessagesTheme.textSecondary
                                          : const Color(0xFF57636C),
                                    ),
                                  )
                                : (when.isNotEmpty
                                    ? Text(
                                        when,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: hub
                                              ? HubMessagesTheme.textMuted
                                              : const Color(0xFF57636C),
                                        ),
                                      )
                                    : null),
                            trailing: isUnread
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hub
                                          ? HubMessagesTheme.teal
                                          : const Color(0xFF007782),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Nova',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () async {
                              final id = n.notificationId?.trim();
                              if (id != null && id.isNotEmpty && mounted) {
                                setState(() =>
                                    _locallyReadNotificationIds.add(id));
                              }
                              if (!context.mounted) return;
                              // Destino único (encomenda / chat / artigo / saco).
                              await FleaberNotificationsInbox.openDestination(
                                context,
                                n.toNotificationsRow(),
                              );
                            },
                          ),
                        );
                        },
                      ),
                    );
                    return ColoredBox(
                      color: hub ? HubMessagesTheme.bg : FleaberColors.bgTint,
                      child: _hubNotifShell(child: notifList),
                    );
                  },
                ),
              ],
            );

    // —— Desktop Mockup B: topbar Hub + caixa de entrada | conversa ——
    if (hubSplit) {
      return GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FleaberColors.bgTint,
          body: SafeArea(
            child: Column(
              children: [
                const FleaHubSiteTopBar(),
                const FleaHubTopBarBleed(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: HubTheme.messagesListPaneWidthFor(context),
                        child: ColoredBox(
                          color: HubMessagesTheme.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMockupBInboxChrome(),
                              const Divider(height: 1, thickness: 1),
                              Expanded(child: tabViews),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: HubMessagesTheme.divider,
                      ),
                      Expanded(
                        child: _hubSelectedChatId == null ||
                                _hubSelectedOtherUserId == null
                            ? _hubEmptyChatPane()
                            : ChatPageWidget(
                                key: ValueKey(
                                  '${_hubSelectedChatId}_${_hubSelectedOrderId ?? ''}',
                                ),
                                chatId: _hubSelectedChatId,
                                otherUserId: _hubSelectedOtherUserId,
                                orderId: _hubSelectedOrderId,
                                requestCancelOnOpen: _hubRequestCancelOnOpen,
                                hubPanelMode: true,
                                onHubPanelClose: _clearHubPanelSelection,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // —— Mobile / estreito: experiência Fleaber original ——
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
          key: scaffoldKey,
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: 0.0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            toolbarHeight: 0.0,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: tabSelected,
              labelColor: tabSelected,
              unselectedLabelColor: tabUnselected,
              labelStyle: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontStyle:
                          FlutterFlowTheme.of(context).titleSmall.fontStyle,
                    ),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).titleSmall.fontStyle,
                  ),
              unselectedLabelStyle:
                  FlutterFlowTheme.of(context).titleSmall.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleSmall.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w500,
                        fontStyle:
                            FlutterFlowTheme.of(context).titleSmall.fontStyle,
                      ),
              tabs: const [
                Tab(text: 'Mensagens'),
                Tab(text: 'Notificações'),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: tabViews,
          ),
          bottomNavigationBar: Container(
            width: double.infinity,
            height: 80.0,
            decoration: BoxDecoration(
              color: hub ? HubMessagesTheme.surface : FleaberColors.bgTint,
              boxShadow: const [FleaberElevation.smNav],
              border: hub
                  ? const Border(
                      top: BorderSide(color: HubMessagesTheme.divider),
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        // Web: landing H01 (não Home clássica).
                        HubNavigation.goAppHome(context, replace: false);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.home_rounded,
                            color: Color(0xFF57636C),
                            size: 24.0,
                          ),
                          Text(
                            'Início',
                            style: FlutterFlowTheme.of(context)
                                .labelSmall
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF57636C),
                                  fontSize: 11.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                          ),
                        ].divide(const SizedBox(height: 4.0)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () =>
                          context.pushNamed(ListaConversasWidget.routeName),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Color(0xFF007782),
                                size: 24.0,
                              ),
                              Positioned(
                                right: -2.0,
                                top: -2.0,
                                child: FutureBuilder<bool>(
                                  future: _hasAnyUnreadMessages(),
                                  builder: (context, unreadSnapshot) {
                                    if (unreadSnapshot.data != true) {
                                      return const SizedBox.shrink();
                                    }
                                    return Container(
                                      width: 8.0,
                                      height: 8.0,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF007782),
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Mensagens',
                            style: FlutterFlowTheme.of(context).labelSmall.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF007782),
                                  fontSize: 11.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                          ),
                        ].divide(const SizedBox(height: 4.0)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: _showCreateBottomSheet,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 53.0,
                            height: 53.0,
                            decoration: const BoxDecoration(
                              color: Color(0xFF007782),
                              shape: BoxShape.circle,
                            ),
                            child: const Align(
                              alignment: AlignmentDirectional(0.0, 0.0),
                              child: Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 28.0,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 2.0, 0.0, 0.0),
                            child: Text(
                              'Vender',
                              style:
                                  FlutterFlowTheme.of(context).labelSmall.override(
                                        font: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontStyle: FlutterFlowTheme.of(context)
                                              .labelSmall
                                              .fontStyle,
                                        ),
                                        color: const Color(0xFF007782),
                                        fontSize: 11.0,
                                        letterSpacing: 0.0,
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelSmall
                                            .fontStyle,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () => context.pushNamed(PerfilWidget.routeName),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF57636C),
                            size: 24.0,
                          ),
                          Text(
                            'Perfil',
                            style: FlutterFlowTheme.of(context).labelSmall.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF57636C),
                                  fontSize: 11.0,
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelSmall
                                      .fontStyle,
                                ),
                          ),
                        ].divide(const SizedBox(height: 4.0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }
}

class _FavoriteNotificationItem {
  const _FavoriteNotificationItem({
    required this.notificationId,
    required this.likerId,
    required this.likerName,
    required this.likerPhotoUrl,
    required this.productId,
    required this.productTitle,
    required this.createdAt,
    this.kind = 'favorite',
    this.helperLinkId,
    this.chatId,
    this.inboxTitle,
    this.isRead,
    this.dedupeKey,
  });

  final String? notificationId;
  final String likerId;
  final String likerName;
  final String? likerPhotoUrl;
  final String? productId;
  final String productTitle;
  final DateTime? createdAt;
  final String kind;
  final String? helperLinkId;
  final String? chatId;
  final String? inboxTitle;
  final bool? isRead;
  final String? dedupeKey;

  bool get isPriceOffer =>
      kind == 'price_offer' || kind == 'price_offer_counter';

  bool get isBundleNotif =>
      kind == 'bundle_proposal' ||
      kind == 'bundle_proposal_counter' ||
      kind == 'bundle_purchase_request';

  /// Notificações com título próprio (não «gostou do artigo»).
  bool get usesInboxTitle =>
      isPriceOffer ||
      isBundleNotif ||
      isHelperInvitation ||
      FleaberNotificationsInbox.isOrderLifecycleKind(kind) ||
      kind == 'seguro_fleaber_paid' ||
      kind == 'chat_message';

  bool get isHelperInvitation => kind.startsWith('helper_invitation');

  UserNotificationsRow toNotificationsRow() => UserNotificationsRow({
        'id': notificationId,
        'kind': kind,
        'title': inboxTitle,
        'body': productTitle,
        'chat_id': chatId,
        'product_id': productId,
        'actor_id': likerId,
        'dedupe_key': dedupeKey,
        'is_read': isRead == true,
      });
}
