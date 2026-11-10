import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/batata_bundle_discounts.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_h10_navigation.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_product_qty_stepper.dart';
import '/widgets/fleaber_primary_button.dart';

class VerConjuntoPageWidget extends StatefulWidget {
  const VerConjuntoPageWidget({
    super.key,
    required this.sellerId,
    required this.productIdsCsv,
    this.initialQuantitiesCsv,
  });

  final String sellerId;
  final String productIdsCsv;
  final String? initialQuantitiesCsv;

  static String routeName = 'VerConjunto';
  static String routePath = '/verConjunto';

  @override
  State<VerConjuntoPageWidget> createState() => _VerConjuntoPageWidgetState();
}

class _VerConjuntoPageWidgetState extends State<VerConjuntoPageWidget> {
  bool _loading = true;
  bool _buying = false;
  bool _proposing = false;
  bool _sendingMessage = false;
  List<ProductsRow> _products = [];
  BundleDiscountTiers _tiers = const BundleDiscountTiers();
  BundleProductQuantities _quantities = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = widget.productIdsCsv
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tiers = await fetchSellerBundleDiscounts(widget.sellerId);
    if (ids.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q.inFilter('id', ids),
      limit: ids.length,
    );
    final byId = {for (final p in rows) if (p.id != null) p.id!: p};
    final ordered = ids.map((id) => byId[id]).whereType<ProductsRow>().toList();
    final preset = parseBundleQuantitiesCsv(widget.initialQuantitiesCsv);
    final quantities = defaultBundleQuantities(ordered);
    preset.forEach((id, qty) {
      if (!quantities.containsKey(id)) return;
      ProductsRow? match;
      for (final p in ordered) {
        if (p.id == id) {
          match = p;
          break;
        }
      }
      final maxQ = (match?.quantity ?? 1).clamp(1, 999);
      quantities[id] = qty.clamp(1, maxQ);
    });
    if (!mounted) return;
    setState(() {
      _products = ordered;
      _tiers = tiers;
      _quantities = quantities;
      _loading = false;
    });
  }

  /// Artigos com quantidade > 0 (qty 0 fica na lista para poder voltar a +).
  List<ProductsRow> get _activeProducts => _products.where((p) {
        final id = p.id?.trim() ?? '';
        if (id.isEmpty) return false;
        return (_quantities[id] ?? 0) > 0;
      }).toList();

  BundleProductQuantities get _activeQuantities {
    final out = <String, int>{};
    for (final p in _activeProducts) {
      final id = p.id;
      if (id == null || id.isEmpty) continue;
      final q = _quantities[id] ?? 0;
      if (q > 0) out[id] = q;
    }
    return out;
  }

  bool get _canProceedBundle => _activeProducts.length >= 2;

  Map<String, String> _selectionResult() {
    final ids = _activeProducts
        .map((p) => p.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    return {
      'productIds': ids.join(','),
      'quantities': encodeBundleQuantitiesCsv(_activeQuantities),
    };
  }

  void _popWithSelection() {
    if (!mounted) return;
    Navigator.of(context).pop(_selectionResult());
  }

  /// Qty unificada com Criar conjunto: 0 = soft-zero (fica na lista; + reabre).
  void _setQuantity(String productId, int qty) {
    if (productId.isEmpty) return;
    ProductsRow? product;
    for (final p in _products) {
      if (p.id == productId) {
        product = p;
        break;
      }
    }
    final maxQ = (product?.quantity ?? 1).clamp(1, 999);
    if (qty <= 0) {
      setState(() => _quantities[productId] = 0);
      return;
    }
    setState(() => _quantities[productId] = qty.clamp(1, maxQ));
  }

  Future<void> _openChat() async {
    if (_sendingMessage) return;
    if (!_canProceedBundle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolhe pelo menos 2 artigos para enviar o conjunto.'),
        ),
      );
      return;
    }
    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para enviar mensagem.')),
      );
      return;
    }
    setState(() => _sendingMessage = true);
    try {
      // Pedido novo → chat novo (forceNew em _persistBundleProposal).
      final result = await createBundlePurchaseRequest(
        sellerId: widget.sellerId,
        products: _activeProducts,
        productQuantities: _activeQuantities,
      );
      if (!mounted) return;
      final chatId = result['chat_id']?.toString();
      await openH10Conversation(
        context,
        otherUserId: widget.sellerId,
        chatId: chatId,
        productId: _activeProducts.first.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim().isEmpty
                ? 'Não foi possível abrir as mensagens.'
                : e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _buyBundle() async {
    if (!_canProceedBundle || _buying) return;
    setState(() => _buying = true);
    try {
      await payBundleNow(
        sellerId: widget.sellerId,
        products: _activeProducts,
        tiers: _tiers,
        productQuantities: _activeQuantities,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checkout aberto. Os artigos ficam vendidos após o pagamento.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _makeOffer() async {
    if (!_canProceedBundle || _proposing) return;
    final totals = calculateBundleTotals(
      products: _activeProducts,
      tiers: _tiers,
      quantitiesByProductId: _activeQuantities,
    );
    final amount = await _askOfferAmount(suggested: totals.total);
    if (amount == null || !mounted) return;
    setState(() => _proposing = true);
    try {
      print(
        'BATATA_BUNDLE_PROPOSAL start ver_conjunto seller=${widget.sellerId} '
        'qty=${encodeBundleQuantitiesCsv(_activeQuantities)} total=$amount',
      );
      final result = await createBundlePriceProposal(
        sellerId: widget.sellerId,
        products: _activeProducts,
        offeredTotalEur: amount,
        productQuantities: _activeQuantities,
      );
      print(
        'BATATA_BUNDLE_PROPOSAL end bundle_id=${result['bundle_id']} '
        'chat_id=${result['chat_id']}',
      );
      if (!mounted) return;
      // Manter _proposing até sair do ecrã — evita «Comprar agora» em paralelo
      // com a navegação H10 (corrida E85.4).
      try {
        await openH10Conversation(
          context,
          otherUserId: widget.sellerId,
          chatId: result['chat_id']?.toString(),
          productId: _activeProducts.first.id,
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proposta de ${formatEuros(amount)} enviada. Abre Mensagens para ver.',
            ),
          ),
        );
      }
    } catch (e, st) {
      print('BATATA_BUNDLE_PROPOSAL FAIL ver_conjunto error=$e stack=$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _proposing = false);
    }
  }

  Future<double?> _askOfferAmount({required double suggested}) {
    return showDialog<double>(
      context: context,
      builder: (ctx) => _BundleOfferAmountDialog(suggested: suggested),
    );
  }

  bool get _useHubChrome =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 1024;

  bool get _useTwoColumn =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    final totals = calculateBundleTotals(
      products: _activeProducts,
      tiers: _tiers,
      quantitiesByProductId: _activeQuantities,
    );
    const shipping = kFleaberCarrierShippingEur;
    final protection =
        calculateFleaberProtectionFee(totals.total, shippingEur: shipping);
    final grandTotal = totals.total + protection + shipping;
    final itemCount = bundleTotalItemCount(_activeProducts, _activeQuantities);

    final body = _loading
        ? const Center(
            child: CircularProgressIndicator(color: FleaberColors.teal),
          )
        : (_useTwoColumn
            ? _buildWideBody(
                totals: totals,
                shipping: shipping,
                protection: protection,
                grandTotal: grandTotal,
                itemCount: itemCount,
                showHubTitle: _useHubChrome,
              )
            : _buildPhoneBody(
                totals: totals,
                shipping: shipping,
                protection: protection,
                grandTotal: grandTotal,
                itemCount: itemCount,
              ));

    final page = _useHubChrome
        ? FleaHubSiteScaffold(
            body: _loading
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: FleaberColors.teal,
                      ),
                    ),
                  )
                : body,
          )
        : Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _popWithSelection,
              ),
              iconTheme: const IconThemeData(color: Color(0xFF101518)),
              title: Text(
                'Ver o conjunto',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            body: body,
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithSelection();
      },
      child: page,
    );
  }

  Widget _buildPhoneBody({
    required ({
      double subtotal,
      double discountPct,
      double discountEur,
      double total
    }) totals,
    required double shipping,
    required double protection,
    required double grandTotal,
    required int itemCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '$itemCount artigos',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ..._productRows(),
              const SizedBox(height: 8),
              ..._priceBreakdown(
                totals: totals,
                shipping: shipping,
                protection: protection,
                grandTotal: grandTotal,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _actionButtons(),
          ),
        ),
      ],
    );
  }

  Widget _buildWideBody({
    required ({
      double subtotal,
      double discountPct,
      double discountEur,
      double total
    }) totals,
    required double shipping,
    required double protection,
    required double grandTotal,
    required int itemCount,
    required bool showHubTitle,
  }) {
    final pad = showHubTitle
        ? FleaHubSiteLayout.pagePadding(context)
        : const EdgeInsets.symmetric(horizontal: 16);
    final summary = Material(
      color: const Color(0xFFF7F9FA),
      borderRadius: FleaberRadius.circularMd,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Resumo',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ..._priceBreakdown(
              totals: totals,
              shipping: shipping,
              protection: protection,
              grandTotal: grandTotal,
            ),
            const SizedBox(height: 16),
            _actionButtons(),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHubTitle) ...[
                Row(
                  children: [
                    IconButton(
                      onPressed: _popWithSelection,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Text(
                      'Ver o conjunto',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$itemCount artigos',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._productRows(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(width: 320, child: summary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _productRows() {
    return _products.map((p) {
      final id = p.id ?? '';
      // Soft-zero: mostrar 0 sem forçar mínimo 1.
      final qty = id.isEmpty ? 0 : (_quantities[id] ?? 0).clamp(0, 999);
      final maxQty = p.quantity < 1 ? 1 : p.quantity.clamp(1, 999);
      String? url;
      for (final raw in p.imageUrls) {
        final n = normalizeProductImageUrl(raw);
        if (n != null && n.isNotEmpty) {
          url = n;
          break;
        }
      }
      const photoPh = ColoredBox(
        color: Color(0xFFF1F4F8),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: Color(0xFF9AA5B1),
            size: 22,
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: FleaberRadius.circularSm,
              child: SizedBox(
                width: 56,
                height: 72,
                child: url != null
                    ? BatataCachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: photoPh,
                      )
                    : photoPh,
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatEuros(p.price ?? 0),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: FleaberColors.teal,
                    ),
                  ),
                  if (id.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    BundleProductQtyStepper(
                      compact: true,
                      quantity: qty,
                      maxQuantity: maxQty,
                      allowZero: true,
                      onChanged: (v) => _setQuantity(id, v),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _priceBreakdown({
    required ({
      double subtotal,
      double discountPct,
      double discountEur,
      double total
    }) totals,
    required double shipping,
    required double protection,
    required double grandTotal,
  }) {
    // Ordem alinhada ao Android: artigos → desconto (compra) → protecção → portes.
    // «Enviar mensagem» = purchase_request ao preço de catálogo (desconto 0 no BD);
    // o desconto do vendedor aplica-se em «Comprar agora» / proposta aceite.
    return [
      _priceLine('Preço', formatEuros(totals.subtotal)),
      if (totals.discountEur > 0)
        _priceLine(
          'Desconto de conjunto (${totals.discountPct.toStringAsFixed(0)}%)',
          '- ${formatEuros(totals.discountEur)}',
          valueColor: const Color(0xFF2E7D32),
        ),
      _priceLine(
        'Taxa de Proteção do Comprador',
        formatEuros(protection),
      ),
      _priceLine('Custos de envio', formatEuros(shipping)),
      const Divider(height: 28),
      _priceLine('Total', formatEuros(grandTotal), bold: true),
      if (totals.discountEur > 0) ...[
        const SizedBox(height: 8),
        Text(
          'O desconto aplica-se em «Comprar agora». '
          '«Enviar mensagem» pede os artigos ao preço de catálogo '
          '(${formatEuros(totals.subtotal)}), como na app.',
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.35,
            color: const Color(0xFF57636C),
          ),
        ),
      ],
    ];
  }

  Widget _actionButtons() {
    return Column(
      children: [
        FleaberPrimaryButton(
          width: double.infinity,
          label: 'Comprar agora',
          loading: _buying,
          onPressed: !_canProceedBundle || _buying ? null : _buyBundle,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _secondaryButton(
                label: 'Enviar mensagem',
                semanticsLabel: 'Enviar mensagem ao vendedor',
                onPressed: (!_canProceedBundle || _sendingMessage)
                    ? null
                    : _openChat,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _secondaryButton(
                label: 'Fazer proposta',
                onPressed:
                    (!_canProceedBundle || _proposing) ? null : _makeOffer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onPressed,
    String? semanticsLabel,
  }) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: FleaberColors.teal,
        side: const BorderSide(color: FleaberColors.teal),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        semanticsLabel: semanticsLabel,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
    if (semanticsLabel == null) return button;
    return Tooltip(message: semanticsLabel, child: button);
  }

  Widget _priceLine(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF57636C),
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: bold ? 18 : 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? const Color(0xFF101518),
            ),
          ),
        ],
      ),
    );
  }
}

class _BundleOfferAmountDialog extends StatefulWidget {
  const _BundleOfferAmountDialog({required this.suggested});

  final double suggested;

  @override
  State<_BundleOfferAmountDialog> createState() => _BundleOfferAmountDialogState();
}

class _BundleOfferAmountDialogState extends State<_BundleOfferAmountDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.suggested > 0 ? widget.suggested.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Indica um valor válido.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Proposta pelo conjunto',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          prefixText: '€ ',
          hintText: 'Valor que ofereces pelos artigos',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: FleaberColors.teal),
          onPressed: _submit,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
