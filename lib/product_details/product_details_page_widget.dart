import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/chat_session_util.dart';
import '/chat_page/chat_page_widget.dart';
import '/favorites_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_logger.dart';
import '/utils/fleaber_stripe_checkout_context.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/utils/live_reservation_queue_service.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_typography.dart';
import '/utils/fleaber_elevation.dart';
import '/seller_listing_actions.dart';
import '/order_cancel_eligibility.dart';
import '/marketplace_feed_refresh.dart';
import '/hub/hub_actions.dart';
import '/utils/fee_calculator.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/profile_avatar.dart';
import '/batata_bundle_discounts.dart';
import '/widgets/marketplace_product_card.dart';
import '/batata_bundle_actions.dart';
import '/batata_offer_actions.dart';
import '/utils/profile_shipping_requirements.dart';
import '/utils/seller_vacation_mode.dart';
import '/utils/seller_professional.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/fleaber_h10_navigation.dart';
import '/widgets/product_offer_sheet.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/widgets/professional_seller_badge.dart';
import '/widgets/seller_consumer_rights_notice.dart';
import '/widgets/fleaber_checkout_ui.dart';
import '/widgets/dpd_pickup_picker_sheet.dart';
import '/utils/dpd_pudo_service.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/order_shipment_weight.dart';
import '/utils/seller_public_display.dart';
import '/hub/hub_account_routes.dart';

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
      'SellerProductForm',
      queryParameters: {
        'editProductId': serializeParam(id, ParamType.String),
      }.withoutNulls,
    );
  }

  Future<void> _onManageListingAction(ProductsRow p, String action) async {
    final id = p.id?.trim();
    if (id == null || id.isEmpty) return;
    try {
      switch (action) {
        case 'edit':
          _openEditListing(p);
          return;
        case 'hide':
          await setSellerListingMarketplaceVisible(
            productId: id,
            visible: false,
          );
          if (!mounted) return;
          await _refreshProductFromDb();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anúncio oculto do marketplace.')),
          );
        case 'show':
          await setSellerListingMarketplaceVisible(
            productId: id,
            visible: true,
          );
          if (!mounted) return;
          await _refreshProductFromDb();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anúncio visível no marketplace.')),
          );
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Eliminar an\u00fancio?'),
              content: const Text(
                'Esta acção remove o artigo do inventário. '
                'Não pode ser desfeita.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          );
          if (ok != true || !mounted) return;
          await deleteSellerListing(id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anúncio eliminado.')),
          );
          context.safePop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
    if (p.isSold || p.quantity <= 0) return 'Vendido';
    if (_listingPaidForUi) return 'Vendido';
    // Sem hold de rifa, products.quantity é a fonte de verdade (multi-qty).
    // availableQty live volta a subtrair unidades já «pago» e mentia «Vendido».
    final snap = _liveStockSnapshot;
    if (snap != null && snap.raffleHoldQty > 0 && snap.availableQty < 1) {
      return 'Indisponível (Rifa)';
    }
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
    String? orderId,
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
          onPressed: () => _onContactar(product, orderId: orderId),
        ),
      ),
    );
  }

  /// Altura aproximada da barra de ações + margem para o scroll não colar ao limite.
  /// +100: botão «Contactar» (119.9) por baixo do vendedor não fica sob a barra.
  double _scrollBottomInset(BuildContext context) {
    const barPadding = 12.0;
    const buttonMinHeight = 48.0;
    var core = barPadding * 2 +
        buttonMinHeight +
        MediaQuery.paddingOf(context).bottom +
        16 +
        100;
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
    if (liveItemId != null) {
      final snap = await LiveCatalogStockService.fetch(liveItemId);
      if (mounted && snap != null) {
        setState(() => _liveStockSnapshot = snap);
      }
      return snap;
    }
    // Marketplace PDP: artigo pode estar na live com hold de rifa.
    final productId = _effectiveProductId;
    if (productId == null) return null;
    final snap =
        await LiveCatalogStockService.fetchForMarketplaceProduct(productId);
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
    if (snap != null && snap.raffleHoldQty > 0) {
      final avail = snap.availableQty;
      if (avail < 1) return 0;
      return avail.clamp(1, 99);
    }
    return product.quantity.clamp(1, 99);
  }

  int _displayQuantity(ProductsRow product) {
    final snap = _liveStockSnapshot;
    // Rifa/hold: usar snapshot live. Sem hold, products.quantity já reflecte
    // vendas «pago» — availableQty live volta a subtrair e parece -2.
    if (snap != null && snap.raffleHoldQty > 0) {
      return snap.availableQty;
    }
    return product.quantity;
  }

  /// Stock efectivo para UI: 0 quando o anúncio já está vendido/pago,
  /// evitando incoerência «Vendido» + «N unidades» no mesmo ecrã.
  int _effectiveStockQuantity(ProductsRow product) {
    if (_liveStockSnapshot == null &&
        (product.isSold || product.quantity <= 0)) {
      return 0;
    }
    return _displayQuantity(product);
  }

  Future<void> _showCheckoutSheet(
    ProductsRow product, {
    double? overrideItemPriceEur,
  }) async {
    if (_isOwnListing(product)) return;
    if (_sellerOnVacation) return;
    const shippingCarrier = kFleaberShippingCarrierMethod;
    const shippingHand = kFleaberShippingHandMethod;
    const paymentInApp = 'Pagamento na app';
    const paymentDirect = 'Pagamento Direto ao Vendedor (MB WAY/Transf)';

    var sellerAllowsDirectPayment = false;
    final sellerId = product.sellerId;
    if (sellerId != null && sellerId.isNotEmpty) {
      final sellerRows = await ProfilesDirectoryTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', sellerId),
        limit: 1,
      );
      if (sellerRows.isNotEmpty) {
        sellerAllowsDirectPayment =
            sellerRows.first.externalPaymentsEnabled;
      }
    }

    var selectedShipping = shippingCarrier;
    /// Domicílio vs loja Pickup (só quando envio DPD / carrier).
    var deliveryMode = 'home'; // home | pickup
    DpdPudoPoint? selectedPudo;
    var selectedPayment = paymentInApp;
    final liveStock = await _fetchLiveStockSnapshot();
    final maxQuantity = _maxCheckoutQuantity(product, stock: liveStock);
    final defaultQty = widget.originPayQty;
    var selectedQuantity = defaultQty != null && defaultQty > 0
        ? defaultQty.clamp(1, maxQuantity)
        : 1;

    // Dados s� de apresenta��o (morada / vendedor) ? sem alterar regras.
    // ZIP 162: hub_profiles_public (anon OK); profiles_directory_public s� authenticated.
    String? sellerDisplayName;
    final sid = (product.sellerId ?? '').trim();
    if (sid.isNotEmpty) {
      sellerDisplayName = await SellerPublicDisplay.displayName(sid);
    }
    ProfilesRow? buyerProfile;
    try {
      buyerProfile = await ProfileShippingRequirements.fetchCurrentProfile();
    } catch (_) {}
    final addressComplete =
        ProfileShippingRequirements.isComplete(buyerProfile);
    final addressLines = buyerProfile == null
        ? <String>[]
        : ProfileShippingRequirements.formatAddress(buyerProfile)
            .split('\n');
    final productImage =
        _imageUrls(product).isNotEmpty ? _imageUrls(product).first : null;
    final productTitle = (product.title ?? 'Artigo').trim();

    if (!context.mounted) return;
    await FleaberCheckoutUi.showHost<void>(
      context: context,
      builder: (ctx) {
        var checkoutProcessing = false;
        // Scaffold próprio ? SnackBar visível no sheet (APP-SEC-005 Redmi).
        return Theme(
          data: ThemeData.light(useMaterial3: false).copyWith(
            textTheme: ThemeData.light().textTheme.apply(
                  bodyColor: const Color(0xFF101518),
                  displayColor: const Color(0xFF101518),
                ),
          ),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              top: false,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  final weightAgg = fleaberAggregateShipmentWeight([
                    FleaberShipmentWeightInput.fromProduct(
                      product,
                      quantity: selectedQuantity,
                    ),
                  ]);
                  // Escal�o s� a partir do peso do vendedor ? o comprador n�o escolhe.
                  final effectiveBand =
                      weightAgg.ok ? weightAgg.band : null;
                  final shippingCost = selectedShipping == shippingHand
                      ? 0.0
                      : (effectiveBand == null
                          ? 0.0
                          : fleaberCheckoutDpdShippingEur(
                              pickup: deliveryMode == 'pickup',
                              weightKg: weightAgg.totalKg,
                              band: effectiveBand,
                            ));
                  final unitPrice =
                      overrideItemPriceEur ?? product.price ?? 0.0;
                  final productPrice = unitPrice * selectedQuantity;
                  final isDirect = selectedPayment == paymentDirect;
                  final protectionFee = calculateFleaberProtectionFee(
                    productPrice,
                    shippingEur: shippingCost,
                  );
                  final effectiveProtectionFee =
                      isDirect ? 0.0 : protectionFee;
                  final total = calculateFleaberBuyerTotal(
                    itemPriceEur: productPrice,
                    shippingEur: shippingCost,
                    includeProtectionFee: !isDirect,
                  );
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FleaberCheckoutHandle(),
                            FleaberCheckoutTitleBar(
                              title: 'Checkout',
                              subtitle:
                                  'Confirma o artigo, o envio e o pagamento.',
                              onClose: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: FleaberCheckoutBody(
                          primaryLabel: checkoutProcessing
                              ? 'A processar…'
                              : (isDirect
                                  ? 'Confirmar reserva'
                                  : 'Confirmar compra'),
                          primaryLoading: checkoutProcessing,
                          primaryEnabled: !checkoutProcessing,
                          footerNote: isDirect
                              ? 'Pagamento directo não inclui a Protecção Fleaber.'
                              : 'Seguro Fleaber: 0,65 € + 5% sobre artigos e portes.',
                          onPrimary: () async {
                            if (total <= 0 || total.isNaN) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Preço inválido'),
                                ),
                              );
                              return;
                            }
                            final sheetNavigator = Navigator.of(ctx);
                            unawaited(
                              FleaberLogger.instance.logStripe(
                                'sheet_confirm_tap',
                                data: {
                                  'source': 'product_details_sheet',
                                  'product_id': product.id,
                                  'payment_method': selectedPayment,
                                  'shipping_method': selectedShipping,
                                  'total': total,
                                  'quantity': selectedQuantity,
                                  'k_is_web': kIsWeb,
                                },
                              ),
                            );
                            if (ProfileShippingRequirements
                                .checkoutNeedsCompleteProfile(
                              shippingMethod: selectedShipping,
                              paymentMethod: selectedPayment,
                            )) {
                              final ready = await ProfileShippingRequirements
                                  .ensureCheckoutReady(context);
                              if (!ready) {
                                unawaited(
                                  FleaberLogger.instance.logStripe(
                                    'shipping_gate_abort',
                                    data: {
                                      'source': 'product_details_sheet',
                                      'product_id': product.id,
                                      'payment_method': selectedPayment,
                                    },
                                  ),
                                );
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Completa o perfil de envio '
                                        'para continuar o pagamento.',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                            }
                            if (selectedShipping == shippingCarrier &&
                                deliveryMode == 'pickup' &&
                                selectedPudo == null) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Escolhe uma loja Pickup DPD para continuar.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            if (selectedShipping == shippingCarrier &&
                                effectiveBand == null) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      kFleaberBuyerWeightMissingMessage,
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            setModalState(() => checkoutProcessing = true);
                            final r = await _submitCheckout(
                              product: product,
                              quantity: selectedQuantity,
                              shippingMethod: selectedShipping,
                              paymentMethod: selectedPayment,
                              total: total,
                              agreedItemPriceEur: overrideItemPriceEur,
                              snackContext: ctx,
                              pickupPoint: selectedShipping == shippingCarrier &&
                                      deliveryMode == 'pickup'
                                  ? selectedPudo
                                  : null,
                              deliveryHome: selectedShipping == shippingCarrier &&
                                  deliveryMode == 'home',
                              shippingWeightKg: weightAgg.totalKg,
                              shippingWeightBand: effectiveBand,
                              shippingCostEur: shippingCost,
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
                                  orderId: r.orderId,
                                );
                              });
                            } else if (ctx.mounted) {
                              setModalState(
                                  () => checkoutProcessing = false);
                            }
                          },
                          children: [
                            FleaberCheckoutProductSummary(
                              title: productTitle,
                              imageUrl: productImage,
                              sellerName: sellerDisplayName,
                              quantityLabel: _checkoutFromLiveBagLine
                                  ? 'Pedido do saco · 1 un.'
                                  : null,
                              priceLabel: formatEuros(unitPrice),
                            ),
                            const SizedBox(height: 14),
                            const FleaberCheckoutSectionLabel(
                                'Morada de entrega'),
                            const SizedBox(height: 8),
                            FleaberCheckoutAddressCard(
                              lines: addressLines,
                              complete: addressComplete,
                              onEdit: () {
                                HubAccountRoutes.openContaDefinicoes(ctx);
                              },
                            ),
                            const SizedBox(height: 16),
                            const FleaberCheckoutSectionLabel('Envio'),
                            const SizedBox(height: 8),
                            // 3 modalidades ao mesmo nível (Casa / Pickup / mão).
                            Builder(builder: (_) {
                              String homePrice = '?';
                              String pickupPrice = '?';
                              try {
                                if (effectiveBand != null) {
                                  homePrice = formatEuros(
                                    fleaberCheckoutDpdShippingEur(
                                      pickup: false,
                                      weightKg: weightAgg.totalKg,
                                      band: effectiveBand,
                                    ),
                                  );
                                  pickupPrice = formatEuros(
                                    fleaberCheckoutDpdShippingEur(
                                      pickup: true,
                                      weightKg: weightAgg.totalKg,
                                      band: effectiveBand,
                                    ),
                                  );
                                }
                              } catch (_) {}
                              final modeKey = selectedShipping == shippingHand
                                  ? 'hand'
                                  : deliveryMode;
                              return Column(
                                children: [
                                  FleaberCheckoutChoiceCard<String>(
                                    value: 'home',
                                    groupValue: modeKey,
                                    title: 'Entrega em casa',
                                    subtitle:
                                        'DPD para a tua morada · $homePrice',
                                    onChanged: checkoutProcessing
                                        ? null
                                        : (_) => setModalState(() {
                                              selectedShipping =
                                                  shippingCarrier;
                                              deliveryMode = 'home';
                                              selectedPudo = null;
                                            }),
                                  ),
                                  const SizedBox(height: 8),
                                  FleaberCheckoutChoiceCard<String>(
                                    value: 'pickup',
                                    groupValue: modeKey,
                                    title: 'Levantar numa loja Pickup',
                                    subtitle: selectedPudo == null
                                        ? 'Ponto DPD · $pickupPrice'
                                        : '${selectedPudo!.name} · $pickupPrice',
                                    onChanged: checkoutProcessing
                                        ? null
                                        : (_) async {
                                            final zip = (buyerProfile
                                                        ?.shippingPostalCode ??
                                                    '')
                                                .trim();
                                            final city = (buyerProfile
                                                        ?.shippingCity ??
                                                    '')
                                                .trim();
                                            final picked =
                                                await showDpdPickupPickerSheet(
                                              ctx,
                                              initialZip: zip,
                                              initialCity: city,
                                            );
                                            if (!ctx.mounted) return;
                                            setModalState(() {
                                              selectedShipping =
                                                  shippingCarrier;
                                              deliveryMode = 'pickup';
                                              if (picked != null) {
                                                selectedPudo = picked;
                                              }
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 8),
                                  FleaberCheckoutChoiceCard<String>(
                                    value: 'hand',
                                    groupValue: modeKey,
                                    title: kFleaberShippingHandLabel,
                                    subtitle:
                                        'Combinas o encontro com o vendedor',
                                    onChanged: checkoutProcessing
                                        ? null
                                        : (_) => setModalState(() {
                                              selectedShipping = shippingHand;
                                              selectedPudo = null;
                                            }),
                                  ),
                                ],
                              );
                            }),
                            const SizedBox(height: 16),
                            const FleaberCheckoutSectionLabel('Pagamento'),
                            const SizedBox(height: 8),
                            FleaberCheckoutChoiceCard<String>(
                              value: paymentInApp,
                              groupValue: selectedPayment,
                              title: paymentInApp,
                              subtitle: 'Cartão com Protecção Fleaber',
                              onChanged: checkoutProcessing
                                  ? null
                                  : (v) => setModalState(
                                        () => selectedPayment = v,
                                      ),
                            ),
                            if (sellerAllowsDirectPayment) ...[
                              const SizedBox(height: 8),
                              FleaberCheckoutChoiceCard<String>(
                                value: paymentDirect,
                                groupValue: selectedPayment,
                                title: paymentDirect,
                                subtitle:
                                    'MB WAY / transferência · sem Protecção Fleaber',
                                onChanged: checkoutProcessing
                                    ? null
                                    : (v) => setModalState(
                                          () => selectedPayment = v,
                                        ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(
                                'Este vendedor só aceita pagamento na app.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: FleaberCheckoutUi.muted,
                                ),
                              ),
                            ],
                            if (!_checkoutFromLiveBagLine) ...[
                              const SizedBox(height: 16),
                              const FleaberCheckoutSectionLabel(
                                  'Quantidade'),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: FleaberRadius.circularMd,
                                  border: Border.all(
                                    color: FleaberCheckoutUi.line,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Unidades',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: FleaberCheckoutUi.ink,
                                        ),
                                      ),
                                    ),
                                    DropdownButton<int>(
                                      value: selectedQuantity.clamp(
                                          1, maxQuantity),
                                      underline: const SizedBox.shrink(),
                                      items: List.generate(
                                        maxQuantity,
                                        (i) => DropdownMenuItem<int>(
                                          value: i + 1,
                                          child: Text('${i + 1}'),
                                        ),
                                      ),
                                      onChanged: checkoutProcessing
                                          ? null
                                          : (v) => setModalState(
                                                () => selectedQuantity =
                                                    v ?? 1,
                                              ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (selectedShipping == shippingCarrier) ...[
                              const SizedBox(height: 12),
                              Text(
                                kFleaberCheckoutShippingDeltaNotice,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: FleaberCheckoutUi.muted,
                                ),
                              ),
                              if (!weightAgg.ok ||
                                  weightAgg.needsBuyerBandChoice) ...[
                                const SizedBox(height: 8),
                                Text(
                                  kFleaberBuyerWeightMissingMessage,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFB45309),
                                    height: 1.35,
                                  ),
                                ),
                              ] else if (effectiveBand != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Portes calculados automaticamente'
                                  '${weightAgg.totalKg != null ? ' � ~${weightAgg.totalKg!.toStringAsFixed(1)} kg' : ''}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: FleaberCheckoutUi.muted,
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 16),
                            const FleaberCheckoutSectionLabel('Resumo'),
                            const SizedBox(height: 8),
                            FleaberCheckoutTotalsCard(
                              lines: [
                                FleaberCheckoutPriceLine(
                                  label:
                                      'Artigos (${formatEuros(unitPrice)} × $selectedQuantity)',
                                  value: formatEuros(productPrice),
                                ),
                                FleaberCheckoutPriceLine(
                                  label: 'Envio',
                                  value: formatEuros(shippingCost),
                                ),
                                FleaberCheckoutPriceLine(
                                  label: 'Protecção Fleaber',
                                  value:
                                      formatEuros(effectiveProtectionFee),
                                ),
                                FleaberCheckoutPriceLine(
                                  label: 'Total a pagar',
                                  value: formatEuros(total),
                                  isTotal: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FutureBuilder<
                                Map<String, SellerTradePublicInfo>>(
                              future: SellerProfessionalCache.warm([
                                if (sid.isNotEmpty) sid,
                              ]),
                              builder: (context, snap) {
                                final info = snap.data?[sid] ??
                                    SellerProfessionalCache.peek(sid) ??
                                    SellerTradePublicInfo.particular(
                                      sid.isEmpty ? 'unknown' : sid,
                                    );
                                return SellerConsumerRightsNotice(
                                  info: info,
                                  sellerDisplayName: sellerDisplayName,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
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
    double? shippingWeightKg,
    FleaberDpdWeightBand? shippingWeightBand,
    bool pickup = false,
  }) async {
    final productId = product.id;
    final sellerId = product.sellerId;
    if (productId == null || productId.isEmpty || sellerId == null) {
      await FleaberLogger.instance.logStripe(
        'checkout_abort',
        data: {
          'reason': 'missing_product_or_seller',
          'order_id': orderId,
          'product_id': productId,
        },
      );
      return false;
    }

    final result = await fleaberInvokeCreatePaymentIntent(
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
        if (shippingWeightKg != null) 'shipping_weight_kg': shippingWeightKg,
        if (shippingWeightBand != null)
          'shipping_weight_band': shippingWeightBand.code,
        'shipping_modality':
            shippingMethod == kFleaberShippingHandMethod
                ? 'hand'
                : (pickup ? 'shop_to_shop' : 'shop_to_home'),
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
      logContext: {'source': 'product_details'},
    );

    // Marketplace: gravar sempre o seller do artigo (não só liveSellerId).
    final checkoutSellerId =
        (liveSellerId != null && liveSellerId.trim().isNotEmpty)
            ? liveSellerId.trim()
            : sellerId;
    await FleaberStripeCheckoutContext.save(
      orderId: orderId,
      productId: productId,
      liveId: liveId,
      playbackId: playbackId,
      isLive: isLive,
      sellerId: checkoutSellerId,
      liveItemId: liveItemId,
      reservationRequestId: reservationRequestId,
      checkoutSessionId: result.checkoutSessionId,
    );
    await FleaberLogger.instance.logStripe(
      'open_browser',
      data: {
        'order_id': orderId,
        'product_id': productId,
        'live_id': liveId,
        'live_item_id': liveItemId,
        'session_id': result.checkoutSessionId,
        'source': 'product_details',
      },
    );

    final opened = await fleaberLaunchStripeCheckout(
      result.checkoutUrl,
      context: {
        'order_id': orderId,
        'session_id': result.checkoutSessionId,
        'source': 'product_details',
      },
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

  Future<void> _applyDeliveryPointChoice({
    required String orderId,
    DpdPudoPoint? pickupPoint,
    bool deliveryHome = false,
  }) async {
    try {
      if (pickupPoint != null) {
        await DpdPudoService.attachPickupToOrder(
          orderId: orderId,
          point: pickupPoint,
        );
      } else if (deliveryHome) {
        await DpdPudoService.attachHomeToOrder(orderId);
      }
    } catch (e) {
      debugPrint('DPD_DELIVERY_POINT_ERR $e');
    }
  }

  Future<({bool ok, bool isReservation, bool isStripeCheckout, String? orderId})>
      _submitCheckout({
    required ProductsRow product,
    required int quantity,
    required String shippingMethod,
    required String paymentMethod,
    required double total,
    double? agreedItemPriceEur,
    BuildContext? snackContext,
    DpdPudoPoint? pickupPoint,
    bool deliveryHome = false,
    double? shippingWeightKg,
    FleaberDpdWeightBand? shippingWeightBand,
    double? shippingCostEur,
  }) async {
    final pageContext = context;
    final msgContext = snackContext ?? pageContext;
    final productId = product.id;
    final sellerId = product.sellerId;
    if (currentUserUid.isEmpty || productId == null || sellerId == null) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'checkout_abort',
          data: {
            'source': 'product_details_submit',
            'reason': 'missing_auth_or_ids',
            'has_uid': currentUserUid.isNotEmpty,
            'product_id': productId,
          },
        ),
      );
      return (
        ok: false,
        isReservation: false,
        isStripeCheckout: false,
        orderId: null,
      );
    }

    if (total <= 0 || total.isNaN) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'checkout_abort',
          data: {
            'source': 'product_details_submit',
            'reason': 'invalid_total',
            'total': total,
            'product_id': productId,
          },
        ),
      );
      if (!msgContext.mounted) {
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
      }
      ScaffoldMessenger.of(msgContext).showSnackBar(
        const SnackBar(content: Text('Preço inválido')),
      );
      return (
        ok: false,
        isReservation: false,
        isStripeCheckout: false,
        orderId: null,
      );
    }

    unawaited(
      FleaberLogger.instance.logStripe(
        'checkout_submit_start',
        data: {
          'source': 'product_details_submit',
          'product_id': productId,
          'payment_method': paymentMethod,
          'total': total,
          'k_is_web': kIsWeb,
        },
      ),
    );

    final isDirect = paymentMethod.contains('Direto ao Vendedor');

    try {
      final freshRows = await ProductsTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', productId),
      );
      if (freshRows.isEmpty) {
        unawaited(
          FleaberLogger.instance.logStripe(
            'checkout_abort',
            data: {
              'source': 'product_details_submit',
              'reason': 'product_gone',
              'product_id': productId,
            },
          ),
        );
        if (!msgContext.mounted) {
          return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
        }
        ScaffoldMessenger.of(msgContext).showSnackBar(
          const SnackBar(content: Text('Artigo já não está disponível.')),
        );
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
      }
      final freshProduct = freshRows.first;
      if (freshProduct.isSold) {
        unawaited(
          FleaberLogger.instance.logStripe(
            'checkout_abort',
            data: {
              'source': 'product_details_submit',
              'reason': 'sold',
              'product_id': productId,
            },
          ),
        );
        if (!msgContext.mounted) {
          return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
        }
        ScaffoldMessenger.of(msgContext).showSnackBar(
          const SnackBar(content: Text('Este artigo já foi vendido.')),
        );
        await _refreshProductFromDb();
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
      }
      if (await _productBlocksCheckoutForCurrentUser(
        productId,
        allowOwnBuyerHold: true,
      )) {
        unawaited(
          FleaberLogger.instance.logStripe(
            'checkout_abort',
            data: {
              'source': 'product_details_submit',
              'reason': 'order_blocks',
              'product_id': productId,
              'hint':
                  'multi-qty: pago antigo não deve bloquear se quantity>0',
            },
          ),
        );
        if (!msgContext.mounted) {
          return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
        }
        ScaffoldMessenger.of(msgContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Já existe uma encomenda activa para este artigo. '
              'Não é possível iniciar outra compra.',
            ),
          ),
        );
        await _refreshProductFromDb();
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
      }

      // Compra ao preço anunciado: não fica à espera de proposta pendente.
      try {
        await supersedePendingOffersForBuyerProduct(
          productId: productId,
          buyerId: currentUserUid,
        );
        await supersedeBuyerPendingBundlesForProducts(
          sellerId: sellerId,
          productIds: [productId],
        );
      } catch (_) {}

      final isHand = shippingMethod == kFleaberShippingHandMethod;
      final seal = fleaberOrderShippingSealFields(
        handDelivery: isHand,
        weightKg: shippingWeightKg,
        band: shippingWeightBand,
        pickup: pickupPoint != null,
        shippingEurCharged: isHand ? 0.0 : shippingCostEur,
      );

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
          ...seal,
          ..._liveOrderContextFields(),
        });

        await _sendReservationChatMessages(
          orderId: order.id!,
          sellerId: sellerId,
          product: product,
          total: total,
          expiresAt: order.reservationExpiresAt ?? reservationExpiresAt,
        );

        await _applyDeliveryPointChoice(
          orderId: order.id!,
          pickupPoint: pickupPoint,
          deliveryHome: deliveryHome,
        );

        try {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.lightImpact();
        } catch (_) {}
        requestOrdersListRefresh();
        pingBatataReservationForNotificationBell();

        if (!pageContext.mounted) {
          return (
            ok: false,
            isReservation: false,
            isStripeCheckout: false,
            orderId: order.id,
          );
        }
        return (
          ok: true,
          isReservation: true,
          isStripeCheckout: false,
          orderId: order.id,
        );
      }

      final itemPrice = agreedItemPriceEur ??
          freshProduct.price ??
          product.price ??
          0.0;
      final shippingCost = shippingMethod == kFleaberShippingHandMethod
          ? 0.0
          : (shippingCostEur ??
              fleaberCheckoutDpdShippingEur(
                pickup: pickupPoint != null,
                weightKg: shippingWeightKg,
                band: shippingWeightBand,
              ));
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
            ...seal,
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
          ...seal,
          ..._liveOrderContextFields(),
        });
        orderId = order.id;
      }
      if (orderId == null || orderId.isEmpty) {
        throw Exception('Não foi possível criar a encomenda.');
      }
      await _applyDeliveryPointChoice(
        orderId: orderId,
        pickupPoint: pickupPoint,
        deliveryHome: deliveryHome,
      );
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
        shippingWeightKg: shippingWeightKg,
        shippingWeightBand: shippingWeightBand,
        pickup: pickupPoint != null,
      );
      if (!stripePaid) {
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: orderId,
        );
      }

      requestMarketplaceFeedRefresh();
      requestOrdersListRefresh();
      pingBatataReservationForNotificationBell();

      if (!pageContext.mounted) {
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: orderId,
        );
      }
      return (
        ok: true,
        isReservation: false,
        isStripeCheckout: true,
        orderId: orderId,
      );
    } catch (e, st) {
      print('DETALHE DO ERRO CHECKOUT: $e');
      unawaited(
        FleaberLogger.instance.logStripe(
          'checkout_catch',
          data: {'source': 'product_details'},
          error: e,
          stackTrace: st,
        ),
      );
      if (!msgContext.mounted) {
        return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
      }
      ScaffoldMessenger.of(msgContext).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
      return (
          ok: false,
          isReservation: false,
          isStripeCheckout: false,
          orderId: null,
        );
    }
  }

  Widget _buildBottomPurchaseBar(ProductsRow p, {bool embedded = false}) {
    if (_blockingProductSync) {
      final loading = Padding(
        padding: EdgeInsets.fromLTRB(
          embedded ? 0 : 16,
          embedded ? 8 : 16,
          embedded ? 0 : 16,
          embedded ? 8 : 16,
        ),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _kTeal,
            ),
          ),
        ),
      );
      if (embedded) return loading;
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
          child: SafeArea(top: false, child: loading),
        ),
      );
    }

    final listingLabel = _listingStatusLabel(p);

    final actions = listingLabel != null
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
                      );

    if (embedded) {
      return actions;
    }

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
            child: actions,
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
    // Preview P13: `#/...?p13_expand_desc=1` abre a descrição expandida (só web).
    if (kIsWeb && Uri.base.toString().contains('p13_expand_desc=1')) {
      _descriptionExpanded = true;
    }
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
          // Multi-qty: encomenda paga não esgota o anúncio enquanto quantity>0.
          if (rows.first.isSold || rows.first.quantity <= 0) {
            listingPaid = true;
          }
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
    });
    // Esperar stock live/rifa antes de pintar quantidade — evita flash «2» ? Vendido.
    if (_originLiveItemId != null || rows.isNotEmpty) {
      await _fetchLiveStockSnapshot();
    }
    if (!mounted) return;
    setState(() => _blockingProductSync = false);
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
      final reason = _blockingProductSync
          ? 'blocking_sync'
          : (p.isSold || _listingPaidForUi)
              ? 'sold'
              : _isOwnListing(p)
                  ? 'own_listing'
                  : 'vacation';
      unawaited(
        FleaberLogger.instance.logStripe(
          'pay_tap_abort',
          data: {
            'source': 'product_details_secure_tap',
            'reason': reason,
            'product_id': p.id,
          },
        ),
      );
      if (!mounted) return;
      final msg = reason == 'sold'
          ? 'Este artigo já foi vendido. Escolhe outro para testar o pagamento.'
          : reason == 'vacation'
              ? 'Vendedor de férias — compra indisponível.'
              : reason == 'own_listing'
                  ? 'Este anúncio é teu.'
                  : 'Ainda a carregar o artigo — tenta outra vez.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (_liveStockSnapshot != null &&
        _liveStockSnapshot!.raffleHoldQty > 0 &&
        _liveStockSnapshot!.availableQty < 1) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'pay_tap_abort',
          data: {
            'source': 'product_details_secure_tap',
            'reason': 'raffle_hold_stock_zero',
            'product_id': p.id,
          },
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem stock disponível neste momento.')),
      );
      return;
    }
    if (p.quantity <= 0) {
      unawaited(
        FleaberLogger.instance.logStripe(
          'pay_tap_abort',
          data: {
            'source': 'product_details_secure_tap',
            'reason': 'product_qty_zero',
            'product_id': p.id,
          },
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem stock disponível neste momento.')),
      );
      return;
    }
    unawaited(
      FleaberLogger.instance.logStripe(
        'pay_tap',
        data: {
          'source': 'product_details_secure_tap',
          'product_id': p.id,
          'k_is_web': kIsWeb,
        },
      ),
    );
    _showCheckoutSheet(
      p,
      overrideItemPriceEur: _agreedOfferPriceEur,
    );
  }

  Future<bool> _productBlocksCheckoutForCurrentUser(
    String productId, {
    bool allowOwnBuyerHold = false,
  }) async {
    final productRows = await ProductsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', productId),
    );
    final product = productRows.isEmpty ? null : productRows.first;
    final stockLeft = product?.quantity ?? 0;
    final listingSold = product?.isSold == true || stockLeft <= 0;

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
      if (!orderStatusBlocksOtherBuyers(o.status)) continue;
      // Multi-qty: pago/enviado já descontou stock — não tranca o anúncio.
      if (!listingSold &&
          stockLeft > 0 &&
          orderStatusAlreadyConsumedStock(o.status)) {
        continue;
      }
      return true;
    }
    return false;
  }

  static String _formatPriceEur(ProductsRow row) {
    final p = row.price;
    if (p == null) return '—';
    return '${p.toStringAsFixed(2).replaceAll('.', ',')} \u20ac';
  }

  static List<String> _imageUrls(ProductsRow row) {
    final out = <String>[];
    for (final raw in row.imageUrls) {
      final n = normalizeProductImageUrl(raw);
      if (n != null) out.add(n);
    }
    return out;
  }

  /// Galeria efectiva: no artigo P13 de teste (web) injecta 8 fotos de proporções
  /// distintas — sem UPDATE à BD.
  List<String> _effectiveImageUrls(ProductsRow p) {
    if (kIsWeb && p.id == _kP13LongDescTestProductId) {
      return List<String>.from(_kP13GalleryFixtureUrls);
    }
    return _imageUrls(p);
  }

  bool _descriptionNeedsToggle(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return false;
    return t.length > 90 || t.contains('\n');
  }

  Future<double?> _averageStars(String? sellerId) async {
    if (sellerId == null || sellerId.isEmpty) return null;
    final rows = await ReviewsPublicRatingsTable().queryRows(
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
    unawaited(
      HubActions.openPublicProfile(
        context,
        sellerId: sid,
        initialTab: initialTab,
      ),
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

  Future<void> _onContactar(
    ProductsRow product, {
    String? orderId,
  }) async {
    final sellerId = product.sellerId;
    if (sellerId == null || sellerId.isEmpty) return;
    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para contactar.')),
      );
      return;
    }
    try {
      await openH10Conversation(
        context,
        otherUserId: sellerId,
        orderId: orderId,
        productId: product.id,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir as mensagens.')),
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

    final urls = _effectiveImageUrls(p);
    final favoritesCount =
        favoriteCountUiOverrideForProduct(p.id) ??
        _favoritesCountOverride ??
        p.favoritesCount;
    final galleryCount = urls.isEmpty ? 1 : urls.length;
    final h = MediaQuery.sizeOf(context).height * 0.4;
    final desc = _effectiveDescription(p);
    final showDescToggle = _descriptionNeedsToggle(desc);
    final sellerId = p.sellerId;
    final listingStatusTag = _listingStatusLabel(p);

    final desktopWeb = _useDesktopProductLayout(context);

    // Web desktop: chrome FleaHub (topbar + footer). Mobile/app: AppBar «Detalhe»
    // intacto — mesma hierarquia da app Android.
    if (desktopWeb) {
      return FleaHubSiteScaffold(
        body: _buildDesktopProductBody(
          context,
          p: p,
          urls: urls,
          favoritesCount: favoritesCount,
          galleryCount: galleryCount,
          desc: desc,
          showDescToggle: showDescToggle,
          sellerId: sellerId,
          listingStatusTag: listingStatusTag,
        ),
      );
    }

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
          if (_isOwnListing(p)) _buildManageListingMenu(p),
        ],
      ),
      // Mobile/tablet: barra fixa via Stack (não bottomNavigationBar) para
      // ficar acima do aviso de cookies no Flutter web.
      bottomNavigationBar: null,
      body: _buildProductDetailsBody(
        context,
        p: p,
        urls: urls,
        favoritesCount: favoritesCount,
        galleryCount: galleryCount,
        galleryHeight: h,
        desc: desc,
        showDescToggle: showDescToggle,
        sellerId: sellerId,
        listingStatusTag: listingStatusTag,
      ),
    );
  }

  PopupMenuButton<String> _buildManageListingMenu(ProductsRow p) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => _onManageListingAction(p, action),
      itemBuilder: (ctx) {
        final listed = _isMarketplaceListing(p) && !p.isSold;
        return [
          const PopupMenuItem(
            value: 'edit',
            child: Text('Editar'),
          ),
          if (!p.isSold)
            PopupMenuItem(
              value: listed ? 'hide' : 'show',
              child: Text(
                listed
                    ? 'Ocultar do marketplace'
                    : 'Publicar no marketplace',
              ),
            ),
          if (!p.isSold)
            const PopupMenuItem(
              value: 'delete',
              child: Text('Eliminar an\u00fancio'),
            ),
        ];
      },
    );
  }

  static const double _kDesktopBreakpoint = 1024;
  static const double _kDesktopMaxWidth = 1100;
  /// Largura dos cartões «Artigos do Vendedor» no desktop (tipo marketplace).
  static const double _kDesktopSellerCardWidth = 152;
  /// Altura da galeria desktop (protagonismo sem distorcer — BoxFit.contain).
  static const double _kDesktopGalleryHeight = 490;
  static const double _kTabletMinWidth = 768;
  static const double _kTabletMaxWidth = 840;

  /// Artigo de teste da preview P13 — descrição longa só em web (não grava BD).
  static const String _kP13LongDescTestProductId =
      'c78c84d6-7268-4bea-bc74-15fa7237261e';

  /// Vendedor de demonstração da preview P13 (nome público se a view
  /// `profiles_directory_public` ainda não o expõe ao anon).
  static const String _kP13DemoSellerId =
      '06ed6f36-acfb-4c36-a3cf-d77a0eeeb451';
  static const String _kP13DemoSellerDisplayName = 'Ana Marques';

  /// Galeria de teste P13 (web): várias fotos realistas do mesmo tipo de peça
  /// (proporções mistas para validar lightbox) — sem placehold técnico.
  static const List<String> _kP13GalleryFixtureUrls = [
    // 1 — hero alinhado à BD do cachecol (malha bege; URLs 404 Unsplash removidas)
    'https://images.unsplash.com/photo-1434389677669-e08b4cac3105?auto=format&fit=crop&w=1200&h=800&q=80',
    // 2 vertical — malha
    'https://images.unsplash.com/photo-1544441893-675973e31985?auto=format&fit=crop&w=900&h=1200&q=80',
    // 3 quadrada — dobrado
    'https://images.unsplash.com/photo-1489987707025-afc232f7ea0f?auto=format&fit=crop&w=900&h=900&q=80',
    // 4 detalhe tecido
    'https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=800&h=1200&q=80',
    // 5 panorama loja
    'https://images.unsplash.com/photo-1441984904996-e0b6ba687e04?auto=format&fit=crop&w=1600&h=600&q=80',
    // 6 vertical knit
    'https://images.unsplash.com/photo-1576566588028-4147f3842f27?auto=format&fit=crop&w=700&h=1100&q=80',
    // 7 horizontal roupeiro
    'https://images.unsplash.com/photo-1467043237213-65f2da53396f?auto=format&fit=crop&w=1100&h=700&q=80',
    // 8 quase quadrada
    'https://images.unsplash.com/photo-1516762689617-e1cffcef479d?auto=format&fit=crop&w=1000&h=950&q=80',
  ];

  /// ~2650 caracteres, vários parágrafos — só para validar Ver mais / Ver menos.
  static const String _kP13LongDescriptionFixture =
      'Cachecol de lã cinzento, macio ao toque, ideal para o dia a dia e para '
      'usar em cima de casacos leves. Peça usada em bom estado geral, com o '
      'cuidado típico de alguém que guarda a roupa fora de época em saco de '
      'tecido e longe de humidade. Serve tanto para o trabalho como para '
      'passeios ao fim de semana, e combina facilmente com tons neutros '
      '(preto, bege, azul-marinho) sem roubar protagonismo ao resto do look.\n\n'
      'Características\n'
      '• Material: mistura de lã com fibras suaves (etiqueta de composição '
      'visível nas fotos). Não pica na pele na maior parte das utilizações; '
      'pessoas com pele muito sensível podem preferir usar por cima de uma '
      'gola alta fina.\n'
      '• Cor: cinzento médio, uniforme, sem descoloração óbvia nas zonas '
      'expostas ao sol. Em luz artificial pode parecer um tom mais claro.\n'
      '• Dimensões aproximadas: comprimento generoso para dar uma volta ao '
      'pescoço com sobra; largura suficiente para cobrir bem o colo.\n'
      '• Acabamentos: franjas regulares nas pontas; costuras firmes; sem '
      'cheiro a mofo nem a produtos de limpeza agressivos.\n\n'
      'Estado de conservação\n'
      'A peça foi usada em poucas estações. Não tem buracos, rasgões nem '
      'manchas visíveis à luz do dia. Pode haver leve sinal de uso nas '
      'franjas (algo normal neste tipo de acessório). Foi lavada segundo as '
      'instruções da etiqueta e está pronta a usar. Guardei-a sempre dobrada '
      'em gaveta arejada, sem exposição prolongada a sol directo.\n\n'
      'Eventuais defeitos / notas honestas\n'
      '• Ligeiro amolgadinho quase imperceptível num canto da franja — '
      'apenas se procurar de muito perto.\n'
      '• Não inclui embalagem original de marca.\n'
      '• Como em qualquer artigo em segunda mão, recomenda-se verificar as '
      'fotografias com atenção; o que se vê nas imagens corresponde ao que '
      'será enviado. Se tiveres dúvida sobre uma zona concreta, pergunta no '
      'chat antes de comprares — respondo com gosto.\n\n'
      'Informações adicionais\n'
      'Envio disponível via DPD ou entrega em mão, conforme as opções do '
      'checkout Fleaber. Posso responder a dúvidas no chat antes da compra. '
      'Se quiseres combinar com outros artigos da mesma loja, usa «Criar '
      'conjunto» para poupar em portes quando o vendedor tiver descontos de '
      'bundle activos. Em conjunto, o cachecol costuma viajar bem com '
      'camisolas e casacos leves sem aumentar muito o volume da embalagem.\n\n'
      'Motivação da venda: renovação de armário. Preferência por compradores '
      'que valorizem peças práticas e quentes para o inverno português. '
      'Disponível para envio rápido após confirmação do pagamento. Embalo com '
      'cuidado (saco protetor + caixa adequada) para a peça chegar em '
      'condições. Obrigado por leres a descrição até ao fim — ajuda a evitar '
      'surpresas e torna a compra mais transparente para os dois lados.';

  String _effectiveDescription(ProductsRow p) {
    final real = p.description?.trim() ?? '';
    // Preview web isolada: forçar texto longo no artigo de teste (sem UPDATE BD).
    if (kIsWeb && p.id == _kP13LongDescTestProductId) {
      return _kP13LongDescriptionFixture;
    }
    return real;
  }

  bool _useDesktopProductLayout(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

  bool _useTabletCenteredLayout(BuildContext context) {
    if (!kIsWeb) return false;
    final w = MediaQuery.sizeOf(context).width;
    return w >= _kTabletMinWidth && w < _kDesktopBreakpoint;
  }

  Widget _buildProductDetailsBody(
    BuildContext context, {
    required ProductsRow p,
    required List<String> urls,
    required int favoritesCount,
    required int galleryCount,
    required double galleryHeight,
    required String desc,
    required bool showDescToggle,
    required String? sellerId,
    required String? listingStatusTag,
  }) {
    // Desktop web usa FleaHubSiteScaffold + _buildDesktopProductBody no build().
    final mobile = _buildMobileProductBody(
      context,
      p: p,
      urls: urls,
      favoritesCount: favoritesCount,
      galleryCount: galleryCount,
      galleryHeight: galleryHeight,
      desc: desc,
      showDescToggle: showDescToggle,
      sellerId: sellerId,
      listingStatusTag: listingStatusTag,
    );
    final stacked = _buildMobileStackedWithPurchaseBar(
      context,
      p: p,
      child: mobile,
    );
    if (_useTabletCenteredLayout(context)) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kTabletMaxWidth),
          child: stacked,
        ),
      );
    }
    return stacked;
  }

  Widget _buildMobileStackedWithPurchaseBar(
    BuildContext context, {
    required ProductsRow p,
    required Widget child,
  }) {
    // Barra no fundo do body (Stack). O MaterialApp.builder já eleva o
    // Scaffold pelo slot do aviso — `bottom: 0` fica logo acima dos cookies.
    // (bottomNavigationBar no Flutter web ficava tapada; o Stack não.)
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomPurchaseBar(p),
        ),
      ],
    );
  }

  Widget _buildMobileProductBody(
    BuildContext context, {
    required ProductsRow p,
    required List<String> urls,
    required int favoritesCount,
    required int galleryCount,
    required double galleryHeight,
    required String desc,
    required bool showDescToggle,
    required String? sellerId,
    required String? listingStatusTag,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: _scrollBottomInset(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProductGallery(
            context,
            p: p,
            urls: urls,
            favoritesCount: favoritesCount,
            galleryCount: galleryCount,
            height: galleryHeight,
          ),
          _buildProductTitleBlock(
            p: p,
            listingStatusTag: listingStatusTag,
          ),
          _buildDescriptionBlock(
            desc: desc,
            showDescToggle: showDescToggle,
          ),
          _buildVacationBanner(sellerId: sellerId),
          _buildSellerRow(p: p, sellerId: sellerId),
          _buildShippingBlock(),
          _buildSellerOtherProducts(p: p, sellerId: sellerId),
          // 119.9: em artigos curtos, garantir scroll para «Contactar»
          // ficar acima da barra sticky Comprar/Proposta.
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildDesktopProductBody(
    BuildContext context, {
    required ProductsRow p,
    required List<String> urls,
    required int favoritesCount,
    required int galleryCount,
    required String desc,
    required bool showDescToggle,
    required String? sellerId,
    required String? listingStatusTag,
  }) {
    // Conteúdo dentro de [FleaHubSiteScaffold] (já com topbar + footer).
    final pad = FleaHubSiteLayout.pagePadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 16, pad.right, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kDesktopMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 55,
                  child: _buildProductGallery(
                    context,
                    p: p,
                    urls: urls,
                    favoritesCount: favoritesCount,
                    galleryCount: galleryCount,
                    height: _kDesktopGalleryHeight,
                    showThumbnails: true,
                    borderRadius: 16,
                    // Sem crop agressivo: proporção da foto respeitada.
                    imageFit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  flex: 45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProductTitleBlock(
                        p: p,
                        listingStatusTag: listingStatusTag,
                        compactPadding: true,
                        trailing: _isOwnListing(p)
                            ? _buildManageListingMenu(p)
                            : null,
                      ),
                      _buildVacationBanner(
                        sellerId: sellerId,
                        compactPadding: true,
                      ),
                      _buildSellerRow(
                        p: p,
                        sellerId: sellerId,
                        compactPadding: true,
                      ),
                      _buildShippingBlock(compactPadding: true),
                      const SizedBox(height: 24),
                      _buildBottomPurchaseBar(p, embedded: true),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            _buildDescriptionBlock(
              desc: desc,
              showDescToggle: showDescToggle,
              compactPadding: true,
              collapsedMaxLines: 5,
            ),
            const SizedBox(height: 28),
            _buildSellerOtherProducts(
              p: p,
              sellerId: sellerId,
              compactPadding: true,
              compactCards: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _galleryNavChip({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildProductGallery(
    BuildContext context, {
    required ProductsRow p,
    required List<String> urls,
    required int favoritesCount,
    required int galleryCount,
    required double height,
    bool showThumbnails = false,
    double borderRadius = 0,
    BoxFit imageFit = BoxFit.cover,
  }) {
    final gallery = SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFFE8EDF2),
            child: PageView.builder(
              controller: _galleryController,
              itemCount: galleryCount,
              itemBuilder: (context, index) {
                if (urls.isEmpty) {
                  return const Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Color(0xFF57636C),
                    ),
                  );
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openGalleryLightbox(context, urls),
                  child: BatataCachedNetworkImage(
                    imageUrl: urls[index],
                    fit: imageFit,
                    alignment: Alignment.center,
                    errorWidget: const ColoredBox(
                      color: Color(0xFFE8EDF2),
                      child: Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  ),
                );
              },
            ),
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
          if (showThumbnails && urls.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _galleryNavChip(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    if (!_galleryController.hasClients) return;
                    final cur = (_galleryController.page ?? 0).round();
                    if (cur <= 0) return;
                    _galleryController.animateToPage(
                      cur - 1,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _galleryNavChip(
                  icon: Icons.chevron_right_rounded,
                  onTap: () {
                    if (!_galleryController.hasClients) return;
                    final cur = (_galleryController.page ?? 0).round();
                    if (cur >= urls.length - 1) return;
                    _galleryController.animateToPage(
                      cur + 1,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ),
            ),
          ],
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
    );

    final clipped = borderRadius > 0
        ? ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: gallery,
          )
        : gallery;

    if (!showThumbnails || urls.length <= 1) {
      return clipped;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        clipped,
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _galleryController,
                builder: (context, _) {
                  var current = 0;
                  if (_galleryController.hasClients) {
                    current = (_galleryController.page ??
                            _galleryController.initialPage.toDouble())
                        .round()
                        .clamp(0, urls.length - 1);
                  }
                  final selected = current == index;
                  return InkWell(
                    onTap: () {
                      if (_galleryController.hasClients) {
                        _galleryController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? _kTeal : const Color(0xFFE0E6EB),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: BatataCachedNetworkImage(
                        imageUrl: urls[index],
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorWidget: const ColoredBox(
                          color: Color(0xFFE8EDF2),
                          child: Icon(Icons.broken_image_outlined, size: 20),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductTitleBlock({
    required ProductsRow p,
    required String? listingStatusTag,
    bool compactPadding = false,
    Widget? trailing,
  }) {
    final hPad = compactPadding ? 0.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listingStatusTag != null)
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
            child: Align(
              alignment: compactPadding ? Alignment.centerLeft : Alignment.center,
              child: _buildTealListingBadge(
                listingStatusTag,
                fullWidth: false,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 8 : 20, hPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      valueOrDefault<String>(p.title, 'Artigo'),
                      style: GoogleFonts.inter(
                        fontSize: compactPadding ? 24 : 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF101518),
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
              if ((p.clothingSize ?? '').trim().isNotEmpty ||
                  (p.state ?? '').trim().isNotEmpty ||
                  _isMarketplaceListing(p) ||
                  _effectiveStockQuantity(p) > 1) ...[
                const SizedBox(height: 4),
                if ((p.clothingSize ?? '').trim().isNotEmpty)
                  _SpecLine(
                    label: 'Tamanho',
                    value: p.clothingSize!.trim(),
                  ),
                if ((_isMarketplaceListing(p) ||
                        _liveStockSnapshot != null ||
                        _effectiveStockQuantity(p) > 1) &&
                    (_effectiveStockQuantity(p) > 0 ||
                        (_liveStockSnapshot?.raffleHoldQty ?? 0) > 0)) ...[
                  if ((p.clothingSize ?? '').trim().isNotEmpty)
                    const SizedBox(height: 4),
                  _SpecLine(
                    label: 'Stock',
                    value: _liveStockSnapshot != null &&
                            (_liveStockSnapshot!.raffleHoldQty > 0)
                        ? '${_effectiveStockQuantity(p)} disponíveis'
                        : '${_effectiveStockQuantity(p)} unidades',
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
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: compactPadding ? 26 : 22,
                  fontWeight: FontWeight.w800,
                  color: _kTeal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionBlock({
    required String desc,
    required bool showDescToggle,
    bool compactPadding = false,
    int collapsedMaxLines = 2,
  }) {
    if (desc.isEmpty) return const SizedBox.shrink();
    final hPad = compactPadding ? 0.0 : 16.0;
    // Desktop: coluna de leitura ~800 px (evita linhas excessivamente longas).
    final readingColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Descri\u00e7\u00e3o',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101518),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          maxLines: _descriptionExpanded ? null : collapsedMaxLines,
          overflow: _descriptionExpanded
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          softWrap: true,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.45,
            color: const Color(0xFF57636C),
          ),
        ),
        if (showDescToggle)
          GestureDetector(
            onTap: () => setState(
              () => _descriptionExpanded = !_descriptionExpanded,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _descriptionExpanded ? 'Ver menos' : '... ver mais',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kTeal,
                ),
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 0 : 16, hPad, 0),
      child: compactPadding
          ? Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: readingColumn,
              ),
            )
          : readingColumn,
    );
  }

  Widget _buildVacationBanner({
    required String? sellerId,
    bool compactPadding = false,
  }) {
    if (sellerId == null || sellerId.isEmpty) {
      return const SizedBox.shrink();
    }
    final hPad = compactPadding ? 0.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 16 : 20, hPad, 0),
      child: FutureBuilder<List<ProfilesRow>>(
        future: ProfilesDirectoryTable().queryRows(
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
    );
  }

  Widget _buildSellerRow({
    required ProductsRow p,
    required String? sellerId,
    bool compactPadding = false,
  }) {
    final hPad = compactPadding ? 0.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 20 : 24, hPad, 0),
      child: FutureBuilder<({String name, String? photoUrl, String? handle})?>(
        future: () async {
          if (sellerId != null && sellerId.isNotEmpty) {
            await SellerProfessionalCache.warm([sellerId]);
          }
          if (sellerId == null || sellerId.isEmpty) {
            return null;
          }
          final loaded = await SellerPublicDisplay.load(sellerId);
          if (loaded != null) return loaded;
          if (kIsWeb && sellerId == _kP13DemoSellerId) {
            return (
              name: _kP13DemoSellerDisplayName,
              photoUrl: null,
              handle: null,
            );
          }
          return null;
        }(),
        builder: (context, snap) {
          final loaded = snap.data;
          final name = (loaded?.name.trim().isNotEmpty == true)
              ? loaded!.name.trim()
              : 'Vendedor';
          final photo = loaded?.photoUrl;
          return FutureBuilder<double?>(
            future: _averageStars(sellerId),
            builder: (context, starSnap) {
              final avg = starSnap.data;
              // 119.9: identidade (avatar + nome + distintivo + avalia��es)
              // e �Contactar� por baixo ? evita aperto numa s� linha no mobile.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openSellerProfile(p),
                      borderRadius: FleaberRadius.circularMd,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: Color(0xFF101518),
                                    ),
                                  ),
                                  if (SellerProfessionalCache.showBadge(
                                    sellerId,
                                  )) ...[
                                    const SizedBox(height: 6),
                                    ProfessionalSellerBadge(
                                      compact: true,
                                      verified: SellerProfessionalCache
                                              .peek(sellerId ?? '')
                                              ?.professionalVerified ==
                                          true,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    avg == null
                                        ? 'Sem avalia\u00e7\u00f5es'
                                        : 'M\u00e9dia: ${avg.toStringAsFixed(1)} / 5',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      color: Color(0xFF57636C),
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
                  if (!_isOwnListing(p)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => _onContactar(p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kTeal,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: FleaberRadius.circularMd,
                          ),
                        ),
                        child: Text(
                          'Contactar',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    // Espaço para «Contactar» subir acima da barra Comprar/Proposta.
                    const SizedBox(height: 88),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildShippingBlock({bool compactPadding = false}) {
    final hPad = compactPadding ? 0.0 : 16.0;
    // Só opções reais do checkout (fee_calculator) — sem prazos inventados.
    final lines = <({IconData icon, String text})>[
      (icon: Icons.local_shipping_outlined, text: kFleaberShippingCarrierLabel),
      (icon: Icons.handshake_outlined, text: kFleaberShippingHandLabel),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 20 : 24, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informa\u00e7\u00e3o de Envio',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Color(0xFF101518),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(lines[i].icon, size: 22, color: _kMutedGray),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lines[i].text,
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
        ],
      ),
    );
  }

  Widget _buildCriarConjuntoButton({
    required String sellerId,
    required String productId,
  }) {
    return OutlinedButton(
      onPressed: () {
        context.pushNamed(
          'CriarConjunto',
          queryParameters: {
            'sellerId': serializeParam(sellerId, ParamType.String),
            'initialProductId': serializeParam(productId, ParamType.String),
          }.withoutNulls,
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: FleaberColors.teal,
        side: const BorderSide(color: FleaberColors.teal, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: FleaberRadius.circularMd,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(
        'Criar conjunto',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSellerProductCard(ProductsRow o, double cardW) {
    final pro = SellerProfessionalCache.peek(o.sellerId ?? '');
    String? cardImage;
    for (final raw in o.imageUrls) {
      final n = normalizeProductImageUrl(raw);
      if (n != null) {
        cardImage = n;
        break;
      }
    }
    return MarketplaceProductCard(
      title: valueOrDefault<String>(o.title, 'Artigo'),
      stateLabel: o.state,
      priceLabel: _formatPriceEur(o),
      // BatataCachedNetworkImage também normaliza; passamos já limpo.
      imageUrl: cardImage,
      favoritesCount: o.favoritesCount,
      isFavorited: false,
      width: cardW,
      showProfessionalBadge: pro?.showProfessionalBadge == true,
      professionalVerified: pro?.professionalVerified == true,
      onTap: () {
        context.push(
          ProductDetailsPageWidget.routePath,
          extra: ProductDetailsPageWidget.routeExtraForProduct(o),
        );
      },
      onFavoriteTap:
          o.sellerId == currentUserUid ? null : () => _toggleFavorite(o),
    );
  }

  Widget _buildSellerOtherProducts({
    required ProductsRow p,
    required String? sellerId,
    bool compactPadding = false,
    bool compactCards = false,
  }) {
    final hPad = compactPadding ? 0.0 : 16.0;
    final canBundle = sellerId != null &&
        sellerId.isNotEmpty &&
        sellerId != currentUserUid &&
        p.id != null;

    final titleBlock = Column(
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, compactPadding ? 8 : 28, hPad, 12),
          child: compactCards
              // Desktop: título + «Criar conjunto» juntos (não aos extremos).
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    titleBlock,
                    if (canBundle)
                      _buildCriarConjuntoButton(
                        sellerId: sellerId!,
                        productId: p.id!,
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleBlock),
                    if (canBundle)
                      _buildCriarConjuntoButton(
                        sellerId: sellerId!,
                        productId: p.id!,
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
                  limit: 36,
                ),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.isEmpty) {
              return Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
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

            if (compactCards) {
              // Grelha Wrap: 1–3 artigos à esquerda; muitos preenchem a largura.
              return Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                child: Wrap(
                  spacing: sepW,
                  runSpacing: 14,
                  alignment: WrapAlignment.start,
                  children: [
                    for (final o in list)
                      _buildSellerProductCard(o, _kDesktopSellerCardWidth),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                var cardW = (maxW - 32 - 14) / 2;
                if (cardW <= 0) cardW = maxW * 0.42;
                if (cardW > 180) cardW = 180;
                final listH =
                    cardW / MarketplaceProductCard.imageAspectRatio + 108;
                return SizedBox(
                  height: listH,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 4),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: sepW),
                    itemBuilder: (context, i) =>
                        _buildSellerProductCard(list[i], cardW),
                  ),
                );
              },
            );
          },
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
  late int _index;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    final next = i.clamp(0, widget.urls.length - 1);
    if (next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBy(int delta) => _goTo(_index + delta);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (widget.urls.length <= 1) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _goBy(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _goBy(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _navCircle({
    required IconData icon,
    required VoidCallback onTap,
    required bool compact,
  }) {
    final padAll = compact ? 8.0 : 10.0;
    final iconSize = compact ? 24.0 : 28.0;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padAll),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final multi = widget.urls.length > 1;
    final narrow = size.width < 700;
    final showThumbs = multi && size.height >= 520 && size.width >= 480;
    final bottomChrome = showThumbs ? 118.0 : (multi ? 56.0 : 24.0);
    final sideInset = narrow ? 4.0 : 8.0;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: bottomChrome + pad.bottom,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.urls.length,
                  onPageChanged: (i) => setState(() => _index = i),
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
                          maxWidth: 1600,
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
              ),
              Positioned(
                top: pad.top + 4,
                left: 4,
                child: IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  iconSize: 28,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (multi)
                Positioned(
                  top: pad.top + 14,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ),
              if (multi) ...[
                Positioned(
                  left: sideInset,
                  top: 0,
                  bottom: bottomChrome + pad.bottom,
                  child: Center(
                    child: _navCircle(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _goBy(-1),
                      compact: narrow,
                    ),
                  ),
                ),
                Positioned(
                  right: sideInset,
                  top: 0,
                  bottom: bottomChrome + pad.bottom,
                  child: Center(
                    child: _navCircle(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _goBy(1),
                      compact: narrow,
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    pad.bottom + 10,
                  ),
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (multi)
                        SmoothPageIndicator(
                          controller: _pageController,
                          count: widget.urls.length,
                          effect: ExpandingDotsEffect(
                            dotHeight: 7,
                            dotWidth: 7,
                            expansionFactor: 3,
                            spacing: 7,
                            activeDotColor: widget.activeDotColor,
                            dotColor: Colors.white.withValues(alpha: 0.4),
                          ),
                          onDotClicked: _goTo,
                        ),
                      if (showThumbs) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 64,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.urls.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final selected = i == _index;
                              return InkWell(
                                onTap: () => _goTo(i),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected
                                          ? widget.activeDotColor
                                          : Colors.white24,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: BatataCachedNetworkImage(
                                    imageUrl: widget.urls[i],
                                    fit: BoxFit.cover,
                                    errorWidget: const ColoredBox(
                                      color: Color(0xFF333333),
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
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
