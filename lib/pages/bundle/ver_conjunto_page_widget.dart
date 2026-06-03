import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/batata_bundle_discounts.dart';
import '/chat_session_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

class VerConjuntoPageWidget extends StatefulWidget {
  const VerConjuntoPageWidget({
    super.key,
    required this.sellerId,
    required this.productIdsCsv,
  });

  final String sellerId;
  final String productIdsCsv;

  static String routeName = 'VerConjunto';
  static String routePath = '/verConjunto';

  @override
  State<VerConjuntoPageWidget> createState() => _VerConjuntoPageWidgetState();
}

class _VerConjuntoPageWidgetState extends State<VerConjuntoPageWidget> {
  bool _loading = true;
  List<ProductsRow> _products = [];
  BundleDiscountTiers _tiers = const BundleDiscountTiers();

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
    if (!mounted) return;
    setState(() {
      _products = ordered;
      _tiers = tiers;
      _loading = false;
    });
  }

  Future<void> _sendProposal() async {
    try {
      final result = await createBundleProposal(
        sellerId: widget.sellerId,
        products: _products,
        tiers: _tiers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta de conjunto enviada no chat.')),
      );
      final chatId = result['chat_id']?.toString() ?? '';
      if (chatId.isNotEmpty) {
        context.pushNamed(
          ChatPageWidget.routeName,
          queryParameters: {
            'chatId': serializeParam(chatId, ParamType.String),
            'otherUserId': serializeParam(widget.sellerId, ParamType.String),
          }.withoutNulls,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openChat() async {
    if (_products.isEmpty) return;
    final chat = await ensureSellerChat(
      otherUserId: widget.sellerId,
      productId: _products.first.id,
    );
    if (!mounted) return;
    context.pushNamed(
      ChatPageWidget.routeName,
      queryParameters: {
        'chatId': serializeParam(chat.id, ParamType.String),
        'otherUserId': serializeParam(widget.sellerId, ParamType.String),
      }.withoutNulls,
    );
  }

  void _buyBundle() {
    if (_products.isEmpty) return;
    final totals = calculateBundleTotals(products: _products, tiers: _tiers);
    final first = _products.first;
    context.push(
      ProductDetailsPageWidget.routePath,
      extra: {
        ...ProductDetailsPageWidget.routeExtraForProduct(first),
        ProductDetailsPageWidget.routeExtraOpenCheckoutKey: true,
        ProductDetailsPageWidget.routeExtraAgreedOfferPriceKey: totals.total,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateBundleTotals(products: _products, tiers: _tiers);
    final protection = calculateFleaberProtectionFee(totals.total);
    const shipping = 1.95;
    final grandTotal = totals.total + protection + shipping;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
        title: Text(
          'Ver o conjunto',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: FleaberColors.teal))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '${_products.length} artigos',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final p = _products[i];
                            final url =
                                p.imageUrls.isNotEmpty ? p.imageUrls.first : null;
                            return ClipRRect(
                              borderRadius: FleaberRadius.circularSm,
                              child: SizedBox(
                                width: 56,
                                height: 72,
                                child: url != null
                                    ? BatataCachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                      )
                                    : const ColoredBox(color: Color(0xFFE0E3E7)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      _priceLine('Preço', formatEuros(totals.subtotal)),
                      _priceLine(
                        'Taxa de Proteção do Comprador',
                        formatEuros(protection),
                      ),
                      _priceLine('Custos de envio', formatEuros(shipping)),
                      if (totals.discountEur > 0)
                        _priceLine(
                          'Desconto de conjunto (${totals.discountPct.toStringAsFixed(0)}%)',
                          '- ${formatEuros(totals.discountEur)}',
                          valueColor: const Color(0xFF2E7D32),
                        ),
                      const Divider(height: 28),
                      _priceLine('Total', formatEuros(grandTotal), bold: true),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      children: [
                        if (currentUserUid != widget.sellerId)
                          OutlinedButton(
                            onPressed: _products.isEmpty ? null : _sendProposal,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 46),
                              foregroundColor: FleaberColors.teal,
                              side: const BorderSide(color: FleaberColors.teal),
                            ),
                            child: const Text('Enviar proposta no chat'),
                          ),
                        if (currentUserUid != widget.sellerId)
                          const SizedBox(height: 10),
                        FleaberPrimaryButton(
                          width: double.infinity,
                          label: 'Comprar agora',
                          onPressed: _products.isEmpty ? null : _buyBundle,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _openChat,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: FleaberColors.teal,
                                  side: const BorderSide(color: FleaberColors.teal),
                                ),
                                child: const Text('Perguntar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _openChat,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: FleaberColors.teal,
                                  side: const BorderSide(color: FleaberColors.teal),
                                ),
                                child: const Text('Fazer proposta'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
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
