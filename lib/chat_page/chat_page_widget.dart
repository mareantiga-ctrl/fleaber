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
import '/widgets/price_offer_chat_card.dart';
import '/marketplace_feed_refresh.dart';
import '/order_cancel_apply.dart';
import '/order_cancel_eligibility.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '/utils/batata_admin_util.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_chat_spacing.dart';
import '/widgets/fleaber_primary_button.dart';
import '/utils/return_label.dart';
import '/perfil_vendedor/perfil_vendedor_widget.dart';
import 'chat_page_model.dart';
export 'chat_page_model.dart';

/// Chave extra para abrir checkout ao navegar para o detalhe (sincronizar com `ProductDetailsPageWidget.routeExtraOpenCheckoutKey`).
const String _kFleaberOpenCheckoutExtra = '__fleaber_open_checkout__';

/// Mesmo valor que `ProductDetailsPageWidget.routeExtraProductKey` (evita import circular).
const String _kProductRouteExtraKey = '__fleaber_product_row__';

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

  final ChatMessagesRow? message;
  final int sourceIndex;
  final _MergedInjectKind injectKind;

  bool get isShippingCard => injectKind == _MergedInjectKind.shipping;
  bool get isReservationPendingInjected =>
      injectKind == _MergedInjectKind.reservationPending;
}

