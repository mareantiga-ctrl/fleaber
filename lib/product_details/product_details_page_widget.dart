import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/chat_session_util.dart';
import '/chat_page/chat_page_widget.dart';
import '/favorites_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_typography.dart';
import '/utils/fleaber_elevation.dart';
import '/order_cancel_eligibility.dart';
import '/marketplace_feed_refresh.dart';
import '/perfil_vendedor/perfil_vendedor_widget.dart';
import '/utils/fee_calculator.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/profile_avatar.dart';
import '/batata_bundle_discounts.dart';
import '/index.dart';
import '/widgets/marketplace_product_card.dart';
import '/batata_offer_actions.dart';
import '/utils/profile_shipping_requirements.dart';
import '/utils/seller_vacation_mode.dart';
import '/utils/live_catalog_stock_service.dart';
import '/widgets/product_offer_sheet.dart';

class ProductDetailsPageWidget extends StatefulWidget {
  const ProductDetailsPageWidget({
    super.key,
    required this.product,
    this.productId,
    this.openCheckoutSheetOnLoad = false,
    this.agreedOfferPriceEur,
    this.originLiveId,
    this.originPlaybackId,
    this.originIsLive,
    this.originSellerId,
    this.originLiveItemId,
    this.originReservationRequestId,
    this.originPayQty,
  });

  final ProductsRow? product;
  final String? productId;

  /// Quando [true], após sincronizar com a BD abre o bottom sheet de checkout (Seguro Fleaber).
  final bool openCheckoutSheetOnLoad;

  /// Preço acordado por proposta aceite (opcional).
  final double? agreedOfferPriceEur;
  final String? originLiveId;
  final String? originPlaybackId;
  final bool? originIsLive;
  final String? originSellerId;
  final String? originLiveItemId;
  final String? originReservationRequestId;
  final int? originPayQty;

  static const String routeName = 'ProductDetails';
  static const String routePath = '/productDetails';

  /// Chave em `extra` do GoRouter para o mapa do produto (evita passar [ProductsRow] cru no `extra`).
  static const String routeExtraProductKey = '__fleaber_product_row__';

  /// Extra opcional para abrir checkout ao entrar (ex.: incentivo desde o chat).
  static const String routeExtraOpenCheckoutKey = '__fleaber_open_checkout__';

  /// Preço acordado após proposta aceite (€).
  static const String routeExtraAgreedOfferPriceKey = '__fleaber_agreed_offer_price__';
  static const String routeExtraOriginLiveIdKey = '__fleaber_origin_live_id__';
  static const String routeExtraOriginPlaybackIdKey = '__fleaber_origin_playback_id__';
  static const String routeExtraOriginIsLiveKey = '__fleaber_origin_is_live__';
  static const String routeExtraOriginSellerIdKey = '__fleaber_origin_seller_id__';
  static const String routeExtraOriginLiveItemIdKey = '__fleaber_origin_live_item_id__';
  static const String routeExtraOriginReservationRequestIdKey =
      '__fleaber_origin_reservation_request_id__';
  static const String routeExtraOriginPayQtyKey = '__fleaber_origin_pay_qty__';

  /// Usa em `context.push(..., extra: …)` para enviar dados serializáveis compatíveis com [extraMap].
  static Map<String, dynamic> routeExtraForProduct(
    ProductsRow row, {
    bool openCheckoutSheet = false,
    double? agreedOfferPriceEur,
    String? originLiveId,
    String? originPlaybackId,
    bool? originIsLive,
    String? originSellerId,
    String? originLiveItemId,
    String? originReservationRequestId,
    int? originPayQty,
  }) =>
      {
        routeExtraProductKey: Map<String, dynamic>.from(row.data),
        if (openCheckoutSheet) routeExtraOpenCheckoutKey: true,
        if (agreedOfferPriceEur != null && agreedOfferPriceEur > 0)
          routeExtraAgreedOfferPriceKey: agreedOfferPriceEur,
        if (originLiveId != null && originLiveId.trim().isNotEmpty)
          routeExtraOriginLiveIdKey: originLiveId.trim(),
        if (originPlaybackId != null && originPlaybackId.trim().isNotEmpty)
          routeExtraOriginPlaybackIdKey: originPlaybackId.trim(),
        if (originIsLive != null) routeExtraOriginIsLiveKey: originIsLive,
        if (originSellerId != null && originSellerId.trim().isNotEmpty)
          routeExtraOriginSellerIdKey: originSellerId.trim(),
        if (originLiveItemId != null && originLiveItemId.trim().isNotEmpty)
          routeExtraOriginLiveItemIdKey: originLiveItemId.trim(),
        if (originReservationRequestId != null &&
            originReservationRequestId.trim().isNotEmpty)
          routeExtraOriginReservationRequestIdKey:
              originReservationRequestId.trim(),
        if (originPayQty != null && originPayQty > 0)
          routeExtraOriginPayQtyKey: originPayQty,
      };

  static double? agreedOfferPriceFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraAgreedOfferPriceKey];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  static bool openCheckoutFromRouteExtra(Object? extra) {
    if (extra is! Map) return false;
    final v = Map<String, dynamic>.from(extra)[routeExtraOpenCheckoutKey];
    return v == true || v == 'true';
  }

  static String? originLiveIdFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginLiveIdKey];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static String? originPlaybackIdFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginPlaybackIdKey];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static bool? originIsLiveFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginIsLiveKey];
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }

  static String? originSellerIdFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginSellerIdKey];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static String? originLiveItemIdFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginLiveItemIdKey];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static String? originReservationRequestIdFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[
        routeExtraOriginReservationRequestIdKey];
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static int? originPayQtyFromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final v = Map<String, dynamic>.from(extra)[routeExtraOriginPayQtyKey];
    if (v is int) return v > 0 ? v : null;
    if (v is num) return v.toInt() > 0 ? v.toInt() : null;
    return int.tryParse(v?.toString() ?? '');
  }

  /// Interpreta `GoRouterState.extra`: [ProductsRow], mapa com [routeExtraProductKey], ou mapa “nu” tipo JSON.
  static ProductsRow? productFromRouteExtra(Object? extra) {
    if (extra == null) return null;
    if (extra is ProductsRow) return extra;
    if (extra is! Map) return null;
    final map = Map<String, dynamic>.from(extra);
    final wrapped = map[routeExtraProductKey];
    if (wrapped is Map) {
      return ProductsRow(Map<String, dynamic>.from(wrapped));
    }
    if (map.containsKey(kTransitionInfoKey)) return null;
    if (map.containsKey('id') &&
        (map.containsKey('seller_id') || map.containsKey('title'))) {
      return ProductsRow(Map<String, dynamic>.from(map));
    }
    return null;
  }

  @override
  State<ProductDetailsPageWidget> createState() => _ProductDetailsPageWidgetState();
}

