import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/hub/hub_account_routes.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_notification_copy.dart';
import '/utils/fleaber_notifications_inbox.dart';
import '/utils/fleaber_radius.dart';
import '/flutter_flow/flutter_flow_util.dart';

import 'fleahub_site_chrome.dart';

/// Sino + painel do centro de notificações (FleaHub topbar).
/// Reutiliza `user_notifications` + RLS existentes — sem schema novo.
class FleaHubNotificationBell extends StatefulWidget {
  const FleaHubNotificationBell({
    super.key,
    this.onOpenBag,
    this.dense = false,
  });

  /// Abrir saco Hub (reservas sem chat associado).
  final VoidCallback? onOpenBag;

  /// Ícones mais compactos na topbar mobile/tablet.
  final bool dense;

  @override
  State<FleaHubNotificationBell> createState() =>
      _FleaHubNotificationBellState();
}

class _FleaHubNotificationBellState extends State<FleaHubNotificationBell> {
  Future<int>? _countFuture;
  int _countTick = -1;
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  bool _panelOpen = false;

  @override
  void initState() {
    super.initState();
    notificationBadgeRefreshTick.addListener(_onBadgeTick);
    AppStateNotifier.instance.addListener(_onAuth);
  }

  @override
  void dispose() {
    notificationBadgeRefreshTick.removeListener(_onBadgeTick);
    AppStateNotifier.instance.removeListener(_onAuth);
    _removeOverlay();
    super.dispose();
  }

  void _onBadgeTick() {
    if (!mounted) return;
    setState(() {
      _countFuture = null;
      _countTick = -1;
    });
  }

  void _onAuth() {
    if (!mounted) return;
    _removeOverlay();
    setState(() {
      _countFuture = null;
      _countTick = -1;
    });
  }

  Future<int> _countForTick() {
    final tick = notificationBadgeRefreshTick.value;
    if (_countFuture == null || _countTick != tick) {
      _countTick = tick;
      _countFuture = FleaberNotificationsInbox.unreadCount();
    }
    return _countFuture!;
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
    _panelOpen = false;
  }