enum _MergedInjectKind { none, shipping, reservationPending }

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
    this.requestCancelOnOpen = false,
  });

  final String? otherUserId;
  final String? chatId;

  /// Abrir o chat a partir das encomendas e enviar já o pedido de cancelamento (comprador).
  final bool requestCancelOnOpen;

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
  static const int _kMinChatLetters = 2;

  ProfilesRow? _otherUser;
  bool _otherUserIsAdmin = false;
  ChatsRow? _chat;
  ProductsRow? _product;
  OrdersRow? _orderForChat;
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
  String? _localFeedbackSubmittedOrderId;
  String? _localDisputeOpenedOrderId;
  String? _disputeThreadOrderId;
  Future<_DisputeThread?>? _disputeThreadFuture;
  _DisputeThread? _disputeThreadCache;
  int? _lastAutoScrolledMessageId;
  Timer? _reservationUiTimer;

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

    final profileRows = await ProfilesTable().querySingleRow(
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

  Future<void> _loadOrderForChat(String productId) async {
    if (productId.isEmpty) return;
    final otherId = widget.otherUserId;
    if (otherId == null || otherId.isEmpty || currentUserUid.isEmpty) return;
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('product_id', productId)
          .or(
            'and(buyer_id.eq.$currentUserUid,seller_id.eq.$otherId),and(buyer_id.eq.$otherId,seller_id.eq.$currentUserUid)',
          )
          .order('created_at', ascending: false),
      limit: 15,
    );
    // Sempre a encomenda mais recente — evita ficar preso a uma mais antiga em «pendente»
    // quando a última já está «cancelado» ou «pago».
    _orderForChat = rows.isNotEmpty ? rows.first : null;
    final loadedOrderId = _orderForChat?.id;
    if (loadedOrderId != _disputeThreadOrderId) {
      _disputeThreadOrderId = null;
      _disputeThreadFuture = null;
      _disputeThreadCache = null;
    }
    await _maybeSimulateReturnDelivery();
  }

  static const String _kFleaberChatJsonPrefix = 'FLEABER_JSON_V1:';

  Map<String, dynamic>? _tryParseFleaberChatJson(String text) {
    if (!text.startsWith(_kFleaberChatJsonPrefix)) return null;
    try {
      final decoded =
          jsonDecode(text.substring(_kFleaberChatJsonPrefix.length));
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
        final url = payload['url']?.toString().trim() ?? '';
        if (url.startsWith('http')) return url;
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
      onTap: () => _openProofImageDialog(imageUrl),
      child: ClipRRect(
        borderRadius: FleaberRadius.circularMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 240,
            maxHeight: 280,
          ),
          child: BatataCachedNetworkImage(
            imageUrl: imageUrl,
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

  Future<void> _maybeInsertReservationReminder(
    List<ChatMessagesRow> messages,
  ) async {
    final order = _orderForChat;
    final chatId = widget.chatId;
    final otherId = widget.otherUserId;
    if (_reservationReminderBusy ||
        order == null ||
        order.id == null ||
        order.id!.isEmpty ||
        chatId == null ||
        chatId.isEmpty ||
        otherId == null ||
        otherId.isEmpty ||
        order.buyerId != currentUserUid) {
      return;
    }
    final status = normalizeOrderStatusKey(order.status);
    if (status != 'reservado' &&
        status != 'aguarda_confirmacao' &&
        status != 'pago') {
      await _maybeInsertAutomaticFeedbackIfDue(messages);
      return;
    }
    final isDirectPayment =
        (order.paymentMethod ?? '').toLowerCase().contains('direto');
    if (status == 'pago' && !(order.isReservation == true && isDirectPayment)) {
      await _maybeInsertAutomaticFeedbackIfDue(messages);
      return;
    }
    if (order.buyerId != currentUserUid) {
      await _maybeInsertAutomaticFeedbackIfDue(messages);
      return;
    }

    final oid = order.id!;
    final reminderKind = switch (status) {
      'aguarda_confirmacao' => 'reservation_payment_check_reminder',
      'pago' => 'reservation_shipping_reminder',
      _ => 'reservation_reminder',
    };
    ChatMessagesRow? lastReminder;
    for (final m in messages.reversed) {
      final p = _tryParseFleaberChatJson(m.text);
      if (p == null) continue;
      if (p['kind'] != reminderKind) continue;
      if (p['order_id']?.toString() != oid) continue;
      lastReminder = m;
      break;
    }
    final now = DateTime.now();
    if (lastReminder != null) {
      final t = lastReminder.createdAt?.toLocal();
      if (t != null && now.difference(t) < const Duration(hours: 24)) {
        return;
      }
    }

    _reservationReminderBusy = true;
    try {
      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': otherId,
        'is_read': false,
        'text': _fleaberChatJsonEncode({
          'kind': reminderKind,
          'order_id': oid,
          'v': 1,
        }),
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
            const Duration(minutes: 5)) {
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
    if (normalizeOrderStatusKey(order.status) != 'aguarda_confirmacao') {
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
      if (pid.isNotEmpty) {
        await ProductsTable().update(
          data: {'is_sold': true},
          matchingRows: (rows) => rows.eqOrNull('id', pid),
        );
      }
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cancelar reserva?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'O artigo volta a ficar disponível no marketplace. Esta acção não pode '
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
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _reservationChatBusy = true);
    try {
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
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
      _playBatataNotify();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva cancelada.')),
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
    final buyerId = widget.otherUserId;
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
    final buyerId = widget.otherUserId;
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
    final chatId = widget.chatId;
    final sellerId = widget.otherUserId;
    final orderId = order?.id;
    if (_cancelChatBusy ||
        order == null ||
        orderId == null ||
        orderId.isEmpty ||
        chatId == null ||
        chatId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return;
    }
    if (order.buyerId != currentUserUid) return;

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
        await applyOrderCancelAndRelist(
          orderId: orderId,
          sellerUserId: currentUserUid,
        );
        print(
          'BATATA_CANCEL_NEGOCIADO aceite order=$orderId novo listing criado',
        );

        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': buyerId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'cancel_request_outcome',
            'order_id': orderId,
            'outcome': 'accepted',
            'display': 'Compra cancelada — encomenda anulada.',
            'v': 1,
          }),
          'chat_id': chatId,
          'is_reservation': false,
        });
        requestMarketplaceFeedRefresh();
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
    final showSellerActions =
        imSeller && orderId != null && !resolved && matchesActiveOrder;

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
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accepted
                ? const Color(0xFFE6F7F5)
                : const Color(0xFFF2F4F7),
            borderRadius: FleaberRadius.circularSm,
            border: Border.all(
              color: accepted
                  ? const Color(0xFF8EC9C5)
                  : const Color(0xFFDDE2E7),
            ),
          ),
          child: Text(
            line,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2D3A42),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationAcceptedCard(Map<String, dynamic> payload) {
    final exp = _parseIsoDate(payload['expires_at']);
    final when = exp != null
        ? DateFormat("d MMM yyyy 'às' HH:mm", 'pt_PT').format(exp)
        : '—';
    final orderId = payload['order_id']?.toString();
    final order = _orderForChat;
    final matches =
        orderId != null && order != null && order.id != null && orderId == order.id;
    final imBuyer =
        matches && (order?.buyerId == currentUserUid);
    final imSeller =
        matches && (order?.sellerId == currentUserUid);

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
                    imBuyer
                        ? 'Reserva aceite! Tens até $when para pagar.'
                        : 'Reserva aceite. Aguarda o pagamento do comprador até $when.',
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

  Widget _buildReservationPaymentSubmittedCard(Map<String, dynamic> payload) {
    final notes = (payload['notes'] ?? '').toString().trim();
    final proofUrl = (payload['proof_url'] ?? '').toString().trim();
    final o = _orderForChat;
    final oid = payload['order_id']?.toString();
    final matchesOrder =
        oid != null && o?.id != null && oid == o!.id;
    final imBuyer = o?.buyerId == currentUserUid;
    final imSeller = matchesOrder && o!.sellerId == currentUserUid;
    final sellerCanConfirm = imSeller &&
        normalizeOrderStatusKey(o?.status) == 'aguarda_confirmacao';

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
            'Pagamento confirmado pelo vendedor. Estado da encomenda: Pago.',
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

  Widget _buildReservationOrderShippedCard() {
    return _buildSimpleReservationInfoCard(
      text: 'O vendedor confirmou o envio da encomenda.',
      icon: Icons.local_shipping_rounded,
      color: const Color(0xFFEFF6FF),
      border: const Color(0xFFBFDBFE),
      textColor: const Color(0xFF1E3A5F),
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

  Widget _buildOrderDisputeOpenedCard(Map<String, dynamic> payload) {
    final orderId =
        (payload['order_id'] ?? _orderForChat?.id ?? '').toString().trim();
    if (orderId.isEmpty) {
      final reason = (payload['reason'] ?? 'problema').toString();
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
    final currentOrder = _orderForChat;
    final isBuyer = currentOrder?.buyerId == currentUserUid;
    final isSeller = currentOrder?.sellerId == currentUserUid;
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
    final buyerHasOpenDecision =
        isBuyer && !blocked && (canBuyerAct || hasReturnOffer || hasPartialRefundOffer);
    final turnOwner = dispute.currentTurn == 'administracao'
        ? 'Administração Fleaber'
        : dispute.currentTurn == 'vendedor'
            ? 'Vendedor'
            : 'Comprador';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: kChatSystemSectionSpacingHalf,
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
                  const Icon(
                    Icons.report_problem_rounded,
                    color: Color(0xFFB45309),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Disputa aberta',
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
                    const SizedBox(width: 8),
                    if (orderStatus == 'pedido_devolucao')
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
                ),
                if (orderStatus == 'pedido_devolucao') ...[
                  const SizedBox(height: kChatMessageItemSpacing),
                  OutlinedButton(
                    onPressed: _disputeBusy
                        ? null
                        : () => _sellerOfferPartialRefund(thread),
                    child: const Text('Oferecer reembolso parcial (%)'),
                  ),
                ],
              ],
              if (buyerHasOpenDecision) ...[
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
              if (blocked) ...[
                const SizedBox(height: kChatSystemSectionSpacing),
                Text(
                  dispute.status == 'escalada_fleaber'
                      ? 'Disputa entregue à Administração do Fleaber.'
                      : 'Disputa fechada.',
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
            onPressed: _disputeBusy ? null : () => _openReturnLabelUrl(labelUrl),
          ),
        ],
      ),
    );
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

  Widget? _buildReservationStickyBar() {
    final o = _orderForChat;
    if (o == null) return null;
    final st = normalizeOrderStatusKey(o.status);
    if (st != 'reservado' &&
        st != 'aguarda_confirmacao' &&
        st != 'enviado' &&
        st != 'concluido') {
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
                          borderRadius: FleaberRadius.circularSm,
                        ),
                      ),
                    ),
                  ),
                ],
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
                                if (st == 'aguarda_confirmacao') {
                                  _confirmSellerMoneyReceivedWithDialog();
                                } else {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Aguarda que o comprador envie a prova de '
                                        'pagamento no chat. Depois podes confirmar a receção.',
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
              if (imBuyer && st == 'enviado') ...[
                if (showPaymentCountdown) const SizedBox(height: 8),
                FleaberPrimaryButton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 10,
                  label: 'Confirmar receção da encomenda',
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
                        borderRadius: FleaberRadius.circularSm,
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
            ],
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
                          'Pedido de Cancelamento: O comprador deseja anular a '
                          'compra. Vendedor, já enviaste o artigo?',
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
    final order = _orderForChat;
    if (order == null) return false;
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
        _localFeedbackSubmittedOrderId != order.id &&
        _localDisputeOpenedOrderId != order.id;
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
      final path =
          'order_disputes/${currentUserUid}_${disputeOrOrderId}_${DateTime.now().millisecondsSinceEpoch}_${i}_$safeName';
      await SupaFlow.client.storage.from('chat_media').uploadBinary(path, bytes);
      urls.add(
        SupaFlow.client.storage.from('chat_media').getPublicUrl(path),
      );
    }
    return urls;
  }

  Future<void> _showSubmitProofDialog() async {
    final order = _orderForChat;
    if (order == null || order.id == null || widget.chatId == null) return;
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
    final order = _orderForChat;
    final chatId = widget.chatId;
    final sellerId = widget.otherUserId;
    if (order == null ||
        order.id == null ||
        chatId == null ||
        chatId.isEmpty ||
        sellerId == null ||
        sellerId.isEmpty) {
      return;
    }
    if (!_shouldShowProofButton) return;

    setState(() => _reservationChatBusy = true);
    try {
      String? proofUrl;
      if (image != null) {
        final bytes = await image.readAsBytes();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        final path = 'order_proofs/$fileName';
        await SupaFlow.client.storage
            .from('chat_media')
            .uploadBinary(path, bytes);
        proofUrl =
            SupaFlow.client.storage.from('chat_media').getPublicUrl(path);
      }

      final orderUpdate = <String, dynamic>{
        'status': 'aguarda_confirmacao',
      };
      if (proofUrl != null && proofUrl.isNotEmpty) {
        orderUpdate['proof_url'] = proofUrl;
      }
      await OrdersTable().update(
        data: orderUpdate,
        matchingRows: (rows) => rows.eqOrNull('id', order.id),
      );
      final payload = <String, dynamic>{
        'kind': 'reservation_payment_submitted',
        'order_id': order.id,
        'notes': notes,
        'v': 1,
      };
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
      await _loadOrderForChat(order.productId ?? '');
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
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            final canSubmit =
                !submitting && descriptionController.text.trim().length >= 6;
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
                    const SizedBox(height: 18),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Abrir disputa',
                      loading: submitting,
                      fontWeight: FontWeight.w800,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      height: null,
                      onPressed: canSubmit
                          ? () async {
                              setSheetState(() => submitting = true);
                              setState(() => _disputeBusy = true);
                              try {
                                await _submitBuyerDispute(
                                  order: order,
                                  reason: reason,
                                  description:
                                      descriptionController.text.trim(),
                                  photos: List<XFile>.from(selectedPhotos),
                                );
                                if (!mounted) return;
                                Navigator.of(sheetContext).pop(true);
                              } catch (e) {
                                print('BATATA_DISPUTE ERRO: $e');
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao abrir disputa: $e'),
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

  Future<void> _sellerAcceptDispute(_DisputeThread thread) async {
    final disputeId = thread.dispute.id;
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
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
    final orderId = _orderForChat?.id;
    if (disputeId == null || orderId == null) return;
    setState(() => _disputeBusy = true);
    try {
      await SupaFlow.client.rpc(
        'batata_process_partial_refund_dispute',
        params: {
          'p_order_id': orderId,
          'p_refund_percent': thread.dispute.sellerRefundPercent ?? 0,
        },
      );
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
        data: {'status': 'concluido'},
        matchingRows: (rows) => rows.eqOrNull('id', orderId),
      );
      await _touchChatLastMessage('Reembolso parcial aceite');
      await _loadOrderForChat(_orderForChat?.productId ?? '');
      await _refreshDisputeThreadForOrder(_orderForChat?.id);
      if (!mounted) return;
      setState(() {});
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

    final proofUrls = await _uploadDisputePhotos(orderId, photos);

    await OrderDisputesTable().insert({
      'order_id': orderId,
      'buyer_id': currentUserUid,
      'reason': reason,
      'description': description,
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
        'description': description,
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

  // Lógica para enviar imagem/vídeo (Bucket: chat_media)
  Future<void> pickMedia() async {
    try {
      final XFile? media = await _picker.pickMedia();
      if (media != null) {
        final bytes = await media.readAsBytes();
        final String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${media.name}';
        final String path = 'chat_uploads/$fileName';

        await SupaFlow.client.storage
            .from('chat_media')
            .uploadBinary(path, bytes);
        final String publicUrl =
            SupaFlow.client.storage.from('chat_media').getPublicUrl(path);

        await ChatMessagesTable().insert({
          'sender_id': currentUserUid,
          'receiver_id': widget.otherUserId,
          'is_read': false,
          'text': _fleaberChatJsonEncode({
            'kind': 'chat_image',
            'url': publicUrl,
            'v': 1,
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
                'Erro ao carregar ficheiro. Garante que o bucket "chat_media" existe no Supabase.')),
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
    context.pushNamed(
      PerfilVendedorWidget.routeName,
      queryParameters: {
        'sellerID': serializeParam(uid, ParamType.String),
      }.withoutNulls,
    );
  }

  /// Esconde «Fazer proposta» / «Comprar» (artigo nosso, vendido, férias ou com encomenda).
  bool _suppressMarketplacePurchaseRow(ProductsRow p) {
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
    final o = _orderForChat;
    final pid = p.id;
    if (o == null || pid == null || pid.isEmpty || o.productId != pid) {
      return false;
    }
    // Regra: tratado como vendido quando pago ou com reserva aceite.
    final status = normalizeOrderStatusKey(o.status);
    return status == 'pago' ||
        status == 'reservado' ||
        status == 'aguarda_confirmacao' ||
        status == 'enviado' ||
        status == 'concluido';
  }

  Widget _buildProductHeaderCard(ProductsRow p) {
    final url = p.imageUrls.isNotEmpty ? p.imageUrls.first : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FleaberRadius.circularMd,
          side: const BorderSide(color: Color(0xFFE0E3E7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _openProductDetails(p),
                borderRadius: FleaberRadius.circularSm,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: FleaberRadius.circularSm,
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: url != null && url.isNotEmpty
                              ? BatataCachedNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.cover,
                                  placeholderColor: const Color(0xFFF1F4F8),
                                  errorWidget: ColoredBox(
                                    color: const Color(0xFFF1F4F8),
                                    child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: Colors.grey.shade500,
                                        size: 28),
                                  ),
                                )
                              : ColoredBox(
                                  color: const Color(0xFFF1F4F8),
                                  child: Icon(Icons.inventory_2_outlined,
                                      color: Colors.grey.shade500, size: 28),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title ?? 'Artigo',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                height: 1.25,
                                color: const Color(0xFF101518),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatProductPrice(p.price),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: _kTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: kChatSystemSectionSpacing),
              if (!_suppressMarketplacePurchaseRow(p))
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _onFazerProposta(p),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kTeal,
                          side: const BorderSide(color: _kTeal, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: FleaberRadius.circularSm,
                          ),
                        ),
                        child: Text(
                          _pendingBuyerOffer != null
                              ? 'Alterar proposta'
                              : 'Fazer proposta',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FleaberPrimaryButton(
                        width: double.infinity,
                        label: 'Comprar',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        borderRadius: 10,
                        height: null,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        disabledBackgroundColor: const Color(0xFFE8EDF2),
                        onPressed: () => _onComprar(p),
                      ),
                    ),
                  ],
                )
              else if (_isProductSoldForCurrentChat(p))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Este artigo já foi vendido.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                )
              else if (_otherUser?.vacationMode == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Este vendedor está de férias — não é possível comprar nem fazer propostas novas.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                )
              else if (_orderForChat?.productId == p.id)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Compra ou reserva associada a esta conversa.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ),
              if (_shouldShowProofButton)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _reservationChatBusy
                          ? null
                          : _showSubmitProofDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: const BorderSide(color: _kTeal, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: FleaberRadius.circularSm,
                        ),
                      ),
                      child: const Text('Enviar Prova de Pagamento'),
                    ),
                  ),
                ),
              if (_canBuyerShowCancelButton)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          _cancelChatBusy ? null : () => _onBuyerRequestCancel(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTeal,
                        side: const BorderSide(color: _kTeal, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: FleaberRadius.circularSm,
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _kTeal,
                        ),
                      ),
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0xFFD9DEE3),
                ),
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

  static const Color _kShippingCardBg = Color(0xFFF5F5F5);
  static const Color _kShippingCardBorder = Color(0xFFE0E0E0);

  bool _showSaleManagementCardInChat(OrdersRow order) {
    final pid = _product?.id;
    if (pid == null || order.productId != pid) return false;
    final imSeller = order.sellerId == currentUserUid;
    final imBuyer = order.buyerId == currentUserUid;
    if (!imSeller && !imBuyer) return false;
    final s = (order.status ?? '').toLowerCase();
    const sellerAllowed = {
      'pago',
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
      'cancelado',
    };
    const buyerAllowed = {
      'pago',
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
    if (imSeller) return sellerAllowed.contains(s);
    return buyerAllowed.contains(s);
  }

  bool _isBuyerViewSaleCard(OrdersRow order) =>
      order.buyerId == currentUserUid;

  bool _sellerCanSimulateShippingLabel(OrdersRow order) {
    if (orderIsCancelled(order.status)) return false;
    final s = normalizeOrderStatusKey(order.status);
    if (s == 'enviado') return false;
    return s == 'pago';
  }

  bool _isDirectReservationOrder(OrdersRow order) =>
      order.isReservation == true &&
      (order.paymentMethod ?? '').toLowerCase().contains('direto');

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

    var filtered = messages;
    if (order != null &&
        order.id != null &&
        order.id!.isNotEmpty &&
        normalizeOrderStatusKey(order.status) == 'reserva_pendente') {
      final oid = order.id!;
      filtered = messages.where((m) {
        final p = _tryParseFleaberChatJson(m.text);
        if (p == null || p['kind'] != 'reservation_request') return true;
        return p['order_id']?.toString() != oid;
      }).toList();
    }

    if (order == null || pid == null || order.productId != pid) {
      return [
        for (var i = 0; i < filtered.length; i++)
          _MergedChatItem.message(filtered[i], i),
      ];
    }

    final showShipping = _showSaleManagementCardInChat(order);
    final showPendingInject = order.isReservation == true &&
        normalizeOrderStatusKey(order.status) == 'reserva_pendente';

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

  int _dayKeyForMergedItem(_MergedChatItem e) {
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
      if (s == 'enviado') return 'Artigo enviado!';
      if (s == 'concluido') return 'Venda concluída!';
      if (s == 'reservado') {
        return 'Reserva aceite — aguardando pagamento.';
      }
      if (s == 'aguarda_confirmacao') {
        return 'Pagamento enviado — aguarda confirmação.';
      }
      return 'Comprado!';
    }
    if (s == 'pedido_devolucao') return 'Pedido de devolução aberto.';
    if (s == 'em_devolucao') return 'Artigo em devolução.';
    if (s == 'devolucao_entregue') return 'Devolução recebida para conferência.';
    if (s == 'disputa_devolucao_vendedor') {
      return 'Problema na devolução enviado ao Fleaber.';
    }
    if (s == 'devolvida') return 'Artigo devolvido ao vendedor.';
    if (s == 'enviado') return 'Artigo enviado';
    if (s == 'concluido') return 'Venda concluída';
    if (s == 'reserva_pendente') {
      return 'Vendido — a aguardar a tua resposta ao pedido de reserva.';
    }
    if (s == 'reservado') {
      return 'Artigo reservado. Aguarda o pagamento do comprador.';
    }
    if (s == 'aguarda_confirmacao') {
      return 'O comprador indicou que já pagou.';
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
        return 'O vendedor marcou o envio. Quando receberes o artigo, confirma no chat.';
      }
      if (s == 'concluido') {
        return 'Receção confirmada. Tens 5 minutos para deixar avaliação (teste).';
      }
      if (s == 'reservado') {
        return 'O vendedor aceitou a reserva. Paga com Seguro Fleaber ou envia a prova se combinaste MB WAY/transferência direta.';
      }
      if (s == 'aguarda_confirmacao') {
        return 'A prova de pagamento foi enviada. O vendedor deve confirmar a receção antes do envio.';
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
      return 'Artigo enviado. Aguarda que o comprador confirme a receção.';
    }
    if (s == 'concluido') {
      return 'O comprador confirmou a receção. Tens 5 minutos para avaliar o cliente (teste).';
    }
    if (s == 'reservado') {
      return 'Quando o comprador pagar, recebes uma notificação no chat.';
    }
    if (s == 'aguarda_confirmacao') {
      return 'Confirma no teu banco ou MB WAY antes de marcar como recebido.';
    }
    if (s == 'reserva_pendente') {
      return 'Responde no chat para aceitar ou recusar o pedido de reserva.';
    }
    if (s == 'pago') {
      final total = order.priceTotal;
      final priceStr = total != null
          ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(total)
          : '—';
      return 'Quando o comprador receber o pedido, o valor de $priceStr será '
          'transferido para o teu saldo. Confirma o envio quando entregares o artigo.';
    }
    return null;
  }

  Future<void> _onSellerConfirmShipment() async {
    final o = _orderForChat;
    final chatId = widget.chatId;
    final buyerId = widget.otherUserId;
    if (_shippingLabelActionBusy ||
        o == null ||
        o.id == null ||
        o.id!.isEmpty ||
        !_sellerCanSimulateShippingLabel(o) ||
        chatId == null ||
        chatId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      return;
    }
    if (o.sellerId != currentUserUid) return;

    setState(() => _shippingLabelActionBusy = true);
    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      await OrdersTable().update(
        data: {'status': 'enviado'},
        matchingRows: (rows) => rows.eqOrNull('id', o.id),
      );

      await ChatMessagesTable().insert({
        'sender_id': currentUserUid,
        'receiver_id': buyerId,
        'is_read': false,
        'text': _fleaberChatJsonEncode({
          'kind': 'reservation_order_shipped',
          'order_id': o.id,
          'v': 1,
        }),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await ChatsTable().update(
        data: {
          'last_message': 'Artigo enviado',
          'last_message_time': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (rows) => rows.eqOrNull('id', chatId),
      );

      final pid = o.productId ?? '';
      await _loadOrderForChat(pid);
      requestMarketplaceFeedRefresh();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      print('BATATA_SHIPPING_LABEL ERRO: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar envio: $e')),
      );
    } finally {
      if (mounted) setState(() => _shippingLabelActionBusy = false);
    }
  }

  Future<void> _onBuyerConfirmOrderReceived() async {
    final o = _orderForChat;
    final chatId = widget.chatId;
    final sellerId = widget.otherUserId;
    if (_reservationChatBusy ||
        o == null ||
        o.id == null ||
        o.id!.isEmpty ||
        normalizeOrderStatusKey(o.status) != 'enviado' ||
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
          'v': 1,
        }),
        'chat_id': chatId,
        'is_reservation': true,
      });
      await _touchChatLastMessage('Venda concluída');
      await _loadOrderForChat(o.productId ?? '');
      if (!mounted) return;
      setState(() {});
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

  Future<void> _onLeaveFeedback() async {
    final o = _orderForChat;
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final value = i + 1;
                    return IconButton(
                      onPressed: () => setDialogState(() => stars = value),
                      icon: Icon(
                        value <= stars
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFFFB300),
                      ),
                    );
                  }),
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
        _localFeedbackSubmittedOrderId = o.id;
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

  Widget _buildSaleManagementCardInList() {
    final order = _orderForChat;
    if (order == null) return const SizedBox.shrink();
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
                                    if (status == 'aguarda_confirmacao') {
                                      _confirmSellerMoneyReceivedWithDialog();
                                    } else {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Aguarda que o comprador envie a prova de '
                                            'pagamento no chat. Depois podes confirmar a receção.',
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
                  if (forBuyer && !cancelled) ...[
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
                  if (showSellerButton) ...[
                    const SizedBox(height: 14),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: directReservation
                          ? 'Confirmar envio'
                          : 'Descarregar etiqueta de envio',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _headerCount() => (_product != null ? 1 : 0) + 1;

  @override
  Widget build(BuildContext context) {
    if (!_metaReady) {
      return const Scaffold(
        backgroundColor: FleaberColors.bgTint,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_otherUser == null) {
      return Scaffold(
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: FlutterFlowIconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _kTeal, size: 30),
            onPressed: () => context.safePop(),
          ),
        ),
        body: Center(
          child: Text(
            'Utilizador não encontrado.',
            style: FlutterFlowTheme.of(context).bodyLarge,
          ),
        ),
      );
    }

    final otherUser = _otherUser!;
    final product = _product;
    final headerCount = _headerCount();
    final reservationBanner = _reservationExpiryBanner();
    final stickyRes = _buildReservationStickyBar();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _kTeal, size: 30),
            onPressed: () => context.safePop(),
          ),
          toolbarHeight: reservationBanner != null ? 72 : kToolbarHeight,
          title: InkWell(
            onTap: _openOtherUserProfile,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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
                            color: _kTeal,
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
                                color: const Color(0xFF57636C),
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _kTeal,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
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
                    final messages = snapshot.data!;
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
                    return ListView.builder(
                      controller: _messagesScrollController,
                      padding: const EdgeInsets.only(
                        bottom: kChatMessageItemSpacing,
                      ),
                      itemCount: headerCount + merged.length,
                      itemBuilder: (context, index) {
                        if (product != null && index == 0) {
                          return _buildProductHeaderCard(product);
                        }
                        if (index == (product != null ? 1 : 0)) {
                          return _buildParticipantStrip(otherUser);
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
                              'auto_feedback_generated',
                              'reservation_cancelled_by_seller',
                              'order_dispute_opened',
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
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF57636C),
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
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF57636C),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (isBatataReservationCard) {
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
                              inner = _buildReservationReminderCard();
                              break;
                            case 'reservation_payment_check_reminder':
                              inner =
                                  _buildReservationPaymentCheckReminderCard();
                              break;
                            case 'reservation_shipping_reminder':
                              inner = _buildReservationShippingReminderCard();
                              break;
                            case 'reservation_seller_confirmed_receipt':
                              inner = _buildReservationSellerConfirmedCard();
                              break;
                            case 'reservation_order_shipped':
                              inner = _buildReservationOrderShippedCard();
                              break;
                            case 'reservation_order_completed':
                              inner = _buildReservationOrderCompletedCard();
                              break;
                            case 'auto_feedback_generated':
                              inner = _buildAutoFeedbackGeneratedCard();
                              break;
                            case 'reservation_cancelled_by_seller':
                              inner = _buildReservationCancelledBySellerCard();
                              break;
                            case 'order_dispute_opened':
                              inner = _buildOrderDisputeOpenedCard(payload!);
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
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF57636C),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
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
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF57636C),
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
                        final bubbleText = payload != null &&
                                chatImageUrl == null
                            ? '[Mensagem do sistema]'
                            : msg.text;

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
                                      borderRadius: BorderRadius.circular(999),
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
                                horizontal: 16,
                                vertical: kChatMessageItemSpacingHalf,
                              ),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
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
                                              ? _kTeal
                                              : Colors.white,
                                          borderRadius:
                                              FleaberRadius.circularMd,
                                          border: isMe
                                              ? null
                                              : Border.all(
                                                  color:
                                                      const Color(0xFFE0E3E7)),
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          bubbleText ?? '',
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          DateFormat('HH:mm').format(date),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isMe
                                                ? Colors.white
                                                    .withValues(alpha: 0.75)
                                                : const Color(0xFF57636C),
                                          ),
                                        ),
                                        if (isMe &&
                                            !_otherUserIsAdmin &&
                                            msg.isRead == true) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.done_all_rounded,
                                            size: 13,
                                            color: Colors.white
                                                .withValues(alpha: 0.85),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 10),
                child: Container(
                  width: double.infinity,
                  height: 70,
                  color: Colors.white,
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
                    child: Row(
                      children: [
                        FlutterFlowIconButton(
                          borderRadius: 30,
                          buttonSize: 44,
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: _kTeal, size: 28),
                          onPressed: () => pickMedia(),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _model.inputMensagemTextController,
                            focusNode: _model.inputMensagemFocusNode,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Escreve uma mensagem...',
                              hintStyle:
                                  FlutterFlowTheme.of(context).labelMedium,
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                    color: Color(0xFFE0E3E7), width: 2),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                    color: _kTeal, width: 2),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF1F4F8),
                              contentPadding:
                                  const EdgeInsetsDirectional.fromSTEB(
                                      20, 0, 20, 0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FlutterFlowIconButton(
                          borderRadius: 19,
                          buttonSize: 38,
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
                          onPressed: () async {
                            final text = (_model
                                        .inputMensagemTextController?.text ??
                                    '')
                                .trim();
                            if (text.runes.length < _kMinChatLetters) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Escreve pelo menos 2 letras para enviar.',
                                  ),
                                ),
                              );
                              return;
                            }
                            await ChatMessagesTable().insert({
                              'sender_id': currentUserUid,
                              'receiver_id': widget.otherUserId,
                              'chat_id': widget.chatId,
                              'text': text,
                              'is_read': false,
                              'is_reservation': false,
                            });
                            await ChatsTable().update(
                              data: {
                                'last_message': text,
                                'last_message_time': DateTime.now()
                                    .toUtc()
                                    .toIso8601String(),
                              },
                              matchingRows: (rows) =>
                                  rows.eqOrNull('id', widget.chatId),
                            );
                            _model.inputMensagemTextController?.clear();
                            setState(() {});
                          },
                        ),
                      ],
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
