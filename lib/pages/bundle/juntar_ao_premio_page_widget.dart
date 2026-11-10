import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/batata_bundle_actions.dart';
import '/batata_bundle_discounts.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_product_qty_stepper.dart';
import '/widgets/fleaber_primary_button.dart';

/// Página gémea de «Criar conjunto»: o vencedor da rifa escolhe artigos da
/// loja para pedir juntos no mesmo envio do prémio (mesmo chat).
class JuntarAoPremioPageWidget extends StatefulWidget {
  const JuntarAoPremioPageWidget({
    super.key,
    required this.sellerId,
    required this.chatId,
    required this.prizeOrderId,
    this.prizeProductId,
  });

  final String sellerId;
  final String chatId;
  final String prizeOrderId;
  final String? prizeProductId;

  static String routeName = 'JuntarAoPremio';
  static String routePath = '/juntarAoPremio';

  @override
  State<JuntarAoPremioPageWidget> createState() =>
      _JuntarAoPremioPageWidgetState();
}

class _JuntarAoPremioPageWidgetState extends State<JuntarAoPremioPageWidget> {
  bool _loading = true;
  bool _buying = false;
  bool _proposing = false;
  BundleDiscountTiers _tiers = const BundleDiscountTiers();
  List<ProductsRow> _products = [];
  final Set<String> _selected = {};
  final Map<String, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sid = widget.sellerId.trim();
    final prizePid = widget.prizeProductId?.trim() ?? '';
    final tiers = await fetchSellerBundleDiscounts(sid);
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eq('list_on_marketplace', true)
          .eq('is_sold', false)
          .order('created_at', ascending: false),
      limit: 60,
    );
    final filtered = rows.where((p) {
      final id = p.id?.trim() ?? '';
      if (id.isEmpty) return false;
      if (prizePid.isNotEmpty && id == prizePid) return false;
      if (p.quantity <= 0) return false;
      return true;
    }).toList();
    if (!mounted) return;
    setState(() {
      _tiers = tiers;
      _products = filtered;
      _loading = false;
    });
  }

  List<ProductsRow> get _selectedProducts => _products
      .where((p) => p.id != null && _selected.contains(p.id))
      .toList();

  BundleProductQuantities _quantitiesForSelected() {
    final out = <String, int>{};
    for (final p in _selectedProducts) {
      final id = p.id;
      if (id == null || id.isEmpty) continue;
      out[id] = _quantities[id] ?? 1;
    }
    return out;
  }

  void _toggleSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selected.remove(id);
        _quantities.remove(id);
      } else {
        _selected.add(id);
        _quantities.putIfAbsent(id, () => 1);
      }
    });
  }

  Future<void> _buyNow() async {
    if (_buying || _selected.isEmpty) return;
    setState(() => _buying = true);
    try {
      await payBundleNow(
        sellerId: widget.sellerId,
        products: _selectedProducts,
        tiers: _tiers,
        productQuantities: _quantitiesForSelected(),
        minProducts: 1,
        chatId: widget.chatId,
        prizeOrderId: widget.prizeOrderId,
        // Peças extra no mesmo pacote do prémio — sem portes duplicados.
        shippingEurOverride: 0,
        shippingMethodOverride: 'Mesmo envio do Prémio da Rifa',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checkout aberto. Após pagares, estas peças vão no mesmo envio do prémio.',
          ),
        ),
      );
      context.safePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<double?> _askOfferAmount(double suggested) async {
    final controller = TextEditingController(
      text: suggested > 0 ? suggested.toStringAsFixed(2) : '',
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Fazer oferta',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '€ ',
              hintText: 'Valor que ofereces',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FleaberColors.teal,
              ),
              onPressed: () {
                final raw = controller.text.trim().replaceAll(',', '.');
                final parsed = double.tryParse(raw);
                if (parsed == null || parsed <= 0) return;
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return amount;
  }

  Future<void> _makeOffer() async {
    if (_proposing || _selected.isEmpty) return;
    final totals = calculateBundleTotals(
      products: _selectedProducts,
      tiers: _tiers,
      quantitiesByProductId: _quantitiesForSelected(),
    );
    final amount = await _askOfferAmount(totals.total);
    if (amount == null || !mounted) return;
    setState(() => _proposing = true);
    try {
      await createBundlePriceProposal(
        sellerId: widget.sellerId,
        products: _selectedProducts,
        offeredTotalEur: amount,
        productQuantities: _quantitiesForSelected(),
        chatIdOverride: widget.chatId,
        skipSupersede: true,
        minProducts: 1,
        prizeOrderId: widget.prizeOrderId,
        requestMode: 'prize_addon',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Oferta de ${formatEuros(amount)} enviada. '
            'A vendedora tem de aceitar.',
          ),
        ),
      );
      context.safePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _proposing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateBundleTotals(
      products: _selectedProducts,
      tiers: _tiers,
      quantitiesByProductId: _quantitiesForSelected(),
    );
    final savings = totals.discountEur;
    final busy = _buying || _proposing;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF101518)),
          onPressed: () => context.safePop(),
        ),
        title: Text(
          'Juntar ao envio do prémio',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FleaberColors.teal),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFFFFF8E1),
                  child: Text(
                    'Escolhe artigos desta loja. Depois de a vendedora aceitar, '
                    'pagas só estas peças — o prémio continua grátis e pode ir '
                    'tudo no mesmo pacote.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5D4037),
                    ),
                  ),
                ),
                if (savings > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: const Color(0xFFE8F5E9),
                    child: Text(
                      '${totals.discountPct.toStringAsFixed(0)}% de desconto. '
                      'Poupas ${formatEuros(savings)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                Expanded(
                  child: _products.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Esta vendedora não tem outros artigos '
                              'disponíveis na loja neste momento.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: const Color(0xFF57636C),
                              ),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.52,
                          ),
                          itemCount: _products.length,
                          itemBuilder: (context, i) {
                            final p = _products[i];
                            final id = p.id ?? '';
                            final selected = _selected.contains(id);
                            final thumb = p.imageUrls.isNotEmpty
                                ? p.imageUrls.first
                                : null;
                            return Material(
                              color: FleaberColors.bgTint,
                              borderRadius: FleaberRadius.circularMd,
                              child: InkWell(
                                onTap: id.isEmpty
                                    ? null
                                    : () => _toggleSelected(id, selected),
                                borderRadius: FleaberRadius.circularMd,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                              top: Radius.circular(12),
                                            ),
                                            child: thumb != null
                                                ? BatataCachedNetworkImage(
                                                    imageUrl: thumb,
                                                    fit: BoxFit.cover,
                                                  )
                                                : const ColoredBox(
                                                    color: Color(0xFFE0E3E7),
                                                  ),
                                          ),
                                          if (selected)
                                            const Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Icon(
                                                Icons.check_circle_rounded,
                                                color: FleaberColors.teal,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        6,
                                        8,
                                        8,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            p.title ?? 'Artigo',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            formatEuros(p.price ?? 0),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: FleaberColors.teal,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          if (selected)
                                            Center(
                                              child: BundleProductQtyStepper(
                                                compact: true,
                                                quantity: _quantities[id] ?? 1,
                                                maxQuantity:
                                                    p.quantity.clamp(1, 999),
                                                onChanged: (v) {
                                                  setState(
                                                    () => _quantities[id] = v,
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Color(0xFFE0E3E7))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selected.isEmpty
                                        ? 'Escolhe artigos'
                                        : '${_selected.length} no pedido',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFF57636C),
                                    ),
                                  ),
                                  Text(
                                    formatEuros(totals.total),
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FleaberPrimaryButton(
                          width: double.infinity,
                          label: 'Comprar',
                          loading: _buying,
                          onPressed: _selected.isEmpty || busy
                              ? null
                              : _buyNow,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _selected.isEmpty || busy
                              ? null
                              : _makeOffer,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FleaberColors.teal,
                            side: const BorderSide(color: FleaberColors.teal),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _proposing ? 'A enviar…' : 'Fazer oferta',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
