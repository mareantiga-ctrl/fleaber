import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/batata_reservation_actions.dart';
import '/batata_offer_actions.dart';
import '/widgets/product_offer_sheet.dart';
import '/bundle_order_status_util.dart';
import '/batata_bundle_actions.dart';
import '/chat_session_util.dart';
import '/utils/bundle_quote_flow.dart';
import '/widgets/bundle_proposal_chat_card.dart';
import '/widgets/bundle_chat_purchase_card.dart';
import '/widgets/bundle_expandable_summary.dart';
import '/widgets/bundle_accepted_checkout_sheet.dart';
import '/widgets/bundle_direct_payment_sheet.dart';
import '/widgets/price_offer_chat_card.dart';
import '/widgets/fleaber_chat_product_header_card.dart';
import '/hub/hub_actions.dart';
import '/hub/theme/hub_messages_theme.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_apply.dart';
import '/order_cancel_eligibility.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/profile_avatar.dart';
import '/utils/fleaber_private_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '/utils/batata_admin_util.dart';
import '/utils/bundle_price_display.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_notify_emit.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_paid_sale_chat.dart';
import '/utils/fleaber_stripe_refund.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_chat_spacing.dart';
import '/utils/fleaber_chat_system_copy.dart';
import '/utils/live_raffle_prize_copy.dart';
import '/utils/reservation_reminder_timing.dart';
import '/widgets/dpd_tracking_sheet.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_raffle_prize_shipping_sheet.dart';
import '/widgets/order_weight_confirm_sheet.dart';
import '/pages/bundle/juntar_ao_premio_page_widget.dart';
import '/utils/return_label.dart';
import '/utils/dpd_expedition_service.dart';
import '/utils/fleaber_dispute_card_title.dart';
import '/perfil_vendedor/perfil_vendedor_widget.dart';
import '/hub/theme/hub_theme.dart';
import 'chat_page_model.dart';
export 'chat_page_model.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Chave extra para abrir checkout ao navegar para o detalhe (sincronizar com `ProductDetailsPageWidget.routeExtraOpenCheckoutKey`).
const String _kFleaberOpenCheckoutExtra = '__fleaber_open_checkout__';

/// Mesmo valor que `ProductDetailsPageWidget.routeExtraProductKey` (evita import circular).
const String _kProductRouteExtraKey = '__fleaber_product_row__';

/// Mínimo de caracteres na descrição ao abrir disputa (APP-058).
const int _kDisputeDescriptionMinChars = 6;

String _normalizeDisputeDescription(String raw) {
  return raw
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .trim();
}

/// Item da lista do chat (mensagem ou cards injectados no scroll).
class _MergedChatItem {
  const _MergedChatItem.message(this.message, this.sourceIndex)
      : injectKind = _MergedInjectKind.none;

  const _MergedChatItem.shipping()
      : message = null,
        sourceIndex = -1,
        injectKind = _MergedInjectKind.shipping;

  const _MergedChatItem.reservationPendingInjected()
      : message = null,
        sourceIndex = -2,
        injectKind = _MergedInjectKind.reservationPending;

  const _MergedChatItem.bundlePurchase()
      : message = null,
        sourceIndex = -3,
        injectKind = _MergedInjectKind.bundlePurchase;

  const _MergedChatItem.bundleShipped()
      : message = null,
        sourceIndex = -4,
        injectKind = _MergedInjectKind.bundleShipped;

  final ChatMessagesRow? message;
  final int sourceIndex;
  final _MergedInjectKind injectKind;

  bool get isShippingCard => injectKind == _MergedInjectKind.shipping;
  bool get isBundlePurchaseCard =>
      injectKind == _MergedInjectKind.bundlePurchase;
  bool get isBundleShippedCard => injectKind == _MergedInjectKind.bundleShipped;
  bool get isReservationPendingInjected =>
      injectKind == _MergedInjectKind.reservationPending;
}

enum _MergedInjectKind {
  none,
  shipping,
  reservationPending,
  bundlePurchase,
  bundleShipped,
}

class _DisputeThread {
  const _DisputeThread({
    required this.dispute,
    required this.replies,
  });

  final OrderDisputesRow dispute;
  final List<OrderDisputeRepliesRow> replies;
}