class _ProductDetailsPageWidgetState extends State<ProductDetailsPageWidget>
    with RouteAware, WidgetsBindingObserver {
  late final PageController _galleryController;
  bool _descriptionExpanded = false;
  ProductsRow? _liveProduct;
  /// Até a 1.ª leitura fiável da BD, não mostrar «Comprar» com dados stale do `extra`.
  bool _blockingProductSync = true;
  bool _sellerOnVacation = false;
  bool _isFavoritedByMe = false;
  int? _favoritesCountOverride;
  bool _favoriteLoading = false;

  /// Só `orders.status == reservado` (aceite pelo vendedor) — selo Teal «Reservado».
  bool _listingReservedForUi = false;
  bool _listingPaidForUi = false;

  /// Comprador com `reserva_pendente` neste produto (barra inferior dedicada).
  bool _buyerHasPendingReserveForThisProduct = false;

  bool _handledRouteOpenCheckout = false;

  /// Preço de proposta aceite (checkout / banner).
  double? _agreedOfferPriceEur;

  LiveCatalogStockSnapshot? _liveStockSnapshot;

  static const Color _kTeal = Color(0xFF007782);
  static const Color _kPageBg = FleaberColors.bgTint;
  static const Color _kMutedGray = Color(0xFF57636C);

  String? get _effectiveProductId {
    final id = widget.product?.id ?? widget.productId;
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  /// Bloqueio BATATA: não comprar / reservar o próprio anúncio (`seller_id` no schema).
  bool _isMarketplaceListing(ProductsRow p) =>
      p.listOnMarketplace == true && _originLiveItemId == null;

  void _openEditListing(ProductsRow p) {
    final id = p.id?.trim();
    if (id == null || id.isEmpty) return;
    context.pushNamed(
      SellerProductFormWidget.routeName,
      queryParameters: {
        'editProductId': serializeParam(id, ParamType.String),
      }.withoutNulls,
    );
  }

  bool _isOwnListing(ProductsRow p) {
    final sid = p.sellerId;
    return currentUserUid.isNotEmpty &&
        sid != null &&
        sid.isNotEmpty &&
        sid == currentUserUid;
  }

  /// Reserva aceite (`reservado`) — bloqueia terceiros; `reserva_pendente` não.
  String? _listingStatusLabel(ProductsRow p) {
    if (p.isSold) return 'Vendido';
    if (_listingPaidForUi) return 'Vendido';
    if (_listingReservedForUi) return 'Reservado (Aguardando Pagamento)';
    return null;
  }

  Widget _buildTealListingBadge(String label, {required bool fullWidth}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      constraints:
          fullWidth ? null : const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: _kTeal,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [FleaberElevation.smAccent(_kTeal)],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: label.length > 18 ? 12.5 : 15,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  void _showPostCheckoutChatSnack(
    ProductsRow product, {
    required bool isReservation,
    bool isStripeCheckout = false,
  }) {
    if (!mounted) return;
    final detail = isStripeCheckout
        ? 'Checkout Stripe aberto no browser. O artigo só fica marcado como vendido depois do pagamento ser confirmado.'
        : isReservation
            ? 'Pedido de reserva enviado. O vendedor ainda tem de aceitar — '
                'não é uma reserva garantida. Abre o chat para acompanhar.'
            : 'O artigo é teu. Vai ao chat para falar com o vendedor.';
    final msg = 'Ação executada com sucesso.\n\n$detail';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        backgroundColor: const Color(0xFF2D3A42),
        content: Text(
          msg,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        action: SnackBarAction(
          label: 'Ir ao chat',
          textColor: const Color(0xFFB8FFF5),
          onPressed: () => _onContactar(product),
        ),
      ),
    );
  }

  /// Altura aproximada da barra de ações + margem para o scroll não colar ao limite.
  double _scrollBottomInset(BuildContext context) {
    const barPadding = 12.0;
    const buttonMinHeight = 48.0;
    var core = barPadding * 2 +
        buttonMinHeight +
        MediaQuery.paddingOf(context).bottom +
        16;
    final p = _liveProduct ?? widget.product;
    if (p != null &&
        _buyerHasPendingReserveForThisProduct &&
        !_isOwnListing(p)) {
      core += 80;
    }
    return core;
  }

  Future<void> _onFazerProposta(ProductsRow product) async {
    if (_blockingProductSync || product.isSold) return;
    if (_isOwnListing(product) || _sellerOnVacation) return;

    final amount = await showProductOfferAmountSheet(
      context: context,
      product: product,
    );
    if (amount == null || !mounted) return;

    try {
      await createBuyerPriceOffer(product: product, amountEur: amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Proposta de ${formatEuros(amount)} enviada. '
            'O vendedor responde no chat.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _onComprarAgora(ProductsRow product) {
    if (_blockingProductSync || product.isSold) return;
    if (_isOwnListing(product)) return;
    if (_sellerOnVacation) return;
    _showCheckoutSheet(
      product,
      overrideItemPriceEur: _agreedOfferPriceEur,
    );
  }

  int _euroCents(double value) => (value * 100).round();

  /// Campos de ligação directa à sessão live (player/VOD/reserva).
  Map<String, String> _liveOrderContextFields() {
    final fields = <String, String>{};
    final liveId = widget.originLiveId?.trim() ?? '';
    final liveItemId = widget.originLiveItemId?.trim() ?? '';
    if (liveId.isNotEmpty) fields['live_id'] = liveId;
    if (liveItemId.isNotEmpty) fields['live_item_id'] = liveItemId;
    return fields;
  }

  String? get _originLiveItemId {
    final id = widget.originLiveItemId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  String? get _originReservationRequestId {
    final id = widget.originReservationRequestId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  bool get _checkoutFromLiveBagLine => _originReservationRequestId != null;

  Future<LiveCatalogStockSnapshot?> _fetchLiveStockSnapshot() async {
    final liveItemId = _originLiveItemId;
    if (liveItemId == null) return null;
    final snap = await LiveCatalogStockService.fetch(liveItemId);
    if (mounted && snap != null) {
      setState(() => _liveStockSnapshot = snap);
    }
    return snap;
  }

  int _maxCheckoutQuantity(ProductsRow product, {LiveCatalogStockSnapshot? stock}) {
    final snap = stock ?? _liveStockSnapshot;
    final payQty = widget.originPayQty;
    if (_checkoutFromLiveBagLine && payQty != null && payQty > 0) {
      final cap = snap?.availableQty ?? payQty;
      return payQty.clamp(1, cap.clamp(1, 99));
    }
    if (_originLiveItemId != null && snap != null) {
      return snap.availableQty.clamp(1, 99);
    }
    return product.quantity.clamp(1, 99);
  }

  int _displayQuantity(ProductsRow product) {
    if (_originLiveItemId != null && _liveStockSnapshot != null) {
      return _liveStockSnapshot!.totalQty;
    }
    return product.quantity;
  }

  Future<void> _showCheckoutSheet(
    ProductsRow product, {
    double? overrideItemPriceEur,
  }) async {
    if (_isOwnListing(product)) return;
    if (_sellerOnVacation) return;
    const shippingCarrier = 'Envio Transportadora (€3.50)';
    const shippingHand = 'Entrega em Mão (€0.00)';
    const paymentInApp = 'Pagamento na App';
    const paymentDirect = 'Pagamento Direto ao Vendedor (MB WAY/Transf)';

    var sellerAllowsDirectPayment = false;
    final sellerId = product.sellerId;
    if (sellerId != null && sellerId.isNotEmpty) {
      final sellerRows = await ProfilesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sellerId),
        limit: 1,
      );
      if (sellerRows.isNotEmpty) {
        sellerAllowsDirectPayment =
            sellerRows.first.externalPaymentsEnabled;
      }
    }

    var selectedShipping = shippingCarrier;
    var selectedPayment = paymentInApp;
    final liveStock = await _fetchLiveStockSnapshot();
    final maxQuantity = _maxCheckoutQuantity(product, stock: liveStock);
    final defaultQty = widget.originPayQty;
    var selectedQuantity = defaultQty != null && defaultQty > 0
        ? defaultQty.clamp(1, maxQuantity)
        : 1;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        var checkoutProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final shippingCost = selectedShipping == shippingCarrier ? 3.5 : 0.0;
            final unitPrice =
                overrideItemPriceEur ?? product.price ?? 0.0;
            final productPrice = unitPrice * selectedQuantity;
            final isDirect = selectedPayment == paymentDirect;
            final protectionFee = calculateFleaberProtectionFee(
              productPrice,
              shippingEur: shippingCost,
            );
            final effectiveProtectionFee = isDirect ? 0.0 : protectionFee;
            final total = calculateFleaberBuyerTotal(
              itemPriceEur: productPrice,
              shippingEur: shippingCost,
              includeProtectionFee: !isDirect,
            );
            final optionStyle = GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF101518),
            );
            return Theme(
              data: ThemeData.light(useMaterial3: false).copyWith(
                textTheme: ThemeData.light().textTheme.apply(
                      bodyColor: const Color(0xFF101518),
                      displayColor: const Color(0xFF101518),
                    ),
                radioTheme: RadioThemeData(
                  fillColor: WidgetStateProperty.resolveWith<Color>(
                    (states) => states.contains(WidgetState.selected)
                        ? _kTeal
                        : const Color(0xFF57636C),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checkout',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Envio',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: shippingCarrier,
                      groupValue: selectedShipping,
                      onChanged: checkoutProcessing
                          ? null
                          : (v) => setModalState(() => selectedShipping = v!),
                      title: Text(shippingCarrier, style: optionStyle),
                      activeColor: _kTeal,
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: shippingHand,
                      groupValue: selectedShipping,
                      onChanged: checkoutProcessing
                          ? null
                          : (v) => setModalState(() => selectedShipping = v!),
                      title: Text(shippingHand, style: optionStyle),
                      activeColor: _kTeal,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pagamento',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: paymentInApp,
                      groupValue: selectedPayment,
                      onChanged: checkoutProcessing
                          ? null
                          : (v) => setModalState(() => selectedPayment = v!),
                      title: Text(paymentInApp, style: optionStyle),
                      activeColor: _kTeal,
                    ),
                    if (sellerAllowsDirectPayment)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: paymentDirect,
                        groupValue: selectedPayment,
                        onChanged: checkoutProcessing
                            ? null
                            : (v) =>
                                setModalState(() => selectedPayment = v!),
                        title: Text(paymentDirect, style: optionStyle),
                        activeColor: _kTeal,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          'Este vendedor só aceita pagamento na app.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF57636C),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (_checkoutFromLiveBagLine)
                      Text(
                        'Pagamento deste pedido do saco (1 unidade).',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF57636C),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quantidade',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF101518),
                              ),
                            ),
                          ),
                          DropdownButton<int>(
                            value: selectedQuantity.clamp(1, maxQuantity),
                            items: List.generate(
                              maxQuantity,
                              (i) => DropdownMenuItem<int>(
                                value: i + 1,
                                child: Text('${i + 1}'),
                              ),
                            ),
                            onChanged: checkoutProcessing
                                ? null
                                : (v) =>
                                    setModalState(() => selectedQuantity = v ?? 1),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kPageBg,
                        borderRadius: FleaberRadius.circularMd,
                        border: Border.all(color: const Color(0xFFD5E4E6)),
                      ),
                      child: Column(
                        children: [
                          _CheckoutPriceLine(
                            label: 'Preço do artigo (${formatEuros(unitPrice)} x $selectedQuantity)',
                            value: formatEuros(productPrice),
                          ),
                          const SizedBox(height: 8),
                          _CheckoutPriceLine(
                            label: 'Envio',
                            value: formatEuros(shippingCost),
                          ),
                          const SizedBox(height: 8),
                          _CheckoutPriceLine(
                            label: 'Taxa de Proteção Fleaber',
                            value: formatEuros(effectiveProtectionFee),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          _CheckoutPriceLine(
                            label: 'Total a pagar',
                            value: formatEuros(total),
                            isTotal: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: checkoutProcessing
                            ? null
                            : () async {
                                if (total <= 0 || total.isNaN) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Preço inválido'),
                                    ),
                                  );
                                  return;
                                }
                                final sheetNavigator = Navigator.of(ctx);
                                if (ProfileShippingRequirements
                                    .checkoutNeedsCompleteProfile(
                                  shippingMethod: selectedShipping,
                                  paymentMethod: selectedPayment,
                                )) {
                                  final ready =
                                      await ProfileShippingRequirements
                                          .ensureCheckoutReady(context);
                                  if (!ready) return;
                                }
                                setModalState(() => checkoutProcessing = true);
                                final r = await _submitCheckout(
                                  product: product,
                                  quantity: selectedQuantity,
                                  shippingMethod: selectedShipping,
                                  paymentMethod: selectedPayment,
                                  total: total,
                                  agreedItemPriceEur: overrideItemPriceEur,
                                );
                                if (!ctx.mounted) return;
                                if (r.ok) {
                                  if (ctx.mounted) {
                                    sheetNavigator.pop();
                                  }
                                  if (!context.mounted) return;
                                  await _refreshProductFromDb();
                                  if (!context.mounted) return;
                                  final productForSnack =
                                      _liveProduct ?? product;
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .clearSnackBars();
                                    _showPostCheckoutChatSnack(
                                      productForSnack,
                                      isReservation: r.isReservation,
                                      isStripeCheckout: r.isStripeCheckout,
                                    );
                                  });
                                } else {
                                  if (ctx.mounted) {
                                    setModalState(
                                        () => checkoutProcessing = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: FleaberRadius.circularSm,
                          ),
                        ),
                        child: Text(
                          checkoutProcessing
                              ? 'A processar...'
                              : (isDirect
                                  ? 'Confirmar reserva'
                                  : 'Confirmar compra'),
                        ),
                      ),
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
  }

  Future<bool> _openStripeCheckoutInBrowser({
    required ProductsRow product,
    required String orderId,
    required int quantity,
    required double itemPrice,
    required double shippingCost,
    required double protectionFee,
    required double total,
    required String shippingMethod,
    String? liveId,
    String? playbackId,
    bool? isLive,
    String? liveSellerId,
    String? liveItemId,
    String? reservationRequestId,
  }) async {
    final productId = product.id;
    final sellerId = product.sellerId;
    if (productId == null || productId.isEmpty || sellerId == null) {
      return false;
    }

    final response = await SupaFlow.client.functions.invoke(
      'create-payment-intent',
      body: {
        'amount': _euroCents(total),
        'currency': 'eur',
        'product_id': productId,
        'buyer_id': currentUserUid,
        'seller_id': sellerId,
        'order_id': orderId,
        'quantity': quantity,
        'item_price': _euroCents(itemPrice),
        'shipping': _euroCents(shippingCost),
        'protection_fee': _euroCents(protectionFee),
        'shipping_method': shippingMethod,
        if (liveId != null && liveId.trim().isNotEmpty)
          'live_id': liveId.trim(),
        if (playbackId != null && playbackId.trim().isNotEmpty)
          'playback_id': playbackId.trim(),
        if (isLive != null) 'is_live': isLive,
        if (liveSellerId != null && liveSellerId.trim().isNotEmpty)
          'live_seller_id': liveSellerId.trim(),
        if (liveItemId != null && liveItemId.trim().isNotEmpty)
          'live_item_id': liveItemId.trim(),
        if (reservationRequestId != null &&
            reservationRequestId.trim().isNotEmpty)
          'reservation_request_id': reservationRequestId.trim(),
      },
    );

    final data = response.data;
    final checkoutUrl = data is Map ? data['checkoutUrl']?.toString() : null;
    final checkoutSessionId =
        data is Map ? data['checkoutSessionId']?.toString() : null;
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      final error = data is Map ? data['error']?.toString() : null;
      throw Exception(
        error == null || error.isEmpty
            ? 'A função Stripe não devolveu link de checkout.'
            : 'Stripe: $error',
      );
    }

    await FleaberStripeCheckoutContext.save(
      orderId: orderId,
      productId: productId,
      liveId: liveId,
      playbackId: playbackId,
      isLive: isLive,
      sellerId: liveSellerId,
      liveItemId: liveItemId,
      reservationRequestId: reservationRequestId,
      checkoutSessionId: checkoutSessionId,
    );
    await FleaberLogger.instance.logStripe(
      'open_browser',
      data: {
        'order_id': orderId,
        'product_id': productId,
        'live_id': liveId,
        'live_item_id': liveItemId,
        'session_id': checkoutSessionId,
      },
    );

    final uri = Uri.parse(checkoutUrl);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
      webViewConfiguration: const WebViewConfiguration(
        enableDomStorage: true,
      ),
    );
    if (!opened) {
      await FleaberStripeCheckoutContext.clear();
      throw Exception('Não foi possível abrir o checkout Stripe.');
    }
    return true;
  }

  /// Reserva pendente ou aceite (`reservado`) do comprador actual neste artigo.
  Future<OrdersRow?> _buyerHoldOrderForProduct(String productId) async {
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('product_id', productId)
          .eqOrNull('buyer_id', currentUserUid)
          .inFilter('status', ['reserva_pendente', 'reservado']),
      limit: 5,
    );
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return rows.first;
  }

  Future<bool> _tryMarkProductAsSold(String productId) async {
    try {
      await ProductsTable().update(
        data: {
          'is_sold': true,
          'list_on_marketplace': false,
        },
        matchingRows: (rows) => rows.eqOrNull('id', productId),
      );
      final rows = await ProductsTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', productId),
      );
      final sold = rows.isNotEmpty &&
          (rows.first.isSold || rows.first.listOnMarketplace == false);
      if (!sold) {
        print(
          'BATATA_STRIPE_CHECKOUT aviso: product update não confirmou sold. '
          'A encomenda paga continua a bloquear o marketplace.',
        );
      }
      return sold;
    } catch (e) {
      print(
        'BATATA_STRIPE_CHECKOUT aviso: RLS bloqueou update do produto: $e',
      );
      return false;
    }
  }

  Future<void> _sendPaidOrderChatMessage({
    required String orderId,
    required String sellerId,
    required ProductsRow product,
    required double total,
  }) async {
    final chat = await ensureSellerChat(
      otherUserId: sellerId,
      productId: product.id,
    );
    final chatId = chat.id;
    if (chatId == null || chatId.isEmpty) return;

    final title = product.title?.trim();
    final text = title == null || title.isEmpty
        ? 'Compra paga através do Seguro Fleaber (${formatEuros(total)}).'
        : 'Compra paga através do Seguro Fleaber: $title (${formatEuros(total)}).';

    await ChatMessagesTable().insert({
      'sender_id': currentUserUid,
      'receiver_id': sellerId,
      'chat_id': chatId,
      'text': text,
      'is_read': false,
      'is_reservation': false,
    });

    await ChatsTable().update(
      data: {
        'last_message': 'Compra paga pelo Seguro Fleaber',
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (rows) => rows.eqOrNull('id', chatId),
    );
  }

  Future<void> _sendReservationChatMessages({
    required String orderId,
    required String sellerId,
    required ProductsRow product,
    required double total,
    required DateTime expiresAt,
  }) async {
    final chat = await ensureSellerChat(
      otherUserId: sellerId,
      productId: product.id,
    );
    final chatId = chat.id;
    if (chatId == null || chatId.isEmpty) return;

    const prefix = 'FLEABER_JSON_V1:';
    final payload = <String, dynamic>{
      'kind': 'reservation_request',
      'order_id': orderId,
      'product_id': product.id,
      'buyer_id': currentUserUid,
      'seller_id': sellerId,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'total': total,
      'v': 1,
    };

    await ChatMessagesTable().insert({
      'sender_id': currentUserUid,
      'receiver_id': sellerId,
      'chat_id': chatId,
      'text': prefix + jsonEncode(payload),
      'is_read': false,
      'is_reservation': true,
    });

    await ChatsTable().update(
      data: {
        'last_message': 'Pedido de reserva',
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
      },
      matchingRows: (rows) => rows.eqOrNull('id', chatId),
    );
  }

  Future<({bool ok, bool isReservation, bool isStripeCheckout})>
      _submitCheckout({
    required ProductsRow product,
    required int quantity,
    required String shippingMethod,
    required String paymentMethod,
    required double total,
    double? agreedItemPriceEur,
  }) async {
    final pageContext = context;
    final productId = product.id;
    final sellerId = product.sellerId;
    if (currentUserUid.isEmpty || productId == null || sellerId == null) {
      return (ok: false, isReservation: false, isStripeCheckout: false);
    }

    if (total <= 0 || total.isNaN) {
      if (!pageContext.mounted) {
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Preço inválido')),
      );
      return (ok: false, isReservation: false, isStripeCheckout: false);
    }

    final isDirect = paymentMethod.contains('Direto ao Vendedor');

    try {
      final freshRows = await ProductsTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', productId),
      );
      if (freshRows.isEmpty) {
        if (!pageContext.mounted) {
          return (ok: false, isReservation: false, isStripeCheckout: false);
        }
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text('Artigo já não está disponível.')),
        );
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }
      final freshProduct = freshRows.first;
      if (freshProduct.isSold) {
        if (!pageContext.mounted) {
          return (ok: false, isReservation: false, isStripeCheckout: false);
        }
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text('Este artigo já foi vendido.')),
        );
        await _refreshProductFromDb();
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }
      if (await _productBlocksCheckoutForCurrentUser(
        productId,
        allowOwnBuyerHold: true,
      )) {
        if (!pageContext.mounted) {
          return (ok: false, isReservation: false, isStripeCheckout: false);
        }
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Já existe uma encomenda activa para este artigo. '
              'Não é possível iniciar outra compra.',
            ),
          ),
        );
        await _refreshProductFromDb();
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }

      if (isDirect) {
        final reservationExpiresAt =
            DateTime.now().toUtc().add(const Duration(days: 5));
        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': total,
          'shipping_method': shippingMethod,
          'payment_method': paymentMethod,
          'status': 'reserva_pendente',
          'is_reservation': true,
          'quantity': quantity < 1 ? 1 : quantity,
          'reservation_expires_at':
              reservationExpiresAt.toIso8601String(),
          ..._liveOrderContextFields(),
        });

        await _sendReservationChatMessages(
          orderId: order.id!,
          sellerId: sellerId,
          product: product,
          total: total,
          expiresAt: order.reservationExpiresAt ?? reservationExpiresAt,
        );

        try {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.lightImpact();
        } catch (_) {}
        requestOrdersListRefresh();
        pingBatataReservationForNotificationBell();

        if (!pageContext.mounted) {
          return (ok: false, isReservation: false, isStripeCheckout: false);
        }
        return (ok: true, isReservation: true, isStripeCheckout: false);
      }

      final itemPrice = agreedItemPriceEur ??
          freshProduct.price ??
          product.price ??
          0.0;
      final shippingCost = shippingMethod.contains('€3.50') ? 3.5 : 0.0;
      final protectionFee = calculateFleaberProtectionFee(
        itemPrice,
        shippingEur: shippingCost,
      );
      final holdOrder = await _buyerHoldOrderForProduct(productId);
      String? orderId;
      if (holdOrder != null && holdOrder.id != null) {
        orderId = holdOrder.id;
        final holdKey = normalizeOrderStatusKey(holdOrder.status);
        await OrdersTable().update(
          data: {
            'price_total': total,
            'shipping_method': shippingMethod,
            'payment_method': paymentMethod,
            'status': holdKey == 'reservado' ? 'reservado' : 'reserva_pendente',
            'is_reservation': holdKey != 'reservado',
            'quantity': quantity < 1 ? 1 : quantity,
            ..._liveOrderContextFields(),
          },
          matchingRows: (rows) => rows.eqOrNull('id', orderId),
        );
      } else {
        final order = await OrdersTable().insert({
          'product_id': productId,
          'buyer_id': currentUserUid,
          'seller_id': sellerId,
          'price_total': total,
          'shipping_method': shippingMethod,
          'payment_method': paymentMethod,
          'status': 'reserva_pendente',
          'is_reservation': false,
          'quantity': quantity < 1 ? 1 : quantity,
          ..._liveOrderContextFields(),
        });
        orderId = order.id;
      }
      if (orderId == null || orderId.isEmpty) {
        throw Exception('Não foi possível criar a encomenda.');
      }
      final originLiveId = widget.originLiveId?.trim() ?? '';
      final originLiveItemId = widget.originLiveItemId?.trim() ?? '';
      final originSellerId =
          widget.originSellerId?.trim() ?? freshProduct.sellerId?.trim() ?? '';
      if (originLiveId.isNotEmpty &&
          originLiveItemId.isNotEmpty &&
          originSellerId.isNotEmpty &&
          currentUserUid.isNotEmpty) {
        await LiveReservationQueueService().ensureStripeCheckoutHold(
          liveId: originLiveId,
          liveItemId: originLiveItemId,
          sellerId: originSellerId,
          buyerId: currentUserUid,
          orderId: orderId,
          reservationRequestId: _originReservationRequestId,
        );
      }
      final stripePaid = await _openStripeCheckoutInBrowser(
        product: freshProduct,
        orderId: orderId,
        quantity: quantity < 1 ? 1 : quantity,
        itemPrice: itemPrice,
        shippingCost: shippingCost,
        protectionFee: protectionFee,
        total: total,
        shippingMethod: shippingMethod,
        liveId: widget.originLiveId,
        playbackId: widget.originPlaybackId,
        isLive: widget.originIsLive,
        liveSellerId: widget.originSellerId,
        liveItemId: widget.originLiveItemId,
        reservationRequestId: _originReservationRequestId,
      );
      if (!stripePaid) {
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }

      requestMarketplaceFeedRefresh();
      requestOrdersListRefresh();
      pingBatataReservationForNotificationBell();

      if (!pageContext.mounted) {
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }
      return (ok: true, isReservation: false, isStripeCheckout: true);
    } catch (e) {
      print('DETALHE DO ERRO CHECKOUT: $e');
      if (!pageContext.mounted) {
        return (ok: false, isReservation: false, isStripeCheckout: false);
      }
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
      return (ok: false, isReservation: false, isStripeCheckout: false);
    }
  }

  Widget _buildBottomPurchaseBar(ProductsRow p) {
    if (_blockingProductSync) {
      return Material(
        color: Colors.white,
        elevation: 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _kTeal,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final listingLabel = _listingStatusLabel(p);

    return Material(
      color: Colors.white,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: listingLabel != null
                ? _buildTealListingBadge(listingLabel, fullWidth: true)
                : _sellerOnVacation && !_isOwnListing(p)
                    ? SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: FleaberRadius.circularMd,
                            border: Border.all(color: const Color(0xFFFFE082)),
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Vendedor de férias — compra indisponível',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Color(0xFF5D4037),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                : _buyerHasPendingReserveForThisProduct && !_isOwnListing(p)
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7FAFA),
                              borderRadius: FleaberRadius.circularMd,
                              border: Border.all(
                                color: const Color(0xFFB8D5D8),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Text(
                                'Reserva a aguardar confirmação',
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: const Color(0xFF2D4A4E),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _blockingProductSync
                                  ? null
                                  : () => _onSecureFleaberCheckoutTap(p),
                              style: FilledButton.styleFrom(
                                backgroundColor: _kTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                              ),
                              child: Text(
                                'Pagar agora (Seguro Fleaber)',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                : _isOwnListing(p)
                    ? SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F8),
                            borderRadius: FleaberRadius.circularMd,
                            border: Border.all(color: const Color(0xFFDDE2E7)),
                          ),
                          child: Center(
                            child: Text(
                              'Este anúncio é teu — compra e reserva não estão disponíveis.',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: _kMutedGray,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => _onFazerProposta(p),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kTeal,
                                  side: const BorderSide(
                                      color: _kTeal, width: 1.5),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: FleaberRadius.circularMd,
                                  ),
                                ),
                                child: Text(
                                  'Fazer proposta',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _kTeal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _onComprarAgora(p),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kTeal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: FleaberRadius.circularMd,
                                  ),
                                ),
                                child: Text(
                                  'Comprar agora',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
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

  @override
  void initState() {
    super.initState();
    _agreedOfferPriceEur = widget.agreedOfferPriceEur;
    _galleryController = PageController();
    WidgetsBinding.instance.addObserver(this);
    _refreshProductFromDb();
    _loadFavoriteState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.unsubscribe(this);
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _galleryController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshProductFromDb();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProductFromDb();
    }
  }

  Future<void> _loadFavoriteState() async {
    final productId = (_liveProduct ?? widget.product)?.id ?? _effectiveProductId;
    if (productId == null || productId.isEmpty || currentUserUid.isEmpty) {
      if (!mounted) return;
      setState(() => _isFavoritedByMe = false);
      return;
    }
    final isFav = await isProductFavoritedByUser(
      userId: currentUserUid,
      productId: productId,
    );
    if (!mounted) return;
    setState(() => _isFavoritedByMe = isFav);
  }

  Future<void> _toggleFavorite(ProductsRow product) async {
    if (_isOwnListing(product)) return;
    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para guardar favoritos.')),
      );
      return;
    }
    if (_favoriteLoading) return;
    final wasFavorited = _isFavoritedByMe;
    final previousCount = _favoritesCountOverride ?? product.favoritesCount;
    setState(() => _favoriteLoading = true);
    try {
      final result = await toggleProductFavorite(
        userId: currentUserUid,
        product: product,
      );
      if (!mounted) return;
      if (result.didFail) {
        setState(() {
          _isFavoritedByMe = wasFavorited;
          _favoritesCountOverride = previousCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível atualizar favorito.')),
        );
        return;
      }
      setState(() {
        _isFavoritedByMe = result.isFavorited;
        _favoritesCountOverride = result.favoritesCount;
      });
      setFavoriteCountUiOverrideForProduct(product.id, result.favoritesCount);
      requestHomeFavoritesUiReload();
      await _refreshProductFromDb();
    } finally {
      if (!mounted) return;
      setState(() => _favoriteLoading = false);
    }
  }

  Future<void> _refreshProductFromDb() async {
    final productId = _effectiveProductId;
    if (productId == null || productId.isEmpty) {
      if (mounted) {
        setState(() {
          _listingReservedForUi = false;
          _listingPaidForUi = false;
          _buyerHasPendingReserveForThisProduct = false;
          _blockingProductSync = false;
        });
      }
      return;
    }
    final rows = await ProductsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', productId),
    );
    if (!mounted) return;

    var listingReserved = false;
    var listingPaid = false;
    var buyerPending = false;
    if (rows.isNotEmpty && !rows.first.isSold) {
      final orows = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('product_id', productId),
        limit: 80,
      );
      for (final o in orows) {
        if (orderIsCancelled(o.status)) continue;
        final s = normalizeOrderStatusKey(o.status);
        if (s == 'reservado') {
          listingReserved = true;
        }
        if (orderStatusBlocksOtherBuyers(o.status) && s != 'reservado') {
          listingPaid = true;
        }
        if (s == 'reserva_pendente' && o.buyerId == currentUserUid) {
          buyerPending = true;
        }
      }
    }

    var sellerVacation = false;
    if (rows.isNotEmpty) {
      sellerVacation = await SellerVacationMode.isOnVacation(rows.first.sellerId);
    }

    setState(() {
      if (rows.isNotEmpty) {
        _liveProduct = rows.first;
        setFavoriteCountUiOverrideForProduct(
          rows.first.id,
          rows.first.favoritesCount,
        );
      }
      _sellerOnVacation = sellerVacation;
      _listingReservedForUi = listingReserved;
      _listingPaidForUi = listingPaid;
      _buyerHasPendingReserveForThisProduct = buyerPending;
      _blockingProductSync = false;
    });
    if (_originLiveItemId != null) {
      unawaited(_fetchLiveStockSnapshot());
    }
    if (rows.isNotEmpty) {
      _loadFavoriteState();
    }
    _maybeOpenCheckoutFromRouteIntent();
  }

  void _maybeOpenCheckoutFromRouteIntent() {
    if (!widget.openCheckoutSheetOnLoad || _handledRouteOpenCheckout) return;
    final p = _liveProduct ?? widget.product;
    if (p == null || _isOwnListing(p) || p.isSold || _sellerOnVacation) return;
    _handledRouteOpenCheckout = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showCheckoutSheet(
        p,
        overrideItemPriceEur: _agreedOfferPriceEur,
      );
    });
  }

  void _onSecureFleaberCheckoutTap(ProductsRow p) {
    if (_blockingProductSync ||
        p.isSold ||
        _listingPaidForUi ||
        _isOwnListing(p) ||
        _sellerOnVacation) {
      return;
    }
    _showCheckoutSheet(
      p,
      overrideItemPriceEur: _agreedOfferPriceEur,
    );
  }

  Future<bool> _productBlocksCheckoutForCurrentUser(
    String productId, {
    bool allowOwnBuyerHold = false,
  }) async {
    final orderRows = await OrdersTable().queryRows(
      queryFn: (q) => q.eqOrNull('product_id', productId),
      limit: 80,
    );
    for (final o in orderRows) {
      if (orderIsCancelled(o.status)) continue;
      final s = normalizeOrderStatusKey(o.status);
      if (s == 'reserva_pendente' || s == 'reservado') {
        if (o.buyerId == currentUserUid && allowOwnBuyerHold) continue;
        if (o.buyerId == currentUserUid) continue;
      }
      if (orderStatusBlocksOtherBuyers(o.status)) return true;
    }
    return false;
  }

  static String _formatPriceEur(ProductsRow row) {
    final p = row.price;
    if (p == null) return '—';
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static List<String> _imageUrls(ProductsRow row) {
    final u = row.imageUrls;
    if (u.isEmpty) return const [];
    return u;
  }

  bool _descriptionNeedsToggle(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return false;
    return t.length > 90 || t.contains('\n');
  }

  Future<double?> _averageStars(String? sellerId) async {
    if (sellerId == null || sellerId.isEmpty) return null;
    final rows = await ReviewsTable().queryRows(
      queryFn: (q) => q.eqOrNull('target_id', sellerId),
      limit: 200,
    );
    if (rows.isEmpty) return null;
    var sum = 0;
    var n = 0;
    for (final r in rows) {
      final s = r.stars;
      if (s != null && s > 0) {
        sum += s;
        n++;
      }
    }
    if (n == 0) return null;
    return sum / n;
  }

  void _openSellerProfile(ProductsRow product) {
    final sid = product.sellerId;
    if (sid == null || sid.isEmpty) return;
    final initialTab =
        product.listOnMarketplace == true ? 'marketplace' : 'diretos';
    context.pushNamed(
      PerfilVendedorWidget.routeName,
      queryParameters: {
        'sellerID': serializeParam(sid, ParamType.String),
        'initialTab': serializeParam(initialTab, ParamType.String),
      }.withoutNulls,
    );
  }

  void _openGalleryLightbox(BuildContext context, List<String> urls) {
    if (urls.isEmpty) return;
    final start = _galleryController.hasClients
        ? (_galleryController.page?.round() ?? 0)
        : 0;
    final i = start.clamp(0, urls.length - 1);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      useSafeArea: false,
      builder: (ctx) => _ProductGalleryLightbox(
        urls: urls,
        initialIndex: i,
        activeDotColor: _kTeal,
      ),
    );
  }

  Future<void> _onContactar(ProductsRow product) async {
    final sellerId = product.sellerId;
    if (sellerId == null || sellerId.isEmpty) return;
    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para contactar.')),
      );
      return;
    }
    try {
      final chat = await ensureSellerChat(
        otherUserId: sellerId,
        productId: product.id,
      );
      if (!mounted) return;
      context.pushNamed(
        ChatPageWidget.routeName,
        queryParameters: {
          'chatId': serializeParam(chat.id, ParamType.String),
          'otherUserId': serializeParam(sellerId, ParamType.String),
        }.withoutNulls,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o chat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _liveProduct ?? widget.product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _kPageBg,
          foregroundColor: const Color(0xFF101518),
          elevation: 0,
        ),
        body: Center(
          child: _blockingProductSync && _effectiveProductId != null
              ? const CircularProgressIndicator(color: Color(0xFF007782))
              : Text(
                  'Artigo não encontrado.',
                  style: GoogleFonts.inter(color: const Color(0xFF57636C)),
                ),
        ),
      );
    }

    final urls = _imageUrls(p);
    final favoritesCount =
        favoriteCountUiOverrideForProduct(p.id) ??
        _favoritesCountOverride ??
        p.favoritesCount;
    final galleryCount = urls.isEmpty ? 1 : urls.length;
    final h = MediaQuery.sizeOf(context).height * 0.4;
    final desc = p.description?.trim() ?? '';
    final showDescToggle = _descriptionNeedsToggle(desc);
    final sellerId = p.sellerId;
    final listingStatusTag = _listingStatusLabel(p);

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: _kPageBg,
        foregroundColor: const Color(0xFF101518),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.safePop(),
        ),
        title: Text(
          'Detalhe',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: const Color(0xFF101518),
          ),
        ),
        actions: [
          if (_isOwnListing(p) && _isMarketplaceListing(p))
            TextButton(
              onPressed: () => _openEditListing(p),
              child: Text(
                'Editar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: _kTeal,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomPurchaseBar(p),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: _scrollBottomInset(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _galleryController,
                    itemCount: galleryCount,
                    itemBuilder: (context, index) {
                      if (urls.isEmpty) {
                        return const ColoredBox(
                          color: Color(0xFFE8EDF2),
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 48,
                              color: Color(0xFF57636C),
                            ),
                          ),
                        );
                      }
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openGalleryLightbox(context, urls),
                        child: BatataCachedNetworkImage(
                          imageUrl: urls[index],
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorWidget: const ColoredBox(
                            color: Color(0xFFE8EDF2),
                            child: Icon(Icons.broken_image_outlined, size: 40),
                          ),
                        ),
                      );
                    },
                  ),
                  if (urls.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: SmoothPageIndicator(
                          controller: _galleryController,
                          count: urls.length,
                          effect: ExpandingDotsEffect(
                            dotHeight: 6,
                            dotWidth: 6,
                            expansionFactor: 3,
                            spacing: 6,
                            activeDotColor: _kTeal,
                            dotColor: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      ignoring: _isOwnListing(p),
                      child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _favoriteLoading || _isOwnListing(p)
                            ? null
                            : () => _toggleFavorite(p),
                        borderRadius: FleaberRadius.circularLg,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: favoritesCount > 0 ? 8.0 : 7.0,
                            vertical: 6.0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: FleaberRadius.circularLg,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isFavoritedByMe
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 15.0,
                                color: _isFavoritedByMe
                                    ? const Color(0xFFFF4D67)
                                    : Colors.white,
                              ),
                              if (favoritesCount > 0) ...[
                                const SizedBox(width: 5.0),
                                Text(
                                  '$favoritesCount',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
            if (listingStatusTag != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Center(
                  child: _buildTealListingBadge(
                    listingStatusTag,
                    fullWidth: false,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueOrDefault<String>(p.title, 'Artigo'),
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF101518),
                      height: 1.25,
                    ),
                  ),
                  if ((p.clothingSize ?? '').trim().isNotEmpty ||
                      (p.state ?? '').trim().isNotEmpty ||
                      _isMarketplaceListing(p) ||
                      _displayQuantity(p) > 1) ...[
                    const SizedBox(height: 4),
                    if ((p.clothingSize ?? '').trim().isNotEmpty)
                      _SpecLine(
                        label: 'Tamanho',
                        value: p.clothingSize!.trim(),
                      ),
                    if (_isMarketplaceListing(p) || _displayQuantity(p) > 1) ...[
                      if ((p.clothingSize ?? '').trim().isNotEmpty)
                        const SizedBox(height: 4),
                      _SpecLine(
                        label: 'Stock',
                        value: '${_displayQuantity(p)} unidades',
                      ),
                    ],
                    if ((p.clothingSize ?? '').trim().isNotEmpty &&
                        (p.state ?? '').trim().isNotEmpty)
                      const SizedBox(height: 4),
                    if ((p.state ?? '').trim().isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.state!.trim(),
                          style: FleaberTypography.cardMeta(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatPriceEur(p),
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _kTeal,
                    ),
                  ),
                ],
              ),
            ),
            if (desc.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descrição',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF101518),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      maxLines: _descriptionExpanded ? 200 : 2,
                      overflow: _descriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.45,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                    if (showDescToggle && !_descriptionExpanded)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _descriptionExpanded = true),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '... ver mais',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kTeal,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (sellerId != null && sellerId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: FutureBuilder<List<ProfilesRow>>(
                  future: ProfilesTable().queryRows(
                    queryFn: (q) => q.eqOrNull('id', sellerId).limit(1),
                  ),
                  builder: (context, vacSnap) {
                    if (!vacSnap.hasData ||
                        vacSnap.data!.isEmpty ||
                        vacSnap.data!.first.vacationMode != true) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFE082)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.beach_access_rounded,
                            color: Color(0xFFF57C00),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              SellerVacationMode.vacationBannerMessage,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5D4037),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: FutureBuilder<List<ProfilesRow>>(
                future: sellerId == null || sellerId.isEmpty
                    ? Future.value(const <ProfilesRow>[])
                    : ProfilesTable().queryRows(
                        queryFn: (q) => q.eqOrNull('id', sellerId).limit(1),
                      ),
                builder: (context, snap) {
                  final profile = snap.data?.firstOrNull;
                  final name = valueOrDefault<String>(
                    profile?.fullName,
                    'Vendedor',
                  );
                  final photo = profile?.photoUrl;
                  return FutureBuilder<double?>(
                    future: _averageStars(sellerId),
                    builder: (context, starSnap) {
                      final avg = starSnap.data;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openSellerProfile(p),
                                borderRadius: FleaberRadius.circularMd,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FleaberProfileAvatar(
                                        userId: sellerId,
                                        fullName: name,
                                        photoUrl: photo,
                                        radius: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              name,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                color: const Color(0xFF101518),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              avg == null
                                                  ? 'Sem avaliações'
                                                  : 'Média: ${avg.toStringAsFixed(1)} / 5',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF57636C),
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
                          ),
                          if (!_isOwnListing(p))
                            ElevatedButton(
                              onPressed: () => _onContactar(p),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: FleaberRadius.circularMd,
                                ),
                              ),
                              child: Text(
                                'Contactar',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informação de Envio',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: const Color(0xFF101518),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 22,
                        color: _kMutedGray,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Envio via transportadora (2-4 dias úteis)',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.4,
                            color: _kMutedGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artigos do Vendedor',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: const Color(0xFF101518),
                          ),
                        ),
                        if (sellerId != null &&
                            sellerId.isNotEmpty &&
                            sellerId != currentUserUid)
                          FutureBuilder<BundleDiscountTiers>(
                            future: fetchSellerBundleDiscounts(sellerId),
                            builder: (context, discSnap) {
                              final tiers = discSnap.data;
                              final maxPct = tiers != null && tiers.enabled
                                  ? maxDiscountPercent(tiers)
                                  : null;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  maxPct != null
                                      ? 'Poupa em custos de envio · até $maxPct% em conjuntos'
                                      : 'Poupa em custos de envio',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFF57636C),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  if (sellerId != null &&
                      sellerId.isNotEmpty &&
                      sellerId != currentUserUid &&
                      p.id != null)
                    OutlinedButton(
                      onPressed: () {
                        context.pushNamed(
                          CriarConjuntoPageWidget.routeName,
                          queryParameters: {
                            'sellerId': serializeParam(
                              sellerId,
                              ParamType.String,
                            ),
                            'initialProductId': serializeParam(
                              p.id,
                              ParamType.String,
                            ),
                          }.withoutNulls,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FleaberColors.teal,
                        side: const BorderSide(
                          color: FleaberColors.teal,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FleaberRadius.circularMd,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        'Criar conjunto',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            FutureBuilder<List<ProductsRow>>(
              future: sellerId == null || sellerId.isEmpty
                  ? Future.value(const <ProductsRow>[])
                  : ProductsTable().queryRows(
                      queryFn: (q) {
                        var qq = q
                            .eqOrNull('seller_id', sellerId)
                            .eq('list_on_marketplace', true)
                            .eq('is_sold', false);
                        qq = qq.neqOrNull('id', p.id);
                        return qq.order('created_at', ascending: false);
                      },
                      limit: 24,
                    ),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Sem outros artigos deste vendedor.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF57636C),
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                final list = snap.data!;
                const sepW = 12.0;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    // Mesma largura de célula que a grelha 2× da Home (padding 16 + gutter 14).
                    var cardW = (maxW - 32 - 14) / 2;
                    if (cardW <= 0) {
                      cardW = maxW * 0.42;
                    }
                    return SizedBox(
                      height: MarketplaceProductCard.horizontalListHeight(cardW),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: sepW),
                        itemBuilder: (context, i) {
                          final o = list[i];
                          return MarketplaceProductCard(
                            title: valueOrDefault<String>(o.title, 'Artigo'),
                            stateLabel: o.state,
                            priceLabel: _formatPriceEur(o),
                            imageUrl: o.imageUrls.isNotEmpty
                                ? o.imageUrls.first
                                : null,
                            favoritesCount: o.favoritesCount,
                            isFavorited: false,
                            width: cardW,
                            onTap: () {
                              context.push(
                                ProductDetailsPageWidget.routePath,
                                extra:
                                    ProductDetailsPageWidget.routeExtraForProduct(
                                  o,
                                ),
                              );
                            },
                            onFavoriteTap: o.sellerId == currentUserUid
                                ? null
                                : () => _toggleFavorite(o),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutPriceLine extends StatelessWidget {
  const _CheckoutPriceLine({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
              color: const Color(0xFF3D4A55),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            color: const Color(0xFF101518),
          ),
        ),
      ],
    );
  }
}

class _ProductGalleryLightbox extends StatefulWidget {
  const _ProductGalleryLightbox({
    required this.urls,
    required this.initialIndex,
    required this.activeDotColor,
  });

  final List<String> urls;
  final int initialIndex;
  final Color activeDotColor;

  @override
  State<_ProductGalleryLightbox> createState() =>
      _ProductGalleryLightboxState();
}

class _ProductGalleryLightboxState extends State<_ProductGalleryLightbox> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final i = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: i);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: BatataCachedNetworkImage(
                      imageUrl: widget.urls[index],
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      placeholderColor: Colors.black,
                      errorWidget: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: pad.top + 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                iconSize: 28,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 20,
                child: Center(
                  child: SmoothPageIndicator(
                    controller: _pageController,
                    count: widget.urls.length,
                    effect: ExpandingDotsEffect(
                      dotHeight: 8,
                      dotWidth: 8,
                      expansionFactor: 3,
                      spacing: 8,
                      activeDotColor: widget.activeDotColor,
                      dotColor: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpecLine extends StatelessWidget {
  const _SpecLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: FleaberTypography.cardMeta(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF101518),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
