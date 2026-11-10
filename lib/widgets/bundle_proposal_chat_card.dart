import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/batata_bundle_discounts.dart';
import '/utils/bundle_price_display.dart';
import '/utils/bundle_quote_flow.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/bundle_offer_amount_sheet.dart';
import '/widgets/bundle_seller_confirm_quote_sheet.dart';
import '/widgets/bundle_thumb_stack.dart';
import '/widgets/fleaber_primary_button.dart';

class BundleProposalChatCard extends StatefulWidget {
  const BundleProposalChatCard({
    super.key,
    required this.payload,
    required this.onUpdated,
  });

  final Map<String, dynamic> payload;
  final Future<void> Function() onUpdated;

  @override
  State<BundleProposalChatCard> createState() => _BundleProposalChatCardState();
}

class _BundleProposalChatCardState extends State<BundleProposalChatCard> {
  bool _busy = false;
  Map<String, dynamic>? _bundle;
  List<ProductsRow> _products = const [];
  List<OrdersRow> _bundleOrders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.payload['bundle_id']?.toString();
    if (id == null || id.isEmpty) return;
    final bundle = await fetchProductBundle(id);
    final rawIds = widget.payload['product_ids'];
    final rawList = rawIds is List
        ? rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    // product_ids pode repetir uuid (qty); UI lista SKUs únicos + product_quantities.
    final ids = <String>[];
    final seen = <String>{};
    for (final id in rawList) {
      if (seen.add(id)) ids.add(id);
    }
    List<ProductsRow> products = const [];
    List<OrdersRow> bundleOrders = const [];
    if (ids.isNotEmpty) {
      final rows = await ProductsTable().queryRows(
        queryFn: (q) => q.inFilter('id', ids),
        limit: ids.length,
      );
      final byId = {for (final p in rows) if (p.id != null) p.id!: p};
      products = ids.map((id) => byId[id]).whereType<ProductsRow>().toList();
    }
    final bundleStatus = bundle?['status']?.toString() ?? '';
    if (bundleStatus == 'accepted' ||
        bundleStatus == 'cancelled' ||
        bundleStatus == 'purchased' ||
        bundleStatus == 'awaiting_payment') {
      bundleOrders = await OrdersTable().queryRows(
        queryFn: (q) => q.eqOrNull('bundle_id', id),
        limit: 20,
      );
    }
    if (!mounted) return;
    setState(() {
      _bundle = bundle;
      _products = products;
      _bundleOrders = bundleOrders;
    });
  }

  String get _status => _bundle?['status']?.toString() ?? 'pending';

  bool get _pending => _status == 'pending';

  bool get _awaitingPayment => _status == 'awaiting_payment';

  bool get _accepted => _status == 'accepted';

  bool get _cancelled => _status == 'cancelled';

  bool get _expired => _status == 'expired';

  bool get _quoteFlow => isQuoteBeforePayBundle(_bundle);

  bool get _isHistorical {
    if (_cancelled || _expired || _status == 'purchased') return true;
    if (_quoteFlow) return !(_pending || _awaitingPayment);
    return _accepted || _status != 'pending';
  }

  Future<void> _sellerCounter() async {
    if (_busy || !_pending || _products.length < 2) return;
    final bundleId = widget.payload['bundle_id']?.toString();
    if (bundleId == null || bundleId.isEmpty) return;
    final sellerId = widget.payload['seller_id']?.toString() ?? '';
    final quantities = parseBundleQuantitiesFromPayload(
      widget.payload['product_quantities'],
      _products,
    );
    final tiers = await fetchSellerBundleDiscounts(sellerId);
    final suggested =
        (widget.payload['total_eur'] as num?)?.toDouble() ?? 0.0;
    final amount = await showBundleOfferAmountSheet(
      context: context,
      products: _products,
      quantities: quantities,
      tiers: tiers,
      title: 'Contraproposta',
      subtitle: 'Envia um novo valor pelo conjunto ao comprador.',
      initialOfferEur: suggested > 0 ? suggested : null,
    );
    if (amount == null || !mounted) return;
    await _run(() => sellerCounterBundleProposal(
          bundleId: bundleId,
          counterTotalEur: amount,
        ));
  }

  Future<void> _buyerNewOffer() async {
    if (_busy || _products.length < 2) return;
    final sellerId = widget.payload['seller_id']?.toString() ?? '';
    if (sellerId.isEmpty) return;
    final quantities = parseBundleQuantitiesFromPayload(
      widget.payload['product_quantities'],
      _products,
    );
    final tiers = await fetchSellerBundleDiscounts(sellerId);
    final suggested =
        (widget.payload['total_eur'] as num?)?.toDouble() ?? 0.0;
    final amount = await showBundleOfferAmountSheet(
      context: context,
      products: _products,
      quantities: quantities,
      tiers: tiers,
      title: 'Nova oferta',
      subtitle: 'Envia uma nova proposta pelo conjunto.',
      initialOfferEur: suggested > 0 ? suggested : null,
    );
    if (amount == null || !mounted) return;
    // Manter a mesma conversa do pedido (não forceNew).
    final existingChatId = _bundle?['chat_id']?.toString().trim() ?? '';
    await _run(() => createBundlePriceProposal(
          sellerId: sellerId,
          products: _products,
          offeredTotalEur: amount,
          productQuantities: quantities,
          chatIdOverride:
              existingChatId.isEmpty ? null : existingChatId,
        ));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await widget.onUpdated();
      await _load();
    } catch (e, st) {
      final message = '$e';
      final bundleId = widget.payload['bundle_id']?.toString() ?? '';
      final requestMode =
          widget.payload['request_mode']?.toString() ?? 'unknown';
      final buyerId = widget.payload['buyer_id']?.toString() ?? '';
      final sellerId = widget.payload['seller_id']?.toString() ?? '';
      debugPrint(
        '[BUNDLE_PROPOSAL_CARD] _run error request_mode=$requestMode bundleId=$bundleId buyerId=$buyerId sellerId=$sellerId e=$message',
      );
      debugPrint(
        '[BUNDLE_PROPOSAL_CARD] _run stack request_mode=$requestMode bundleId=$bundleId st=$st',
      );
      final isRlsDenied = e is BundleProposalPermissionException ||
          message.contains('42501') ||
          message.contains('codex42501');
      if (isRlsDenied || message.contains('já foi respondido')) {
        await widget.onUpdated();
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRlsDenied
                    ? kBundleCounterRlsUserMessage
                    : 'Este conjunto já foi atualizado no chat.',
              ),
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buyerId = widget.payload['buyer_id']?.toString();
    final sellerId = widget.payload['seller_id']?.toString();
    final requestMode =
        widget.payload['request_mode']?.toString() ?? 'discount';
    final frozen = _isHistorical;
    final total = frozen
        ? (widget.payload['total_eur'] as num?)?.toDouble() ?? 0.0
        : (_bundle?['total_eur'] as num?)?.toDouble() ??
            (widget.payload['total_eur'] as num?)?.toDouble() ??
            0.0;
    final discountEur = frozen
        ? (widget.payload['discount_eur'] as num?)?.toDouble() ?? 0.0
        : (_bundle?['discount_eur'] as num?)?.toDouble() ??
            (widget.payload['discount_eur'] as num?)?.toDouble() ??
            0.0;
    final imBuyer = buyerId == currentUserUid;
    final imSeller = sellerId == currentUserUid;
    final quantities = parseBundleQuantitiesFromPayload(
      widget.payload['product_quantities'],
      _products,
    );

    String headline;
    String? statusBody;
    if (_quoteFlow && _bundle != null) {
      headline = imBuyer
          ? bundleBuyerStatusHeadline(_bundle!)
          : bundleSellerStatusHeadline(_bundle!);
      statusBody = imBuyer
          ? bundleBuyerStatusBody(_bundle!)
          : bundleSellerStatusBody(_bundle!);
    } else if (_accepted) {
      headline = 'Compra em conjunto aceite';
    } else if (_cancelled) {
      headline = _bundleOrders.isNotEmpty
          ? 'Reserva do conjunto cancelada'
          : 'Pedido de conjunto recusado';
    } else if (_expired) {
      headline = 'O pedido expirou. Não foste cobrada.';
    } else if (requestMode == 'prize_addon') {
      headline = imBuyer
          ? 'Pediste juntar estas peças ao envio do prémio.'
          : 'O vencedor quer juntar estas peças ao envio do prémio.';
    } else if (requestMode == 'seller_counter') {
      headline = imSeller
          ? 'Enviaste uma contraproposta de ${formatEuros(total)}.'
          : 'O vendedor contrapropõe ${formatEuros(total)}.';
    } else if (requestMode == 'purchase_request') {
      headline = imBuyer
          ? 'Pediste comprar estes artigos em conjunto.'
          : 'O comprador pretende comprar estes artigos em conjunto.';
    } else {
      headline = imBuyer
          ? 'Enviaste uma proposta de conjunto.'
          : 'Proposta de conjunto · ${formatEuros(total)}';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: frozen ? const Color(0xFFF8FAFB) : Colors.white,
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(
              color: frozen ? const Color(0xFFE0E3E7) : const Color(0xFFB8D5D8),
            ),
            boxShadow: frozen
                ? null
                : [
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
                  headline,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF101518),
                  ),
                ),
                if (statusBody != null && statusBody.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    statusBody,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.35,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                if (_quoteFlow && _awaitingPayment && _bundle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Artigos: ${formatBundleEur(centsToEur(_bundle!['articles_cents']))}\n'
                    'Portes: ${formatBundleEur(centsToEur(_bundle!['shipping_cents']))}\n'
                    'Proteção Fleaber: ${formatBundleEur(centsToEur(_bundle!['protection_cents']))}\n'
                    'Total: ${formatBundleEur(centsToEur(_bundle!['grand_total_cents']))}',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF101518),
                    ),
                  ),
                ],
                if (_products.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final urls = <String>[];
                      for (final p in _products) {
                        final imgs = p.imageUrls;
                        final u = imgs.isNotEmpty ? imgs.first.trim() : '';
                        if (u.isNotEmpty) urls.add(u);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (urls.isNotEmpty) ...[
                            BundleThumbStack(
                              imageUrls: urls,
                              thumbWidth: 44,
                              thumbHeight: 52,
                              stackWidth: 70,
                              stackHeight: 64,
                              offsetX: 14,
                              offsetY: 4,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final p in _products)
                                  Builder(
                                    builder: (_) {
                                      final qty = bundleQuantityForProduct(
                                        quantities,
                                        p,
                                      );
                                      final suffix = qty > 1 ? ' ×$qty' : '';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '• ${p.title ?? 'Artigo'}$suffix',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: const Color(0xFF57636C),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                // Com breakdown de cotação (awaiting_payment) o total já está
                // acima — não repetir «Total negociado» (só artigos).
                if (!_awaitingPayment && (discountEur > 0 || total > 0)) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final view = BundlePriceDisplay.forProposalCard(
                        totalEur: total,
                        discountEur: discountEur,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${view.primaryCaption}: ${view.primaryAmount}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: discountEur > 0
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF57636C),
                            ),
                          ),
                          if (view.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              view.subtitle!,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: const Color(0xFF57636C),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
                if (_quoteFlow && _pending && imSeller) ...[
                  const SizedBox(height: 12),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Confirmar peso e portes',
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final bundleId =
                                  widget.payload['bundle_id']?.toString();
                              if (bundleId == null) return;
                              final ok = await showBundleSellerConfirmQuoteSheet(
                                context: context,
                                bundleId: bundleId,
                                bundleMeta: _bundle,
                              );
                              if (ok) await _load();
                            }),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final bundleId =
                                  widget.payload['bundle_id']?.toString();
                              if (bundleId == null) return;
                              final res = await batataBundleAbandon(
                                bundleId: bundleId,
                                reason: 'seller_cancel',
                              );
                              if (res['ok'] != true) {
                                throw Exception(humanizeBundleQuoteError(res));
                              }
                            }),
                    child: const Text('Recusar pedido'),
                  ),
                ],
                if (_quoteFlow &&
                    (_pending || _awaitingPayment) &&
                    imBuyer) ...[
                  const SizedBox(height: 12),
                  if (_awaitingPayment)
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Pagar',
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                final bundleId =
                                    widget.payload['bundle_id']?.toString();
                                if (bundleId == null) return;
                                try {
                                  await payQuotedBundleCheckout(
                                    bundleId: bundleId,
                                  );
                                } catch (e) {
                                  final msg = e.toString();
                                  if (msg.contains('já não está disponível') ||
                                      msg.contains('quote_invalid') ||
                                      msg.contains('article_unavailable')) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Este conjunto já não está disponível '
                                            'nas condições anteriores.',
                                          ),
                                        ),
                                      );
                                    }
                                    await _load();
                                    return;
                                  }
                                  rethrow;
                                }
                              }),
                    ),
                  if (_awaitingPayment) const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final bundleId =
                                  widget.payload['bundle_id']?.toString();
                              if (bundleId == null) return;
                              final res = await batataBundleAbandon(
                                bundleId: bundleId,
                                reason: 'buyer_abandon',
                              );
                              if (res['ok'] != true) {
                                throw Exception(humanizeBundleQuoteError(res));
                              }
                            }),
                    child: const Text('Desistir'),
                  ),
                ],
                if (!_quoteFlow && _pending && imSeller) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final bundleId =
                                        widget.payload['bundle_id']?.toString();
                                    if (bundleId == null) return;
                                    await rejectBundleProposal(
                                      bundleId: bundleId,
                                    );
                                  }),
                          child: const Text('Recusar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _sellerCounter,
                          child: const Text('Contrapropor'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Aceitar',
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final bundleId =
                                  widget.payload['bundle_id']?.toString();
                              if (bundleId == null) return;
                              final prizeOrderId = widget.payload['prize_order_id']
                                      ?.toString()
                                      .trim() ??
                                  '';
                              if (prizeOrderId.isNotEmpty ||
                                  (widget.payload['request_mode']?.toString() ==
                                      'prize_addon')) {
                                await acceptPrizeAddonBundleProposal(
                                  bundleId: bundleId,
                                  prizeOrderId: prizeOrderId,
                                );
                              } else {
                                await acceptBundleProposal(bundleId: bundleId);
                              }
                            }),
                  ),
                ],
                if (!_quoteFlow && _accepted && imBuyer) ...[
                  const SizedBox(height: 10),
                  Text(
                    bundleOrdersDirectPaymentPending(_bundleOrders)
                        ? 'Pagamento directo escolhido — usa «Ver dados de pagamento» '
                            'e «Confirmo pagamento» no topo do chat.'
                        : bundleOrdersAwaitingCheckoutChoice(_bundleOrders)
                            ? 'Usa «Concluir compra» no topo do chat para escolher '
                                'envio e pagamento.'
                            : 'Segue os passos no topo do chat para concluir o conjunto.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.35,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                if (!_quoteFlow &&
                    _pending &&
                    imBuyer &&
                    requestMode == 'seller_counter') ...[
                  const SizedBox(height: 10),
                  Text(
                    'O vendedor enviou uma contraproposta.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Aceitar contraproposta',
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final bundleId =
                                  widget.payload['bundle_id']?.toString();
                              if (bundleId == null) return;
                              final prizeOrderId = widget.payload['prize_order_id']
                                      ?.toString()
                                      .trim() ??
                                  '';
                              if (prizeOrderId.isNotEmpty ||
                                  (widget.payload['request_mode']?.toString() ==
                                      'prize_addon')) {
                                await acceptPrizeAddonBundleProposal(
                                  bundleId: bundleId,
                                  prizeOrderId: prizeOrderId,
                                  buyerAccepts: true,
                                );
                              } else {
                                await buyerAcceptBundleProposal(
                                  bundleId: bundleId,
                                );
                              }
                            }),
                  ),
                ],
                if (!_quoteFlow &&
                    _pending &&
                    imBuyer &&
                    requestMode != 'seller_counter') ...[
                  const SizedBox(height: 10),
                  Text(
                    'Aguarda resposta do vendedor.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                if ((_cancelled || _expired) && imBuyer) ...[
                  const SizedBox(height: 12),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Nova oferta',
                    onPressed: _busy ? null : _buyerNewOffer,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