class _DisputeInfoLine extends StatelessWidget {
  const _DisputeInfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF3D4A55),
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _DisputeReplyTile extends StatelessWidget {
  const _DisputeReplyTile({
    required this.reply,
    required this.isMine,
  });

  final OrderDisputeRepliesRow reply;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final date = reply.createdAt == null
        ? ''
        : DateFormat('dd MMM, HH:mm', 'pt_PT').format(reply.createdAt!.toLocal());
    return Container(
      margin: const EdgeInsets.only(bottom: kChatMessageItemSpacing),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFFE6F7F5) : Colors.white,
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(color: const Color(0xFFE6D8C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMine ? 'Tu' : 'Outra parte',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF7C3E00),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reply.message ?? '',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              color: const Color(0xFF101518),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reply.proofPhotos.isNotEmpty) ...[
            const SizedBox(height: kChatMessageItemSpacing),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reply.proofPhotos.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: kChatMessageItemSpacing),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: FleaberRadius.circularSm,
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: BatataCachedNetworkImage(
                      imageUrl: reply.proofPhotos[index],
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (date.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              date,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF57636C),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatPageWidget extends StatefulWidget {
  const ChatPageWidget({
    super.key,
    this.otherUserId,
    this.chatId,
    this.orderId,
    this.requestCancelOnOpen = false,
    this.hubPanelMode = false,
    this.onHubPanelClose,
  });

  final String? otherUserId;
  final String? chatId;
  /// Encomenda concreta (ex. compra concluída no histórico de referências).
  final String? orderId;

  /// Abrir o chat a partir das encomendas e enviar já o pedido de cancelamento (comprador).
  final bool requestCancelOnOpen;

  /// Web P10 desktop: embutido no painel direito (sem pop da rota lista).
  /// Android / rota normal: manter `false`.
  final bool hubPanelMode;

  /// Fechar painel (limpar selecção na lista). Só usado com [hubPanelMode].
  final VoidCallback? onHubPanelClose;

  static String get routeName => 'ChatPage';
  static String get routePath => '/chatPage';

  @override
  State<ChatPageWidget> createState() => _ChatPageWidgetState();
}

class _ChatPageWidgetState extends State<ChatPageWidget> {
  late ChatPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _messagesScrollController = ScrollController();

  static const Color _kTeal = Color(0xFF007782);
  static final BorderRadius _stickyBarBtnRadius = BorderRadius.circular(10);
  static const int _kMinChatLetters = 2;

  ProfilesRow? _otherUser;
  bool _otherUserIsAdmin = false;
  ChatsRow? _chat;
  ProductsRow? _product;
  OrdersRow? _orderForChat;
  /// Encomendas do par comprador/vendedor neste artigo (para cards por order_id).
  final Map<String, OrdersRow> _ordersByIdForChat = {};
  List<OrdersRow> _bundleOrdersForChat = [];
  List<OrdersRow> _bundlePaidTimelineOrders = [];
  String? _focusedBundleId;
  String? _focusedBundleStatus;
  String? _bundlePaidTimelineBundleId;
  Map<String, dynamic>? _focusedBundleMeta;
  double? _focusedBundleItemsTotalEur;
  final Set<String> _bundleLinkedOrderIds = {};
  Map<String, ProductsRow> _bundleChatProducts = {};
  bool _bundleHeaderExpanded = false;
  bool _bundleHeaderMsgHydrateBusy = false;
  List<ChatMessagesRow> _lastChatMessagesForMerge = const [];
  bool _metaReady = false;
  Timer? _orderRefreshTimer;
  bool _cancelChatBusy = false;
  bool _routeCancelHandled = false;
  bool _shippingLabelActionBusy = false;
  int? _lastChatMessageIdSeenForOrderSync;
  bool _reservationChatBusy = false;
  bool _offerChatBusy = false;
  ProductOffersRow? _pendingBuyerOffer;
  bool _reservationReminderBusy = false;
  bool _feedbackBusy = false;
  bool _disputeBusy = false;
  bool _buyerFeedbackDone = false;
  bool _sellerFeedbackDone = false;
  String? _localDisputeOpenedOrderId;
  String? _disputeThreadOrderId;
  Future<_DisputeThread?>? _disputeThreadFuture;
  _DisputeThread? _disputeThreadCache;
  int? _lastAutoScrolledMessageId;
  Timer? _reservationUiTimer;
  final Map<String, Future<String>> _chatImageResolveCache = {};

  Future<String> _resolvedChatImageUrl(String imageUrl) =>
      _chatImageResolveCache.putIfAbsent(
        imageUrl,
        () => FleaberPrivateStorage.resolveChatImageUrl(imageUrl),
      );

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ChatPageModel());
    _model.inputMensagemTextController ??= TextEditingController();
    _model.inputMensagemFocusNode ??= FocusNode();
    ChatMessagesTable().update(
      data: {'is_read': true},
      matchingRows: (rows) => rows
          .eqOrNull('receiver_id', currentUserUid)
          .eqOrNull('chat_id', widget.chatId)
          .eqOrNull('is_read', false),
    );
    _loadMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
    _orderRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final pid = _product?.id;
      if (!mounted || pid == null || pid.isEmpty) return;
      await _loadOrderForChat(pid);
      if (!mounted) return;
      await _maybeInsertReservationReminderFromDb();
      if (mounted) setState(() {});
    });
    _reservationUiTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      final pid = _product?.id;
      if (!mounted || pid == null || pid.isEmpty) return;
      final o = _orderForChat;
      if (o != null &&
          (normalizeOrderStatusKey(o.status) == 'reservado' ||
              normalizeOrderStatusKey(o.status) == 'reserva_pendente')) {
        setState(() {});
      }
    });
  }

  String? _otherUserIdFromChat(ChatsRow chat) {
    final me = currentUserUid;
    if (chat.userA == me) return chat.userB;
    if (chat.userB == me) return chat.userA;
    return null;
  }

  String? _resolvedOtherUserId() {
    final fromWidget = widget.otherUserId?.trim() ?? '';
    if (fromWidget.isNotEmpty) return fromWidget;
    final fromProfile = _otherUser?.id?.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final chat = _chat;
    if (chat == null) return null;
    return _otherUserIdFromChat(chat)?.trim();
  }

  Future<void> _loadMeta() async {
    final cid = widget.chatId;
    var uid = widget.otherUserId?.trim() ?? '';

    if (cid != null && cid.isNotEmpty) {
      final chatRows = await ChatsTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', cid),
      );
      _chat = chatRows.isNotEmpty ? chatRows.first : null;
      if (uid.isEmpty && _chat != null) {
        uid = _otherUserIdFromChat(_chat!)?.trim() ?? '';
      }
    }

    if (uid.isEmpty) {
      if (mounted) setState(() => _metaReady = true);
      return;
    }

    final profileRows = await ProfilesDirectoryTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', uid),
    );
    _otherUser = profileRows.isNotEmpty ? profileRows.first : null;
    _otherUserIsAdmin = batataIsAdminUserType(_otherUser?.userType);

    if (_chat != null) {
      final pid = _chat?.productId;
      if (pid != null && pid.isNotEmpty) {
        final prows = await ProductsTable().querySingleRow(
          queryFn: (q) => q.eqOrNull('id', pid),
        );
        _product = prows.isNotEmpty ? prows.first : null;
        await _loadOrderForChat(pid);
        await _loadPendingBuyerOffer();
        // Maestro/autologin: o chat abre antes do uid estar pronto → sticky vazio.
        if (_orderForChat == null && currentUserUid.isEmpty) {
          for (var i = 0; i < 8 && mounted; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            if (currentUserUid.isEmpty) continue;
            await _loadOrderForChat(pid);
            await _loadPendingBuyerOffer();
            break;
          }
        }
      } else {
        // Chat sem product_id (ou só âncora vazia): mesmo assim carregar
        // conjunto operacional pendente/aceite para o header H10.
        await _loadBundleOrdersForChat();
      }
      // Reforço: pedido de conjunto (pending) tem de mandar no assunto
      // visual — nunca ficar só com o 1.º product_id do chat.
      if (_bundleOrdersForChat.length < 2) {
        await _loadBundleOrdersForChat();
      }
    }

    if (mounted) {
      setState(() => _metaReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _maybeInsertReservationReminderFromDb();
      });
      if (widget.requestCancelOnOpen && !_routeCancelHandled) {
        _routeCancelHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _onBuyerRequestCancel();
          if (mounted) setState(() {});
        });
      }
    }
  }

  /// Prioridade ao abrir chat do mesmo artigo com várias encomendas (CHAT-MULTI).
  OrdersRow? _pickPreferredOrderForChat(Iterable<OrdersRow> rows) {
    const priority = <String>[
      'reserva_pendente',
      'reservado',
      'aguarda_confirmacao',
      'pago',
      'enviado',
      'concluido',
    ];
    final list = rows.toList();
    for (final key in priority) {
      for (final o in list) {
        if (normalizeOrderStatusKey(o.status) == key) return o;
      }
    }
    for (final o in list) {
      if (!orderIsCancelled(o.status)) return o;
    }
    return null;
  }

  Future<void> _loadOrderForChat(String productId) async {
    if (productId.isEmpty) return;
    final pinnedOrderId = widget.orderId?.trim() ?? '';
    final chatId = widget.chatId?.trim() ?? '';

    void cacheOrders(Iterable<OrdersRow> list) {
      for (final o in list) {
        final id = o.id?.trim() ?? '';
        if (id.isNotEmpty) _ordersByIdForChat[id] = o;
      }
    }

    // 1) orderId da rota (explícito) — respeitar sempre se não estiver cancelado.
    if (pinnedOrderId.isNotEmpty) {
      final pinned = await OrdersTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', pinnedOrderId),
      );
      if (pinned.isNotEmpty) {
        cacheOrders(pinned);
        if (!orderIsCancelled(pinned.first.status)) {
          _orderForChat = pinned.first;
          final loadedOrderId = _orderForChat?.id;
          if (loadedOrderId != _disputeThreadOrderId) {
            _disputeThreadOrderId = null;
            _disputeThreadFuture = null;
            _disputeThreadCache = null;
          }
          await _loadBundleOrdersForChat();
          await _syncFeedbackFlagsFromReviews();
          return;
        }
      }
    }

    final otherId = _resolvedOtherUserId();
    if (otherId == null || otherId.isEmpty || currentUserUid.isEmpty) {
      // Ainda assim carregar conjunto do chat (pedido pending) — não
      // depender de encomenda individual / uid para o header H10.
      await _loadBundleOrdersForChat();
      return;
    }
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('product_id', productId)
          .or(
            'and(buyer_id.eq.$currentUserUid,seller_id.eq.$otherId),and(buyer_id.eq.$otherId,seller_id.eq.$currentUserUid)',
          )
          .order('created_at', ascending: false),
      limit: 20,
    );
    cacheOrders(rows);

    // 2) Mensagens do chat → candidatos; escolher por prioridade de estado
    // (não o 1.º JSON antigo de uma venda concluída).
    if (chatId.isNotEmpty) {
      final referencedIds = await _orderIdsReferencedInChat(chatId);
      if (referencedIds.isNotEmpty) {
        final byId = <String, OrdersRow>{
          for (final o in rows)
            if ((o.id ?? '').isNotEmpty) o.id!: o,
        };
        final referencedOrders = <OrdersRow>[];
        for (final id in referencedIds) {
          final hit = byId[id];
          if (hit != null) {
            referencedOrders.add(hit);
            continue;
          }
          try {
            final fetched = await OrdersTable().querySingleRow(
              queryFn: (q) => q.eqOrNull('id', id),
            );
            if (fetched.isNotEmpty) {
              cacheOrders(fetched);
              referencedOrders.add(fetched.first);
            }
          } catch (_) {}
        }
        final preferred = _pickPreferredOrderForChat(referencedOrders);
        if (preferred != null) {
          _orderForChat = preferred;
          final loadedOrderId = _orderForChat?.id;
          if (loadedOrderId != _disputeThreadOrderId) {
            _disputeThreadOrderId = null;
            _disputeThreadFuture = null;
            _disputeThreadCache = null;
          }
          await _loadBundleOrdersForChat();
          await _syncFeedbackFlagsFromReviews();
          return;
        }
        // CHAT-MULTI: este chat referencia encomendas, mas nenhuma activa.
        // Não importar a compra nova de outra conversa (card inject «clonava»).
        if (referencedOrders.isNotEmpty || referencedIds.isNotEmpty) {
          _orderForChat = null;
          _disputeThreadOrderId = null;
          _disputeThreadFuture = null;
          _disputeThreadCache = null;
          await _loadBundleOrdersForChat();
          await _syncFeedbackFlagsFromReviews();
          return;
        }
      }
    }

    _orderForChat = _pickPreferredOrderForChat(rows);
    final loadedOrderId = _orderForChat?.id;
    if (loadedOrderId != _disputeThreadOrderId) {
      _disputeThreadOrderId = null;
      _disputeThreadFuture = null;
      _disputeThreadCache = null;
    }
    await _maybeSimulateReturnDelivery();
    await _loadBundleOrdersForChat();
    await _syncFeedbackFlagsFromReviews();
  }

  /// IDs de encomenda referidos nas mensagens (mais recentes primeiro).
  Future<List<String>> _orderIdsReferencedInChat(String chatId) async {
    final cid = chatId.trim();
    if (cid.isEmpty) return const [];
    try {
      final messages = await ChatMessagesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('chat_id', cid)
            .eqOrNull('is_reservation', true)
            .order('created_at', ascending: false),
        limit: 50,
      );
      final out = <String>[];
      final seen = <String>{};
      for (final m in messages) {
        final p = _tryParseFleaberChatJson(m.text);
        if (p == null) continue;
        final oid = p['order_id']?.toString().trim() ?? '';
        if (oid.isEmpty || !seen.add(oid)) continue;
        out.add(oid);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Compat: primeiro candidato útil (legado).
  Future<String?> _orderIdReferencedInChat(String chatId) async {
    final ids = await _orderIdsReferencedInChat(chatId);
    return ids.isEmpty ? null : ids.first;
  }

  Future<void> _syncFeedbackFlagsFromReviews() async {
    final candidates = <OrdersRow>[
      if (_orderForChat != null) _orderForChat!,
      ..._bundleActivePaidOrders,
      ..._bundlePaidTimelineOrders,
    ];
    final ids = <String>{};
    for (final o in candidates) {
      final id = o.id?.trim() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return;
    var buyerDone = _buyerFeedbackDone;
    var sellerDone = _sellerFeedbackDone;
    try {
      for (final oid in ids) {
        final existing = await ReviewsTable().queryRows(
          queryFn: (q) => q.eqOrNull('order_id', oid),
          limit: 10,
        );
        if (existing.any((r) => _isBuyerFeedbackRole(r.authorRole))) {
          buyerDone = true;
        }
        if (existing.any((r) => _isSellerFeedbackRole(r.authorRole))) {
          sellerDone = true;
        }
      }
    } catch (_) {}
    _buyerFeedbackDone = buyerDone;
    _sellerFeedbackDone = sellerDone;
  }

  Future<void> _loadBundleOrdersForChat() async {
    _bundleOrdersForChat = [];
    _bundlePaidTimelineOrders = [];
    _bundleChatProducts = {};
    _focusedBundleId = null;
    _focusedBundleStatus = null;
    _bundlePaidTimelineBundleId = null;
    _focusedBundleMeta = null;
    _focusedBundleItemsTotalEur = null;
    _bundleLinkedOrderIds.clear();

    final chatId = widget.chatId?.trim() ?? '';

    Map<String, dynamic>? opBundle;

    if (chatId.isNotEmpty) {
      opBundle = await fetchLatestOperationalBundleForChat(chatId);
      if (opBundle != null) {
        _focusedBundleMeta = opBundle;
        final bid = opBundle['id']?.toString().trim() ?? '';
        _focusedBundleId = bid.isEmpty ? null : bid;
        _focusedBundleStatus = opBundle['status']?.toString();
        _focusedBundleItemsTotalEur =
            (opBundle['total_eur'] as num?)?.toDouble();

        if (bid.isNotEmpty) {
          if (_focusedBundleStatus == 'accepted') {
            final rows = await OrdersTable().queryRows(
              queryFn: (q) => q.eqOrNull('bundle_id', bid),
              limit: 20,
            );
            if (rows.length >= 2) {
              _bundleOrdersForChat = [...rows]
                ..sort((a, b) {
                  final ta =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final tb =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return ta.compareTo(tb);
                });
              if (bundleAllOrdersPaidOrBeyond(_bundleOrdersForChat)) {
                _bundlePaidTimelineOrders = [..._bundleOrdersForChat];
                _bundlePaidTimelineBundleId = bid;
              }
            } else {
              _bundleOrdersForChat =
                  await buildBundleDisplayOrdersFromMeta(opBundle);
            }
          } else if (_focusedBundleStatus == 'pending' ||
              _focusedBundleStatus == 'awaiting_payment') {
            _bundleOrdersForChat =
                await buildBundleDisplayOrdersFromMeta(opBundle);
          }
          // Fallback: product_ids mal tipados / produtos ainda a carregar →
          // reconstruir a partir da mensagem bundle_proposal do chat.
          if (_bundleOrdersForChat.length < 2) {
            final fromMsg =
                await buildBundleDisplayOrdersFromLatestChatMessage(chatId);
            if (fromMsg.length >= 2) {
              _bundleOrdersForChat = fromMsg;
            }
          }
          for (final o in _bundleOrdersForChat) {
            final oid = o.id?.trim();
            if (oid != null && oid.isNotEmpty) {
              _bundleLinkedOrderIds.add(oid);
            }
          }
        }
      } else {
        final latest = await fetchLatestBundleMetaForChat(chatId);
        if (latest != null) {
          _focusedBundleMeta = latest;
          final bid = latest['id']?.toString().trim() ?? '';
          _focusedBundleId = bid.isEmpty ? null : bid;
          _focusedBundleStatus = latest['status']?.toString();
          _focusedBundleItemsTotalEur =
              (latest['total_eur'] as num?)?.toDouble();
          if (bid.isNotEmpty) {
            _bundleOrdersForChat =
                await buildBundleDisplayOrdersFromMeta(latest);
            if (_bundleOrdersForChat.length < 2) {
              final fromMsg =
                  await buildBundleDisplayOrdersFromLatestChatMessage(chatId);
              if (fromMsg.length >= 2) {
                _bundleOrdersForChat = fromMsg;
              }
            }
            for (final o in _bundleOrdersForChat) {
              final oid = o.id?.trim();
              if (oid != null && oid.isNotEmpty) {
                _bundleLinkedOrderIds.add(oid);
              }
            }
          }
        } else {
          final fromMsg =
              await buildBundleDisplayOrdersFromLatestChatMessage(chatId);
          if (fromMsg.length >= 2) {
            _bundleOrdersForChat = fromMsg;
            _focusedBundleStatus ??= 'pending';
          }
        }
      }
    }

    // NÃO ir buscar conjuntos por product_id noutros chats — isso misturava
    // a rifa antiga na conversa nova (APP-216b-CHAT-NEW). Bundles só via chat_id
    // (acima) ou bundle_id da encomenda DESTE chat (abaixo).

    final bid = _orderForChat?.bundleId?.trim() ?? '';
    if (bid.isNotEmpty &&
        _bundleOrdersForChat.isEmpty &&
        _focusedBundleStatus != 'pending') {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('bundle_id', bid),
        limit: 20,
      );
      if (rows.length >= 2) {
        _bundleOrdersForChat = rows;
        _focusedBundleId ??= bid;
        if (bundleAllOrdersPaidOrBeyond(rows)) {
          _bundlePaidTimelineOrders = [...rows]
            ..sort((a, b) {
              final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return ta.compareTo(tb);
            });
          _bundlePaidTimelineBundleId = bid;
        }
        for (final o in rows) {
          final oid = o.id?.trim();
          if (oid != null && oid.isNotEmpty) {
            _bundleLinkedOrderIds.add(oid);
          }
        }
      }
    }

    final pids = <String>{
      ..._bundleOrdersForChat.map((o) => o.productId).whereType<String>(),
      ..._bundlePaidTimelineOrders.map((o) => o.productId).whereType<String>(),
    };
    final metaForPids = opBundle ?? _focusedBundleMeta;
    if (metaForPids != null) {
      final rawIds = metaForPids['product_ids'];
      if (rawIds is List) {
        for (final id in rawIds) {
          final s = id.toString().trim();
          if (s.isNotEmpty) pids.add(s);
        }
      }
    }
    final pidList = pids.where((s) => s.isNotEmpty).toList();
    if (pidList.isEmpty) return;

    final prows = await ProductsTable().queryRows(
      queryFn: (q) => q.inFilter('id', pidList),
      limit: pidList.length,
    );
    for (final p in prows) {
      if (p.id != null) _bundleChatProducts[p.id!] = p;
    }
  }

  Future<void> _refreshBundleProposalThreadState({String? productId}) async {
    final chatId = widget.chatId?.trim() ?? '';
    if (chatId.isNotEmpty) {
      final rows = await ChatMessagesTable().queryRows(
        queryFn: (q) => q.eqOrNull('chat_id', chatId).order('created_at'),
        limit: 400,
      );
      _lastChatMessagesForMerge = rows;
    }
    _lastChatMessageIdSeenForOrderSync = null;
    _lastAutoScrolledMessageId = null;
    _model.containerSupabaseStream = null;
    await _loadBundleOrdersForChat();
    final pid = productId?.trim() ?? '';
    if (pid.isNotEmpty) {
      await _loadOrderForChat(pid);
    }
    await _loadPendingBuyerOffer();
  }

  bool get _isBundleChatContext => _bundleHeaderOrders.length >= 2;

  List<OrdersRow> get _bundleHeaderOrders {
    if (_focusedBundleStatus == 'pending' ||
        _focusedBundleStatus == 'awaiting_payment' ||
        _focusedBundleStatus == 'accepted' ||
        _focusedBundleStatus == 'cancelled' ||
        _focusedBundleStatus == 'expired') {
      if (_bundleOrdersForChat.length >= 2) return _bundleOrdersForChat;
    }
    if (_focusedBundleId != null &&
        _focusedBundleId != _bundlePaidTimelineBundleId &&
        _bundleOrdersForChat.length >= 2) {
      return _bundleOrdersForChat;
    }
    if (_bundlePaidTimelineOrders.length >= 2) {
      return _bundlePaidTimelineOrders;
    }
    return _bundleOrdersForChat;
  }

  bool get _bundleHeaderIsPrePayment =>
      _focusedBundleStatus == 'pending' ||
      _focusedBundleStatus == 'awaiting_payment' ||
      _focusedBundleStatus == 'accepted' ||
      _bundleHeaderOrders.any((o) {
        final s = normalizeOrderStatusKey(o.status);
        return s == 'reservado' || s == 'reserva_pendente';
      });

  String _bundleChatTotalLabel(List<OrdersRow> orders) {
    final audience = _isCurrentUserSellerInChat
        ? BundlePriceAudience.seller
        : BundlePriceAudience.buyer;
    return BundlePriceDisplay.forChatHeader(
      audience: audience,
      orders: orders,
      bundleMeta: _focusedBundleMeta,
      bundleStatus: _focusedBundleStatus,
    ).primaryAmount;
  }

  String _bundleChatTotalCaption(List<OrdersRow> orders) {
    final audience = _isCurrentUserSellerInChat
        ? BundlePriceAudience.seller
        : BundlePriceAudience.buyer;
    return BundlePriceDisplay.forChatHeader(
      audience: audience,
      orders: orders,
      bundleMeta: _focusedBundleMeta,
      bundleStatus: _focusedBundleStatus,
    ).primaryCaption;
  }

  String? _bundleChatTotalSubtitle(List<OrdersRow> orders) {
    if (_isCurrentUserSellerInChat) return null;
    return BundlePriceDisplay.forChatHeader(
      audience: BundlePriceAudience.buyer,
      orders: orders,
      bundleMeta: _focusedBundleMeta,
      bundleStatus: _focusedBundleStatus,
    ).subtitle;
  }

  bool get _isCurrentUserSellerInChat {
    final p = _product;
    if (p != null && p.sellerId == currentUserUid) return true;
    if (_bundleHeaderOrders.isNotEmpty &&
        _bundleHeaderOrders.first.sellerId == currentUserUid) {
      return true;
    }
    return _orderForChat?.sellerId == currentUserUid;
  }

  DateTime? _bundleAcceptanceAnchor() {
    final raw = _focusedBundleMeta?['responded_at'];
    if (raw is DateTime) return raw.toLocal();
    if (raw != null) {
      return DateTime.tryParse(raw.toString())?.toLocal();
    }
    return null;
  }

  DateTime? _orderLocalUpdatedAt(OrdersRow order) {
    final rawUpdated = order.data['updated_at'];
    if (rawUpdated is DateTime) return rawUpdated.toLocal();
    if (rawUpdated != null) {
      return DateTime.tryParse(rawUpdated.toString())?.toLocal();
    }
    return order.createdAt?.toLocal();
  }

  List<OrdersRow> _bundleChatOrdersForId(String bundleId) {
    if (bundleId.isEmpty) return const [];
    final seen = <String>{};
    final out = <OrdersRow>[];
    for (final o in [..._bundleOrdersForChat, ..._bundlePaidTimelineOrders]) {
      if (o.bundleId?.trim() != bundleId) continue;
      final oid = o.id?.trim() ?? '';
      if (oid.isNotEmpty && seen.contains(oid)) continue;
      if (oid.isNotEmpty) seen.add(oid);
      out.add(o);
    }
    return out;
  }

  bool _shouldHideReservationReminderMessage(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final kind = payload['kind']?.toString();
    if (_isCurrentUserSellerInChat &&
        kind == 'reservation_reminder') {
      return true;
    }
    if (kind == 'reservation_shipping_reminder' &&
        _bundleActivePaidOrders.length >= 2 &&
        (_sellerCanSimulateBundleShipment() || _bundleTimelineIsShipped())) {
      return true;
    }
    final bundleId = payload['bundle_id']?.toString().trim() ?? '';
    if (bundleId.isNotEmpty) {
      final orders = _bundleChatOrdersForId(bundleId);
      if (orders.length >= 2 && bundleAllOrdersPaidOrBeyond(orders)) {
        return true;
      }
    }
    final orderId = payload['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) return false;
    for (final o in [..._bundleOrdersForChat, ..._bundlePaidTimelineOrders]) {
      if (o.id == orderId) {
        final s = normalizeOrderStatusKey(o.status);
        return s == 'pago' ||
            s == 'premio_rifa' ||
            s == 'enviado' ||
            s == 'concluido';
      }
    }
    if (_orderForChat?.id == orderId) {
      final s = normalizeOrderStatusKey(_orderForChat?.status);
      return s == 'pago' ||
          s == 'premio_rifa' ||
          s == 'enviado' ||
          s == 'concluido';
    }
    return false;
  }

  bool _shouldOmitChatMessage(ChatMessagesRow message) {
    final payload = _tryParseFleaberChatJson(message.text);
    if (payload == null) return false;
    final kind = payload['kind']?.toString();
    if (kind == null) return false;
    const hiddenKinds = {
      'reservation_reminder',
      'reservation_payment_check_reminder',
      'reservation_shipping_reminder',
    };
    if (!hiddenKinds.contains(kind)) {
      if (kind == 'reservation_seller_confirmed_receipt' &&
          _isBundleReservationOutcomeMessage(payload)) {
        return true;
      }
      return false;
    }
    return _shouldHideReservationReminderMessage(payload);
  }

  bool get _hasAcceptedOperationalBundle =>
      _focusedBundleId != null &&
      _focusedBundleStatus == 'accepted' &&
      _bundleHeaderOrders.length >= 2;

  bool get _hasQuotedAwaitingPaymentBundle =>
      _focusedBundleId != null &&
      _focusedBundleStatus == 'awaiting_payment' &&
      _bundleHeaderOrders.length >= 2;

  OrdersRow? get _bundlePrimaryReservationOrder {
    if (_bundleHeaderOrders.isEmpty) return null;
    for (final o in _bundleHeaderOrders) {
      final st = normalizeOrderStatusKey(o.status);
      if (st == 'reservado' || st == 'aguarda_confirmacao') return o;
    }
    return _bundleHeaderOrders.first;
  }

  double _bundleTotalPaid(Iterable<OrdersRow> orders) {
    var sum = 0.0;
    for (final o in orders) {
      sum += o.priceTotal ?? 0;
    }
    return sum;
  }

  bool _bundleChatFullySold() {
    if (!_isBundleChatContext) return false;
    for (final o in _bundleHeaderOrders) {
      final p = _bundleChatProducts[o.productId ?? ''];
      if (p == null) continue;
      if (!p.isSold && p.quantity > 0) return false;
    }
    return true;
  }

  double _bundleChatTotalPaid() => _bundleTotalPaid(_bundleHeaderOrders);

  bool _isMarketplaceBagPaidPlainText(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return false;
    // Só conjunto — NÃO esconder «Compra paga…» de artigo único (CHAT-MULTI).
    return t.startsWith('Compra em conjunto paga através do Seguro Fleaber');
  }

  bool _shouldHideMarketplaceBagChatMessage(String? text) {
    if (_isMarketplaceBagPaidPlainText(text)) return true;
    final raw = text?.trim();
    if (raw == null || raw.isEmpty) return false;
    final payload = _tryParseFleaberChatJson(raw);
    return payload?['kind']?.toString() == 'marketplace_bag_paid';
  }

  /// Texto legado «Compra paga… [order:uuid]» — mostrar card, não bolha com UUID.
  bool _isLegacySeguroFleaberPaidPlainText(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return false;
    if (_isMarketplaceBagPaidPlainText(t)) return false;
    return t.startsWith('Compra paga através do Seguro Fleaber');
  }

  String _stripOrderMarkerFromChatText(String text) {
    return text
        .replaceAll(RegExp(r'\s*\[order:[0-9a-fA-F\-]+\]\s*'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  Widget _buildSeguroFleaberPaidCard({
    Map<String, dynamic>? payload,
    String? legacyPlainText,
    required bool forBuyer,
    List<ChatMessagesRow> allMessages = const [],
  }) {
    double? totalEur;
    final rawTotal = payload?['total'];
    if (rawTotal is num) {
      totalEur = rawTotal.toDouble();
    } else if (rawTotal != null) {
      totalEur = double.tryParse(rawTotal.toString().replaceAll(',', '.'));
    }
    if (totalEur == null && legacyPlainText != null) {
      final m = RegExp(r'\(([0-9]+[.,][0-9]{2})\s*€\)')
          .firstMatch(legacyPlainText);
      if (m != null) {
        totalEur = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      }
    }

    String? orderId = payload?['order_id']?.toString().trim();
    if ((orderId == null || orderId.isEmpty) && legacyPlainText != null) {
      final m = RegExp(r'\[order:([0-9a-fA-F\-]+)\]')
          .firstMatch(legacyPlainText);
      orderId = m?.group(1);
    }
    final cancelled = orderId != null &&
        orderId.isNotEmpty &&
        _chatShowsOrderCancelled(orderId, allMessages);
    final amountBit =
        totalEur != null && totalEur > 0 ? ' · ${formatEuros(totalEur)}' : '';

    if (cancelled) {
      return BundleChatPurchaseCard(
        key: ValueKey('seguro_paid_cancel_${orderId ?? 'x'}'),
        forBuyer: forBuyer,
        primaryLine: 'Compra cancelada',
        secondaryLine: forBuyer
            ? 'Esta compra foi cancelada$amountBit'
            : 'O comprador cancelou esta compra$amountBit',
        backgroundColor: const Color(0xFFFDECEC),
        borderColor: const Color(0xFFF1B0B0),
      );
    }

    final label = payload?['label']?.toString().trim();
    final labelBit =
        (label != null && label.isNotEmpty) ? ' · $label' : '';

    // Botão de envio no card desta encomenda se estiver paga e for a do card
    // (não depende de _orderForChat de outra thread).
    OrdersRow? cardOrder;
    if (orderId != null && orderId.isNotEmpty) {
      cardOrder = _ordersByIdForChat[orderId];
      if (cardOrder == null && _orderForChat?.id == orderId) {
        cardOrder = _orderForChat;
      }
    }
    final showShip = !forBuyer &&
        cardOrder != null &&
        !orderIsCancelled(cardOrder.status) &&
        _sellerCanSimulateShippingLabel(cardOrder);

    return BundleChatPurchaseCard(
      key: ValueKey('seguro_paid_${orderId ?? 'x'}'),
      forBuyer: forBuyer,
      primaryLine: forBuyer ? 'Comprado!' : 'Venda paga',
      secondaryLine: forBuyer
          ? 'Paga através do Seguro Fleaber$amountBit$labelBit'
          : 'Compra paga através do Seguro Fleaber$amountBit$labelBit',
      backgroundColor: _kShippingCardBg,
      borderColor: _kShippingCardBorder,
      showSellerShipButton: showShip,
      sellerShipBusy: _shippingLabelActionBusy,
      onSellerConfirmShipment: showShip
          ? () {
              // Garantir que a acção usa esta encomenda.
              if (cardOrder != null) _orderForChat = cardOrder;
              _onSellerConfirmShipment();
            }
          : null,
    );
  }

  /// Cancelada na BD **ou** com `cancel_request_outcome` aceite no próprio chat.
  bool _chatShowsOrderCancelled(
    String orderId,
    List<ChatMessagesRow> messages,
  ) {
    final oid = orderId.trim();
    if (oid.isEmpty) return false;
    final cached = _ordersByIdForChat[oid];
    if (cached != null && orderIsCancelled(cached.status)) return true;
    if (_orderForChat?.id == oid &&
        orderIsCancelled(_orderForChat?.status)) {
      return true;
    }
    for (final m in messages) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['order_id']?.toString().trim() != oid) continue;
      if (p['kind']?.toString() == 'cancel_request_outcome' &&
          p['outcome']?.toString() == 'accepted') {
        return true;
      }
    }
    return false;
  }

  static const String _kFleaberChatJsonPrefix = 'FLEABER_JSON_V1:';

  Map<String, dynamic>? _tryParseFleaberChatJson(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    // Canónico: FLEABER_JSON_V1:{...}
    // Legado (cron expire antigo): JSON bare com "kind" — ainda renderizar card.
    String jsonPart;
    if (raw.startsWith(_kFleaberChatJsonPrefix)) {
      jsonPart = raw.substring(_kFleaberChatJsonPrefix.length);
    } else if (raw.startsWith('{') && raw.contains('"kind"')) {
      jsonPart = raw;
    } else {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonPart);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _fleaberChatJsonEncode(Map<String, dynamic> m) =>
      _kFleaberChatJsonPrefix + jsonEncode(m);

  /// URL de imagem enviada no chat (payload novo ou legado só com link).
  String? _chatImageUrlFromMessage(String? text) {
    if (text == null || text.isEmpty) return null;
    final payload = _tryParseFleaberChatJson(text);
    if (payload != null) {
      if (payload['kind']?.toString() == 'chat_image') {
        // Preferir URL assinada já persistida (útil em seeds / TTL); senão path
        // privado para re-assinatura na sessão.
        final url = payload['url']?.toString().trim() ?? '';
        if (url.startsWith('http')) return url;
        final path = payload['path']?.toString().trim() ?? '';
        if (path.startsWith('chat_uploads/')) return path;
      }
      return null;
    }
    final raw = text.trim();
    if (!raw.startsWith('http')) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final path = uri.path.toLowerCase();
    if (path.contains('chat_uploads') || path.contains('order_proofs')) {
      return raw;
    }
    const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'];
    if (exts.any(path.endsWith)) return raw;
    return null;
  }

  Widget _buildChatImageBubble(String imageUrl, {required bool isMe}) {
    return GestureDetector(
      onTap: () async {
        final resolved = await _resolvedChatImageUrl(imageUrl);
        if (!mounted) return;
        _openProofImageDialog(resolved);
      },
      child: ClipRRect(
        borderRadius: FleaberRadius.circularMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 240,
            maxHeight: 280,
          ),
          child: FutureBuilder<String>(
            future: _resolvedChatImageUrl(imageUrl),
            builder: (context, snap) {
              final url = snap.data ?? imageUrl;
              return BatataCachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholderColor: const Color(0xFFE8EDF2),
                errorWidget: ColoredBox(
                  color: const Color(0xFFE8EDF2),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey.shade600,
                    size: 36,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _playBatataNotify() {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    requestOrdersListRefresh();
    pingBatataReservationForNotificationBell();
  }

  String _formatCountdownTo(DateTime deadlineLocal) {
    final now = DateTime.now();
    if (!deadlineLocal.isAfter(now)) return '0s';
    var left = deadlineLocal.difference(now);
    final days = left.inDays;
    left -= Duration(days: days);
    final hours = left.inHours;
    left -= Duration(hours: hours);
    final mins = left.inMinutes;
    left -= Duration(minutes: mins);
    final secs = left.inSeconds.clamp(0, 59);
    if (days > 0) {
      return '${days}d ${hours}h ${mins}m ${secs}s';
    }
    if (hours > 0) return '${hours}h ${mins}m ${secs}s';
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }

  DateTime? _parseIsoDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }

  Future<void> _touchChatLastMessage(String preview) async {
    final chatId = widget.chatId;
    if (chatId == null || chatId.isEmpty) return;
    await ChatsTable().update(
      data: {
        'last_message': preview,
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (rows) => rows.eqOrNull('id', chatId),
    );
  }

  void _scrollMessagesToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messagesScrollController.hasClients) return;
      final target = _messagesScrollController.position.maxScrollExtent;
      if (animate) {
        _messagesScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _messagesScrollController.jumpTo(target);
      }
    });
  }

  bool _sendBusy = false;

  /// Mensagens enviadas localmente até o realtime/stream as confirmar (sem refresh).
  final List<ChatMessagesRow> _optimisticOutgoing = <ChatMessagesRow>[];
  int _optimisticSeq = 0;

  bool _optimisticMatchesConfirmed(
    ChatMessagesRow opt,
    List<ChatMessagesRow> fromStream,
  ) {
    return fromStream.any(
      (m) =>
          m.senderId == opt.senderId &&
          m.text == opt.text &&
          m.id > 0 &&
          (m.createdAt == null ||
              opt.createdAt == null ||
              m.createdAt!.difference(opt.createdAt!).inSeconds.abs() < 120),
    );
  }

  List<ChatMessagesRow> _messagesWithOptimistic(
    List<ChatMessagesRow> fromStream,
  ) {
    if (_optimisticOutgoing.isEmpty) return fromStream;
    final stillPending = _optimisticOutgoing
        .where((opt) => !_optimisticMatchesConfirmed(opt, fromStream))
        .toList();
    if (stillPending.length != _optimisticOutgoing.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _optimisticOutgoing
          ..clear()
          ..addAll(stillPending);
      });
    }
    if (stillPending.isEmpty) return fromStream;
    return [...fromStream, ...stillPending];
  }

  /// Envio de texto: limpa o campo só após insert OK; UI imediata sem refresh.
  Future<void> _sendChatMessage() async {
    if (_sendBusy) return;
    final text =
        (_model.inputMensagemTextController?.text ?? '').trim();
    if (text.runes.length < _kMinChatLetters) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escreve pelo menos 2 letras para enviar.'),
        ),
      );
      return;
    }
    final receiverId = _resolvedOtherUserId();
    if (receiverId == null || receiverId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar o destinatário.'),
        ),
      );
      return;
    }
    final chatId = widget.chatId;
    if (chatId == null || chatId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversa inválida — não foi possível enviar.'),
        ),
      );
      return;
    }

    _sendBusy = true;
    if (mounted) setState(() {});
    try {
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': receiverId,
        'chat_id': chatId,
        'text': text,
        'is_read': false,
        'is_reservation': false,
      });
      // Limpar logo após persistência (não depender do update da lista de chats).
      _model.inputMensagemTextController?.clear();
      final opt = ChatMessagesRow({
        'id': -1000000 - (++_optimisticSeq),
        'sender_id': currentUserUid,
        'receiver_id': receiverId,
        'chat_id': chatId,
        'text': text,
        'is_read': false,
        'is_reservation': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _optimisticOutgoing.add(opt);
      if (mounted) setState(() {});
      _scrollMessagesToBottom(animate: true);
      try {
        await ChatsTable().update(
          data: {
            'last_message': text,
            'last_message_time':
                DateTime.now().toUtc().toIso8601String(),
          },
          matchingRows: (rows) => rows.eqOrNull('id', chatId),
        );
      } catch (_) {
        // Best-effort: a mensagem já está em chat_messages.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível enviar a mensagem. O texto manteve-se — tenta outra vez.',
          ),
        ),
      );
    } finally {
      _sendBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _maybeInsertReservationReminder(
    List<ChatMessagesRow> messages,
  ) async {
    final chatId = widget.chatId;
    final otherId = widget.otherUserId;
    if (_reservationReminderBusy ||
        chatId == null ||
        chatId.isEmpty ||
        otherId == null ||
        otherId.isEmpty) {
      return;
    }

    OrdersRow? reminderOrder;
    DateTime? acceptanceAt;

    if (_hasAcceptedOperationalBundle) {
      if (_bundleHeaderOrders.first.buyerId != currentUserUid) {
        return;
      }
      if (bundleAllOrdersPaidOrBeyond(_bundleHeaderOrders)) {
        await _maybeInsertAutomaticFeedbackIfDue(messages);
        return;
      }
      if (bundleOrdersAwaitingCheckoutChoice(_bundleHeaderOrders)) {
        await _maybeInsertAutomaticFeedbackIfDue(messages);
        return;
      }
      reminderOrder = _bundlePrimaryReservationOrder;
      acceptanceAt = _bundleAcceptanceAnchor();
      if (reminderOrder != null && acceptanceAt == null) {
        acceptanceAt = _reservationAcceptanceAnchor(reminderOrder);
      }
    } else {
      final order = _orderForChat;
      if (order == null ||
          order.id == null ||
          order.id!.isEmpty ||
          order.buyerId != currentUserUid) {
        return;
      }
      if (order.sellerId == currentUserUid) {
        return;
      }
      final bundleId = order.bundleId?.trim() ?? '';
      if (bundleId.isNotEmpty &&
          _focusedBundleId != null &&
          bundleId == _focusedBundleId &&
          _focusedBundleStatus == 'accepted') {
        return;
      }
      reminderOrder = order;
      acceptanceAt = _reservationAcceptanceAnchor(order);
    }

    if (reminderOrder == null ||
        reminderOrder.id == null ||
        reminderOrder.id!.isEmpty) {
      return;
    }

    final status = normalizeOrderStatusKey(reminderOrder.status);
    if (status != 'reservado' &&
        status != 'aguarda_confirmacao' &&
        status != 'pago') {
      await _maybeInsertAutomaticFeedbackIfDue(messages);
      return;
    }
    final isDirectPayment = bundlePaymentMethodIsDirect(
      reminderOrder.paymentMethod,
    );
    if (status == 'pago' &&
        !(reminderOrder.isReservation == true && isDirectPayment)) {
      await _maybeInsertAutomaticFeedbackIfDue(messages);
      return;
    }

    final oid = reminderOrder.id!;
    final reminderKind = switch (status) {
      'aguarda_confirmacao' => 'reservation_payment_check_reminder',
      'pago' => 'reservation_shipping_reminder',
      _ => 'reservation_reminder',
    };

    final bundleIdForReminder =
        reminderOrder.bundleId?.trim() ?? _focusedBundleId?.trim() ?? '';
    if (bundleIdForReminder.isNotEmpty) {
      final bundleOrders = _bundleChatOrdersForId(bundleIdForReminder);
      if (bundleOrders.length >= 2) {
        if (bundleAllOrdersPaidOrBeyond(bundleOrders)) {
          await _maybeInsertAutomaticFeedbackIfDue(messages);
          return;
        }
        if (reminderKind == 'reservation_shipping_reminder' ||
            (_shouldInjectPaidBundleTimeline &&
                _sellerCanSimulateBundleShipment())) {
          await _maybeInsertAutomaticFeedbackIfDue(messages);
          return;
        }
      }
    }

    ChatMessagesRow? lastReminder;
    for (final m in messages.reversed) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != reminderKind) continue;
      final msgOrderId = p['order_id']?.toString();
      final msgBundleId = p['bundle_id']?.toString();
      if (_hasAcceptedOperationalBundle && _focusedBundleId != null) {
        if (msgBundleId != null && msgBundleId == _focusedBundleId) {
          lastReminder = m;
          break;
        }
        if (msgOrderId == oid) {
          lastReminder = m;
          break;
        }
      } else if (msgOrderId == oid) {
        lastReminder = m;
        break;
      }
    }
    final now = DateTime.now();
    final firstAnchor = switch (reminderKind) {
      'reservation_reminder' => acceptanceAt,
      'reservation_payment_check_reminder' =>
        _orderLocalUpdatedAt(reminderOrder) ?? acceptanceAt,
      'reservation_shipping_reminder' =>
        _orderLocalUpdatedAt(reminderOrder) ?? acceptanceAt,
      _ => acceptanceAt,
    };
    final lastReminderAt = lastReminder?.createdAt?.toLocal();
    if (!shouldInsertReservationReminder(
      now: now,
      anchor: firstAnchor,
      lastReminderAt: lastReminderAt,
    )) {
      return;
    }

    _reservationReminderBusy = true;
    try {
      final payload = <String, dynamic>{
        'kind': reminderKind,
        'order_id': oid,
        'v': 1,
      };
      if (_focusedBundleId != null && _hasAcceptedOperationalBundle) {
        payload['bundle_id'] = _focusedBundleId;
      }
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': otherId,
        'is_read': false,
        'text': _fleaberChatJsonEncode(payload),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await _touchChatLastMessage(
        reminderKind == 'reservation_shipping_reminder'
            ? 'Lembrete de envio'
            : reminderKind == 'reservation_payment_check_reminder'
                ? 'Lembrete de pagamento'
                : 'Lembrete de reserva',
      );
      _playBatataNotify();
    } catch (e) {
      print('BATATA_REMINDER ERRO: $e');
    } finally {
      _reservationReminderBusy = false;
    }
    await _maybeInsertAutomaticFeedbackIfDue(messages);
  }

  Future<void> _maybeInsertAutomaticFeedbackIfDue(
    List<ChatMessagesRow> messages,
  ) async {
    final order = _orderForChat;
    if (order == null ||
        order.id == null ||
        order.id!.isEmpty ||
        normalizeOrderStatusKey(order.status) != 'concluido') {
      return;
    }
    ChatMessagesRow? completed;
    for (final m in messages.reversed) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'reservation_order_completed') continue;
      if (p['order_id']?.toString() != order.id) continue;
      completed = m;
      break;
    }
    final completedAt = completed?.createdAt;
    if (completedAt == null ||
        DateTime.now().difference(completedAt.toLocal()) <
            const Duration(hours: 48)) {
      return;
    }
    final oid = order.id!;
    try {
      final existing = await ReviewsTable().queryRows(
        queryFn: (q) => q.eqOrNull('order_id', oid),
        limit: 10,
      );
      final hasBuyerReview =
          existing.any((r) => _isBuyerFeedbackRole(r.authorRole));
      final hasSellerReview =
          existing.any((r) => _isSellerFeedbackRole(r.authorRole));
      if (!hasBuyerReview && order.sellerId != null) {
        await ReviewsTable().insert({
          'target_id': order.sellerId,
          'buyer_id': order.buyerId,
          'stars': 5,
          'comment': 'Avaliação automática: venda concluída sem feedback no prazo.',
          'is_automatic': true,
          'target_type': 'seller',
          'author_role': 'comprador',
          'order_id': oid,
        });
      }
      if (!hasSellerReview && order.buyerId != null) {
        await ReviewsTable().insert({
          'target_id': order.buyerId,
          'buyer_id': order.sellerId,
          'stars': 5,
          'comment':
              'Avaliação automática: comprador sem feedback no prazo.',
          'is_automatic': true,
          'target_type': 'buyer',
          'author_role': 'vendedor',
          'order_id': oid,
        });
      }
    } catch (e) {
      print('BATATA_AUTO_FEEDBACK ERRO: $e');
    }
  }

  bool _isBuyerFeedbackRole(String? role) =>
      role == 'buyer' || role == 'comprador';

  bool _isSellerFeedbackRole(String? role) =>
      role == 'seller' || role == 'vendedor';

  DateTime? _reservationAcceptanceAnchor(OrdersRow order) {
    return reservationAcceptanceAnchor(
      status: orderStatusRawFromData(order.data),
      reservationExpiresAt: order.reservationExpiresAt,
      updatedAt: _orderLocalUpdatedAt(order),
      createdAt: order.createdAt?.toLocal(),
    );
  }

  Future<void> _maybeInsertReservationReminderFromDb() async {
    final chatId = widget.chatId;
    if (chatId == null || chatId.isEmpty) return;
    try {
      final rows = await ChatMessagesTable().queryRows(
        queryFn: (q) =>
            q.eqOrNull('chat_id', chatId).order('id', ascending: true),
        limit: 400,
      );
      await _maybeInsertReservationReminder(rows);
    } catch (e) {
      print('BATATA_REMINDER_DB ERRO: $e');
    }
  }

  Future<void> _confirmSellerMoneyReceivedWithDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Confirmar receção',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Tens a certeza? Só deves confirmar quando o valor estiver visível no '
          'teu banco ou MB WAY. Esta ação não pode ser desfeita.',
          style: GoogleFonts.inter(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton(
            label: 'Confirmar',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await _onSellerConfirmPaymentReceived();
    }
  }

  Future<void> _onSellerConfirmPaymentReceived() async {
    final order = _orderForChat;
    final chatId = widget.chatId;
    final buyerId = widget.otherUserId;
    if (_reservationChatBusy ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }

    final bundleId = (_focusedBundleId ?? order?.bundleId)?.trim() ?? '';
    if (bundleId.isNotEmpty) {
      final bundleOrders = _bundleHeaderOrders.length >= 2
          ? _bundleHeaderOrders
          : await OrdersTable().queryRows(
              queryFn: (q) => q.eqOrNull('bundle_id', bundleId),
              limit: 20,
            );
      if (bundleOrders.length >= 2 &&
          bundleOrders.first.sellerId == currentUserUid &&
          (bundleOrdersAwaitingSellerPaymentConfirm(bundleOrders) ||
              bundleOrders.any(
                (o) => normalizeOrderStatusKey(o.status) == 'reservado',
              ))) {
        setState(() => _reservationChatBusy = true);
        try {
          await confirmSellerBundleDirectPayment(bundleId: bundleId);
          final pid = _product?.id ?? bundleOrders.first.productId ?? '';
          await _loadOrderForChat(pid);
          requestMarketplaceFeedRefresh();
          if (!mounted) return;
          setState(() {});
          _playBatataNotify();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conjunto marcado como pago. Envia os artigos.'),
            ),
          );
        } catch (e) {
          print('BATATA_SELLER_BUNDLE_RECEIPT ERRO: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e')),
          );
        } finally {
          if (mounted) setState(() => _reservationChatBusy = false);
        }
        return;
      }
    }

    if (order == null ||
        order.id == null ||
        order.id!.isEmpty ||
        order.sellerId != currentUserUid) {
      return;
    }
    final st = normalizeOrderStatusKey(order.status);
    if (st != 'aguarda_confirmacao' && st != 'reservado') {
      return;
    }

    setState(() => _reservationChatBusy = true);
    try {
      final oid = order.id!;
      final pid = order.productId ?? '';
      await OrdersTable().update(
        data: {'status': 'pago'},
        matchingRows: (rows) => rows.eqOrNull('id', oid),
      );
      await batataSyncLiveCatalogForOrder(oid);
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': buyerId,
        'is_read': false,
        'text': _fleaberChatJsonEncode({
          'kind': 'reservation_seller_confirmed_receipt',
          'order_id': oid,
          'v': 1,
        }),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await _touchChatLastMessage('Pagamento confirmado');
      await _loadOrderForChat(pid);
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      _playBatataNotify();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encomenda marcada como paga.')),
      );
    } catch (e) {
      print('BATATA_SELLER_RECEIPT ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _onSellerCancelReservationWithDialog() async {
    final order = _orderForChat;
    final chatId = widget.chatId;
    final buyerId = widget.otherUserId;
    if (_reservationChatBusy ||
        order == null ||
        order.id == null ||
        order.id!.isEmpty ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }
    if (order.sellerId != currentUserUid) return;
    final st = normalizeOrderStatusKey(order.status);
    if (st != 'reservado' && st != 'aguarda_confirmacao') return;

    final bundleId = order.bundleId?.trim() ??
        _focusedBundleId?.trim() ??
        '';
    final isAcceptedBundle = bundleId.isNotEmpty &&
        _focusedBundleStatus == 'accepted' &&
        _bundleHeaderOrders.length >= 2;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAcceptedBundle ? 'Cancelar reserva do conjunto?' : 'Cancelar reserva?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          isAcceptedBundle
              ? 'O conjunto volta a ficar disponível no marketplace. '
                  'Esta acção cancela todas as linhas do conjunto e não pode '
                  'ser desfeita.'
              : 'O artigo volta a ficar disponível no marketplace. Esta acção não pode '
                  'ser desfeita.',
          style: GoogleFonts.inter(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: FleaberColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(isAcceptedBundle ? 'Cancelar conjunto' : 'Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _reservationChatBusy = true);
    try {
      if (isAcceptedBundle) {
        await cancelSellerAcceptedBundleReservation(
          bundleId: bundleId,
          chatId: chatId,
          buyerId: buyerId,
        );
        await _loadBundleOrdersForChat();
        await _loadOrderForChat(order.productId ?? '');
      } else {
        final oid = order.id!;
        final pid = order.productId ?? '';
        await OrdersTable().update(
          data: {'status': 'cancelado'},
          matchingRows: (rows) => rows.eqOrNull('id', oid),
        );
        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'reservation_cancelled_by_seller',
            'order_id': oid,
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': true,
        });
        await _touchChatLastMessage('Reserva cancelada');
        await _loadOrderForChat(pid);
      }
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      _playBatataNotify();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAcceptedBundle ? 'Reserva do conjunto cancelada.' : 'Reserva cancelada.',
          ),
        ),
      );
    } catch (e) {
      print('BATATA_SELLER_CANCEL_RESERVATION ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _onSellerAcceptReservation({
    required String orderId,
    required ChatMessagesRow requestMsg,
    required List<ChatMessagesRow> allMessages,
  }) async {
    final chatId = widget.chatId;
    final buyerId = _resolvedOtherUserId();
    if (_reservationChatBusy ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }

    for (final m in allMessages) {
      if (m.id <= requestMsg.id) continue;
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'reservation_request_outcome') continue;
      if (p['order_id']?.toString() != orderId) continue;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido já foi respondido.')),
      );
      return;
    }

    final rows = await OrdersTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', orderId),
    );
    if (rows.isEmpty) return;
    final order = rows.first;
    if (order.sellerId != currentUserUid) return;
    if (normalizeOrderStatusKey(order.status) != 'reserva_pendente') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido já não está pendente.')),
      );
      return;
    }

    setState(() => _reservationChatBusy = true);
    try {
      await batataSellerAcceptReservaPendente(
        orderId: orderId,
        buyerId: buyerId,
        productId: order.productId ?? '',
      );

      await _touchChatLastMessage('Reserva aceite');
      await _loadOrderForChat(order.productId ?? '');
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      _playBatataNotify();
    } catch (e) {
      print('BATATA_ACCEPT_RESERVATION ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _onSellerDeclineReservation({
    required String orderId,
    required ChatMessagesRow requestMsg,
    required List<ChatMessagesRow> allMessages,
  }) async {
    final chatId = widget.chatId;
    final buyerId = _resolvedOtherUserId();
    if (_reservationChatBusy ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }

    for (final m in allMessages) {
      if (m.id <= requestMsg.id) continue;
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'reservation_request_outcome') continue;
      if (p['order_id']?.toString() != orderId) continue;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido já foi respondido.')),
      );
      return;
    }

    final rows = await OrdersTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', orderId),
    );
    if (rows.isEmpty) return;
    final order = rows.first;
    if (order.sellerId != currentUserUid) return;
    if (normalizeOrderStatusKey(order.status) != 'reserva_pendente') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido já não está pendente.')),
      );
      return;
    }

    setState(() => _reservationChatBusy = true);
    try {
      await batataSellerDeclineReservaPendente(
        orderId: orderId,
        buyerId: buyerId,
        productId: order.productId ?? '',
      );

      await _touchChatLastMessage('Reserva recusada');
      await _loadOrderForChat(order.productId ?? '');
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      _playBatataNotify();
    } catch (e) {
      print('BATATA_DECLINE_RESERVATION ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  bool _orderAllowsBuyerCancel(OrdersRow order) =>
      orderAllowsBuyerCancelStatus(order.status);

  bool get _canBuyerShowCancelButton {
    final order = _orderForChat;
    if (order == null) return false;
    if (order.buyerId != currentUserUid) return false;
    if (orderIsCancelled(order.status)) return false;
    return _orderAllowsBuyerCancel(order);
  }

  bool _cancelOutcomeExistsAfter(
    List<ChatMessagesRow> messages,
    int requestMsgId,
    String orderId,
  ) {
    for (final m in messages) {
      if (m.id <= requestMsgId) continue;
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'cancel_request_outcome') continue;
      if (p['order_id']?.toString() != orderId) continue;
      return true;
    }
    return false;
  }

  bool _hasOpenCancelRequest(List<ChatMessagesRow> messages, String orderId) {
    for (final m in messages) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'cancel_request') continue;
      if (p['order_id']?.toString() != orderId) continue;
      if (_cancelOutcomeExistsAfter(messages, m.id, orderId)) continue;
      return true;
    }
    return false;
  }

  Future<void> _onBuyerRequestCancel() async {
    final order = _orderForChat;
    final sellerId = widget.otherUserId;
    final orderId = order?.id;
    if (_cancelChatBusy ||
        order == null ||
        orderId == null ||
        orderId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return;
    }
    if (order.buyerId != currentUserUid) return;

    // Preferir o chat onde está a mensagem «Compra paga» desta encomenda
    // (evita cancel noutra thread-clone).
    var chatId = widget.chatId?.trim() ?? '';
    try {
      final byOrder = await findChatForOrderId(orderId);
      final resolved = byOrder?.id?.trim() ?? '';
      if (resolved.isNotEmpty) chatId = resolved;
    } catch (_) {}
    if (chatId.isEmpty) return;

    if (orderIsCancelled(order.status)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta encomenda já foi cancelada.'),
        ),
      );
      return;
    }
    if (!_orderAllowsBuyerCancel(order)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não é possível pedir cancelamento nesta fase.'),
        ),
      );
      return;
    }

    final msgs = await ChatMessagesTable().queryRows(
      queryFn: (q) => q.eqOrNull('chat_id', chatId).order('id', ascending: true),
      limit: 400,
    );
    if (_hasOpenCancelRequest(msgs, orderId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Já existe um pedido de cancelamento pendente nesta conversa.',
          ),
        ),
      );
      return;
    }

    setState(() => _cancelChatBusy = true);
    try {
      final payload = _fleaberChatJsonEncode({
        'kind': 'cancel_request',
        'order_id': orderId,
        'v': 1,
      });
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': sellerId,
        'is_read': false,
        'text': payload,
        'chat_id': chatId,
        'is_reservation': false,
      });
      await ChatsTable().update(
        data: {
          'last_message': 'Pedido de cancelamento',
          'last_message_time': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', chatId),
      );
      if (!mounted) return;
      print('BATATA_CANCEL_NEGOCIADO pedido enviado order=$orderId');
    } catch (e) {
      print('BATATA_CANCEL_NEGOCIADO ERRO pedido: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar pedido: $e')),
      );
    } finally {
      if (mounted) setState(() => _cancelChatBusy = false);
    }
  }

  Future<void> _onSellerCancelDecision({
    required bool accept,
    required ChatMessagesRow requestMessage,
    required String orderId,
  }) async {
    if (_cancelChatBusy) return;
    final chatId = widget.chatId;
    final buyerId = widget.otherUserId;
    if (chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }

    final orderRows = await OrdersTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', orderId),
    );
    if (orderRows.isEmpty) return;
    final order = orderRows.first;
    if (order.sellerId != currentUserUid) return;

    final allMsgs = await ChatMessagesTable().queryRows(
      queryFn: (q) => q.eqOrNull('chat_id', chatId).order('id', ascending: true),
      limit: 400,
    );
    if (_cancelOutcomeExistsAfter(allMsgs, requestMessage.id, orderId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido já foi respondido.')),
      );
      return;
    }

    setState(() => _cancelChatBusy = true);
    try {
      if (accept) {
        final refundResult = await applyOrderCancelAndRelist(
          orderId: orderId,
          sellerUserId: currentUserUid,
        );
        print(
          'BATATA_CANCEL_NEGOCIADO aceite order=$orderId novo listing criado '
          'stripe_refund_ok=${refundResult.stripeRefundOk} '
          'stripe_err=${refundResult.stripeRefundError}',
        );

        final pm = (order.paymentMethod ?? '').toLowerCase();
        final isDirectPay = pm.contains('direto') ||
            pm.contains('mb way') ||
            pm.contains('mbway') ||
            pm.contains('transfer');
        String cancelDisplay;
        if (isDirectPay) {
          cancelDisplay =
              'Compra cancelada — encomenda anulada. Em pagamento directo '
              '(MB WAY/transferência), o reembolso é combinado entre comprador '
              'e vendedor; a Fleaber não processa esse valor.';
        } else if (refundResult.stripeRefundAttempted &&
            (refundResult.stripeRefundOk ||
                refundResult.stripeRefundAlready)) {
          cancelDisplay =
              'Compra cancelada — encomenda anulada. Reembolso Stripe iniciado '
              'para o método de pagamento original (tipicamente até 10 dias '
              'úteis no extrato, sujeito ao banco).';
        } else if (refundResult.stripeRefundAttempted &&
            (refundResult.stripeRefundError ?? '').isNotEmpty) {
          cancelDisplay =
              'Compra cancelada — encomenda anulada. O reembolso automático '
              'falhou (${refundResult.stripeRefundError}). Contacte '
              'geral@fleaber.pt com o ID da encomenda.';
        } else {
          cancelDisplay =
              'Compra cancelada — encomenda anulada. Com Protecção Fleaber, '
              'o valor retido não é libertado ao vendedor; a Fleaber processa o '
              'reembolso conforme Reembolsos e Disputas.';
        }

        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'cancel_request_outcome',
            'order_id': orderId,
            'outcome': 'accepted',
            'display': cancelDisplay,
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': false,
        });
        // Actualizar cache local para o card «Compra paga» passar a cancelada.
        final cached = _ordersByIdForChat[orderId];
        if (cached != null) {
          _ordersByIdForChat[orderId] = OrdersRow({
            ...cached.data,
            'status': 'cancelado',
          });
        }
        if (_orderForChat?.id == orderId) {
          _orderForChat = OrdersRow({
            ..._orderForChat!.data,
            'status': 'cancelado',
          });
        }
        requestMarketplaceFeedRefresh();
        final pid = order.productId?.trim() ?? '';
        if (pid.isNotEmpty) {
          await _loadOrderForChat(pid);
        }
      } else {
        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'cancel_request_outcome',
            'order_id': orderId,
            'outcome': 'rejected',
            'display':
                'O vendedor já enviou o artigo. O pedido de cancelamento foi recusado.',
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': false,
        });
        print(
          'BATATA_CANCEL_NEGOCIADO recusado (já enviado) order=$orderId',
        );
      }

      await ChatsTable().update(
        data: {
          'last_message': accept ? 'Compra cancelada' : 'Cancelamento recusado',
          'last_message_time': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', chatId),
      );

      final pid = order.productId ?? '';
      await _loadOrderForChat(pid);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      print('BATATA_CANCEL_NEGOCIADO ERRO decisão: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _cancelChatBusy = false);
    }
  }

  Widget _buildCancelOutcomeFromPayload(Map<String, dynamic> payload) {
    final display = (payload['display'] ?? '').toString().trim();
    final line = display.isNotEmpty
        ? display
        : 'Pedido de cancelamento atualizado.';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDF2),
            borderRadius: FleaberRadius.circularSm,
          ),
          child: Text(
            line,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF4F5B67),
            ),
          ),
        ),
      ),
    );
  }

  bool _reservationOutcomeExistsAfter(
    List<ChatMessagesRow> messages,
    int requestMsgId,
    String orderId,
  ) {
    for (final m in messages) {
      if (m.id <= requestMsgId) continue;
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != 'reservation_request_outcome') continue;
      if (p['order_id']?.toString() != orderId) continue;
      return true;
    }
    return false;
  }

  ChatMessagesRow? _findReservationRequestForOrder(
    List<ChatMessagesRow> allMessages,
    String orderId,
  ) {
    ChatMessagesRow? hit;
    for (final m in allMessages) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null || p['kind'] != 'reservation_request') continue;
      if (p['order_id']?.toString() == orderId) hit = m;
    }
    return hit;
  }

  Widget _buildBatataDicaSeguranca({required bool forBuyer}) {
    final body = forBuyer
        ? '⚠️ Atenção: Ao escolheres pagar por fora (MBWay direto), este artigo '
            'continua disponível para outros compradores. Só o pagamento oficial '
            'Fleaber garante a reserva imediata e proteção total em caso de disputa.'
        : 'Dica: Pagamentos via App geram etiquetas automáticas e poupam-te 15 minutos de trabalho.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: FleaberRadius.circularSm,
        border: Border.all(color: const Color(0xFFE6D49A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dica de Segurança',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF6B4E00),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.35,
              color: const Color(0xFF3D2E12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReservationPendingSystemCard(List<ChatMessagesRow> allMessages) {
    final order = _orderForChat;
    final orderId = order?.id;
    final requestMsg = (orderId != null && orderId.isNotEmpty)
        ? _findReservationRequestForOrder(allMessages, orderId)
        : null;
    final imBuyer = order?.buyerId == currentUserUid;
    final imSeller = order?.sellerId == currentUserUid;
    final resolved = orderId != null &&
        requestMsg != null &&
        (_reservationOutcomeExistsAfter(allMessages, requestMsg.id, orderId) ||
            (order != null &&
                normalizeOrderStatusKey(order.status) != 'reserva_pendente'));
    final showSellerActions =
        imSeller && orderId != null && !resolved && requestMsg != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: const Color(0xFFB8D5D8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    imBuyer
                        ? 'Pedido de reserva enviado! Aguarda que o vendedor aceite. '
                            'Dica: Pagamentos oficiais garantem o artigo na hora.'
                        : 'Pedido de reserva pendente — responde em baixo.',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  if (imBuyer || imSeller) ...[
                    const SizedBox(height: 10),
                    _buildBatataDicaSeguranca(forBuyer: imBuyer == true),
                  ],
                  if (imSeller) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Ao aceitar, o artigo fica reservado por 5 dias e sai do marketplace.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (resolved) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Este pedido já foi tratado.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (requestMsg == null && !resolved) ...[
                    const SizedBox(height: kChatMessageItemSpacing),
                    Text(
                      'A sincronizar o pedido de reserva…',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (showSellerActions && orderId != null && requestMsg != null) ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reservationChatBusy
                                ? null
                                : () => _onSellerDeclineReservation(
                                      orderId: orderId,
                                      requestMsg: requestMsg,
                                      allMessages: allMessages,
                                    ),
                            child: const Text('Recusar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Aceitar e Enviar Dados',
                            height: null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            fontSize: 13,
                            onPressed: _reservationChatBusy
                                ? null
                                : () => _onSellerAcceptReservation(
                                      orderId: orderId,
                                      requestMsg: requestMsg,
                                      allMessages: allMessages,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationRequestCard(
    ChatMessagesRow msg,
    List<ChatMessagesRow> allMessages,
  ) {
    final p = _tryParseFleaberChatJson(msg.text);
    final orderId = p?['order_id']?.toString();
    final buyerId = p?['buyer_id']?.toString();
    final sellerId = p?['seller_id']?.toString();
    final order = _orderForChat;
    final matchesActiveOrder = orderId != null &&
        order != null &&
        order.id != null &&
        orderId == order.id;
    final resolved = orderId != null &&
        (_reservationOutcomeExistsAfter(allMessages, msg.id, orderId) ||
            (matchesActiveOrder &&
                normalizeOrderStatusKey(order?.status) != 'reserva_pendente'));
    final imBuyer = buyerId == currentUserUid;
    final imSeller = sellerId == currentUserUid;
    // Aceitar/Recusar: não exigir que _orderForChat seja exactamente este order_id
    // (com várias compras do mesmo artigo o pin pode ser um «pago» antigo).
    final showSellerActions = imSeller && orderId != null && !resolved;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: const Color(0xFFB8D5D8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    imBuyer
                        ? 'Pedido de reserva enviado! Aguarda que o vendedor aceite. '
                            'Dica: Pagamentos oficiais garantem o artigo na hora.'
                        : 'Pedido de reserva — responde abaixo.',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  if (imBuyer || imSeller) ...[
                    const SizedBox(height: 10),
                    _buildBatataDicaSeguranca(forBuyer: imBuyer),
                  ],
                  if (imSeller) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Ao aceitar, o artigo fica reservado por 5 dias e sai do marketplace.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (resolved) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Este pedido já foi tratado.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (showSellerActions && orderId != null) ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reservationChatBusy
                                ? null
                                : () => _onSellerDeclineReservation(
                                      orderId: orderId,
                                      requestMsg: msg,
                                      allMessages: allMessages,
                                    ),
                            child: const Text('Recusar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Aceitar e Enviar Dados',
                            height: null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            fontSize: 13,
                            onPressed: _reservationChatBusy
                                ? null
                                : () => _onSellerAcceptReservation(
                                      orderId: orderId,
                                      requestMsg: msg,
                                      allMessages: allMessages,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoftSystemNoticeCard(
    String line, {
    required Color tone,
    required Color border,
    required Color foreground,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: tone,
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: border),
          ),
          child: Text(
            line,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationRequestOutcomeCard(Map<String, dynamic> payload) {
    final accepted = payload['outcome']?.toString() == 'accepted';
    final line = accepted
        ? 'Reserva aceite — o prazo de pagamento foi iniciado.'
        : 'O vendedor recusou o pedido de reserva.';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: _buildSoftSystemNoticeCard(
        line,
        tone: accepted
            ? HubMessagesTheme.successBg
            : HubMessagesTheme.neutralBg,
        border: accepted
            ? HubMessagesTheme.successBorder
            : HubMessagesTheme.neutralBorder,
        foreground: accepted
            ? HubMessagesTheme.successText
            : HubMessagesTheme.textSecondary,
      ),
    );
  }

  Widget _buildReservationAcceptedCard(Map<String, dynamic> payload) {
    final exp = _parseIsoDate(payload['expires_at']);
    final when = exp != null
        ? DateFormat("d MMM yyyy 'às' HH:mm", 'pt_PT').format(exp)
        : null;
    final orderId = payload['order_id']?.toString();
    final order = _orderForChat;
    final matches =
        orderId != null && order != null && order.id != null && orderId == order.id;
    final imBuyer =
        matches && (order?.buyerId == currentUserUid);
    final imSeller =
        matches && (order?.sellerId == currentUserUid);
    // Sem expires_at: nunca mostrar «até —» — copy sem prazo explícito.
    final String acceptedLine;
    if (imBuyer) {
      acceptedLine = when != null
          ? 'Reserva aceite! Tens até $when para pagar.'
          : 'Reserva aceite — o prazo de pagamento foi iniciado.';
    } else {
      acceptedLine = when != null
          ? 'Reserva aceite. Aguarda o pagamento do comprador até $when.'
          : 'Reserva aceite. Aguarda o pagamento do comprador.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF5FBFB),
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: _kTeal.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    acceptedLine,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  if (imBuyer || imSeller) ...[
                    const SizedBox(height: 10),
                    _buildBatataDicaSeguranca(forBuyer: imBuyer),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Phase 7 — plain-text system DMs from `batata_commerce_post_reservation_dm`.
  ///
  /// Marcador: `[[fleaber_res:<kind>:<ref>]]` — o `<ref>` pode ser UUID **ou**
  /// outro token opaco (ex. seeds de QA). Nunca mostrar o marcador na UI.
  Widget? _tryBuildCommerceReservationDmCard(
    String raw, {
    required DateTime date,
    required bool showSeparator,
  }) {
    final marker = RegExp(
      r'\[\[fleaber_res:([a-z_]+):([^\]]+)\]\]',
      caseSensitive: false,
    );
    final m = marker.firstMatch(raw);
    if (m == null) {
      // Texto cru com marcador parcial / legado — ainda esconder se parecer sistema.
      if (raw.contains('[[fleaber_res:') ||
          RegExp(r'Fleaber\s*[|·]\s*sistema', caseSensitive: false)
              .hasMatch(raw)) {
        final kindGuess = RegExp(r'fleaber_res:([a-z_]+):', caseSensitive: false)
                .firstMatch(raw)
                ?.group(1) ??
            'reservation_guaranteed';
        return _buildCommerceReservationDmColumn(
          kind: kindGuess,
          rawBody: raw,
          date: date,
          showSeparator: showSeparator,
          marker: marker,
        );
      }
      return null;
    }
    return _buildCommerceReservationDmColumn(
      kind: m.group(1) ?? '',
      rawBody: raw,
      date: date,
      showSeparator: showSeparator,
      marker: marker,
    );
  }

  String _commerceReservationHeadline(String kind) {
    switch (kind) {
      case 'reservation_guaranteed':
        return 'Reserva confirmada';
      case 'reservation_accepted':
        return 'Reserva aceite';
      case 'reservation_rejected':
        return 'Reserva recusada';
      case 'pending_expired_buyer_notice':
        return 'Pedido de reserva expirado';
      case 'guaranteed_expired_buyer_notice':
        return 'Reserva expirada';
      default:
        return fleaberChatSystemKindLabel(kind);
    }
  }

  /// Limpa corpo de DMs de reserva: remove marcadores, seeds e prefixos técnicos.
  String _sanitizeCommerceReservationBody(String raw, RegExp marker) {
    var body = raw
        .replaceAll(marker, '')
        .replaceAll(RegExp(r'\[\[fleaber_res:[^\]]*\]\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[H10_TESTE[^\]]*\]\s*'), '')
        .replaceAll(RegExp(r'H10_TESTE_COMPLETO_\d+\s*'), '')
        .replaceAll(RegExp(r'\(seed[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bseed\b', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'^Fleaber\s*[|·]\s*sistema\s*',
                multiLine: true, caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'^Reserva garantida\s*',
                multiLine: true, caseSensitive: false),
            '')
        .trim();
    // Normalizar linhas vazias e espaços.
    body = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => !l.startsWith('[[') && !l.contains('fleaber_res:'))
        .join('\n');
    return body.trim();
  }

  Widget _buildCommerceReservationDmColumn({
    required String kind,
    required String rawBody,
    required DateTime date,
    required bool showSeparator,
    required RegExp marker,
  }) {
    final body = _sanitizeCommerceReservationBody(rawBody, marker);
    final headline = _commerceReservationHeadline(kind);
    final Color accent;
    final Color tone;
    final Color border;
    switch (kind) {
      case 'reservation_guaranteed':
      case 'reservation_accepted':
        accent = HubMessagesTheme.successText;
        tone = HubMessagesTheme.successBg;
        border = HubMessagesTheme.successBorder;
        break;
      case 'pending_expired_buyer_notice':
      case 'guaranteed_expired_buyer_notice':
        accent = HubMessagesTheme.warningText;
        tone = HubMessagesTheme.warningBg;
        border = HubMessagesTheme.warningBorder;
        break;
      case 'reservation_rejected':
        accent = HubMessagesTheme.errorText;
        tone = HubMessagesTheme.errorBg;
        border = HubMessagesTheme.errorBorder;
        break;
      default:
        accent = HubMessagesTheme.textMuted;
        tone = HubMessagesTheme.neutralBg;
        border = HubMessagesTheme.neutralBorder;
    }
    final lines = body.isEmpty
        ? <String>[
            if (kind == 'reservation_guaranteed')
              '1 unidade reservada. Efetua o pagamento no saco até ao fim do prazo indicado.'
            else
              fleaberChatSystemKindLabel(kind),
          ]
        : body.split('\n');
    return Column(
      children: [
        if (showSeparator)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: kChatSystemSectionSpacing,
            ),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: HubMessagesTheme.systemChipBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  getDisplayDate(date),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: HubMessagesTheme.systemChipText,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: kChatSystemSectionSpacingHalf,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: FleaberRadius.circularMd,
                  border: Border.all(color: border),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        headline,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...lines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            style: GoogleFonts.inter(
                              fontSize: line == lines.first ? 13.5 : 13,
                              height: 1.4,
                              fontWeight: line == lines.first
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: HubMessagesTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: kChatSystemSectionSpacingHalf),
          child: Center(
            child: Text(
              DateFormat('HH:mm').format(date),
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: HubMessagesTheme.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReservationPaymentSubmittedCard(Map<String, dynamic> payload) {
    final notes = (payload['notes'] ?? '').toString().trim();
    final proofUrl = (payload['proof_url'] ?? '').toString().trim();
    final o = _orderForChat;
    final oid = payload['order_id']?.toString();
    final matchesOrder =
        oid != null && o?.id != null && oid == o!.id;
    final imBuyer = o?.buyerId == currentUserUid;
    final imSeller = matchesOrder && o!.sellerId == currentUserUid;
    final sellerSt = normalizeOrderStatusKey(o?.status);
    // Vendedor pode confirmar dinheiro sem prova prévia do comprador.
    final sellerCanConfirm = imSeller &&
        (sellerSt == 'aguarda_confirmacao' || sellerSt == 'reservado');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E6),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: const Color(0xFFE6D49A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                imBuyer
                    ? 'Indicaste que já pagaste. O vendedor vai confirmar a receção.'
                    : 'O comprador confirmou o pagamento. Confirma no teu banco.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: kChatMessageItemSpacing),
                Text(
                  'Observações: $notes',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF57636C)),
                ),
              ],
              if (proofUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => _openProofImageDialog(proofUrl),
                    borderRadius: FleaberRadius.circularSm,
                    child: ClipRRect(
                      borderRadius: FleaberRadius.circularSm,
                      child: SizedBox(
                        width: 86,
                        height: 86,
                        child: BatataCachedNetworkImage(
                          imageUrl: proofUrl,
                          fit: BoxFit.cover,
                          placeholderColor: const Color(0xFFFFF8E6),
                          errorWidget: Container(
                            color: const Color(0xFFF2F4F7),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFF57636C),
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (sellerCanConfirm) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'Confirmar Receção de Dinheiro',
                  height: null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  fontSize: 14,
                  onPressed: _reservationChatBusy
                      ? null
                      : _confirmSellerMoneyReceivedWithDialog,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openProofImageDialog(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: BatataCachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholderColor: Colors.black,
                  errorWidget: const Padding(
                    padding: EdgeInsets.all(32),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReservationReminderCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Text(
            'Lembrete: tens uma reserva activa. Completa o pagamento dentro do prazo.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E3A5F),
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationPaymentCheckReminderCard() {
    return _buildSimpleReservationInfoCard(
      text:
          'Lembrete enviado ao vendedor para verificar o pagamento confirmado pelo comprador.',
      icon: Icons.notifications_active_rounded,
      color: const Color(0xFFFFF8E6),
      border: const Color(0xFFE6D49A),
      textColor: const Color(0xFF6B4E00),
    );
  }

  Widget _buildReservationShippingReminderCard() {
    return _buildSimpleReservationInfoCard(
      text:
          'Lembrete enviado ao vendedor para confirmar o envio da encomenda.',
      icon: Icons.local_shipping_outlined,
      color: const Color(0xFFEFF6FF),
      border: const Color(0xFFBFDBFE),
      textColor: const Color(0xFF1E3A5F),
    );
  }

  Widget _buildReservationSellerConfirmedCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F7F5),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: const Color(0xFF8EC9C5)),
          ),
          child: Text(
            'Pagamento confirmado pelo vendedor. Encomenda paga.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0D3D38),
            ),
          ),
        ),
      ),
    );
  }

  /// Entrega em mão do prémio (ou encomenda com shipping_method de mão).
  bool _isHandDeliveryOrder(OrdersRow? order) {
    if (order == null) return false;
    return LiveRafflePrizeCopy.isHandShippingMethod(order.shippingMethod);
  }

  Widget _buildReservationOrderShippedCard([Map<String, dynamic>? payload]) {
    final order = _orderForChat;
    final hand = payload?['hand_delivery'] == true ||
        _isHandDeliveryOrder(order);
    final oid = order?.id?.trim() ?? '';
    final showTrack = !hand && oid.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSimpleReservationInfoCard(
          text: hand
              ? 'A vendedora confirmou a entrega em mão. Confirma a receção quando tiveres o artigo.'
              : 'O vendedor confirmou o envio da encomenda.',
          icon: hand ? Icons.handshake_rounded : Icons.local_shipping_rounded,
          color: const Color(0xFFEFF6FF),
          border: const Color(0xFFBFDBFE),
          textColor: const Color(0xFF1E3A5F),
        ),
        if (showTrack) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: OutlinedButton.icon(
              onPressed: () => unawaited(
                showDpdTrackingSheet(
                  context,
                  orderId: oid,
                  knownGuide: order?.dpdTrackingCode,
                ),
              ),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: Text(
                'Ver seguimento DPD',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF007782),
                side: const BorderSide(color: Color(0xFF007782)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReservationOrderCompletedCard() {
    final o = _orderForChat;
    final isBuyer = o?.buyerId == currentUserUid;
    return _buildSimpleReservationInfoCard(
      text: isBuyer
          ? 'Venda concluída. Obrigado! Podes deixar avaliação ao vendedor.'
          : 'O comprador confirmou a receção. Venda concluída. Podes avaliar o cliente.',
      icon: Icons.verified_rounded,
      color: const Color(0xFFE6F7F5),
      border: const Color(0xFF8EC9C5),
      textColor: const Color(0xFF0D3D38),
    );
  }

  Widget _buildBundleBuyerConfirmedReceiptCard() {
    final imSeller = _isCurrentUserSellerInChat;
    return _buildSimpleReservationInfoCard(
      text: imSeller
          ? 'O comprador confirmou a receção do conjunto.'
          : 'Receção do conjunto confirmada.',
      icon: Icons.verified_rounded,
      color: const Color(0xFFE6F7F5),
      border: const Color(0xFF8EC9C5),
      textColor: const Color(0xFF0D3D38),
    );
  }

  Widget _buildAutoFeedbackGeneratedCard() {
    return _buildSimpleReservationInfoCard(
      text:
          'Feedback automático gerado: passou o prazo sem avaliação manual, por isso o sistema atribuiu 5 estrelas ao comprador e ao vendedor.',
      icon: Icons.star_rounded,
      color: const Color(0xFFFFF8E6),
      border: const Color(0xFFE6D49A),
      textColor: const Color(0xFF6B4E00),
    );
  }

  Widget _buildRafflePrizeAwardedCard(Map<String, dynamic> payload) {
    final order = _orderForChat;
    // Card de gestão (inject) + sticky já têm os CTAs — não duplicar aqui.
    if (order != null && _showSaleManagementCardInChat(order)) {
      return const SizedBox.shrink();
    }

    final status = normalizeOrderStatusKey(order?.status);
    final custom = payload['message']?.toString().trim() ?? '';
    final String body;
    if (status == 'premio_rifa') {
      // Ignorar copy antiga do SQL («Pagas apenas o envio») se já temos ordem.
      body = LiveRafflePrizeCopy.chatCardBodyPending;
    } else if (status == 'pago' &&
        LiveRafflePrizeCopy.isHandShippingMethod(order?.shippingMethod)) {
      body = LiveRafflePrizeCopy.chatCardBodyHand;
    } else if (status == 'pago' ||
        status == 'enviado' ||
        status == 'concluido') {
      body = LiveRafflePrizeCopy.chatCardBodyPaid;
    } else if (custom.isNotEmpty) {
      body = custom;
    } else {
      body = LiveRafflePrizeCopy.chatCardBodyPending;
    }

    final showPay = order != null &&
        order.buyerId == currentUserUid &&
        status == 'premio_rifa';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSimpleReservationInfoCard(
          text: body,
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFFFFF8E1),
          border: const Color(0xFFE6C35C),
          textColor: const Color(0xFF5D4037),
        ),
        if (showPay) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FleaberPrimaryButton(
              width: double.infinity,
              label: 'Pagar envio do prémio',
              height: 44,
              borderRadius: 10,
              onPressed: () => unawaited(_onBuyerPayRafflePrizeShipping()),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: OutlinedButton(
              onPressed: () => unawaited(_openRafflePrizeSellerShop()),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF007782),
                side: const BorderSide(color: Color(0xFF007782)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Ver loja desta vendedora',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderReviewSubmittedCard(Map<String, dynamic> payload) {
    final authorRole = payload['author_role']?.toString() ?? '';
    final stars = payload['stars'];
    final starsLabel = stars == null ? '' : ' ($stars★)';
    final bundleSellerId =
        _bundleAnchorOrder()?.sellerId ?? _orderForChat?.sellerId;
    final bundleBuyerId =
        _bundleAnchorOrder()?.buyerId ?? _orderForChat?.buyerId;
    final imSeller = bundleSellerId == currentUserUid;
    final imBuyer = bundleBuyerId == currentUserUid;

    if (authorRole == 'comprador' && imSeller) {
      return _buildSimpleReservationInfoCard(
        text:
            'Avaliação recebida$starsLabel. O valor ficará disponível na tua carteira.',
        icon: Icons.star_rounded,
        color: const Color(0xFFF5F5F5),
        border: const Color(0xFFE0E0E0),
        textColor: const Color(0xFF101518),
      );
    }
    if (authorRole == 'comprador' && imBuyer) {
      return _buildSimpleReservationInfoCard(
        text: 'Avaliação enviada$starsLabel. Obrigado pelo teu feedback.',
        icon: Icons.star_rounded,
        color: const Color(0xFFF5F5F5),
        border: const Color(0xFFE0E0E0),
        textColor: const Color(0xFF101518),
      );
    }
    return _buildSimpleReservationInfoCard(
      text: 'Avaliação registada$starsLabel.',
      icon: Icons.star_rounded,
      color: const Color(0xFFF5F5F5),
      border: const Color(0xFFE0E0E0),
      textColor: const Color(0xFF101518),
    );
  }

  Widget _buildOrderDisputeOpenedCard(Map<String, dynamic> payload) {
    final orderId =
        (payload['order_id'] ?? _orderForChat?.id ?? '').toString().trim();
    if (orderId.isEmpty) {
      final reason =
          _disputeReasonLabel((payload['reason'] ?? 'problema').toString());
      return _buildSimpleReservationInfoCard(
        text:
            'O comprador abriu uma disputa. Motivo: $reason. O saldo desta transação encontra-se temporariamente bloqueado.',
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFFFF7ED),
        border: const Color(0xFFF3C27A),
        textColor: const Color(0xFF7C3E00),
      );
    }
    final cached = _disputeThreadOrderId == orderId ? _disputeThreadCache : null;
    if (cached != null) {
      return _buildDisputeThreadCard(cached);
    }
    return FutureBuilder<_DisputeThread?>(
      future: _loadDisputeThread(orderId),
      builder: (context, snapshot) {
        final thread = snapshot.data;
        if (thread == null) {
          return _buildSimpleReservationInfoCard(
            text:
                'Disputa aberta. O saldo desta transação encontra-se temporariamente bloqueado.',
            icon: Icons.report_problem_rounded,
            color: const Color(0xFFFFF7ED),
            border: const Color(0xFFF3C27A),
            textColor: const Color(0xFF7C3E00),
          );
        }
        return _buildDisputeThreadCard(thread);
      },
    );
  }

  Widget _buildDisputeThreadCard(_DisputeThread thread) {
    final dispute = thread.dispute;
    // Multi-encomenda no mesmo chat: botões/estado devem seguir a encomenda
    // da disputa (não outra venda no mesmo product_id) — SEC-025 / BUG-043 sibling.
    final disputeOrderId = (dispute.orderId ?? dispute.data['order_id'] ?? '')
        .toString()
        .trim();
    final OrdersRow? currentOrder = disputeOrderId.isNotEmpty
        ? (_ordersByIdForChat[disputeOrderId] ??
            (_orderForChat?.id == disputeOrderId ? _orderForChat : null))
        : _orderForChat;
    final disputeBuyerId =
        (dispute.buyerId ?? dispute.data['buyer_id'] ?? '').toString().trim();
    final chatSellerId = (_orderForChat?.sellerId ?? '').trim();
    // Comprador = dono da disputa OU (no chat) não somos o vendedor da encomenda.
    final isBuyer = currentUserUid.isNotEmpty &&
        (disputeBuyerId == currentUserUid ||
            (currentOrder?.buyerId ?? '').trim() == currentUserUid ||
            (chatSellerId.isNotEmpty && chatSellerId != currentUserUid));
    final isSeller = currentUserUid.isNotEmpty &&
        !isBuyer &&
        ((currentOrder?.sellerId ?? '').trim() == currentUserUid ||
            chatSellerId == currentUserUid);
    final deadline = dispute.nextDeadline?.toLocal();
    final deadlineText = deadline == null
        ? 'Sem prazo definido'
        : DateFormat('dd MMM, HH:mm', 'pt_PT').format(deadline);
    final remainingText = deadline == null
        ? 'Sem prazo definido'
        : _formatCountdownTo(deadline);
    final hasReturnOffer = dispute.sellerOfferType == 'return' ||
        dispute.sellerOfferType == 'return_and_partial_refund';
    final hasPartialRefundOffer = dispute.sellerOfferType == 'partial_refund' ||
        dispute.sellerOfferType == 'return_and_partial_refund';
    final canSellerAct = isSeller &&
        (dispute.currentTurn == 'vendedor' ||
            (dispute.currentTurn == 'comprador' &&
                dispute.status == 'respondida_vendedor'));
    final canBuyerAct = isBuyer && dispute.currentTurn == 'comprador';
    final orderStatus = normalizeOrderStatusKey(currentOrder?.status);
    final sellerReviewingReturn = isSeller && orderStatus == 'devolucao_entregue';
    final blocked = dispute.currentTurn == 'administracao' ||
        dispute.status == 'escalada_fleaber' ||
        dispute.status == 'resolvida';
    final buyerDecisionKey = (dispute.buyerDecision ?? '').trim();
    final buyerAlreadyDecided = buyerDecisionKey.isNotEmpty;
    // Ofertas Aceitar/Recusar: turno comprador + oferta pendente.
    // A disputa (não o cache de status da encomenda) manda nos botões — SEC-025:
    // cache stale `enviado` escondia Aceitar/Recusar com proposta já visível.
    final offerPendingForBuyer = (hasReturnOffer || hasPartialRefundOffer) &&
        dispute.currentTurn == 'comprador' &&
        !buyerAlreadyDecided &&
        !blocked;
    final buyerCanDecideOffers = offerPendingForBuyer &&
        currentUserUid.isNotEmpty &&
        (isBuyer ||
            (chatSellerId.isNotEmpty && chatSellerId != currentUserUid) ||
            (disputeBuyerId.isNotEmpty && disputeBuyerId == currentUserUid));
    final buyerReturnInProgress =
        isBuyer && !blocked && orderStatus == 'em_devolucao';
    final turnOwner = dispute.currentTurn == 'administracao'
        ? 'Administração Fleaber'
        : dispute.currentTurn == 'vendedor'
            ? 'Vendedor'
            : 'Comprador';
    // Título: só «fechada» quando resolvida/recusada.
    // Escalada à administração = em análise (não fechada) — auditoria C26 APP-072.
    final disputeTitle = fleaberDisputeCardTitle(
      status: dispute.status,
      currentTurn: dispute.currentTurn,
    );
    final disputeResolved = disputeTitle == 'Disputa fechada';
    final disputeEscalated = disputeTitle == 'Disputa em análise';
    final disputeTitleIcon = disputeResolved
        ? Icons.check_circle_outline_rounded
        : disputeEscalated
            ? Icons.manage_search_rounded
            : Icons.report_problem_rounded;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        kChatSystemSectionSpacingHalf,
        12,
        // Espaço extra para Aceitar/Recusar não ficarem atrás do composer.
        buyerCanDecideOffers ? 96 : kChatSystemSectionSpacingHalf,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(color: const Color(0xFFF3C27A)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    disputeTitleIcon,
                    color: const Color(0xFFB45309),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      disputeTitle,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7C3E00),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DisputeInfoLine(
                label: 'Motivo',
                value: _disputeReasonLabel(dispute.reason ?? ''),
              ),
              if ((dispute.description ?? '').trim().isNotEmpty)
                _DisputeInfoLine(
                  label: 'Descrição',
                  value: dispute.description!.trim(),
                ),
              _DisputeInfoLine(
                label: 'Quem tem de responder',
                value: turnOwner,
              ),
              _DisputeInfoLine(label: 'Prazo limite', value: deadlineText),
              _DisputeInfoLine(label: 'Tempo restante', value: remainingText),
              if (hasReturnOffer)
                _DisputeInfoLine(
                  label: 'Proposta do vendedor',
                  value: dispute.sellerPaysReturnShipping
                      ? 'Aceita devolução e oferece-se para pagar os portes.'
                      : 'Aceita devolução. Portes a cargo do comprador.',
                ),
              if (hasPartialRefundOffer)
                _DisputeInfoLine(
                  label: 'Proposta do vendedor',
                  value:
                      'Reembolso parcial de ${(dispute.sellerRefundPercent ?? 0).toStringAsFixed(0)}% e o comprador fica com o artigo.',
                ),
              if (orderStatus == 'em_devolucao' && isBuyer)
                _DisputeInfoLine(
                  label: 'Etiqueta de devolução',
                  value:
                      'Tens ${ReturnLabelRules.downloadDays} dias para descarregar a etiqueta e enviar o artigo. ${ReturnLabelRules.formatDeadline(dispute.returnLabelCreatedAt, labelDeadline: dispute.returnLabelDeadline)}.',
                ),
              if (orderStatus == 'em_devolucao' && !isBuyer)
                const _DisputeInfoLine(
                  label: 'Devolução',
                  value: 'O comprador deve descarregar a etiqueta e enviar o artigo.',
                ),
              if (orderStatus == 'devolucao_entregue')
                _DisputeInfoLine(
                  label: 'Conferência do vendedor',
                  value:
                      'Artigo recebido. O vendedor tem até ${deadlineText == 'Sem prazo definido' ? '2 dias' : deadlineText} para validar.',
                ),
              if (_buyerCanDownloadReturnLabel(
                isBuyer: isBuyer,
                orderStatus: orderStatus,
                dispute: dispute,
              ))
                _buildBuyerReturnLabelSection(thread),
              _buildDisputePhotos(dispute.proofPhotos),
              if (thread.replies.isNotEmpty) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                Text(
                  'Histórico de respostas',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF7C3E00),
                  ),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                for (final reply in thread.replies)
                  _DisputeReplyTile(
                    reply: reply,
                    isMine: reply.senderId == currentUserUid,
                  ),
              ],
              if (!blocked && canSellerAct) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                // Após proposta já enviada (turno comprador), só «Adicionar informação».
                // Não reabrir Aceitar devolução / reembolso parcial — BUG-C25-DISPUTE-SELLER-OFFER.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _disputeBusy
                            ? null
                            : () => _openDisputeReplySheet(thread),
                        child: Text(
                          dispute.currentTurn == 'vendedor'
                              ? 'Enviar resposta'
                              : 'Adicionar informação',
                        ),
                      ),
                    ),
                    if (orderStatus == 'pedido_devolucao' &&
                        !hasReturnOffer) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _disputeBusy
                              ? null
                              : () => _sellerOfferReturn(thread),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB45309),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Aceitar devolução'),
                        ),
                      ),
                    ],
                  ],
                ),
                // Só oferece se ainda não há oferta de return nem parcial.
                if (orderStatus == 'pedido_devolucao' &&
                    !hasReturnOffer &&
                    !hasPartialRefundOffer) ...[
                  const SizedBox(height: kChatMessageItemSpacing),
                  OutlinedButton(
                    onPressed: _disputeBusy
                        ? null
                        : () => _sellerOfferPartialRefund(thread),
                    child: const Text('Oferecer reembolso parcial (%)'),
                  ),
                ],
              ],
              if (buyerCanDecideOffers) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                if (hasReturnOffer) ...[
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Aceitar devolução',
                    onPressed:
                        _disputeBusy ? null : () => _buyerAcceptReturn(thread),
                  ),
                  const SizedBox(height: kChatMessageItemSpacing),
                  OutlinedButton(
                    onPressed: _disputeBusy
                        ? null
                        : () => _buyerRejectOffer(thread, 'return'),
                    child: const Text('Recusar devolução'),
                  ),
                ],
                if (hasPartialRefundOffer) ...[
                  if (hasReturnOffer) const SizedBox(height: 8),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Aceitar reembolso parcial',
                    onPressed: _disputeBusy
                        ? null
                        : () => _buyerAcceptPartialRefund(thread),
                  ),
                  const SizedBox(height: kChatMessageItemSpacing),
                  OutlinedButton(
                    onPressed: _disputeBusy
                        ? null
                        : () => _buyerRejectOffer(thread, 'partial_refund'),
                    child: const Text('Recusar reembolso parcial'),
                  ),
                ],
                const SizedBox(height: kChatMessageItemSpacing),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _disputeBusy
                            ? null
                            : () => _buyerCancelDispute(thread),
                        child: const Text('Cancelar disputa'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FleaberPrimaryButton(
                        width: double.infinity,
                        label: 'Escalar',
                        onPressed: _disputeBusy
                            ? null
                            : () => _buyerEscalateDispute(thread),
                      ),
                    ),
                  ],
                ),
                if (canBuyerAct) ...[
                  const SizedBox(height: kChatMessageItemSpacing),
                  OutlinedButton(
                    onPressed: _disputeBusy
                        ? null
                        : () => _openDisputeReplySheet(thread),
                    child: const Text('Responder ao vendedor'),
                  ),
                ],
              ],
              // Em devolução: etiqueta + Cancelar disputa (desistir da devolução).
              // Sem Aceitar/Recusar/Escalar — BUG-C25-BUYER-OFFER-BUTTONS.
              if (buyerReturnInProgress) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                OutlinedButton(
                  onPressed: _disputeBusy
                      ? null
                      : () => _buyerCancelDispute(thread),
                  child: const Text('Cancelar disputa'),
                ),
              ],
              if (!blocked && sellerReviewingReturn) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'Devolução recebida em bom estado',
                  onPressed:
                      _disputeBusy ? null : () => _sellerConfirmReturnOk(thread),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                OutlinedButton(
                  onPressed: _disputeBusy
                      ? null
                      : () => _sellerOpenReturnIssue(thread),
                  child: const Text('Abrir problema com a devolução'),
                ),
              ],
              if (blocked && dispute.status == 'escalada_fleaber') ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                Text(
                  'Disputa entregue à Administração do Fleaber.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF7C3E00),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _buyerCanDownloadReturnLabel({
    required bool isBuyer,
    required String orderStatus,
    required OrderDisputesRow dispute,
  }) {
    if (!isBuyer || orderStatus != 'em_devolucao') return false;
    return dispute.returnLabelCreatedAt != null ||
        dispute.buyerDecision == 'accepted_return' ||
        dispute.adminResolution == 'approve_return';
  }

  Future<void> _openReturnLabelUrl(String? url) async {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etiqueta ainda não está disponível.')),
      );
      return;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link da etiqueta inválido.')),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a etiqueta.')),
      );
    }
  }

  Widget _buildBuyerReturnLabelSection(_DisputeThread thread) {
    final dispute = thread.dispute;
    final orderId = _orderForChat?.id ?? '';
    final labelUrl = (dispute.returnLabelUrl?.trim().isNotEmpty == true)
        ? dispute.returnLabelUrl
        : (orderId.isEmpty
            ? null
            : 'https://fleaber.app/return-label/$orderId');
    final buyerPaysShipping = !dispute.sellerPaysReturnShipping;
    final feeText = NumberFormat.currency(locale: 'pt_PT', symbol: '€')
        .format(ReturnLabelRules.shippingFeeEur);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (buyerPaysShipping)
            Text(
              'Custo da etiqueta: $feeText. Este valor será abatido ao reembolso após a conclusão da venda.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7C3E00),
              ),
            )
          else
            Text(
              'Os portes da devolução são pagos pelo vendedor.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7C3E00),
              ),
            ),
          const SizedBox(height: 8),
          FleaberPrimaryButton(
            width: double.infinity,
            label: buyerPaysShipping
                ? 'Descarregar etiqueta ($feeText)'
                : 'Descarregar etiqueta',
            icon: const Icon(Icons.download_rounded, size: 20, color: Colors.white),
            loading: _disputeBusy,
            onPressed: _disputeBusy
                ? null
                : () => _onBuyerDownloadReturnLabel(thread),
          ),
        ],
      ),
    );
  }

  /// Stub staging (= envio vendedor): toque marca devolução como enviada/entregue.
  /// Quando houver API real de etiqueta, abrir PDF/URL e só depois marcar.
  Future<void> _onBuyerDownloadReturnLabel(_DisputeThread thread) async {
    final order = _orderForChat;
    final dispute = thread.dispute;
    final disputeId = dispute.id;
    final orderId = order?.id;
    if (order == null ||
        disputeId == null ||
        orderId == null ||
        normalizeOrderStatusKey(order.status) != 'em_devolucao') {
      return;
    }
    if (_disputeBusy) return;
    setState(() => _disputeBusy = true);
    try {
      // Placeholder fleaber.app → não abrir Chrome (página inexistente).
      final rawUrl = (dispute.returnLabelUrl ?? '').trim();
      final isPlaceholder = rawUrl.isEmpty ||
          rawUrl.contains('fleaber.app/return-label/');
      if (!isPlaceholder) {
        await _openReturnLabelUrl(rawUrl);
      }

      final now = DateTime.now().toUtc();
      await OrdersTable().update(
        data: {'status': 'devolucao_entregue'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await OrderDisputesTable().update(
        data: {
          'return_delivered_at': now.toIso8601String(),
          'seller_inspection_deadline':
              now.add(const Duration(days: 2)).toIso8601String(),
          'current_turn': 'vendedor',
          'next_deadline': now.add(const Duration(days: 2)).toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message':
            'O comprador descarregou a etiqueta e enviou a devolução. O vendedor tem 2 dias para conferir o artigo.',
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Devolução enviada pelo comprador');
      await _loadOrderForChat(order.productId ?? '');
      await _refreshDisputeThreadForOrder(orderId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Devolução marcada como enviada. O vendedor vai conferir o artigo.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível marcar o envio: $e')),
      );
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Widget _buildDisputePhotos(List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: kChatMessageItemSpacing),
          itemBuilder: (context, index) => ClipRRect(
            borderRadius: FleaberRadius.circularSm,
            child: SizedBox(
              width: 74,
              height: 74,
              child: BatataCachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleReservationInfoCard({
    required String text,
    required IconData icon,
    required Color color,
    required Color border,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReservationCancelledBySellerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: const Color(0xFFF1B0B0)),
          ),
          child: Text(
            'O vendedor cancelou a reserva.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7A1F1F),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBundleReservationCancelledBySellerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(color: const Color(0xFFF1B0B0)),
          ),
          child: Text(
            'O vendedor cancelou a reserva do conjunto.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7A1F1F),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildReservationStickyBar() {
    if (_bundleActivePaidOrders.length >= 2 &&
        _sellerCanSimulateBundleShipment() &&
        _bundleActivePaidOrders.first.sellerId == currentUserUid) {
      return _buildBundleSellerShipStickyBar();
    }
    if (_hasQuotedAwaitingPaymentBundle) {
      final meta = _focusedBundleMeta;
      final buyerId = meta?['buyer_id']?.toString();
      final sellerId = meta?['seller_id']?.toString();
      if (buyerId == currentUserUid) {
        return _buildQuotedBundleBuyerStickyBar();
      }
      if (sellerId == currentUserUid) {
        return _buildQuotedBundleSellerStickyBar();
      }
    }
    if (_hasAcceptedOperationalBundle) {
      final ref = _bundleHeaderOrders.first;
      if (ref.buyerId == currentUserUid) {
        return _buildBundleBuyerOperationalStickyBar();
      }
      if (ref.sellerId == currentUserUid) {
        return _buildBundleSellerOperationalStickyBar();
      }
    }

    final o = _orderForChat;
    if (o != null &&
        o.bundleId?.trim().isNotEmpty == true &&
        o.bundleId!.trim() == (_focusedBundleId?.trim() ?? '') &&
        _focusedBundleStatus == 'accepted') {
      return null;
    }
    if (o == null) return null;
    final st = normalizeOrderStatusKey(o.status);
    if (st != 'reservado' &&
        st != 'aguarda_confirmacao' &&
        st != 'enviado' &&
        st != 'concluido' &&
        st != 'premio_rifa' &&
        !(st == 'pago' && _isHandDeliveryOrder(o))) {
      return null;
    }
    final imBuyer = o.buyerId == currentUserUid;
    final imSeller = o.sellerId == currentUserUid;
    if (!imBuyer && !imSeller) return null;
    final exp = o.reservationExpiresAt?.toLocal();
    final showPaymentCountdown =
        exp != null && (st == 'reservado' || st == 'aguarda_confirmacao');

    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFD5E4E6), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: kChatSystemSectionSpacingHalf,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPaymentCountdown)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: _kTeal.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        imBuyer
                            ? 'Tempo limite para pagar: ${_formatCountdownTo(exp)} – '
                                'Após este tempo, o artigo volta ao Marketplace.'
                            : 'Tempo limite do comprador para pagar: ${_formatCountdownTo(exp)} – '
                                'Após este tempo, o artigo volta ao Marketplace.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: const Color(0xFF1A3D40),
                        ),
                      ),
                    ),
                  ],
                ),
              if (imBuyer && st == 'aguarda_confirmacao') ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                Text(
                  'Prova de pagamento enviada — aguarda a confirmação do vendedor.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: const Color(0xFF1A3D40),
                  ),
                ),
              ],
              if (imBuyer && st == 'reservado') ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: 'Pagar agora (Seguro Fleaber)',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  onPressed: _reservationChatBusy
                      ? null
                      : _onBuyerTapSecureFleaberPayFromReservation,
                ),
                if (_shouldShowProofButton) ...[
                  const SizedBox(height: kChatMessageItemSpacing),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    height: 44,
                    borderRadius: 10,
                    label: 'Ver dados de pagamento',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    onPressed: _reservationChatBusy
                        ? null
                        : () => _openOrderDirectPaymentDetails(o),
                  ),
                  const SizedBox(height: kChatMessageItemSpacing),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _reservationChatBusy
                          ? null
                          : _showSubmitProofDialog,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(
                        'Confirmo pagamento',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: const BorderSide(color: _kTeal, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: _stickyBarBtnRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (imBuyer && st == 'premio_rifa') ...[
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: 'Pagar envio do prémio',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  onPressed: _reservationChatBusy
                      ? null
                      : () => unawaited(_onBuyerPayRafflePrizeShipping()),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed:
                        _reservationChatBusy ? null : _openJuntarAoPremio,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: _stickyBarBtnRadius,
                      ),
                    ),
                    child: Text(
                      'Juntar mais peças ao envio',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _reservationChatBusy
                        ? null
                        : () => unawaited(_openRafflePrizeSellerShop()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: _stickyBarBtnRadius,
                      ),
                    ),
                    child: Text(
                      'Ver loja desta vendedora',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
              if (imSeller &&
                  (st == 'reservado' || st == 'aguarda_confirmacao')) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reservationChatBusy
                            ? null
                            : _onSellerCancelReservationWithDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FleaberColors.danger,
                          side: const BorderSide(
                            color: FleaberColors.danger,
                            width: 1.1,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: _stickyBarBtnRadius,
                          ),
                        ),
                        child: Text(
                          'Cancelar Reserva',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FleaberPrimaryButton(
                        width: double.infinity,
                        label: 'Confirmar Receção de Dinheiro',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        height: null,
                        onPressed: _reservationChatBusy
                            ? null
                            : () {
                                if (st == 'aguarda_confirmacao' ||
                                    st == 'reservado') {
                                  _confirmSellerMoneyReceivedWithDialog();
                                } else {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Só podes confirmar quando o pedido '
                                        'estiver a aguardar pagamento.',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
              if (imBuyer &&
                  (st == 'enviado' ||
                      (st == 'pago' && _isHandDeliveryOrder(o)))) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: _isHandDeliveryOrder(o)
                      ? 'Confirmei receção em mão'
                      : 'Confirmar receção da encomenda',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  onPressed: _reservationChatBusy
                      ? null
                      : _onBuyerConfirmOrderReceived,
                ),
              ],
              if (_buyerCanResolveDeliveredOrder(o)) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: Text(
                      'Deixar avaliação',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: _stickyBarBtnRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_disputeBusy || _feedbackBusy) ? null : _openBuyerDisputeSheet,
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: Text(
                      'Tenho um problema',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: const BorderSide(
                        color: Color(0xFFB45309),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FleaberRadius.circularSm,
                      ),
                    ),
                  ),
                ),
              ],
              if (_buyerCanStartConsumerWithdrawal(o)) ...[
                const SizedBox(height: kChatMessageItemSpacing),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _feedbackBusy
                        ? null
                        : () => _onStartConsumerWithdrawal(o),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: Text(
                      'Exercer livre resolução (14 dias)',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(
                        color: Color(0xFF0F766E),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FleaberRadius.circularSm,
                      ),
                    ),
                  ),
                ),
              ],
              if (imSeller && _sellerCanLeaveFeedback(o)) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: Text(
                      'Deixar avaliação',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: _stickyBarBtnRadius,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedBundleBuyerStickyBar() {
    final bundleId = _focusedBundleId ?? '';
    final meta = _focusedBundleMeta ?? {};
    final total = centsToEur(meta['grand_total_cents']);
    final until = formatBundleDeadlinePt(meta['pay_expires_at']);
    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Portes confirmados — já podes pagar',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101518),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                until == null
                    ? 'Total ${formatBundleEur(total)}. Tens 48 horas para concluir a compra.'
                    : 'Total ${formatBundleEur(total)}. Paga até $until.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.35,
                  color: const Color(0xFF57636C),
                ),
              ),
              const SizedBox(height: 10),
              FleaberPrimaryButton(
                width: double.infinity,
                height: 44,
                borderRadius: 10,
                label: _reservationChatBusy ? 'A abrir…' : 'Pagar',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                onPressed: _reservationChatBusy || bundleId.isEmpty
                    ? null
                    : () async {
                        setState(() => _reservationChatBusy = true);
                        try {
                          await payQuotedBundleCheckout(bundleId: bundleId);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                          await _loadOrderForChat(_product?.id ?? '');
                        } finally {
                          if (mounted) {
                            setState(() => _reservationChatBusy = false);
                          }
                        }
                      },
              ),
              TextButton(
                onPressed: _reservationChatBusy || bundleId.isEmpty
                    ? null
                    : () async {
                        setState(() => _reservationChatBusy = true);
                        try {
                          final res = await batataBundleAbandon(
                            bundleId: bundleId,
                            reason: 'buyer_abandon',
                          );
                          if (res['ok'] != true) {
                            throw Exception(humanizeBundleQuoteError(res));
                          }
                          if (mounted) {
                            await _loadOrderForChat(_product?.id ?? '');
                            setState(() {});
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        } finally {
                          if (mounted) {
                            setState(() => _reservationChatBusy = false);
                          }
                        }
                      },
                child: Text(
                  'Desistir',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedBundleSellerStickyBar() {
    final meta = _focusedBundleMeta ?? {};
    final until = formatBundleDeadlinePt(meta['pay_expires_at']);
    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Text(
            until == null
                ? 'À espera do pagamento da compradora. Os artigos continuam disponíveis para venda.'
                : 'À espera do pagamento até $until. Os artigos continuam disponíveis para venda.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A3D40),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBundleBuyerOperationalStickyBar() {
    final orders = _bundleHeaderOrders;
    final primary = _bundlePrimaryReservationOrder ?? orders.first;
    final st = normalizeOrderStatusKey(primary.status);
    final exp = primary.reservationExpiresAt?.toLocal();
    final showPaymentCountdown =
        exp != null && (st == 'reservado' || st == 'aguarda_confirmacao');
    final awaitingCheckout = bundleOrdersAwaitingCheckoutChoice(orders);
    final directPending = bundleOrdersDirectPaymentPending(orders);
    final awaitingSellerConfirm = bundleOrdersAwaitingSellerPaymentConfirm(orders);
    final bundleId = _focusedBundleId ?? '';

    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFD5E4E6), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: kChatSystemSectionSpacingHalf,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPaymentCountdown)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: _kTeal.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tempo limite para pagar: ${_formatCountdownTo(exp)} – '
                        'Após este tempo, os artigos voltam ao Marketplace.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: const Color(0xFF1A3D40),
                        ),
                      ),
                    ),
                  ],
                ),
              if (awaitingSellerConfirm) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                Text(
                  'Prova de pagamento enviada — aguarda a confirmação do vendedor.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: const Color(0xFF1A3D40),
                  ),
                ),
              ],
              if (awaitingCheckout) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: 'Concluir compra',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  onPressed: _reservationChatBusy || bundleId.isEmpty
                      ? null
                      : () => showBundleAcceptedCheckoutSheet(
                            context: context,
                            bundleId: bundleId,
                            bundleMeta: _focusedBundleMeta,
                            onUpdated: () async {
                              await _loadOrderForChat(_product?.id ?? '');
                              if (mounted) setState(() {});
                            },
                          ),
                ),
              ] else if (directPending && !awaitingSellerConfirm) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: 'Ver dados de pagamento',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  onPressed: _reservationChatBusy || bundleId.isEmpty
                      ? null
                      : () => _openBundleDirectPaymentDetails(bundleId),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed:
                        _reservationChatBusy ? null : _showSubmitProofDialog,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(
                      'Confirmo pagamento',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: _stickyBarBtnRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kChatMessageItemSpacing),
                TextButton(
                  onPressed: _reservationChatBusy || bundleId.isEmpty
                      ? null
                      : () => showBundleAcceptedCheckoutSheet(
                            context: context,
                            bundleId: bundleId,
                            bundleMeta: _focusedBundleMeta,
                            onUpdated: () async {
                              await _loadOrderForChat(_product?.id ?? '');
                              if (mounted) setState(() {});
                            },
                          ),
                  child: Text(
                    'Mudar para Seguro Fleaber',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: _kTeal,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Recomendamos o Seguro Fleaber para maior protecção '
                    'na compra em conjunto.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      height: 1.35,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBundleSellerOperationalStickyBar() {
    final orders = _bundleHeaderOrders;
    if (orders.length < 2 || orders.first.sellerId != currentUserUid) {
      return const SizedBox.shrink();
    }
    final awaitingConfirm = bundleOrdersAwaitingSellerPaymentConfirm(orders);
    final primary = _bundlePrimaryReservationOrder ?? orders.first;
    final st = normalizeOrderStatusKey(primary.status);
    if (!awaitingConfirm &&
        st != 'reservado' &&
        st != 'aguarda_confirmacao') {
      return const SizedBox.shrink();
    }
    final exp = primary.reservationExpiresAt?.toLocal();
    final showPaymentCountdown =
        exp != null && (awaitingConfirm || st == 'reservado');

    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFD5E4E6), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: kChatSystemSectionSpacingHalf,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPaymentCountdown)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: _kTeal.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tempo limite do comprador para pagar: '
                        '${_formatCountdownTo(exp)} – Após este tempo, '
                        'os artigos voltam ao Marketplace.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: const Color(0xFF1A3D40),
                        ),
                      ),
                    ),
                  ],
                ),
              if (awaitingConfirm) ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                Text(
                  'Prova de pagamento enviada — confirma quando o valor '
                  'estiver no teu banco ou MB WAY.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: const Color(0xFF1A3D40),
                  ),
                ),
              ],
              if (showPaymentCountdown || awaitingConfirm)
                const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reservationChatBusy
                          ? null
                          : _onSellerCancelReservationWithDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FleaberColors.danger,
                        side: const BorderSide(
                          color: FleaberColors.danger,
                          width: 1.1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: _stickyBarBtnRadius,
                        ),
                      ),
                      child: Text(
                        'Cancelar Reserva',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Confirmar Receção de Dinheiro',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      height: null,
                      onPressed: _reservationChatBusy
                          ? null
                          : () {
                              // Vendedor confirma que recebeu o dinheiro — não
                              // exige prova prévia do comprador.
                              _confirmSellerMoneyReceivedWithDialog();
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBundleSellerShipStickyBar() {
    final orders = _bundleActivePaidOrders;
    if (orders.isEmpty || orders.first.sellerId != currentUserUid) {
      return const SizedBox.shrink();
    }
    final shipLabel = bundleSellerShipButtonLabel(orders);

    return Material(
      elevation: 0,
      color: const Color(0xFFF0F7F8),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFD5E4E6), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: kChatSystemSectionSpacingHalf,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _bundleSaleCardPrimaryLine(false, shippedPhase: false),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A3D40),
                ),
              ),
              const SizedBox(height: 8),
              FleaberPrimaryButton(
                width: double.infinity,
                height: 44,
                borderRadius: 10,
                label: shipLabel,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                loading: _shippingLabelActionBusy,
                onPressed: _shippingLabelActionBusy
                    ? null
                    : _onSellerConfirmShipment,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBundleDirectPaymentDetails(String bundleId) async {
    try {
      final details =
          await buildBundleDirectPaymentDetails(bundleId: bundleId);
      if (!mounted) return;
      await showBundleDirectPaymentDetailsSheet(context, details: details);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _openOrderDirectPaymentDetails(OrdersRow order) async {
    final oid = order.id?.trim() ?? '';
    final sellerId = order.sellerId?.trim() ?? '';
    if (oid.isEmpty || sellerId.isEmpty) return;
    try {
      final details = await buildOrderDirectPaymentDetails(
        orderId: oid,
        sellerId: sellerId,
        amountEur: order.priceTotal ?? 0,
      );
      if (!mounted) return;
      await showBundleDirectPaymentDetailsSheet(context, details: details);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Widget _buildBundleDirectPaymentDetailsCard(Map<String, dynamic> payload) {
    final amount = (payload['amount_eur'] as num?)?.toDouble() ?? 0.0;
    final bundleId = payload['bundle_id']?.toString() ?? '';
    final orderId = payload['order_id']?.toString() ?? '';
    final imBuyer = (_bundleHeaderOrders.isNotEmpty &&
            _bundleHeaderOrders.first.buyerId == currentUserUid) ||
        _orderForChat?.buyerId == currentUserUid;
    final orderSt = normalizeOrderStatusKey(
      _orderForChat?.status ??
          (_bundleHeaderOrders.isNotEmpty
              ? _bundleHeaderOrders.first.status
              : null),
    );
    final stillNeedsDirectPay = orderSt == 'reservado' ||
        orderSt == 'aguarda_confirmacao' ||
        orderSt.isEmpty;
    final showDetailsButton = imBuyer &&
        stillNeedsDirectPay &&
        (bundleId.isNotEmpty || orderId.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7F8),
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: const Color(0xFFB8D5D8)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    bundleId.isNotEmpty
                        ? 'Pagamento directo — conjunto'
                        : 'Pagamento directo',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stillNeedsDirectPay
                        ? 'Valor a transferir: ${formatEuros(amount)}'
                        : 'Valor: ${formatEuros(amount)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: const Color(0xFF007782),
                    ),
                  ),
                  if (stillNeedsDirectPay) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Toca em «Ver dados de pagamento» para ver MB WAY ou IBAN '
                      'do vendedor. Depois usa «Confirmo pagamento» no topo do chat.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (showDetailsButton) ...[
                    const SizedBox(height: 10),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      height: 40,
                      label: 'Ver dados de pagamento',
                      fontSize: 12.5,
                      onPressed: () {
                        if (bundleId.isNotEmpty) {
                          _openBundleDirectPaymentDetails(bundleId);
                        } else if (_orderForChat != null) {
                          _openOrderDirectPaymentDetails(_orderForChat!);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelRequestChatCard(
    ChatMessagesRow msg,
    List<ChatMessagesRow> allMessages,
  ) {
    final p = _tryParseFleaberChatJson(msg.text);
    final orderId = p?['order_id']?.toString();
    final order = _orderForChat;
    final matchesActiveOrder = orderId != null &&
        order != null &&
        order.id != null &&
        orderId == order.id;
    final resolved = orderId != null &&
        (_cancelOutcomeExistsAfter(allMessages, msg.id, orderId) ||
            (matchesActiveOrder && orderIsCancelled(order?.status)));

    final isSeller = order?.sellerId == currentUserUid;
    final showSellerActions =
        isSeller && orderId != null && !resolved && matchesActiveOrder;
    final cancelReasonRaw = (p?['reason'] ?? '').toString().trim();
    final cancelReason = cancelReasonRaw
        .replaceAll(RegExp(r'\(seed[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bseed\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'H10_TESTE_COMPLETO_\d+'), '')
        .trim();
    final cancelHeadline = cancelReason.isNotEmpty
        ? 'Pedido de cancelamento: $cancelReason'
        : 'Pedido de cancelamento: o comprador deseja anular a compra. '
            'Vendedor, já enviaste o artigo?';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: const Color(0xFFDDE2E7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: _kTeal.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cancelHeadline,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF101518),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (resolved) ...[
                    const SizedBox(height: 10),
                    Text(
                      matchesActiveOrder && orderIsCancelled(order?.status)
                          ? 'Cancelamento aceite — encomenda anulada.'
                          : 'Este pedido já foi respondido.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ] else if (!matchesActiveOrder) ...[
                    const SizedBox(height: kChatMessageItemSpacing),
                    Text(
                      'Pedido relativo a uma encomenda anterior.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ] else if (order?.buyerId == currentUserUid) ...[
                    const SizedBox(height: kChatMessageItemSpacing),
                    Text(
                      'Aguarda a resposta do vendedor.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                  if (showSellerActions && orderId != null) ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelChatBusy
                                ? null
                                : () => _onSellerCancelDecision(
                                      accept: false,
                                      requestMessage: msg,
                                      orderId: orderId,
                                    ),
                            child: const Text('Sim, já enviei'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Não, aceito cancelar',
                            onPressed: _cancelChatBusy
                                ? null
                                : () => _onSellerCancelDecision(
                                      accept: true,
                                      requestMessage: msg,
                                      orderId: orderId,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _reservationExpiryBanner() {
    final order = _orderForChat;
    if (order == null || order.isReservation != true) return null;
    final status = (order.status ?? '').toLowerCase();
    if (status != 'reserva_pendente') return null;
    final exp = order.reservationExpiresAt;
    if (exp == null) return null;
    final now = DateTime.now();
    if (!exp.toLocal().isAfter(now)) {
      return 'Reserva expirada';
    }
    final diff = exp.toLocal().difference(now);
    final days = diff.inHours ~/ 24;
    if (days >= 1) {
      return 'Reserva expira em $days ${days == 1 ? 'dia' : 'dias'}';
    }
    if (diff.inHours >= 1) {
      return 'Reserva expira em ${diff.inHours} horas';
    }
    return 'Reserva expira em breve';
  }

  bool get _shouldShowProofButton {
    if (_hasAcceptedOperationalBundle &&
        bundleOrdersAwaitingSellerPaymentConfirm(_bundleHeaderOrders)) {
      return false;
    }
    if (_hasAcceptedOperationalBundle &&
        bundleOrdersDirectPaymentPending(_bundleHeaderOrders) &&
        _bundleHeaderOrders.first.buyerId == currentUserUid) {
      return true;
    }
    final order = _orderForChat;
    if (order == null) return false;
    if (order.bundleId?.trim().isNotEmpty == true &&
        order.bundleId!.trim() == (_focusedBundleId?.trim() ?? '') &&
        _focusedBundleStatus == 'accepted') {
      return false;
    }
    final status = normalizeOrderStatusKey(order.status);
    final paymentMethod = (order.paymentMethod ?? '').toLowerCase();
    return order.buyerId == currentUserUid &&
        status == 'reservado' &&
        paymentMethod.contains('direto');
  }

  bool _orderWalletReleaseStillRetained(OrdersRow order) {
    return order.data['wallet_release_processed_at'] == null;
  }

  bool _buyerCanResolveDeliveredOrder(OrdersRow order) {
    final status = normalizeOrderStatusKey(order.status);
    final deliveredForValidation = status == 'concluido' || status == 'entregue';
    return order.buyerId == currentUserUid &&
        deliveredForValidation &&
        _orderWalletReleaseStillRetained(order) &&
        !_hasLocalFeedback(order, asBuyer: true) &&
        _localDisputeOpenedOrderId != order.id;
  }

  bool _buyerCanStartConsumerWithdrawal(OrdersRow order) {
    if (order.buyerId != currentUserUid) return false;
    if (!order.isB2cChannel) return false;
    final exc = (order.withdrawalExceptionCode ?? '').trim();
    if (exc.isNotEmpty) return false;
    final st = (order.consumerWithdrawalStatus ?? '').trim().toLowerCase();
    if (st == 'requested' ||
        st == 'return_in_transit' ||
        st == 'open' ||
        st == 'refunded') {
      return false;
    }
    final deadline = order.consumerWithdrawalDeadlineAt;
    if (deadline == null || deadline.isBefore(DateTime.now())) return false;
    final status = normalizeOrderStatusKey(order.status);
    return status == 'concluido' || status == 'entregue';
  }

  Future<void> _onStartConsumerWithdrawal(OrdersRow order) async {
    final id = order.id?.trim();
    if (id == null || id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exercer livre resolução'),
        content: const Text(
          'Tens 14 dias após a receção para desistir da compra sem indicar '
          'motivo (salvo excepções legais). Vais devolver o artigo; a Fleaber '
          'executa o reembolso Stripe quando a devolução estiver concluída. '
          'Isto é distinto de «Tenho um problema» (Proteção Fleaber, 48 h).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton(
            label: 'Confirmar pedido',
            height: 40,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_start_consumer_withdrawal',
        params: {'p_order_id': id},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      if (map?['ok'] != true) {
        final err = map?['error']?.toString() ?? 'pedido_falhou';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir a livre resolução ($err).')),
        );
        return;
      }
      order.data['consumer_withdrawal_status'] = 'requested';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Livre resolução pedida. Segue as instruções de devolução no chat.',
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na livre resolução: $e')),
      );
    }
  }

  bool _hasLocalFeedback(OrdersRow order, {required bool asBuyer}) {
    return asBuyer ? _buyerFeedbackDone : _sellerFeedbackDone;
  }

  bool _sellerCanLeaveFeedback(OrdersRow order) {
    if (order.sellerId != currentUserUid) return false;
    if (normalizeOrderStatusKey(order.status) != 'concluido') return false;
    return !_sellerFeedbackDone;
  }

  bool _buyerCanLeaveFeedbackOnly(OrdersRow order) {
    if (order.buyerId != currentUserUid) return false;
    if (normalizeOrderStatusKey(order.status) != 'concluido') return false;
    return !_buyerFeedbackDone;
  }

  String _disputeReasonLabel(String reason) {
    switch (reason) {
      case 'danificado':
        return 'Artigo Danificado';
      case 'nao_corresponde':
        return 'Não corresponde à descrição';
      case 'em_falta':
        return 'Artigo/peça em falta';
      case 'outro':
        return 'Outro problema';
      default:
        return reason;
    }
  }

  Future<_DisputeThread?> _fetchDisputeThread(String orderId) async {
    final disputes = await OrderDisputesTable().queryRows(
      queryFn: (q) => q.eqOrNull('order_id', orderId),
      limit: 1,
    );
    if (disputes.isEmpty) return null;
    final dispute = disputes.first;
    // Sempre refrescar a encomenda da disputa (evita status stale no cache).
    final oid = orderId.trim();
    if (oid.isNotEmpty) {
      try {
        final orows = await OrdersTable().querySingleRow(
          queryFn: (q) => q.eqOrNull('id', oid),
        );
        if (orows.isNotEmpty) {
          _ordersByIdForChat[oid] = orows.first;
        }
      } catch (_) {}
    }
    final disputeId = dispute.id;
    final replies = disputeId == null || disputeId.isEmpty
        ? <OrderDisputeRepliesRow>[]
        : await OrderDisputeRepliesTable().queryRows(
            queryFn: (q) => q
                .eqOrNull('dispute_id', disputeId)
                .order('created_at', ascending: true),
            limit: 80,
          );
    return _DisputeThread(dispute: dispute, replies: replies);
  }

  Future<_DisputeThread?> _loadDisputeThread(
    String orderId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh &&
        _disputeThreadOrderId == orderId &&
        _disputeThreadFuture != null) {
      return _disputeThreadFuture!;
    }

    _disputeThreadOrderId = orderId;
    _disputeThreadFuture = _fetchDisputeThread(orderId).then((thread) {
      if (_disputeThreadOrderId == orderId) {
        _disputeThreadCache = thread;
      }
      return thread;
    });
    return _disputeThreadFuture!;
  }

  Future<_DisputeThread?> _refreshDisputeThreadForOrder(String? orderId) async {
    final id = orderId?.trim();
    if (id == null || id.isEmpty) return null;
    _disputeThreadFuture = null;
    return _loadDisputeThread(id, forceRefresh: true);
  }

  Future<_DisputeThread?> _activeDisputeForCurrentOrder() async {
    final orderId = _orderForChat?.id;
    if (orderId == null || orderId.isEmpty) return null;
    return _loadDisputeThread(orderId);
  }

  Future<void> _maybeSimulateReturnDelivery() async {
    final order = _orderForChat;
    if (order == null || normalizeOrderStatusKey(order.status) != 'em_devolucao') {
      return;
    }
    final thread = await _activeDisputeForCurrentOrder();
    final dispute = thread?.dispute;
    final labelAt = dispute?.returnLabelCreatedAt;
    if (dispute == null || labelAt == null) return;
    final elapsed = DateTime.now().toUtc().difference(labelAt.toUtc());
    if (elapsed < const Duration(minutes: 1)) return;
    final now = DateTime.now().toUtc();
    await OrdersTable().update(
      data: {'status': 'devolucao_entregue'},
      matchingRows: (rows) => rows.eqOrNull('id', order.id),
    );
    await OrderDisputesTable().update(
      data: {
        'return_delivered_at': now.toIso8601String(),
        'seller_inspection_deadline':
            now.add(const Duration(days: 2)).toIso8601String(),
        'current_turn': 'vendedor',
        'next_deadline': now.add(const Duration(days: 2)).toIso8601String(),
      },
      matchingRows: (rows) => rows.eqOrNull('id', dispute.id),
    );
    await _refreshDisputeThreadForOrder(order.id);
    _orderForChat = OrdersRow({
      ...order.data,
      'status': 'devolucao_entregue',
    });
  }

  Future<List<String>> _uploadDisputePhotos(
    String disputeOrOrderId,
    List<XFile> photos,
  ) async {
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final bytes = await photo.readAsBytes();
      final safeName = photo.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      urls.add(
        await FleaberPrivateStorage.uploadOrderDisputePhoto(
          bytes: bytes,
          fileName: safeName,
          disputeOrOrderId: disputeOrOrderId,
          index: i,
        ),
      );
    }
    return urls;
  }

  Future<void> _showSubmitProofDialog() async {
    if (!_shouldShowProofButton) return;
    final notesController = TextEditingController();
    XFile? selectedFile;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: FleaberRadius.circularMd,
              ),
              title: Text(
                'Enviar Prova de Pagamento',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101518),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Usa este botão se pagaste por MB WAY/transferência direta fora da app.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesController,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF101518),
                      ),
                      decoration: InputDecoration(
                        labelText: 'Notas',
                        hintText: 'Ex.: MB WAY enviado às 10:42',
                        labelStyle: GoogleFonts.inter(
                          color: const Color(0xFF57636C),
                        ),
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF9AA4B2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E3E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                          borderSide:
                              const BorderSide(color: _kTeal, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: kChatSystemSectionSpacing),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (picked == null) return;
                        setDialogState(() => selectedFile = picked);
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        selectedFile == null
                            ? 'Anexar ficheiro/imagem da prova'
                            : 'Anexo: ${selectedFile!.name}',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: const BorderSide(color: _kTeal),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Voltar'),
                ),
                FleaberPrimaryButton(
                  label: 'Confirmar',
                  height: null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  maxLines: 1,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      return;
    }

    await _submitProofForOrder(
      image: selectedFile,
      notes: notesController.text.trim(),
    );
  }

  Future<void> _submitProofForOrder({
    required XFile? image,
    required String notes,
  }) async {
    final chatId = widget.chatId;
    final sellerId = widget.otherUserId;
    if (chatId == null ||
        chatId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return;
    }
    if (!_shouldShowProofButton) return;

    final bundleProof =
        _hasAcceptedOperationalBundle &&
            bundleOrdersDirectPaymentPending(_bundleHeaderOrders);
    final ordersToUpdate = bundleProof
        ? _bundleHeaderOrders
            .where(
              (o) => normalizeOrderStatusKey(o.status) == 'reservado',
            )
            .toList()
        : <OrdersRow>[];
    final order = bundleProof
        ? (ordersToUpdate.isNotEmpty ? ordersToUpdate.first : null)
        : _orderForChat;
    if (order == null || order.id == null) return;

    setState(() => _reservationChatBusy = true);
    try {
      String? proofUrl;
      if (image != null) {
        final bytes = await image.readAsBytes();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        proofUrl = await FleaberPrivateStorage.uploadOrderProof(
          bytes: bytes,
          fileName: fileName,
          orderId: order.id!,
        );
      }

      final orderUpdate = <String, dynamic>{
        'status': 'aguarda_confirmacao',
      };
      if (proofUrl != null && proofUrl.isNotEmpty) {
        orderUpdate['proof_url'] = proofUrl;
      }
      if (bundleProof) {
        for (final o in ordersToUpdate) {
          final oid = o.id;
          if (oid == null || oid.isEmpty) continue;
          await OrdersTable().update(
            data: orderUpdate,
            matchingRows: (rows) => rows.eqOrNull('id', oid),
          );
        }
      } else {
        await OrdersTable().update(
          data: orderUpdate,
          matchingRows: (rows) => rows.eqOrNull('id', order.id),
        );
      }
      final payload = <String, dynamic>{
        'kind': 'reservation_payment_submitted',
        'order_id': order.id,
        'notes': notes,
        'v': 1,
      };
      if (bundleProof && _focusedBundleId != null) {
        payload['bundle_id'] = _focusedBundleId;
      }
      if (proofUrl != null && proofUrl.isNotEmpty) {
        payload['proof_url'] = proofUrl;
      }
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': sellerId,
        'is_read': false,
        'text': _fleaberChatJsonEncode(payload),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await _touchChatLastMessage('Prova de pagamento enviada');
      await _loadOrderForChat(_product?.id ?? order.productId ?? '');
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prova de pagamento enviada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao submeter prova de pagamento.')),
      );
      print('ERRO SUBMETER_COMPROVATIVO: $e');
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _openBuyerDisputeSheet() async {
    final order = _orderForChat;
    if (order == null ||
        order.id == null ||
        order.id!.isEmpty ||
        widget.chatId == null ||
        widget.chatId!.isEmpty ||
        order.sellerId == null ||
        order.sellerId!.isEmpty ||
        !_buyerCanResolveDeliveredOrder(order)) {
      return;
    }

    final descriptionController = TextEditingController();
    final selectedPhotos = <XFile>[];
    var reason = 'danificado';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        var submitting = false;
        var descriptionTooShort = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            final descLen = _normalizeDisputeDescription(
              descriptionController.text,
            ).length;
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, bottomInset + 18),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7E2E5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tenho um problema',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: kChatMessageItemSpacing),
                    Text(
                      'Explica o que aconteceu. O saldo desta venda fica retido enquanto a disputa é analisada.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        color: const Color(0xFF57636C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: reason,
                      decoration: InputDecoration(
                        labelText: 'Motivo',
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'danificado',
                          child: Text('Artigo Danificado'),
                        ),
                        DropdownMenuItem(
                          value: 'nao_corresponde',
                          child: Text('Não corresponde à descrição'),
                        ),
                        DropdownMenuItem(
                          value: 'em_falta',
                          child: Text('Artigo/peça em falta'),
                        ),
                        DropdownMenuItem(
                          value: 'outro',
                          child: Text('Outro problema'),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setSheetState(() => reason = value);
                            },
                    ),
                    const SizedBox(height: kChatSystemSectionSpacing),
                    TextField(
                      controller: descriptionController,
                      enabled: !submitting,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: 'Descrição do problema',
                        hintText: 'Ex.: o artigo chegou rasgado na manga...',
                        helperText:
                            'Mínimo $_kDisputeDescriptionMinChars caracteres a explicar o problema.',
                        errorText: descriptionTooShort
                            ? 'Escreve pelo menos $_kDisputeDescriptionMinChars caracteres antes de abrir a disputa.'
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                        enabledBorder: descriptionTooShort
                            ? OutlineInputBorder(
                                borderRadius: FleaberRadius.circularMd,
                                borderSide: const BorderSide(
                                  color: Color(0xFFC62828),
                                  width: 1.4,
                                ),
                              )
                            : null,
                        focusedBorder: descriptionTooShort
                            ? OutlineInputBorder(
                                borderRadius: FleaberRadius.circularMd,
                                borderSide: const BorderSide(
                                  color: Color(0xFFC62828),
                                  width: 1.6,
                                ),
                              )
                            : null,
                      ),
                      onChanged: (_) => setSheetState(() {
                        descriptionTooShort = false;
                      }),
                    ),
                    const SizedBox(height: kChatSystemSectionSpacing),
                    OutlinedButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              final remaining = 4 - selectedPhotos.length;
                              if (remaining <= 0) return;
                              final picked = await _picker.pickMultiImage(
                                imageQuality: 82,
                                limit: remaining,
                              );
                              if (picked == null || picked.isEmpty) return;
                              setSheetState(() {
                                selectedPhotos.addAll(picked.take(remaining));
                              });
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        selectedPhotos.isEmpty
                            ? 'Adicionar fotos de prova'
                            : '${selectedPhotos.length} foto(s) adicionada(s)',
                      ),
                    ),
                    if (selectedPhotos.isNotEmpty) ...[
                      const SizedBox(height: kChatMessageItemSpacing),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < selectedPhotos.length; i++)
                            Chip(
                              label: Text(
                                selectedPhotos[i].name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: submitting
                                  ? null
                                  : () => setSheetState(
                                        () => selectedPhotos.removeAt(i),
                                      ),
                            ),
                        ],
                      ),
                    ],
                    if (descriptionTooShort) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: FleaberRadius.circularSm,
                          border: Border.all(color: const Color(0xFFEF9A9A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Color(0xFFC62828),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                descLen == 0
                                    ? 'Para abrir a disputa tens de descrever o problema (mínimo $_kDisputeDescriptionMinChars caracteres).'
                                    : 'A descrição ainda é demasiado curta ($descLen/$_kDisputeDescriptionMinChars). Explica o que aconteceu.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFB71C1C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Abrir disputa',
                      loading: submitting,
                      fontWeight: FontWeight.w800,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      height: null,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      onPressed: submitting
                          ? null
                          : () async {
                              final desc = _normalizeDisputeDescription(
                                descriptionController.text,
                              );
                              if (desc.length < _kDisputeDescriptionMinChars) {
                                setSheetState(() => descriptionTooShort = true);
                                return;
                              }
                              setSheetState(() {
                                descriptionTooShort = false;
                                submitting = true;
                              });
                              setState(() => _disputeBusy = true);
                              try {
                                await _submitBuyerDispute(
                                  order: order,
                                  reason: reason,
                                  description: desc,
                                  photos: List<XFile>.from(selectedPhotos),
                                );
                                if (!mounted) return;
                                Navigator.of(sheetContext).pop(true);
                              } catch (e) {
                                print('BATATA_DISPUTE ERRO: $e');
                                if (!mounted) return;
                                final msg = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                final isDescError = msg.contains('caracteres');
                                if (isDescError) {
                                  setSheetState(() {
                                    descriptionTooShort = true;
                                    submitting = false;
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao abrir disputa: $msg'),
                                    ),
                                  );
                                  setSheetState(() => submitting = false);
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _disputeBusy = false);
                                }
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disputa aberta.')),
      );
    }
  }

  Future<void> _openDisputeReplySheet(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final order = _orderForChat;
    if (disputeId == null || disputeId.isEmpty || order == null) return;
    final controller = TextEditingController();
    final selectedPhotos = <XFile>[];
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        var submitting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            final canSubmit = !submitting && controller.text.trim().length >= 3;
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, bottomInset + 18),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Responder à disputa',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: kChatSystemSectionSpacing),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 6,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'Mensagem',
                        border: OutlineInputBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: kChatSystemSectionSpacing),
                    OutlinedButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              final remaining = 4 - selectedPhotos.length;
                              if (remaining <= 0) return;
                              final picked = await _picker.pickMultiImage(
                                imageQuality: 82,
                                limit: remaining,
                              );
                              if (picked == null || picked.isEmpty) return;
                              setSheetState(() {
                                selectedPhotos.addAll(picked.take(remaining));
                              });
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        selectedPhotos.isEmpty
                            ? 'Adicionar fotos'
                            : '${selectedPhotos.length} foto(s) adicionada(s)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Enviar resposta',
                      loading: submitting,
                      onPressed: canSubmit
                          ? () async {
                              setSheetState(() => submitting = true);
                              setState(() => _disputeBusy = true);
                              try {
                                await _submitDisputeReply(
                                  thread: thread,
                                  message: controller.text.trim(),
                                  photos: List<XFile>.from(selectedPhotos),
                                );
                                if (!mounted) return;
                                Navigator.of(sheetContext).pop(true);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro na disputa: $e'),
                                  ),
                                );
                                setSheetState(() => submitting = false);
                              } finally {
                                if (mounted) {
                                  setState(() => _disputeBusy = false);
                                }
                              }
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resposta enviada.')),
      );
    }
  }

  Future<void> _submitDisputeReply({
    required _DisputeThread thread,
    required String message,
    required List<XFile> photos,
  }) async {
    final dispute = thread.dispute;
    final disputeId = dispute.id;
    final order = _orderForChat;
    if (disputeId == null || disputeId.isEmpty || order == null) return;
    final isSeller = order.sellerId == currentUserUid;
    final isBuyer = order.buyerId == currentUserUid;
    final urls = await _uploadDisputePhotos(disputeId, photos);
    await OrderDisputeRepliesTable().insert({
      'dispute_id': disputeId,
      'sender_id': currentUserUid,
      'message': message,
      'proof_photos': urls,
    });

    final update = <String, dynamic>{
      'next_deadline': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 72))
          .toIso8601String(),
    };
    if (isSeller && dispute.currentTurn == 'vendedor') {
      update['status'] = 'respondida_vendedor';
      update['current_turn'] = 'comprador';
    } else if (isBuyer && dispute.currentTurn == 'comprador') {
      update['status'] = 'respondida_comprador';
      update['current_turn'] = 'vendedor';
    }
    await OrderDisputesTable().update(
      data: update,
      matchingRows: (rows) => rows.eqOrNull('id', disputeId),
    );
    await _touchChatLastMessage('Nova resposta na disputa');
    await _refreshDisputeThreadForOrder(order.id);
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _refundSeguroBeforeDevolvida(String orderId) async {
    if (!orderIsSeguroFleaberPayment(_orderForChat?.paymentMethod)) {
      return true;
    }
    final refund = await requestSeguroFleaberStripeRefund(orderId: orderId);
    if (refund.stripeRefundSucceeded) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refund.stripeRefundError ??
              'Não foi possível reembolsar o comprador. Tenta outra vez.',
        ),
      ),
    );
    return false;
  }

  Future<void> _sellerAcceptDispute(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      if (!await _refundSeguroBeforeDevolvida(orderId)) return;
      await OrderDisputesTable().update(
        data: {
          'status': 'resolvida',
          'current_turn': 'administracao',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': 'devolvida'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await _touchChatLastMessage('Disputa aceite pelo vendedor');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _sellerOfferReturn(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    if (disputeId == null) return;
    var sellerPaysShipping = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Aceitar devolução?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Por defeito, os portes da devolução são responsabilidade do comprador.',
              ),
              CheckboxListTile(
                value: sellerPaysShipping,
                onChanged: (value) {
                  setDialogState(() => sellerPaysShipping = value == true);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Ofereço-me para pagar os portes'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar proposta'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _disputeBusy = true);
    try {
      final now = DateTime.now().toUtc();
      final nextOfferType = thread.dispute.sellerOfferType == 'partial_refund'
          ? 'return_and_partial_refund'
          : 'return';
      await OrderDisputesTable().update(
        data: {
          'seller_offer_type': nextOfferType,
          'seller_pays_return_shipping': sellerPaysShipping,
          'seller_refund_percent': thread.dispute.sellerRefundPercent,
          'status': 'respondida_vendedor',
          'current_turn': 'comprador',
          'next_deadline': now.add(const Duration(hours: 72)).toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message': sellerPaysShipping
            ? 'O vendedor aceita a devolução e oferece-se para pagar os portes.'
            : 'O vendedor aceita a devolução. Os portes ficam a cargo do comprador.',
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Vendedor aceitou devolução');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _sellerOfferPartialRefund(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    if (disputeId == null) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oferecer reembolso parcial'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Percentagem do reembolso',
            hintText: 'Ex.: 20',
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enviar proposta'),
          ),
        ],
      ),
    );
    final percent = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (ok != true || percent == null || percent <= 0 || percent > 100) return;
    setState(() => _disputeBusy = true);
    try {
      final now = DateTime.now().toUtc();
      final nextOfferType = thread.dispute.sellerOfferType == 'return'
          ? 'return_and_partial_refund'
          : 'partial_refund';
      await OrderDisputesTable().update(
        data: {
          'seller_offer_type': nextOfferType,
          'seller_refund_percent': percent,
          'seller_pays_return_shipping': thread.dispute.sellerPaysReturnShipping,
          'status': 'respondida_vendedor',
          'current_turn': 'comprador',
          'next_deadline': now.add(const Duration(hours: 72)).toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message':
            'O vendedor propôs reembolsar ${percent.toStringAsFixed(0)}% do valor e o comprador fica com o artigo.',
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Vendedor propôs reembolso parcial');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerCloseDispute(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      await OrdersTable().update(
        data: {'status': 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      try {
        await SupaFlow.client.rpc(
          'batata_release_seller_wallet_for_order',
          params: {'p_order_id': orderId},
        );
      } catch (_) {}
      await OrderDisputesTable().update(
        data: {
          'status': 'resolvida',
          'current_turn': 'administracao',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await _touchChatLastMessage('Disputa fechada pelo comprador');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerCancelDispute(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      await OrderDisputesTable().update(
        data: {
          'status': 'resolvida',
          'current_turn': 'administracao',
          'buyer_decision': 'cancelled',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await _touchChatLastMessage('Disputa cancelada pelo comprador');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerRejectOffer(
    _DisputeThread thread,
    String rejectedOffer,
  ) async {
    final disputeId = thread.dispute.id;
    if (disputeId == null) return;
    final current = thread.dispute.sellerOfferType;
    String? nextOfferType;
    if (current == 'return_and_partial_refund') {
      nextOfferType =
          rejectedOffer == 'return' ? 'partial_refund' : 'return';
    } else if (current == rejectedOffer) {
      nextOfferType = null;
    } else {
      nextOfferType = current;
    }

    final rejectedText = rejectedOffer == 'return'
        ? 'O comprador recusou a devolução proposta.'
        : 'O comprador recusou o reembolso parcial proposto.';

    setState(() => _disputeBusy = true);
    try {
      await OrderDisputesTable().update(
        data: {
          'seller_offer_type': nextOfferType,
          if (rejectedOffer == 'return') 'seller_pays_return_shipping': false,
          if (rejectedOffer == 'partial_refund') 'seller_refund_percent': null,
          'status': 'respondida_comprador',
          'current_turn': 'vendedor',
          'next_deadline': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 72))
              .toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message': rejectedText,
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Comprador recusou uma proposta');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerAcceptReturn(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      final now = DateTime.now().toUtc();
      final labelDeadline =
          now.add(const Duration(days: ReturnLabelRules.downloadDays));
      final labelUrl = 'https://fleaber.app/return-label/$orderId';
      await OrderDisputesTable().update(
        data: {
          'buyer_decision': 'accepted_return',
          'status': 'respondida_comprador',
          'current_turn': 'comprador',
          'return_label_created_at': now.toIso8601String(),
          'return_label_deadline': labelDeadline.toIso8601String(),
          'return_label_url': labelUrl,
          'next_deadline': labelDeadline.toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': 'em_devolucao'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message':
            'O comprador aceitou devolver o artigo. Etiqueta de devolução disponível durante ${ReturnLabelRules.downloadDays} dias.',
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Devolução iniciada pelo comprador');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerAcceptPartialRefund(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = (thread.dispute.orderId ??
            thread.dispute.data['order_id'] ??
            _orderForChat?.id)
        ?.toString()
        .trim();
    if (disputeId == null ||
        disputeId.isEmpty ||
        orderId == null ||
        orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar a disputa.')),
      );
      return;
    }
    setState(() => _disputeBusy = true);
    try {
      final percent = thread.dispute.sellerRefundPercent ?? 0;
      final seguroFull =
          percent >= 100 && orderIsSeguroFleaberPayment(_orderForChat?.paymentMethod);
      if (seguroFull) {
        final refund = await requestSeguroFleaberStripeRefund(orderId: orderId);
        if (!refund.stripeRefundSucceeded) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                refund.stripeRefundError ??
                    'Não foi possível concluir o reembolso. Tenta outra vez.',
              ),
            ),
          );
          return;
        }
      } else {
        await SupaFlow.client.rpc(
          'batata_process_partial_refund_dispute',
          params: {
            'p_order_id': orderId,
            'p_refund_percent': percent,
          },
        );
      }
      await OrderDisputesTable().update(
        data: {
          'buyer_decision': 'accepted_partial_refund',
          'status': 'resolvida',
          'current_turn': 'administracao',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': seguroFull ? 'devolvida' : 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await _touchChatLastMessage(
        seguroFull ? 'Reembolso total aceite' : 'Reembolso parcial aceite',
      );
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(orderId);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível concluir o reembolso parcial. Tenta de novo ou contacta o suporte.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _sellerConfirmReturnOk(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      if (!await _refundSeguroBeforeDevolvida(orderId)) return;
      await OrderDisputesTable().update(
        data: {
          'status': 'resolvida',
          'current_turn': 'administracao',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': 'devolvida'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await _touchChatLastMessage('Devolução validada pelo vendedor');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _sellerOpenReturnIssue(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      final now = DateTime.now().toUtc();
      await OrderDisputesTable().update(
        data: {
          'status': 'escalada_fleaber',
          'current_turn': 'administracao',
          'seller_return_issue_at': now.toIso8601String(),
          'next_deadline': now.toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await OrdersTable().update(
        data: {'status': 'disputa_devolucao_vendedor'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await OrderDisputeRepliesTable().insert({
        'dispute_id': disputeId,
        'sender_id': currentUserUid,
        'message':
            'O vendedor reportou problema com a devolução. A disputa foi enviada para o Fleaber decidir.',
        'proof_photos': const <String>[],
      });
      await _touchChatLastMessage('Problema na devolução escalado ao Fleaber');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível reportar o problema: $e')),
      );
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _buyerEscalateDispute(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    if (disputeId == null) return;
    setState(() => _disputeBusy = true);
    try {
      await OrderDisputesTable().update(
        data: {
          'status': 'escalada_fleaber',
          'current_turn': 'administracao',
          'next_deadline': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', disputeId),
      );
      await _touchChatLastMessage('Disputa entregue à Administração Fleaber');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _disputeBusy = false);
    }
  }

  Future<void> _submitBuyerDispute({
    required OrdersRow order,
    required String reason,
    required String description,
    required List<XFile> photos,
  }) async {
    final orderId = order.id;
    final sellerId = order.sellerId;
    final chatId = widget.chatId;
    if (orderId == null ||
        orderId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty ||
        chatId == null ||
        chatId.isEmpty) {
      throw Exception('Dados da encomenda incompletos.');
    }
    if (!_buyerCanResolveDeliveredOrder(order)) {
      throw Exception('Esta encomenda já não permite abrir disputa.');
    }

    final desc = _normalizeDisputeDescription(description);
    if (desc.length < _kDisputeDescriptionMinChars) {
      throw Exception(
        'Escreve pelo menos $_kDisputeDescriptionMinChars caracteres a explicar o problema.',
      );
    }

    final proofUrls = await _uploadDisputePhotos(orderId, photos);

    await OrderDisputesTable().insert({
      'order_id': orderId,
      'buyer_id': currentUserUid,
      'reason': reason,
      'description': desc,
      'proof_photos': proofUrls,
      'status': 'aberta',
      'current_turn': 'vendedor',
      'next_deadline': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 72))
          .toIso8601String(),
    });

    await OrdersTable().update(
      data: {'status': 'pedido_devolucao'},
      matchingRows: (rows) => rows.eqOrNull('id', orderId),
    );

    final motivo = _disputeReasonLabel(reason);
    await ChatMessagesTable().insert({
      'sender_id': currentUserUid,
      'receiver_id': sellerId,
      'is_read': false,
      'text': _fleaberChatJsonEncode({
        'kind': 'order_dispute_opened',
        'order_id': orderId,
        'reason': motivo,
        'description': desc,
        'proof_photos': proofUrls,
        'v': 1,
      }),
      'chat_id': chatId,
      'is_reservation': true,
    });
    await _touchChatLastMessage('Disputa aberta pelo comprador');
    _localDisputeOpenedOrderId = orderId;
    await _loadOrderForChat(order.productId ?? '');
    await _refreshDisputeThreadForOrder(orderId);
    requestMarketplaceFeedRefresh();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _orderRefreshTimer?.cancel();
    _reservationUiTimer?.cancel();
    _messagesScrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  void _onBuyerTapSecureFleaberPayFromReservation() {
    final p = _product;
    if (p == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abre este chat a partir do artigo para usares o checkout.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    context.push(
      '/productDetails',
      extra: {
        _kProductRouteExtraKey: Map<String, dynamic>.from(p.data),
        _kFleaberOpenCheckoutExtra: true,
      },
    );
  }

  Future<void> _onBuyerPayRafflePrizeShipping() async {
    final order = _orderForChat;
    final product = _product;
    if (order == null || product == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abre este chat a partir do artigo do prémio para pagar o envio.',
          ),
        ),
      );
      return;
    }
    if (normalizeOrderStatusKey(order.status) != 'premio_rifa') return;
    if (!mounted) return;

    final sellerName = _otherUser?.fullName?.trim();
    final result = await LiveRafflePrizeShippingSheet.show(
      context: context,
      order: order,
      product: product,
      sellerDisplayName: sellerName,
    );
    if (!mounted) return;
    if (result == LiveRafflePrizeShippingResult.browseSeller) {
      unawaited(_openRafflePrizeSellerShop());
      return;
    }
    if (result == LiveRafflePrizeShippingResult.handConfirmed) {
      final pid = order.productId?.trim() ?? _product?.id?.trim() ?? '';
      final chatId = widget.chatId?.trim() ?? '';
      final sellerId = order.sellerId?.trim() ?? '';
      if (chatId.isNotEmpty && sellerId.isNotEmpty) {
        try {
          await ChatMessagesTable().insert({
            'sender_id': currentUserUid,
            'receiver_id': sellerId,
            'chat_id': chatId,
            'text':
                'Escolhi entrega em mão para o Prémio da Rifa. Combinamos o encontro.',
            'is_read': false,
            'is_reservation': false,
          });
          await _touchChatLastMessage(
            'Prémio da Rifa · entrega em mão combinada',
          );
        } catch (_) {}
      }
      if (pid.isNotEmpty) {
        await _loadOrderForChat(pid);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entrega em mão confirmada. Combina o encontro com a vendedora. '
            'Quando receberes, confirma a receção no chat para deixar feedback.',
          ),
        ),
      );
      setState(() {});
      return;
    }
    if (result == LiveRafflePrizeShippingResult.paidStripeOpened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conclui o pagamento do envio no ecrã Stripe.'),
        ),
      );
    }
  }

  void _openProductDetails(ProductsRow p) {
    context.push(
      '/productDetails',
      extra: {
        _kProductRouteExtraKey: Map<String, dynamic>.from(p.data),
      },
    );
  }

  Future<void> _loadPendingBuyerOffer() async {
    final p = _product;
    final pid = p?.id;
    if (pid == null ||
        pid.isEmpty ||
        p!.sellerId == currentUserUid ||
        currentUserUid.isEmpty) {
      _pendingBuyerOffer = null;
      return;
    }
    _pendingBuyerOffer = await fetchPendingOfferForProductBuyer(
      productId: pid,
      buyerId: currentUserUid,
    );
  }

  Future<void> _onFazerProposta(ProductsRow p) async {
    if (p.isSold || _offerChatBusy) return;
    if (p.sellerId == currentUserUid) return;

    final altering = _pendingBuyerOffer != null;
    final amount = await showProductOfferAmountSheet(
      context: context,
      product: p,
      title: altering ? 'Alterar proposta' : 'Fazer proposta',
      subtitle: altering
          ? 'Envia um novo valor. A proposta anterior deixa de estar activa.'
          : null,
    );
    if (amount == null || !mounted) return;

    setState(() => _offerChatBusy = true);
    try {
      await createBuyerPriceOffer(product: p, amountEur: amount);
      if (!mounted) return;
      await _loadPendingBuyerOffer();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            altering
                ? 'Proposta actualizada para ${formatEuros(amount)}.'
                : 'Proposta de ${formatEuros(amount)} enviada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _offerChatBusy = false);
    }
  }

  void _onComprar(ProductsRow p) {
    if (p.isSold) return;
    _openProductDetails(p);
  }

  // Media de chat → fleaber_private (URL assinada; sem CDN público).
  Future<void> pickMedia() async {
    try {
      final XFile? media = await _picker.pickMedia();
      if (media != null) {
        final chatId = widget.chatId?.trim() ?? '';
        if (chatId.isEmpty) return;
        final bytes = await media.readAsBytes();
        final String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${media.name}';
        final uploaded = await FleaberPrivateStorage.uploadChatMedia(
          bytes: bytes,
          fileName: fileName,
          chatId: chatId,
        );

        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': widget.otherUserId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'chat_image',
            'path': uploaded.path,
            'url': uploaded.signedUrl,
            'v': 2,
          }),
          'chat_id': widget.chatId,
          'is_reservation': false,
        });
        await ChatsTable().update(
          data: {
            'last_message': '[Media]',
            'last_message_time': DateTime.now().toUtc().toIso8601String(),
          },
          matchingRows: (rows) => rows.eqOrNull('id', widget.chatId),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Erro ao carregar ficheiro. Tenta outra vez ou verifica a ligação.')),
      );
    }
  }

  String getDisplayDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (dateToCheck == today) return 'Hoje';
    if (dateToCheck == yesterday) return 'Ontem';
    return DateFormat('dd/MM/yyyy').format(dateTime);
  }

  String _formatProductPrice(double? price) {
    if (price == null) return '—';
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(price);
  }

  String _lastSeenLine() {
    final t = _chat?.lastMessageTime;
    if (t == null) return 'Sem informação recente';
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    if (d == today) {
      return 'Hoje, ${DateFormat('HH:mm').format(local)}';
    }
    final y = today.subtract(const Duration(days: 1));
    if (d == y) {
      return 'Ontem, ${DateFormat('HH:mm').format(local)}';
    }
    return DateFormat("dd/MM/yyyy 'às' HH:mm").format(local);
  }

  void _openOtherUserProfile() {
    final uid = _resolvedOtherUserId() ?? '';
    if (uid.isEmpty || uid == currentUserUid) return;
    if (_otherUserIsAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta de apoio Fleaber — sem perfil público de vendedor.'),
        ),
      );
      return;
    }
    unawaited(HubActions.openPublicProfile(context, sellerId: uid));
  }

  /// CTA «Ver loja» / «Ver mais desta vendedora» no prémio da rifa —
  /// abre o perfil na aba Marketplace se houver artigos; senão Diretos.
  Future<void> _openRafflePrizeSellerShop() async {
    final fromOrder = _orderForChat?.sellerId?.trim() ?? '';
    final fromProduct = _product?.sellerId?.trim() ?? '';
    final sellerId =
        (fromOrder.isNotEmpty ? fromOrder : fromProduct).trim();
    if (sellerId.isEmpty || sellerId == currentUserUid) {
      _openOtherUserProfile();
      return;
    }

    var tab = 'diretos';
    try {
      final rows = await ProductsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sellerId)
            .eq('list_on_marketplace', true)
            .eq('is_sold', false),
        limit: 1,
      );
      if (rows.isNotEmpty) tab = 'marketplace';
    } catch (_) {
      tab = 'marketplace';
    }

    if (!mounted) return;
    await HubActions.openPublicProfile(
      context,
      sellerId: sellerId,
      initialTab: tab,
    );
  }

  /// Abre a página gémea do conjunto para juntar peças ao envio do prémio.
  void _openJuntarAoPremio() {
    final order = _orderForChat;
    final sellerId = order?.sellerId?.trim() ??
        _product?.sellerId?.trim() ??
        '';
    final chatId = widget.chatId?.trim() ?? '';
    final prizeOrderId = order?.id?.trim() ?? '';
    final prizeProductId = order?.productId?.trim() ?? _product?.id?.trim();
    if (sellerId.isEmpty || chatId.isEmpty || prizeOrderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a loja do prémio. Reabre o chat.'),
        ),
      );
      return;
    }
    context.pushNamed(
      JuntarAoPremioPageWidget.routeName,
      queryParameters: {
        'sellerId': serializeParam(sellerId, ParamType.String),
        'chatId': serializeParam(chatId, ParamType.String),
        'prizeOrderId': serializeParam(prizeOrderId, ParamType.String),
        if (prizeProductId != null && prizeProductId.isNotEmpty)
          'prizeProductId': serializeParam(prizeProductId, ParamType.String),
      }.withoutNulls,
    );
  }

  /// @Deprecated — usar [_openRafflePrizeSellerShop].
  void _openRafflePrizeSellerProfile() {
    unawaited(_openRafflePrizeSellerShop());
  }

  /// Esconde «Fazer proposta» / «Comprar» (artigo nosso, vendido, férias ou com encomenda).
  bool _suppressMarketplacePurchaseRow(ProductsRow p) {
    // Proposta de conjunto pendente: manter Comprar/Proposta no artigo principal.
    // Só esconder quando o conjunto já está aceite / em checkout.
    if (_isBundleChatContext && _focusedBundleStatus != 'pending') return true;
    if (_isProductSoldForCurrentChat(p)) return true;
    if (_otherUser?.vacationMode == true) return true;
    final sellerId = p.sellerId?.trim() ?? '';
    if (sellerId.isNotEmpty && sellerId == currentUserUid) return true;
    final o = _orderForChat;
    final pid = p.id;
    if (pid == null || pid.isEmpty || o == null) return false;
    return o.productId == pid;
  }

  bool _isProductSoldForCurrentChat(ProductsRow p) {
    // Multi-qty: stock restante > 0 continua comprável — não marcar «vendido»
    // só porque existe uma encomenda paga neste chat.
    if (p.isSold || p.quantity <= 0) return true;
    if (_isBundleChatContext) return _bundleChatFullySold();
    return false;
  }

  Widget _buildBundleChatHeaderCard() {
    final orders = _bundleHeaderOrders;
    if (orders.length < 2) return const SizedBox.shrink();
    final totalLabel = _bundleChatTotalLabel(orders);
    final totalSubtitle = _bundleChatTotalSubtitle(orders);
    final totalCaption = _bundleChatTotalCaption(orders);
    // Pedido/proposta pendente: não usar frase de encomenda individual.
    // Cancelado/expirado quote-before-pay: não cair em «Pedido de Reserva»
    // (ordens sintéticas do meta não são reservas reais).
    final statusPhrase = _focusedBundleStatus == 'pending'
        ? 'Pedido enviado — sem reserva de artigos'
        : _focusedBundleStatus == 'awaiting_payment'
            ? 'Portes confirmados — pronto a pagar'
            : _focusedBundleStatus == 'expired'
                ? 'Pedido de conjunto expirado'
                : _focusedBundleStatus == 'cancelled'
                    ? 'Pedido de conjunto cancelado'
                    : _focusedBundleStatus == 'purchased'
                        ? 'Conjunto pago'
                        : bundleGroupAggregatedStatusPhrase(orders);
    final subtitle = _bundleChatFullySold()
        ? 'Este conjunto já não está disponível nas condições anteriores.'
        : (_focusedBundleStatus == 'pending'
            ? 'Os artigos não ficam reservados — continuam à venda.'
            : _focusedBundleStatus == 'awaiting_payment'
                ? 'Pagamento único (artigos + portes + Proteção Fleaber).'
                : totalSubtitle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: BundleExpandableSummary(
        orders: orders,
        productsById: _bundleChatProducts,
        totalLabel: totalLabel,
        totalCaption: totalCaption,
        statusPhrase: statusPhrase,
        subtitle: subtitle,
        expanded: _bundleHeaderExpanded,
        onExpandedChanged: (v) => setState(() => _bundleHeaderExpanded = v),
      ),
    );
  }

  Widget _buildProductHeaderCard(ProductsRow p) {
    // Conjunto com ≥2 artigos: cabeçalho «Conjunto · N artigos» também em
    // pending (pedido de compra / proposta). O product_id do chat é só âncora
    // interna — não deve substituir o assunto visual do conjunto (H10 / Android).
    if (_isBundleChatContext && _bundleHeaderOrders.length >= 2) {
      return _buildBundleChatHeaderCard();
    }

    String? statusNote;
    if (_suppressMarketplacePurchaseRow(p)) {
      if (_isProductSoldForCurrentChat(p)) {
        statusNote = 'Este artigo já foi vendido.';
      } else if (_otherUser?.vacationMode == true) {
        statusNote =
            'Este vendedor está de férias — não é possível comprar nem fazer propostas novas.';
      } else if (_orderForChat?.productId == p.id) {
        statusNote = 'Compra ou reserva associada a esta conversa.';
      }
    }

    return FleaberChatProductHeaderCard(
      product: p,
      priceLabel: _formatProductPrice(p.price),
      showPurchaseActions: !_suppressMarketplacePurchaseRow(p),
      offerLabel: _pendingBuyerOffer != null
          ? 'Alterar proposta'
          : 'Fazer proposta',
      onOpenDetails: () => _openProductDetails(p),
      onBuy: () => _onComprar(p),
      onOffer: () => _onFazerProposta(p),
      actionsTrailing: widget.hubPanelMode,
      embedded: widget.hubPanelMode,
      statusNote: statusNote,
      proofButton: _shouldShowProofButton
          ? OutlinedButton(
              onPressed:
                  _reservationChatBusy ? null : _showSubmitProofDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTeal,
                side: const BorderSide(color: _kTeal, width: 1.2),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: FleaberRadius.circularSm,
                ),
              ),
              child: const Text('Enviar Prova de Pagamento'),
            )
          : null,
      // Cancelar só quando a encomenda cancelável é a do artigo do cabeçalho
      // e não há Comprar/Proposta (evita barra permanente a competir com o CTA).
      cancelButton: _shouldShowHeaderCancelForProduct(p)
          ? TextButton(
              onPressed:
                  _cancelChatBusy ? null : () => _onBuyerRequestCancel(),
              style: TextButton.styleFrom(
                foregroundColor: HubMessagesTheme.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Cancelar encomenda',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: HubMessagesTheme.textMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: HubMessagesTheme.textMuted,
                ),
              ),
            )
          : null,
    );
  }

  /// Cancelamento contextual no cabeçalho: mesma encomenda do artigo, sem CTAs.
  bool _shouldShowHeaderCancelForProduct(ProductsRow p) {
    if (!_canBuyerShowCancelButton) return false;
    if (!_suppressMarketplacePurchaseRow(p)) return false;
    final order = _orderForChat;
    final pid = p.id?.trim() ?? '';
    if (order == null || pid.isEmpty) return false;
    return (order.productId?.trim() ?? '') == pid;
  }

  static const Color _kShippingCardBg = Color(0xFFF5F5F5);
  static const Color _kShippingCardBorder = Color(0xFFE0E0E0);

  bool _showSaleManagementCardInChat(OrdersRow order) {
    if (_isBundleChatContext &&
        (order.bundleId ?? '').trim().isNotEmpty &&
        _bundleOrdersForChat.isNotEmpty) {
      final imSeller = order.sellerId == currentUserUid;
      final imBuyer = order.buyerId == currentUserUid;
      if (!imSeller && !imBuyer) return false;
      final s = normalizeOrderStatusKey(order.status);
      const allowed = {
        'pago',
        'premio_rifa',
        'reservado',
        'aguarda_confirmacao',
        'enviado',
        'concluido',
        'pedido_devolucao',
        'em_devolucao',
        'devolucao_entregue',
        'disputa_devolucao_vendedor',
        'devolvida',
        'cancelado',
      };
      return allowed.contains(s);
    }
    final pid = _product?.id;
    if (pid == null || order.productId != pid) return false;
    final imSeller = order.sellerId == currentUserUid;
    final imBuyer = order.buyerId == currentUserUid;
    if (!imSeller && !imBuyer) return false;
    final s = (order.status ?? '').toLowerCase();
    const sellerAllowed = {
      'pago',
      'premio_rifa',
      'reservado',
      'aguarda_confirmacao',
      'reserva_pendente',
      'enviado',
      'concluido',
      'pedido_devolucao',
      'em_devolucao',
      'devolucao_entregue',
      'disputa_devolucao_vendedor',
      'devolvida',
      // cancelado: não injectar card de gestão — a compra cancelada fica
      // no card «Compra paga» / mensagem de cancelamento (CHAT-MULTI).
    };
    const buyerAllowed = {
      'pago',
      'premio_rifa',
      'reservado',
      'aguarda_confirmacao',
      'enviado',
      'concluido',
      'pedido_devolucao',
      'em_devolucao',
      'devolucao_entregue',
      'disputa_devolucao_vendedor',
      'devolvida',
    };
    if (imSeller) return sellerAllowed.contains(s);
    return buyerAllowed.contains(s);
  }

  bool _isBuyerViewSaleCard(OrdersRow order) =>
      order.buyerId == currentUserUid;

  bool _sellerCanSimulateShippingLabel(OrdersRow order) {
    if (orderIsCancelled(order.status)) return false;
    final s = normalizeOrderStatusKey(order.status);
    if (s == 'enviado') return false;
    // Só depois do porte pago (premio_rifa → pago).
    return s == 'pago';
  }

  bool _isDirectReservationOrder(OrdersRow order) =>
      order.isReservation == true &&
      (order.paymentMethod ?? '').toLowerCase().contains('direto');

  DateTime? _bundlePurchaseAnchorTime() {
    final messages = _lastChatMessagesForMerge;
    DateTime? earliestMsg;
    if (messages.isNotEmpty) {
      for (var i = 0; i < messages.length; i++) {
        final payload = _tryParseFleaberChatJson(messages[i].text);
        final kind = payload?['kind']?.toString();
        if (kind != 'reservation_payment_submitted' &&
            kind != 'reservation_seller_confirmed_receipt' &&
            kind != 'marketplace_bag_paid') {
          continue;
        }
        final t = messages[i].createdAt;
        if (t == null) continue;
        if (earliestMsg == null || t.isBefore(earliestMsg)) earliestMsg = t;
      }
    }
    if (earliestMsg != null) return earliestMsg;
    final orders = _bundleActivePaidOrders;
    if (orders.isEmpty) return null;
    DateTime? earliest;
    for (final o in orders) {
      final t = o.createdAt;
      if (t == null) continue;
      if (earliest == null || t.isBefore(earliest)) earliest = t;
    }
    return earliest ?? _orderForChat?.createdAt;
  }

  /// Posição cronológica na timeline; mensagens sem `created_at` vão para o fim.
  int _computeInsertIndexForTime(
    List<ChatMessagesRow> messages,
    DateTime? anchor,
  ) {
    if (anchor == null) return messages.length;
    for (var i = 0; i < messages.length; i++) {
      final t = messages[i].createdAt;
      if (t != null && !t.isBefore(anchor)) return i;
    }
    return messages.length;
  }

  int _computeBundleShippedCardInsertIndex(List<ChatMessagesRow> messages) {
    if (!_bundleTimelineIsShipped()) return -1;
    var last = -1;
    for (var i = 0; i < messages.length; i++) {
      final payload = _tryParseFleaberChatJson(messages[i].text);
      final kind = payload?['kind']?.toString();
      if (kind == 'reservation_order_shipped' ||
          kind == 'reservation_payment_submitted') {
        last = i;
      }
    }
    if (last >= 0) return last + 1;
    return _computeInsertIndexForTime(
      messages,
      _bundleShippedAnchorTimeFromOrders() ?? _bundlePurchaseAnchorTime(),
    );
  }

  DateTime? _bundleShippedAnchorTimeFromOrders() {
    DateTime? latest;
    for (final o in _bundleActivePaidOrders) {
      final s = normalizeOrderStatusKey(o.status);
      if (s != 'enviado' && s != 'concluido') continue;
      final rawUpdated = o.data['updated_at'];
      DateTime? t;
      if (rawUpdated is DateTime) {
        t = rawUpdated;
      } else if (rawUpdated != null) {
        t = DateTime.tryParse(rawUpdated.toString());
      }
      t ??= o.createdAt;
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  bool _isBundleShippedChatMessage(ChatMessagesRow message) {
    final payload = _tryParseFleaberChatJson(message.text);
    return payload?['kind']?.toString() == 'reservation_order_shipped';
  }

  OrdersRow? _bundleAnchorOrder() {
    final orders = _bundleActivePaidOrders;
    return orders.isNotEmpty ? orders.first : null;
  }

  bool _bundleAllHaveStatus(String status) {
    final orders = _bundleActivePaidOrders;
    if (orders.length < 2) return false;
    return orders.every(
      (o) => normalizeOrderStatusKey(o.status) == status,
    );
  }

  bool _buyerCanConfirmBundleReceipt() {
    final anchor = _bundleAnchorOrder();
    if (anchor == null || anchor.buyerId != currentUserUid) return false;
    if (_bundleAllHaveStatus('enviado')) return true;
    // Mão: comprador pode confirmar receção sem esperar o vendedor marcar enviado.
    if (_bundleOrdersAreHandDelivery() &&
        _bundleActivePaidOrders.every((o) {
          final s = normalizeOrderStatusKey(o.status);
          return s == 'pago' || s == 'enviado';
        })) {
      return true;
    }
    return false;
  }

  bool _buyerCanLeaveFeedbackForBundle() {
    final anchor = _bundleAnchorOrder();
    if (anchor == null || anchor.buyerId != currentUserUid) return false;
    if (!_bundleAllHaveStatus('concluido')) return false;
    return _buyerCanLeaveFeedbackOnly(anchor);
  }

  bool _sellerCanLeaveFeedbackForBundle() {
    final anchor = _bundleAnchorOrder();
    if (anchor == null || anchor.sellerId != currentUserUid) return false;
    if (!_bundleAllHaveStatus('concluido')) return false;
    return _sellerCanLeaveFeedback(anchor);
  }

  OrdersRow? _resolveFeedbackOrder() {
    final single = _orderForChat;
    if (single != null &&
        normalizeOrderStatusKey(single.status) == 'concluido' &&
        (single.buyerId == currentUserUid || single.sellerId == currentUserUid)) {
      return single;
    }
    if (_buyerCanLeaveFeedbackForBundle() || _sellerCanLeaveFeedbackForBundle()) {
      return _bundleAnchorOrder();
    }
    return null;
  }

  DateTime? _bundleShippedAnchorTime(List<ChatMessagesRow> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final payload = _tryParseFleaberChatJson(messages[i].text);
      if (payload?['kind']?.toString() == 'reservation_order_shipped') {
        return messages[i].createdAt;
      }
    }
    return null;
  }

  bool _bundleTimelineIsShipped() {
    for (final o in _bundleActivePaidOrders) {
      final s = normalizeOrderStatusKey(o.status);
      if (s == 'enviado' || s == 'concluido') return true;
    }
    return false;
  }

  List<OrdersRow> get _bundleActivePaidOrders {
    if (_focusedBundleStatus == 'pending' ||
        _focusedBundleStatus == 'awaiting_payment' ||
        _focusedBundleStatus == 'accepted') {
      return _bundleOrdersForChat.length >= 2 ? _bundleOrdersForChat : const [];
    }
    if (_bundlePaidTimelineOrders.length >= 2 &&
        (_focusedBundleId == null ||
            _focusedBundleId == _bundlePaidTimelineBundleId)) {
      return _bundlePaidTimelineOrders;
    }
    return _bundleOrdersForChat.length >= 2
        ? _bundleOrdersForChat
        : const [];
  }

  bool get _shouldInjectPaidBundleTimeline =>
      _bundlePaidTimelineOrders.length >= 2 &&
      bundleAllOrdersPaidOrBeyond(_bundlePaidTimelineOrders) &&
      (_focusedBundleId == null ||
          _focusedBundleId == _bundlePaidTimelineBundleId);

  bool _isBundleReservationOutcomeMessage(Map<String, dynamic>? payload) {
    final orderId = payload?['order_id']?.toString().trim() ?? '';
    if (orderId.isEmpty) return false;
    return _bundleLinkedOrderIds.contains(orderId);
  }

  bool _bundleOrdersEligibleForShipButton(List<OrdersRow> orders) {
    if (orders.length < 2) return false;
    for (final o in orders) {
      if (orderIsCancelled(o.status)) return false;
      if (normalizeOrderStatusKey(o.status) != 'pago' &&
          normalizeOrderStatusKey(o.status) != 'premio_rifa') {
        return false;
      }
    }
    return true;
  }

  bool _sellerCanSimulateBundleShipment() {
    final orders = _bundleActivePaidOrders;
    if (!_bundleOrdersEligibleForShipButton(orders)) return false;
    final sellerId = orders.first.sellerId?.trim() ?? '';
    return sellerId.isNotEmpty && sellerId == currentUserUid;
  }

  int _computeShippingCardInsertIndex(
    List<ChatMessagesRow> messages,
    OrdersRow order,
  ) {
    final anchor = order.createdAt;
    var posAfterAnchor = 0;
    if (anchor != null) {
      posAfterAnchor = messages.length;
      for (var i = 0; i < messages.length; i++) {
        final t = messages[i].createdAt;
        if (t != null && !t.isBefore(anchor)) {
          posAfterAnchor = i;
          break;
        }
      }
    }
    var lastRes = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].isReservation == true) {
        lastRes = i;
      }
    }
    final resTail = lastRes < 0 ? 0 : lastRes + 1;
    return math.max(posAfterAnchor, resTail).clamp(0, messages.length);
  }

  List<_MergedChatItem> _mergeShippingIntoMessages(
    List<ChatMessagesRow> messages,
  ) {
    final order = _orderForChat;
    final pid = _product?.id;

    var filtered = messages.where((m) {
      return !_shouldHideMarketplaceBagChatMessage(m.text);
    }).toList();
    filtered = filtered.where((m) => !_shouldOmitChatMessage(m)).toList();

    final canInjectReservationPending = order != null &&
        order.id != null &&
        order.id!.isNotEmpty &&
        order.isReservation == true &&
        normalizeOrderStatusKey(order.status) == 'reserva_pendente' &&
        pid != null &&
        order.productId == pid;

    // Só esconder o JSON raw se vamos injectar o card — senão a reserva some
    // do chat (APP-SEC-MBWAY-B regressão com vários «pago» no mesmo artigo).
    if (canInjectReservationPending) {
      final oid = order!.id!;
      filtered = filtered.where((m) {
        final p = _tryParseFleaberChatJson(m.text);
        if (p == null || p['kind'] != 'reservation_request') return true;
        return p['order_id']?.toString() != oid;
      }).toList();
    }

    if (order == null) {
      return [
        for (var i = 0; i < filtered.length; i++)
          _MergedChatItem.message(filtered[i], i),
      ];
    }

    if (_shouldInjectPaidBundleTimeline && _bundleActivePaidOrders.length >= 2) {
      return _mergeBundleTimelineCards(filtered, order);
    }

    if (pid == null || order.productId != pid) {
      return [
        for (var i = 0; i < filtered.length; i++)
          _MergedChatItem.message(filtered[i], i),
      ];
    }

    final showShippingRaw = _showSaleManagementCardInChat(order);
    final orderId = order.id?.trim() ?? '';
    final hasSeguroPaidCard = orderId.isNotEmpty &&
        filtered.any((m) {
          final p = _tryParseFleaberChatJson(m.text);
          return p?['kind']?.toString() == 'seguro_fleaber_paid' &&
              p?['order_id']?.toString() == orderId;
        });
    // Pagamento na App / Seguro Fleaber: o recibo É o JSON — nunca injectar
    // card singleton (é isso que «actualizava» a mensagem antiga).
    final pm = (order.paymentMethod ?? '').toLowerCase();
    final isSeguroAppPay = pm.contains('app') ||
        pm.contains('stripe') ||
        pm.contains('seguro') ||
        pm.contains('cartão') ||
        pm.contains('cartao');
    final st = normalizeOrderStatusKey(order.status);
    final postPaySeguro = isSeguroAppPay &&
        (st == 'pago' ||
            st == 'enviado' ||
            st == 'concluido' ||
            st == 'premio_rifa');
    final showShipping =
        showShippingRaw && !hasSeguroPaidCard && !postPaySeguro;
    final showPendingInject = canInjectReservationPending;

    if (!showShipping && !showPendingInject) {
      return [
        for (var i = 0; i < filtered.length; i++)
          _MergedChatItem.message(filtered[i], i),
      ];
    }

    final pos = _computeShippingCardInsertIndex(filtered, order);
    final out = <_MergedChatItem>[];
    for (var i = 0; i < filtered.length; i++) {
      if (i == pos) {
        if (showPendingInject) {
          out.add(const _MergedChatItem.reservationPendingInjected());
        }
        if (showShipping) {
          out.add(const _MergedChatItem.shipping());
        }
      }
      out.add(_MergedChatItem.message(filtered[i], i));
    }
    if (pos == filtered.length) {
      if (showPendingInject) {
        out.add(const _MergedChatItem.reservationPendingInjected());
      }
      if (showShipping) {
        out.add(const _MergedChatItem.shipping());
      }
    }
    return out;
  }

  List<_MergedChatItem> _mergeBundleTimelineCards(
    List<ChatMessagesRow> filtered,
    OrdersRow order,
  ) {
    final showPendingInject = order.isReservation == true &&
        normalizeOrderStatusKey(order.status) == 'reserva_pendente';
    final purchasePos = _computeInsertIndexForTime(
      filtered,
      _bundlePurchaseAnchorTime(),
    );
    final shippedPos = _bundleTimelineIsShipped()
        ? _computeBundleShippedCardInsertIndex(filtered)
        : -1;

    final injectAt = <int, List<_MergedChatItem>>{};
    void addAt(int pos, _MergedChatItem item) {
      final key = pos.clamp(0, filtered.length);
      injectAt.putIfAbsent(key, () => []).add(item);
    }

    if (showPendingInject) {
      addAt(purchasePos, const _MergedChatItem.reservationPendingInjected());
    }
    addAt(purchasePos, const _MergedChatItem.bundlePurchase());
    if (shippedPos >= 0) {
      addAt(shippedPos, const _MergedChatItem.bundleShipped());
    }

    final out = <_MergedChatItem>[];
    for (var i = 0; i <= filtered.length; i++) {
      final extras = injectAt[i];
      if (extras != null) out.addAll(extras);
      if (i < filtered.length) {
        final message = filtered[i];
        if (_isBundleShippedChatMessage(message)) continue;
        out.add(_MergedChatItem.message(message, i));
      }
    }
    return out;
  }

  int _dayKeyForMergedItem(_MergedChatItem e) {
    if (e.isBundlePurchaseCard) {
      final t = _bundlePurchaseAnchorTime() ?? _orderForChat?.createdAt ?? DateTime.now();
      final d = t.toLocal();
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }
    if (e.isBundleShippedCard) {
      final t = _bundleShippedAnchorTime(_lastChatMessagesForMerge) ??
          _orderForChat?.createdAt ??
          DateTime.now();
      final d = t.toLocal();
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }
    if (e.isShippingCard || e.isReservationPendingInjected) {
      final t = _orderForChat?.createdAt ?? DateTime.now();
      final d = t.toLocal();
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }
    final t = (e.message!.createdAt ?? DateTime.now()).toLocal();
    return DateTime(t.year, t.month, t.day).millisecondsSinceEpoch;
  }

  String _saleCardPrimaryLine(OrdersRow order, bool forBuyer) {
    if (orderIsCancelled(order.status)) {
      return 'Encomenda Cancelada. Este processo foi interrompido.';
    }
    final s = normalizeOrderStatusKey(order.status);
    if (forBuyer) {
      if (s == 'pedido_devolucao') return 'Pedido de devolução aberto.';
      if (s == 'em_devolucao') return 'Devolução em curso.';
      if (s == 'devolucao_entregue') return 'Devolução entregue ao vendedor.';
      if (s == 'disputa_devolucao_vendedor') {
        return 'Problema na devolução em análise pelo Fleaber.';
      }
      if (s == 'devolvida') return 'Encomenda devolvida e reembolsada.';
      if (s == 'enviado') {
        if (_isHandDeliveryOrder(order)) {
          return 'Entrega em mão — confirma a receção';
        }
        return 'Artigo enviado!';
      }
      if (s == 'concluido') return 'Venda concluída!';
      if (s == 'reservado') {
        return 'Reserva aceite — aguardando pagamento.';
      }
      if (s == 'aguarda_confirmacao') {
        return 'Pagamento enviado — aguarda confirmação.';
      }
      if (s == 'premio_rifa') {
        return 'Prémio da Rifa — falta o envio';
      }
      if (s == 'pago' && _isHandDeliveryOrder(order)) {
        return 'Prémio da Rifa — entrega em mão';
      }
      // Recibo «Comprado!» fica no card seguro_fleaber_paid (CHAT-MULTI).
      if (s == 'pago') return 'Aguarda o envio do artigo';
      return 'Comprado!';
    }
    if (s == 'pedido_devolucao') return 'Pedido de devolução aberto.';
    if (s == 'em_devolucao') return 'Artigo em devolução.';
    if (s == 'devolucao_entregue') return 'Devolução recebida para conferência.';
    if (s == 'disputa_devolucao_vendedor') {
      return 'Problema na devolução enviado ao Fleaber.';
    }
    if (s == 'devolvida') return 'Artigo devolvido ao vendedor.';
    if (s == 'enviado') {
      if (_isHandDeliveryOrder(order)) {
        return 'Entrega em mão confirmada — aguarda o comprador';
      }
      return 'Artigo enviado';
    }
    if (s == 'concluido') return 'Venda concluída';
    if (s == 'reserva_pendente') {
      return 'Pedido de reserva pendente — responde ao comprador.';
    }
    if (s == 'reservado') {
      return 'Artigo reservado. Aguarda o pagamento do comprador.';
    }
    if (s == 'premio_rifa') {
      return 'Prémio da Rifa — aguarda o envio do vencedor';
    }
    if (s == 'pago' && _isHandDeliveryOrder(order)) {
      return 'Prémio da Rifa — entrega em mão combinada';
    }
    if (s == 'aguarda_confirmacao') {
      return 'Pagamento assinalado pelo comprador.';
    }
    return 'Vendido — envia o artigo';
  }

  String? _saleCardSecondaryLine(OrdersRow order, bool forBuyer) {
    if (orderIsCancelled(order.status)) return null;
    final s = normalizeOrderStatusKey(order.status);
    if (forBuyer) {
      if (s == 'pedido_devolucao') {
        return 'A disputa foi aberta. Aguarda os próximos passos da devolução.';
      }
      if (s == 'em_devolucao') {
        return 'O artigo está a caminho de volta para o vendedor.';
      }
      if (s == 'devolucao_entregue') {
        return 'A devolução foi entregue ao vendedor. Ele tem 2 dias para conferir.';
      }
      if (s == 'disputa_devolucao_vendedor') {
        return 'O vendedor reportou problema na devolução. O Fleaber vai decidir.';
      }
      if (s == 'devolvida') {
        return 'O reembolso foi lançado para a tua carteira Fleaber.';
      }
      if (s == 'enviado') {
        if (_isHandDeliveryOrder(order)) {
          return 'A vendedora confirmou a entrega em mão. Quando tiveres o artigo, confirma a receção.';
        }
        return 'O vendedor marcou o envio. Quando receberes o artigo, confirma no chat.';
      }
      if (s == 'concluido') {
        if (_hasLocalFeedback(order, asBuyer: true)) {
          return 'Avaliação enviada. Obrigado pelo teu feedback.';
        }
        if (order.isB2cChannel) {
          return 'Receção confirmada. Tens 48 horas (Proteção Fleaber) para '
              'reportar um problema e, se aplicável, 14 dias para exercer a '
              'livre resolução.';
        }
        return 'Receção confirmada. Tens 48 horas para deixar avaliação ou reportar um problema.';
      }
      if (s == 'reservado') {
        return 'O vendedor aceitou a reserva. Paga com Seguro Fleaber ou envia a prova se combinaste MB WAY/transferência direta.';
      }
      if (s == 'aguarda_confirmacao') {
        return 'A prova de pagamento foi enviada. O vendedor deve confirmar a receção antes do envio.';
      }
      if (s == 'premio_rifa') {
        return LiveRafflePrizeCopy.buyerPayHint;
      }
      if (s == 'pago' && _isHandDeliveryOrder(order)) {
        return LiveRafflePrizeCopy.buyerHandHint;
      }
      return 'O vendedor já recebeu o teu pedido e deve enviar o artigo em breve.';
    }
    if (s == 'pedido_devolucao') {
      return 'O comprador pediu devolução. Aguarda a resolução antes de enviar novo estado.';
    }
    if (s == 'em_devolucao') {
      return 'Acompanha a devolução até receberes o artigo de volta.';
    }
    if (s == 'devolucao_entregue') {
      return 'Confere o artigo devolvido. Tens 2 dias para validar ou reportar problema.';
    }
    if (s == 'disputa_devolucao_vendedor') {
      return 'A tua reclamação sobre a devolução foi enviada ao Fleaber.';
    }
    if (s == 'devolvida') {
      return 'A devolução foi fechada e o reembolso foi lançado ao comprador.';
    }
    if (s == 'enviado') {
      if (_isHandDeliveryOrder(order)) {
        return 'Confirmaste a entrega em mão. Aguarda que o comprador confirme a receção.';
      }
      return 'Artigo enviado. Aguarda que o comprador confirme a receção.';
    }
    if (s == 'concluido') {
      if (_hasLocalFeedback(order, asBuyer: false)) {
        return 'Já avaliaste este comprador. Obrigado!';
      }
      if (order.isB2cChannel) {
        return 'O comprador confirmou a receção. Em vendas profissionais o '
            'valor fica retido até 14 dias (livre resolução), além da Proteção '
            'Fleaber de 48 horas.';
      }
      return 'O comprador confirmou a receção. Tens 48 horas para avaliar o cliente.';
    }
    if (s == 'reservado') {
      return 'Quando o comprador pagar, recebes uma notificação no chat.';
    }
    if (s == 'aguarda_confirmacao') {
      return 'Confirma no teu banco ou MB WAY se o valor entrou e depois marca o pagamento como recebido.';
    }
    if (s == 'reserva_pendente') {
      return 'Responde no chat para aceitar ou recusar o pedido de reserva.';
    }
    if (s == 'pago') {
      if (_isHandDeliveryOrder(order)) {
        return LiveRafflePrizeCopy.sellerHandHint;
      }
      final total = order.priceTotal;
      final priceStr = total != null
          ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(total)
          : '—';
      return 'Quando o comprador receber o pedido, o valor de $priceStr será '
          'transferido para o teu saldo. Confirma o envio quando entregares o artigo.';
    }
    if (s == 'premio_rifa') {
      return LiveRafflePrizeCopy.sellerHint;
    }
    return null;
  }

  Future<void> _onSellerConfirmShipment() async {
    final bundleOrders = _bundleActivePaidOrders;
    final canShipBundle = _sellerCanSimulateBundleShipment();
    final o = _orderForChat;
    final chatId = widget.chatId;
    final buyerId = _resolvedOtherUserId();
    if (_shippingLabelActionBusy ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }
    if (canShipBundle) {
      if (bundleOrders.first.sellerId != currentUserUid) return;
    } else if (o == null ||
        o.id == null ||
        o.id!.isEmpty ||
        !_sellerCanSimulateShippingLabel(o)) {
      return;
    } else if (o.sellerId != currentUserUid) {
      return;
    }

    final activeOrders = _bundleActivePaidOrders;
    final hand = _isHandDeliveryOrder(o) ||
        activeOrders.any(_isHandDeliveryOrder) ||
        LiveRafflePrizeCopy.isHandShippingMethod(o?.shippingMethod);

    setState(() => _shippingLabelActionBusy = true);
    try {
      // DPD carrier: obter etiqueta (idempotente). NÃO marcar enviado.
      // Stub 2s removido (ZIP 135). Enviado só com aceitação física DPD.
      if (!hand) {
        final orderId = (o?.id ??
                (activeOrders.isNotEmpty ? activeOrders.first.id : null) ??
                '')
            .trim();
        if (orderId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Etiqueta temporariamente indisponível'),
              ),
            );
          }
          return;
        }
        final result = await DpdExpeditionService.obtainLabel(orderId: orderId);
        if (!mounted) return;
        if (!result.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.createDisabled
                    ? 'Obter etiqueta ainda não está activo (teste / GO pendente).'
                    : result.userMessage,
              ),
            ),
          );
        } else {
          final guide = (result.trackingCode ?? '').trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                guide.isEmpty
                    ? 'Etiqueta pronta. A encomenda ainda não está marcada como enviada.'
                    : 'Etiqueta pronta · guia $guide. Ainda não marcada como enviada.',
              ),
            ),
          );
          if ((result.labelUrl ?? '').trim().isNotEmpty) {
            // ignore: unawaited_futures
            launchURL(result.labelUrl!.trim());
          }
        }
        final pid = o?.productId ??
            (activeOrders.isNotEmpty ? activeOrders.first.productId : null) ??
            '';
        await _loadOrderForChat(pid);
        await _loadBundleOrdersForChat();
        if (!mounted) return;
        setState(() {});
        return;
      }

      // Entrega em mão — confirma envio/entrega sem DPD.
      var bundleId = o?.bundleId?.trim() ?? '';
      if (bundleId.isEmpty &&
          activeOrders.length >= 2 &&
          (activeOrders.first.bundleId ?? '').trim().isNotEmpty) {
        bundleId = activeOrders.first.bundleId!.trim();
      }
      if (bundleId.isNotEmpty) {
        await OrdersTable().update(
          data: {'status': 'enviado'},
          matchingRows: (rows) => rows.eqOrNull('bundle_id', bundleId),
        );
        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'reservation_order_shipped',
            'bundle_id': bundleId,
            'hand_delivery': true,
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': true,
        });
        await _touchChatLastMessage('Entrega em mão confirmada');
      } else {
        await OrdersTable().update(
          data: {'status': 'enviado'},
          matchingRows: (rows) => rows.eqOrNull('id', o!.id),
        );
        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'reservation_order_shipped',
            'order_id': o!.id,
            'hand_delivery': true,
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': true,
        });
        await ChatsTable().update(
          data: {
            'last_message': 'Entrega em mão confirmada',
            'last_message_time': DateTime.now().toUtc().toIso8601String(),
          },
          matchingRows: (rows) => rows.eqOrNull('id', chatId),
        );
      }

      try {
        final shipOrderId = (o?.id ?? '').trim();
        if (buyerId.isNotEmpty && shipOrderId.isNotEmpty) {
          final nid = await FleaberNotifyEmit.emit(
            recipientId: buyerId,
            kind: 'reservation_order_shipped',
            title: 'A tua encomenda foi enviada',
            body: 'O vendedor confirmou a entrega em mão.',
            chatId: chatId,
            orderId: shipOrderId,
            dedupeKey: 'shipped:$shipOrderId',
          );
          unawaited(FleaberNotifyEmit.requestDispatch(nid));
        }
      } catch (_) {}

      final pid = o?.productId ??
          (activeOrders.isNotEmpty ? activeOrders.first.productId : null) ??
          '';
      await _loadOrderForChat(pid);
      await _loadBundleOrdersForChat();
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      print('BATATA_SHIPPING_LABEL ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etiqueta temporariamente indisponível'),
        ),
      );
    } finally {
      if (mounted) setState(() => _shippingLabelActionBusy = false);
    }
  }

  Future<void> _onBuyerConfirmOrderReceived() async {
    if (_buyerCanConfirmBundleReceipt()) {
      await _onBuyerConfirmBundleReceived();
      return;
    }
    final o = _orderForChat;
    final chatId = widget.chatId;
    final sellerId = _resolvedOtherUserId();
    final status = normalizeOrderStatusKey(o?.status);
    final hand = _isHandDeliveryOrder(o);
    // Mão: comprador pode concluir a partir de pago ou enviado.
    final statusOk = status == 'enviado' || (hand && status == 'pago');
    if (_reservationChatBusy ||
        o == null ||
        o.id == null ||
        o.id!.isEmpty ||
        !statusOk ||
        o.buyerId != currentUserUid ||
        chatId == null ||
        chatId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return;
    }
    setState(() => _reservationChatBusy = true);
    try {
      await OrdersTable().update(
        data: {'status': 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('id', o.id),
      );
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': sellerId,
        'is_read': false,
        'text': _fleaberChatJsonEncode({
          'kind': 'reservation_order_completed',
          'order_id': o.id,
          if (hand) 'hand_delivery': true,
          'v': 1,
        }),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await _touchChatLastMessage(
        hand ? 'Receção em mão confirmada' : 'Venda concluída',
      );
      await _loadOrderForChat(o.productId ?? '');
      if (!mounted) return;
      setState(() {});
      // Convidar feedback na hora.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _onLeaveFeedback();
    } catch (e) {
      print('BATATA_CONFIRM_RECEIPT ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao confirmar receção: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _onBuyerConfirmBundleReceived() async {
    final orders = _bundleActivePaidOrders;
    final chatId = widget.chatId;
    final sellerId = _resolvedOtherUserId();
    if (_reservationChatBusy ||
        orders.length < 2 ||
        chatId == null ||
        chatId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty ||
        orders.first.buyerId != currentUserUid) {
      return;
    }
    final bundleId = orders.first.bundleId?.trim() ?? '';
    if (bundleId.isEmpty) return;

    setState(() => _reservationChatBusy = true);
    try {
      await OrdersTable().update(
        data: {'status': 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('bundle_id', bundleId),
      );
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': sellerId,
        'is_read': false,
        'text': _fleaberChatJsonEncode({
          'kind': 'bundle_buyer_confirmed_receipt',
          'bundle_id': bundleId,
          'order_id': orders.first.id,
          'v': 1,
        }),
        'chat_id': chatId,
        'is_reservation': true,
      });
      final hand = _bundleOrdersAreHandDelivery();
      await _touchChatLastMessage(
        hand ? 'Receção em mão confirmada' : 'Receção do conjunto confirmada',
      );
      final pid = orders.first.productId ?? '';
      await _loadOrderForChat(pid);
      await _loadBundleOrdersForChat();
      if (!mounted) return;
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _onLeaveFeedback();
    } catch (e) {
      print('BATATA_CONFIRM_BUNDLE_RECEIPT ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao confirmar receção: $e')),
      );
    } finally {
      if (mounted) setState(() => _reservationChatBusy = false);
    }
  }

  Future<void> _onLeaveFeedback() async {
    final o = _resolveFeedbackOrder();
    if (_feedbackBusy ||
        o == null ||
        o.id == null ||
        normalizeOrderStatusKey(o.status) != 'concluido') {
      return;
    }
    final isBuyer = o.buyerId == currentUserUid;
    final isSeller = o.sellerId == currentUserUid;
    if (!isBuyer && !isSeller) return;
    final targetId = isBuyer ? o.sellerId : o.buyerId;
    if (targetId == null || targetId.isEmpty) return;

    var stars = 5;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularMd),
          title: Text(
            'Deixar avaliação',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // IconButton default ~48px × 5 = overflow em ecrãs estreitos (TCL).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) {
                      final value = i + 1;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () => setDialogState(() => stars = value),
                        icon: Icon(
                          value <= stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFFFB300),
                          size: 32,
                        ),
                      );
                    }),
                  ),
                ),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Comentário',
                    hintText: 'Como correu a experiência?',
                    border: OutlineInputBorder(
                      borderRadius: FleaberRadius.circularMd,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voltar'),
            ),
            FleaberPrimaryButton(
              label: 'Enviar',
              height: null,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      return;
    }
    setState(() => _feedbackBusy = true);
    try {
      final existing = await ReviewsTable().queryRows(
        queryFn: (q) => q.eqOrNull('order_id', o.id),
        limit: 10,
      );
      final alreadyReviewed = existing.any(
        (r) => isBuyer
            ? _isBuyerFeedbackRole(r.authorRole)
            : _isSellerFeedbackRole(r.authorRole),
      );
      if (alreadyReviewed) {
        if (!mounted) return;
        if (isBuyer) {
          _buyerFeedbackDone = true;
        } else {
          _sellerFeedbackDone = true;
        }
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já deixaste avaliação nesta venda.')),
        );
        return;
      }
      await ReviewsTable().insert({
        'target_id': targetId,
        'buyer_id': currentUserUid,
        'stars': stars,
        'comment': controller.text.trim(),
        'is_automatic': false,
        'target_type': isBuyer ? 'seller' : 'buyer',
        'author_role': isBuyer ? 'comprador' : 'vendedor',
        'order_id': o.id,
      });
      if (isBuyer) {
        _buyerFeedbackDone = true;
      } else {
        _sellerFeedbackDone = true;
      }
      final chatId = widget.chatId;
      final otherId = widget.otherUserId;
      if (chatId != null &&
          chatId.isNotEmpty &&
          otherId != null &&
          otherId.isNotEmpty) {
        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': otherId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'order_review_submitted',
            'order_id': o.id,
            'author_role': isBuyer ? 'comprador' : 'vendedor',
            'stars': stars,
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': true,
        });
        await _touchChatLastMessage(
          isBuyer ? 'Avaliação enviada' : 'Avaliação recebida',
        );
      }
      await _loadOrderForChat(o.productId ?? '');
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avaliação enviada.')),
      );
    } catch (e) {
      print('BATATA_FEEDBACK ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar avaliação: $e')),
      );
    } finally {
      if (mounted) setState(() => _feedbackBusy = false);
    }
  }

  bool _bundleOrdersAreHandDelivery() {
    final orders = _bundleActivePaidOrders.isNotEmpty
        ? _bundleActivePaidOrders
        : _bundlePaidTimelineOrders;
    if (orders.any(_isHandDeliveryOrder)) return true;
    final o = _orderForChat;
    return _isHandDeliveryOrder(o);
  }

  String? _bundleSaleCardSecondaryLine(bool forBuyer, {required bool shippedPhase}) {
    final count = bundleTotalItemCountFromOrders(_bundleActivePaidOrders);
    final hand = _bundleOrdersAreHandDelivery();
    if (shippedPhase) {
      if (forBuyer) {
        return hand
            ? 'A vendedora confirmou a entrega em mão. Quando tiveres os artigos, confirma a receção.'
            : 'O vendedor marcou o envio. Quando receberes os artigos, confirma no chat.';
      }
      return hand
          ? 'Confirmaste a entrega em mão. Aguarda que o comprador confirme a receção.'
          : 'Artigos enviados. Aguarda que o comprador confirme a receção.';
    }
    if (forBuyer) {
      if (hand) {
        return 'Combinaste entrega em mão. Acerta o encontro com a vendedora.';
      }
      if (count > 1) {
        return 'O vendedor já recebeu o pedido dos $count artigos e deve enviar em breve.';
      }
      return 'O vendedor já recebeu o teu pedido e deve enviar o artigo em breve.';
    }
    if (hand) {
      return 'O comprador escolheu entrega em mão. Combina o encontro e confirma quando entregares.';
    }
    if (count > 1) {
      return 'Envia os $count artigos do conjunto quando estiverem prontos.';
    }
    return null;
  }

  String _bundleSaleCardPrimaryLine(bool forBuyer, {required bool shippedPhase}) {
    final count = bundleTotalItemCountFromOrders(_bundleActivePaidOrders);
    final hand = _bundleOrdersAreHandDelivery();
    if (shippedPhase) {
      if (hand) {
        return forBuyer
            ? 'Entrega em mão — confirma a receção'
            : 'Entrega em mão confirmada — aguarda o comprador';
      }
      return forBuyer ? 'Artigos enviados!' : 'Artigos enviados';
    }
    if (forBuyer) {
      if (hand) return 'Prémio / conjunto — entrega em mão';
      return count > 1 ? 'Conjunto comprado!' : 'Comprado!';
    }
    if (hand) return 'Entrega em mão combinada';
    return count > 1 ? 'Vendido — envia os artigos' : 'Vendido — envia o artigo';
  }

  Widget _buildBundlePurchaseTimelineCard() {
    final activeOrders = _bundleActivePaidOrders;
    final anchorOrder =
        activeOrders.isNotEmpty ? activeOrders.first : _orderForChat;
    final forBuyer = anchorOrder?.buyerId == currentUserUid;
    return BundleChatPurchaseCard(
      forBuyer: forBuyer,
      primaryLine: _bundleSaleCardPrimaryLine(forBuyer, shippedPhase: false),
      secondaryLine:
          _bundleSaleCardSecondaryLine(forBuyer, shippedPhase: false),
      showSellerShipButton: !forBuyer && _sellerCanSimulateBundleShipment(),
      sellerShipBusy: _shippingLabelActionBusy,
      onSellerConfirmShipment: _onSellerConfirmShipment,
      sellerShipLabel: bundleSellerShipButtonLabel(activeOrders),
      backgroundColor: _kShippingCardBg,
      borderColor: _kShippingCardBorder,
    );
  }

  Widget _buildBundleShippedTimelineCard() {
    final anchorOrder = _bundlePaidTimelineOrders.isNotEmpty
        ? _bundlePaidTimelineOrders.first
        : _orderForChat;
    final forBuyer = anchorOrder?.buyerId == currentUserUid;
    final allCompleted = _bundleAllHaveStatus('concluido');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BundleChatPurchaseCard(
          forBuyer: forBuyer,
          primaryLine: allCompleted && forBuyer
              ? 'Venda concluída!'
              : allCompleted && !forBuyer
                  ? 'Venda concluída'
                  : _bundleSaleCardPrimaryLine(forBuyer, shippedPhase: true),
          secondaryLine: allCompleted
              ? (forBuyer
                  ? (_buyerFeedbackDone
                      ? 'Avaliação enviada. Obrigado pelo teu feedback.'
                      : 'Receção confirmada. Deixa a tua avaliação abaixo.')
                  : (_sellerFeedbackDone
                      ? 'Já avaliaste este comprador. Obrigado!'
                      : 'O comprador confirmou a receção. Avalia o cliente abaixo.'))
              : _bundleSaleCardSecondaryLine(forBuyer, shippedPhase: true),
          backgroundColor: _kShippingCardBg,
          borderColor: _kShippingCardBorder,
        ),
        if (forBuyer && _buyerCanConfirmBundleReceipt()) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FleaberPrimaryButton(
              width: double.infinity,
              height: 44,
              borderRadius: 10,
              label: _bundleOrdersAreHandDelivery()
                  ? 'Confirmei receção em mão'
                  : 'Confirmar receção da encomenda',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              loading: _reservationChatBusy,
              onPressed:
                  _reservationChatBusy ? null : _onBuyerConfirmOrderReceived,
            ),
          ),
        ],
        if (forBuyer && _buyerCanLeaveFeedbackForBundle()) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                icon: const Icon(Icons.star_rounded, size: 18),
                label: Text(
                  'Deixar avaliação',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kTeal,
                  side: const BorderSide(color: _kTeal, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: FleaberRadius.circularSm,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (!forBuyer &&
            anchorOrder != null &&
            _sellerCanLeaveFeedbackForBundle()) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                icon: const Icon(Icons.star_rounded, size: 18),
                label: Text(
                  'Deixar avaliação',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kTeal,
                  side: const BorderSide(color: _kTeal, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: FleaberRadius.circularSm,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBundleSaleManagementCardInList() {
    return _buildBundlePurchaseTimelineCard();
  }

  Widget _buildSaleManagementCardInList() {
    final order = _orderForChat;
    if (order == null) return const SizedBox.shrink();
    if (_bundleActivePaidOrders.length >= 2) {
      return const SizedBox.shrink();
    }
    if (_isBundleChatContext && (order.bundleId ?? '').trim().isNotEmpty) {
      return _buildBundleSaleManagementCardInList();
    }
    final forBuyer = _isBuyerViewSaleCard(order);
    final status = (order.status ?? '').toLowerCase();
    final cancelled = orderIsCancelled(order.status);
    final directReservation = _isDirectReservationOrder(order);
    final showSellerButton =
        !forBuyer && !cancelled && _sellerCanSimulateShippingLabel(order);
    final primary = _saleCardPrimaryLine(order, forBuyer);
    final secondary = _saleCardSecondaryLine(order, forBuyer);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: kChatSystemSectionSpacingHalf,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _kShippingCardBg,
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(color: _kShippingCardBorder, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cancelled)
                    Text(
                      primary,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.35,
                        color: FleaberColors.danger,
                      ),
                    )
                  else ...[
                    Text(
                      primary,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        height: 1.25,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        secondary,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.38,
                          color: const Color(0xFF3D4A55),
                        ),
                      ),
                    ],
                  ],
                  if (!forBuyer &&
                      !cancelled &&
                      (status == 'reservado' ||
                          status == 'aguarda_confirmacao')) ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reservationChatBusy
                                ? null
                                : _onSellerCancelReservationWithDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: FleaberColors.danger,
                              side: const BorderSide(
                                color: FleaberColors.danger,
                                width: 1.1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                            ),
                            child: Text(
                              'Cancelar Reserva',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FleaberPrimaryButton(
                            width: double.infinity,
                            label: 'Confirmar Receção de Dinheiro',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            borderRadius: 10,
                            height: null,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            onPressed: _reservationChatBusy
                                ? null
                                : () {
                                    if (status == 'aguarda_confirmacao' ||
                                        status == 'reservado') {
                                      _confirmSellerMoneyReceivedWithDialog();
                                    } else {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Só podes confirmar quando o pedido '
                                            'estiver a aguardar pagamento.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (forBuyer && !cancelled && status == 'premio_rifa') ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Pagar envio do prémio',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      textAlign: TextAlign.center,
                      borderRadius: 10,
                      height: null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: _reservationChatBusy
                          ? null
                          : () => unawaited(_onBuyerPayRafflePrizeShipping()),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed:
                          _reservationChatBusy ? null : _openJuntarAoPremio,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF007782),
                        side: const BorderSide(color: Color(0xFF007782)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Juntar mais peças ao envio',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _reservationChatBusy
                          ? null
                          : () => unawaited(_openRafflePrizeSellerShop()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF007782),
                        side: const BorderSide(color: Color(0xFF007782)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Ver loja desta vendedora',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  if (forBuyer && !cancelled && status != 'premio_rifa') ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          status == 'enviado'
                              ? Icons.check_circle_rounded
                              : Icons.inventory_2_outlined,
                          color: _kTeal,
                          size: 28,
                        ),
                      ],
                    ),
                  ],
                  if (forBuyer &&
                      !cancelled &&
                      (status == 'enviado' ||
                          (status == 'pago' && _isHandDeliveryOrder(order)))) ...[
                    const SizedBox(height: kChatSystemSectionSpacing),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: _isHandDeliveryOrder(order)
                          ? 'Confirmei receção em mão'
                          : 'Confirmar receção da encomenda',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      textAlign: TextAlign.center,
                      borderRadius: 10,
                      height: null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: _reservationChatBusy
                          ? null
                          : _onBuyerConfirmOrderReceived,
                    ),
                  ],
                  if (!cancelled &&
                      !_isHandDeliveryOrder(order) &&
                      (status == 'enviado' ||
                          status == 'pago' ||
                          (order.dpdTrackingCode ?? '').trim().isNotEmpty) &&
                      (order.id ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(
                          showDpdTrackingSheet(
                            context,
                            orderId: order.id!.trim(),
                            knownGuide: order.dpdTrackingCode,
                          ),
                        ),
                        icon: const Icon(Icons.local_shipping_outlined, size: 18),
                        label: Text(
                          'Ver seguimento DPD',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kTeal,
                          side: const BorderSide(color: _kTeal, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: _stickyBarBtnRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (showSellerButton &&
                      !_isHandDeliveryOrder(order) &&
                      normalizeOrderStatusKey(order.status) == 'pago') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => showOrderWeightConfirmSheet(
                          context: context,
                          orderId: order.id ?? '',
                          chargedBand: order.shippingWeightChargedBand ??
                              order.shippingWeightBand,
                        ),
                        child: Text(
                          'Confirmar peso / diferença portes',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (forBuyer &&
                      normalizeOrderStatusKey(order.status) == 'pago') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => showOrderShippingDeltaPaySheet(
                          context: context,
                          orderId: order.id ?? '',
                        ),
                        child: Text(
                          'Pagar diferença de portes',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (showSellerButton) ...[
                    const SizedBox(height: 14),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: () {
                        if (_isHandDeliveryOrder(order)) {
                          return 'Confirmei entrega em mão';
                        }
                        return 'Obter etiqueta de envio';
                      }(),
                      loading: _shippingLabelActionBusy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      textAlign: TextAlign.center,
                      borderRadius: 10,
                      height: null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: _shippingLabelActionBusy
                          ? null
                          : _onSellerConfirmShipment,
                    ),
                  ],
                  if (forBuyer &&
                      !cancelled &&
                      _buyerCanLeaveFeedbackOnly(order)) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                        icon: const Icon(Icons.star_rounded, size: 18),
                        label: Text(
                          'Deixar avaliação',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kTeal,
                          side: const BorderSide(color: _kTeal, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: _stickyBarBtnRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!forBuyer &&
                      !cancelled &&
                      _sellerCanLeaveFeedback(order)) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _feedbackBusy ? null : _onLeaveFeedback,
                        icon: const Icon(Icons.star_rounded, size: 18),
                        label: Text(
                          'Deixar avaliação',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kTeal,
                          side: const BorderSide(color: _kTeal, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: _stickyBarBtnRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Artigo (opcional) + strip do interlocutor.
  /// Mockup B (hubPanelMode): cabeçalho + cartão sticky fora do scroll.
  int _headerCount() {
    if (widget.hubPanelMode) return 0;
    return (_product != null ? 1 : 0) + 1;
  }

  /// Cabeçalho conversa Mockup B — avatar + nome + localização (sem X gigante).
  Widget _buildMockupBConversationHeader(ProfilesRow user) {
    final loc = user.location?.trim();
    return Material(
      color: HubMessagesTheme.surface,
      child: InkWell(
        onTap: _openOtherUserProfile,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: HubMessagesTheme.divider),
            ),
          ),
          child: Row(
            children: [
              FleaberProfileAvatar(
                userId: user.id,
                fullName: user.fullName,
                photoUrl: user.photoUrl,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.fullName ?? 'Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: HubMessagesTheme.textPrimary,
                      ),
                    ),
                    if (loc != null && loc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        loc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: HubMessagesTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: HubMessagesTheme.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantStrip(ProfilesRow user) {
    final loc = user.location?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Material(
        color: const Color(0xFFFAFBFC),
        borderRadius: FleaberRadius.circularMd,
        child: InkWell(
          onTap: _openOtherUserProfile,
          borderRadius: FleaberRadius.circularMd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: FleaberRadius.circularMd,
              border: Border.all(
                color: const Color(0xFFDDE2E7),
                width: 0.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FleaberProfileAvatar(
                  userId: user.id,
                  fullName: user.fullName,
                  photoUrl: user.photoUrl,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName ?? 'Utilizador',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: const Color(0xFF101518),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (loc != null && loc.isNotEmpty)
                            ? loc
                            : 'Localização não indicada',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF57636C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Visto pela última vez · ${_lastSeenLine()}',
                        maxLines: 2,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF57636C),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Chrome Hub só na web — Android mantém tema claro. Cartões oferta/disputa
    // continuam claros por cima do fundo grafite.
    final hubChrome = kIsWeb;
    final hubWide = hubChrome &&
        MediaQuery.sizeOf(context).width >= HubTheme.messagesSplitBreakpoint;
    final scaffoldBg = hubChrome ? HubMessagesTheme.bg : FleaberColors.bgTint;
    final appBarBg = hubChrome ? HubMessagesTheme.surface : Colors.white;
    final titleColor = hubChrome ? HubMessagesTheme.accent : _kTeal;
    final subtitleColor =
        hubChrome ? HubMessagesTheme.textMuted : const Color(0xFF57636C);
    final threadHPad = hubWide ? 20.0 : 16.0;

    if (!_metaReady) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: CircularProgressIndicator(
            color: hubChrome ? HubMessagesTheme.accent : null,
          ),
        ),
      );
    }
    if (_otherUser == null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          backgroundColor: appBarBg,
          leading: FlutterFlowIconButton(
            icon: Icon(
              widget.hubPanelMode
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              color: titleColor,
              size: 30,
            ),
            onPressed: () {
              if (widget.hubPanelMode) {
                widget.onHubPanelClose?.call();
              } else {
                context.safePop();
              }
            },
          ),
        ),
        body: Center(
          child: Text(
            'Utilizador não encontrado.',
            style: hubChrome
                ? HubMessagesTheme.body
                : FlutterFlowTheme.of(context).bodyLarge,
          ),
        ),
      );
    }

    final otherUser = _otherUser!;
    final product = _product;
    final headerCount = _headerCount();
    final reservationBanner = _reservationExpiryBanner();
    final stickyRes = _buildReservationStickyBar();

    // Mockup B (painel Hub): header compacto + cartão sticky; AppBar mobile intacto.
    final mockupB = widget.hubPanelMode;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: scaffoldBg,
        appBar: mockupB
            ? null
            : AppBar(
                backgroundColor: appBarBg,
                automaticallyImplyLeading: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: FlutterFlowIconButton(
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: titleColor,
                    size: 30,
                  ),
                  onPressed: () => context.safePop(),
                ),
                toolbarHeight:
                    reservationBanner != null ? 72 : kToolbarHeight,
                title: InkWell(
                  onTap: _openOtherUserProfile,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                otherUser.fullName ?? 'Chat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: titleColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                              if (reservationBanner != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    reservationBanner,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: subtitleColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: titleColor,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (mockupB) _buildMockupBConversationHeader(otherUser),
              if (mockupB && product != null)
                _buildProductHeaderCard(product),
              if (stickyRes != null) stickyRes,
              Expanded(
                child: StreamBuilder<List<ChatMessagesRow>>(
                  stream: _model.containerSupabaseStream ??= SupaFlow.client
                      .from("chat_messages")
                      .stream(primaryKey: ['id'])
                      .eqOrNull('chat_id', widget.chatId)
                      .order('created_at', ascending: true)
                      .map((list) =>
                          list.map((item) => ChatMessagesRow(item)).toList()),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final messages =
                        _messagesWithOptimistic(snapshot.data!);
                    _lastChatMessagesForMerge = messages;
                    // H10: se o sticky ainda mostra 1 artigo mas o fio já tem
                    // pedido de conjunto (≥2), hidratar header a partir das msgs.
                    if (!_bundleHeaderMsgHydrateBusy &&
                        _bundleHeaderOrders.length < 2 &&
                        messages.any((m) {
                          final p = tryParseBundleProposalChatPayload(
                            m.text ?? '',
                          );
                          if (p == null) return false;
                          return parseBundleProductIds(p['product_ids']).length >=
                              2;
                        })) {
                      _bundleHeaderMsgHydrateBusy = true;
                      final cid = widget.chatId?.trim() ?? '';
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        try {
                          if (!mounted || cid.isEmpty) return;
                          final fromMsg =
                              await buildBundleDisplayOrdersFromLatestChatMessage(
                            cid,
                          );
                          if (!mounted || fromMsg.length < 2) return;
                          setState(() {
                            _bundleOrdersForChat = fromMsg;
                            _focusedBundleStatus ??= 'pending';
                            for (final o in fromMsg) {
                              final oid = o.id?.trim();
                              if (oid != null && oid.isNotEmpty) {
                                _bundleLinkedOrderIds.add(oid);
                              }
                            }
                          });
                        } finally {
                          _bundleHeaderMsgHydrateBusy = false;
                        }
                      });
                    }
                    final lastMsgId =
                        messages.isNotEmpty ? messages.last.id : null;
                    if (lastMsgId != null &&
                        lastMsgId != _lastChatMessageIdSeenForOrderSync &&
                        product?.id != null &&
                        product!.id!.isNotEmpty) {
                      _lastChatMessageIdSeenForOrderSync = lastMsgId;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) return;
                        await _loadOrderForChat(product!.id!);
                        await _loadPendingBuyerOffer();
                        if (mounted) setState(() {});
                      });
                    }
                    final merged = _mergeShippingIntoMessages(messages);
                    if (lastMsgId != null &&
                        lastMsgId != _lastAutoScrolledMessageId) {
                      final hadPreviousAutoScroll =
                          _lastAutoScrolledMessageId != null;
                      _lastAutoScrolledMessageId = lastMsgId;
                      _scrollMessagesToBottom(
                        animate: hadPreviousAutoScroll,
                      );
                    } else if (lastMsgId == null &&
                        _lastAutoScrolledMessageId == null) {
                      _scrollMessagesToBottom();
                    }
                    final threadList = ListView.builder(
                      controller: _messagesScrollController,
                      padding: EdgeInsets.only(
                        bottom: 12,
                        top: 4,
                        left: hubWide ? 12 : 4,
                        right: hubWide ? 12 : 4,
                      ),
                      itemCount: headerCount + merged.length,
                      itemBuilder: (context, index) {
                        if (!widget.hubPanelMode) {
                          if (product != null && index == 0) {
                            return _buildProductHeaderCard(product);
                          }
                          if (index == (product != null ? 1 : 0)) {
                            return _buildParticipantStrip(otherUser);
                          }
                        }

                        final mi = index - headerCount;
                        final entry = merged[mi];

                        final showSeparator = mi == 0 ||
                            _dayKeyForMergedItem(merged[mi - 1]) !=
                                _dayKeyForMergedItem(entry);

                        if (entry.isReservationPendingInjected) {
                          final anchor =
                              (_orderForChat?.createdAt ?? DateTime.now())
                                  .toLocal();
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(anchor),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildReservationPendingSystemCard(messages),
                            ],
                          );
                        }

                        if (entry.isBundlePurchaseCard) {
                          final anchor = (_bundlePurchaseAnchorTime() ??
                                  _orderForChat?.createdAt ??
                                  DateTime.now())
                              .toLocal();
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(anchor),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildBundlePurchaseTimelineCard(),
                            ],
                          );
                        }

                        if (entry.isBundleShippedCard) {
                          final anchor = (_bundleShippedAnchorTime(messages) ??
                                  _orderForChat?.createdAt ??
                                  DateTime.now())
                              .toLocal();
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(anchor),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildBundleShippedTimelineCard(),
                            ],
                          );
                        }

                        if (entry.isShippingCard) {
                          final anchor =
                              (_orderForChat?.createdAt ?? DateTime.now())
                                  .toLocal();
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(anchor),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildSaleManagementCardInList(),
                            ],
                          );
                        }

                        final msg = entry.message!;
                        final date = msg.createdAt ?? DateTime.now();

                        final payload = _tryParseFleaberChatJson(msg.text);
                        final isCancelRequest = payload != null &&
                            payload['kind'] == 'cancel_request';
                        final isCancelOutcome = payload != null &&
                            payload['kind'] == 'cancel_request_outcome';

                        final isPriceOffer = payload != null &&
                            payload['kind'] == 'price_offer';
                        final isPriceOfferOutcome = payload != null &&
                            payload['kind'] == 'price_offer_outcome';
                        final bundlePayload =
                            tryParseBundleProposalChatPayload(msg.text);

                        final batataKind = payload?['kind']?.toString();
                        final isBatataReservationCard = payload != null &&
                            batataKind != null &&
                            const {
                              'reservation_request',
                              'reservation_request_outcome',
                              'reservation_accepted',
                              'reservation_payment_submitted',
                              'reservation_reminder',
                              'reservation_payment_check_reminder',
                              'reservation_shipping_reminder',
                              'reservation_seller_confirmed_receipt',
                              'reservation_order_shipped',
                              'reservation_order_completed',
                              'bundle_buyer_confirmed_receipt',
                              'auto_feedback_generated',
                              'raffle_prize_awarded',
                              'order_review_submitted',
                              'reservation_cancelled_by_seller',
                              'bundle_reservation_cancelled_by_seller',
                              'order_dispute_opened',
                              'seguro_fleaber_paid',
                              'pending_expired_buyer_notice',
                              'guaranteed_expired_buyer_notice',
                            }.contains(batataKind);

                        if (isPriceOffer && payload != null) {
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: PriceOfferChatCard(
                                  payload: payload,
                                  allMessages: messages,
                                  messageId: msg.id.toString(),
                                  product: product,
                                  onUpdated: () {
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (isPriceOfferOutcome && payload != null) {
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: PriceOfferOutcomeChatCard(
                                  payload: payload,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (bundlePayload != null) {
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: BundleProposalChatCard(
                                  payload: bundlePayload,
                                  onUpdated: () async {
                                    if (!mounted) return;
                                    await _refreshBundleProposalThreadState(
                                      productId: product?.id,
                                    );
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        final bundleDirectPaymentPayload =
                            tryParseBundleDirectPaymentPayload(msg.text ?? '');
                        if (bundleDirectPaymentPayload != null) {
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildBundleDirectPaymentDetailsCard(
                                bundleDirectPaymentPayload,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (isBatataReservationCard) {
                          if (_isBundleReservationOutcomeMessage(payload) &&
                              (batataKind == 'reservation_accepted' ||
                                  batataKind ==
                                      'reservation_request_outcome')) {
                            return const SizedBox.shrink();
                          }
                          Widget inner;
                          switch (batataKind) {
                            case 'reservation_request':
                              inner = _buildReservationRequestCard(
                                  msg, messages);
                              break;
                            case 'reservation_request_outcome':
                              inner =
                                  _buildReservationRequestOutcomeCard(payload!);
                              break;
                            case 'reservation_accepted':
                              inner = _buildReservationAcceptedCard(payload!);
                              break;
                            case 'reservation_payment_submitted':
                              inner = _buildReservationPaymentSubmittedCard(
                                  payload!);
                              break;
                            case 'reservation_reminder':
                              inner = _shouldHideReservationReminderMessage(
                                      payload)
                                  ? const SizedBox.shrink()
                                  : _buildReservationReminderCard();
                              break;
                            case 'reservation_payment_check_reminder':
                              inner = _shouldHideReservationReminderMessage(
                                      payload)
                                  ? const SizedBox.shrink()
                                  : _buildReservationPaymentCheckReminderCard();
                              break;
                            case 'reservation_shipping_reminder':
                              inner = _shouldHideReservationReminderMessage(
                                      payload)
                                  ? const SizedBox.shrink()
                                  : _buildReservationShippingReminderCard();
                              break;
                            case 'reservation_seller_confirmed_receipt':
                              inner = _isBundleReservationOutcomeMessage(
                                      payload)
                                  ? const SizedBox.shrink()
                                  : _buildReservationSellerConfirmedCard();
                              break;
                            case 'reservation_order_shipped':
                              inner = _buildReservationOrderShippedCard(payload);
                              break;
                            case 'reservation_order_completed':
                              inner = _buildReservationOrderCompletedCard();
                              break;
                            case 'bundle_buyer_confirmed_receipt':
                              inner = _buildBundleBuyerConfirmedReceiptCard();
                              break;
                            case 'auto_feedback_generated':
                              inner = _buildAutoFeedbackGeneratedCard();
                              break;
                            case 'raffle_prize_awarded':
                              inner = _buildRafflePrizeAwardedCard(payload!);
                              break;
                            case 'order_review_submitted':
                              inner = _buildOrderReviewSubmittedCard(payload!);
                              break;
                            case 'reservation_cancelled_by_seller':
                              inner = _buildReservationCancelledBySellerCard();
                              break;
                            case 'bundle_reservation_cancelled_by_seller':
                              inner = _buildBundleReservationCancelledBySellerCard();
                              break;
                            case 'order_dispute_opened':
                              inner = _buildOrderDisputeOpenedCard(payload!);
                              break;
                            case 'seguro_fleaber_paid':
                              inner = _buildSeguroFleaberPaidCard(
                                payload: payload,
                                forBuyer: msg.senderId == currentUserUid ||
                                    _orderForChat?.buyerId == currentUserUid,
                                allMessages: messages,
                              );
                              break;
                            case 'pending_expired_buyer_notice':
                            case 'guaranteed_expired_buyer_notice':
                              inner = _buildSoftSystemNoticeCard(
                                fleaberChatSystemKindLabel(
                                  batataKind,
                                  title: payload?['title']?.toString(),
                                  display: payload?['display']?.toString(),
                                ),
                                tone: HubMessagesTheme.warningBg,
                                border: HubMessagesTheme.warningBorder,
                                foreground: HubMessagesTheme.warningText,
                              );
                              break;
                            default:
                              inner = const SizedBox.shrink();
                          }
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: inner,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        // Phase 7 — system DM from commerce reservation lifecycle
                        final fleaberResDm = _tryBuildCommerceReservationDmCard(
                          msg.text,
                          date: date,
                          showSeparator: showSeparator,
                        );
                        if (fleaberResDm != null) {
                          return fleaberResDm;
                        }

                        if (isCancelRequest || isCancelOutcome) {
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: isCancelRequest
                                    ? _buildCancelRequestChatCard(
                                        msg, messages)
                                    : _buildCancelOutcomeFromPayload(
                                        payload!),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (_isLegacySeguroFleaberPaidPlainText(msg.text)) {
                          final forBuyerLegacy = msg.senderId ==
                                  currentUserUid ||
                              _orderForChat?.buyerId == currentUserUid;
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4F5B67),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _buildSeguroFleaberPaidCard(
                                legacyPlainText: msg.text,
                                forBuyer: forBuyerLegacy,
                                allMessages: messages,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        final bool isMe = msg.senderId == currentUserUid;
                        final chatImageUrl =
                            _chatImageUrlFromMessage(msg.text);
                        // Payload JSON sem cartão dedicado → aviso suave, nunca
                        // «[Mensagem do sistema]» nem JSON cru.
                        if (payload != null && chatImageUrl == null) {
                          final label = fleaberChatSystemKindLabel(
                            payload['kind']?.toString(),
                            title: payload['title']?.toString(),
                            display: payload['display']?.toString() ??
                                payload['label']?.toString(),
                          );
                          return Column(
                            children: [
                              if (showSeparator)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: kChatSystemSectionSpacing,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: HubMessagesTheme.systemChipBg,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        getDisplayDate(date),
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              HubMessagesTheme.systemChipText,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: threadHPad,
                                  vertical: kChatSystemSectionSpacingHalf,
                                ),
                                child: _buildSoftSystemNoticeCard(
                                  label,
                                  tone: HubMessagesTheme.neutralBg,
                                  border: HubMessagesTheme.neutralBorder,
                                  foreground: HubMessagesTheme.textSecondary,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: kChatSystemSectionSpacingHalf,
                                ),
                                child: Center(
                                  child: Text(
                                    DateFormat('HH:mm').format(date),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: HubMessagesTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        final rawBubble = msg.text;
                        final bubbleText = rawBubble == null
                            ? null
                            : _stripOrderMarkerFromChatText(rawBubble);

                        return Column(
                          children: [
                            if (showSeparator)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: kChatSystemSectionSpacing,
                                ),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: HubMessagesTheme.systemChipBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      getDisplayDate(date),
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: HubMessagesTheme.systemChipText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: threadHPad,
                                vertical: kChatMessageItemSpacingHalf,
                              ),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: hubWide
                                        ? 440
                                        : (MediaQuery.sizeOf(context).width *
                                            0.82),
                                  ),
                                  child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (chatImageUrl != null)
                                      _buildChatImageBubble(
                                        chatImageUrl,
                                        isMe: isMe,
                                      )
                                    else
                                      Container(
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? HubMessagesTheme.bubbleSent
                                              : HubMessagesTheme.bubbleReceived,
                                          borderRadius:
                                              FleaberRadius.circularMd,
                                          border: isMe
                                              ? null
                                              : Border.all(
                                                  color: HubMessagesTheme
                                                      .border),
                                          boxShadow: !isMe
                                              ? HubMessagesTheme.cardShadow
                                              : null,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          bubbleText ?? '',
                                          style: GoogleFonts.inter(
                                            fontSize: 14.5,
                                            height: 1.35,
                                            color: isMe
                                                ? Colors.white
                                                : HubMessagesTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          DateFormat('HH:mm').format(date),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: HubMessagesTheme.textMuted,
                                          ),
                                        ),
                                        if (isMe &&
                                            !_otherUserIsAdmin &&
                                            msg.isRead == true) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.done_all_rounded,
                                            size: 13,
                                            color: HubMessagesTheme.teal,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                    if (hubWide) {
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: HubTheme.messagesThreadMaxWidth,
                          ),
                          child: threadList,
                        ),
                      );
                    }
                    return threadList;
                  },
                ),
              ),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: hubChrome ? HubMessagesTheme.surface : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: hubChrome
                          ? HubMessagesTheme.divider
                          : const Color(0xFFF1F4F8),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: hubWide
                            ? HubTheme.messagesThreadMaxWidth
                            : double.infinity,
                      ),
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FlutterFlowIconButton(
                          borderRadius: 30,
                          buttonSize: 46,
                          icon: Icon(Icons.add_circle_outline_rounded,
                              color: titleColor, size: 28),
                          onPressed: () => pickMedia(),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _model.inputMensagemTextController,
                            focusNode: _model.inputMensagemFocusNode,
                            onChanged: (_) => setState(() {}),
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onFieldSubmitted: (_) => _sendChatMessage(),
                            style: GoogleFonts.inter(
                              color: HubMessagesTheme.textPrimary,
                              fontSize: 15,
                              height: 1.35,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Escreve uma mensagem...',
                              hintStyle: HubMessagesTheme.body.copyWith(
                                fontSize: 14,
                                color: HubMessagesTheme.textMuted,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: HubMessagesTheme.border,
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: titleColor, width: 1.5),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              filled: true,
                              fillColor: HubMessagesTheme.surfaceElevated,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FlutterFlowIconButton(
                          borderRadius: 22,
                          buttonSize: 44,
                          fillColor:
                              ((_model.inputMensagemTextController?.text ?? '')
                                          .trim()
                                          .runes
                                          .length >=
                                      _kMinChatLetters)
                                  ? _kTeal
                                  : const Color(0xFFB7C1C8),
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                          onPressed: _sendChatMessage,
                        ),
                      ],
                    ),
                  ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