  Future<void> _togglePanel() async {
    if (currentUserUid.isEmpty) return;
    if (_panelOpen) {
      setState(() => _removeOverlay());
      return;
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (!wide) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _NotificationPanelSheet(
          onOpenBag: widget.onOpenBag,
          onClose: () => Navigator.of(ctx).maybePop(),
        ),
      );
      if (mounted) setState(() {});
      return;
    }

    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _removeOverlay();
                  setState(() {});
                },
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: const Offset(-280, 48),
              child: Material(
                color: Colors.transparent,
                child: _NotificationPanelCard(
                  width: 360,
                  maxHeight: 440,
                  onOpenBag: widget.onOpenBag,
                  onClose: () {
                    _removeOverlay();
                    setState(() {});
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    setState(() => _panelOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserUid.isEmpty) return const SizedBox.shrink();

    return CompositedTransformTarget(
      link: _link,
      child: ValueListenableBuilder<int>(
        valueListenable: notificationBadgeRefreshTick,
        builder: (context, _, __) {
          return FutureBuilder<int>(
            key: ValueKey<int>(notificationBadgeRefreshTick.value),
            future: _countForTick(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              final dense = widget.dense;
              return IconButton(
                tooltip: 'Notificações',
                onPressed: () => unawaited(_togglePanel()),
                padding: EdgeInsets.all(dense ? 6 : 8),
                constraints: BoxConstraints(
                  minWidth: dense ? 40 : 44,
                  minHeight: dense ? 40 : 44,
                ),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Icon(
                    _panelOpen
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    color: FleaberColors.teal,
                    size: dense ? 24 : 26,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationPanelSheet extends StatelessWidget {
  const _NotificationPanelSheet({
    required this.onClose,
    this.onOpenBag,
  });

  final VoidCallback onClose;
  final VoidCallback? onOpenBag;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: h,
            decoration: const BoxDecoration(
              color: FleaberColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: _NotificationPanelCard(
              width: double.infinity,
              maxHeight: h,
              onOpenBag: onOpenBag,
              onClose: onClose,
              sheetHandle: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationPanelCard extends StatefulWidget {
  const _NotificationPanelCard({
    required this.width,
    required this.maxHeight,
    required this.onClose,
    this.onOpenBag,
    this.sheetHandle = false,
  });

  final double width;
  final double maxHeight;
  final VoidCallback onClose;
  final VoidCallback? onOpenBag;
  final bool sheetHandle;

  @override
  State<_NotificationPanelCard> createState() => _NotificationPanelCardState();
}

class _NotificationPanelCardState extends State<_NotificationPanelCard> {
  late Future<List<UserNotificationsRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = FleaberNotificationsInbox.listRecent();
    notificationBadgeRefreshTick.addListener(_onBadgeTick);
  }

  @override
  void dispose() {
    notificationBadgeRefreshTick.removeListener(_onBadgeTick);
    super.dispose();
  }

  void _onBadgeTick() {
    if (!mounted) return;
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _future = FleaberNotificationsInbox.listRecent());
  }

  String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays < 7) return '${diff.inDays} d';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }

  String _titleFor(UserNotificationsRow n) {
    return fleaberNotificationInboxTitle(
      kind: n.kind ?? '',
      inboxTitle: n.title,
      likerName: 'Utilizador',
      productTitle: n.body ?? '',
    );
  }

  IconData _iconFor(UserNotificationsRow n) {
    switch (FleaberNotificationsInbox.destinationFor(n)) {
      case FleaberNotificationDestination.orders:
        return Icons.local_shipping_outlined;
      case FleaberNotificationDestination.bag:
        return Icons.shopping_bag_outlined;
      case FleaberNotificationDestination.product:
        return Icons.inventory_2_outlined;
      case FleaberNotificationDestination.helperInvite:
        return Icons.handshake_outlined;
      case FleaberNotificationDestination.wallet:
        return Icons.account_balance_wallet_outlined;
      case FleaberNotificationDestination.chat:
      case FleaberNotificationDestination.messagesInbox:
        return Icons.chat_bubble_outline_rounded;
      case FleaberNotificationDestination.none:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(
          widget.sheetHandle ? 0 : FleaberRadius.md,
        ),
        border: widget.sheetHandle
            ? null
            : Border.all(color: FleaberColors.alternate),
        boxShadow: widget.sheetHandle ? null : const [FleaberElevation.md],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sheetHandle) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: FleaberColors.alternate,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Notificações',
                    style: GoogleFonts.inter(
                      color: FleaberColors.text,
                      fontSize: FleaHubSiteLayout.typeSection,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await FleaberNotificationsInbox.markAllRead();
                    await _reload();
                  },
                  child: Text(
                    'Marcar lidas',
                    style: GoogleFonts.inter(
                      color: FleaberColors.teal,
                      fontWeight: FontWeight.w700,
                      fontSize: FleaHubSiteLayout.typeCaption,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<UserNotificationsRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: FleaberColors.teal,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 36,
                          color: FleaberColors.muted.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ainda não tens notificações',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: FleaberColors.muted,
                            fontSize: FleaHubSiteLayout.typeBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: FleaberColors.alternate.withValues(alpha: 0.7),
                  ),
                  itemBuilder: (context, i) {
                    final n = rows[i];
                    final unread = n.isRead != true;
                    return InkWell(
                      onTap: () async {
                        widget.onClose();
                        await FleaberNotificationsInbox.openDestination(
                          context,
                          n,
                          onOpenBag: widget.onOpenBag,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: FleaberColors.bgTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _iconFor(n),
                                size: 18,
                                color: FleaberColors.teal,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _titleFor(n),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: FleaberColors.text,
                                      fontSize: FleaHubSiteLayout.typeBody,
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                  if ((n.body ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      n.body!.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: FleaberColors.muted,
                                        fontSize:
                                            FleaHubSiteLayout.typeSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _when(n.createdAt),
                                    style: GoogleFonts.inter(
                                      color: FleaberColors.muted
                                          .withValues(alpha: 0.85),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (unread)
                              Container(
                                margin: const EdgeInsets.only(left: 6, top: 4),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: FleaberColors.danger,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: TextButton(
              onPressed: () {
                widget.onClose();
                HubAccountRoutes.openNotificacoes(context);
              },
              child: Text(
                'Ver todas em Mensagens',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w800,
                  fontSize: FleaHubSiteLayout.typeBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
