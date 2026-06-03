import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

class CriarConjuntoPageWidget extends StatefulWidget {
  const CriarConjuntoPageWidget({
    super.key,
    required this.sellerId,
    this.initialProductId,
  });

  final String sellerId;
  final String? initialProductId;

  static String routeName = 'CriarConjunto';
  static String routePath = '/criarConjunto';

  @override
  State<CriarConjuntoPageWidget> createState() => _CriarConjuntoPageWidgetState();
}

class _CriarConjuntoPageWidgetState extends State<CriarConjuntoPageWidget> {
  bool _loading = true;
  BundleDiscountTiers _tiers = const BundleDiscountTiers();
  List<ProductsRow> _products = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sid = widget.sellerId;
    final tiers = await fetchSellerBundleDiscounts(sid);
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eq('list_on_marketplace', true)
          .eq('is_sold', false)
          .order('created_at', ascending: false),
      limit: 40,
    );
    if (!mounted) return;
    setState(() {
      _tiers = tiers;
      _products = rows;
      _loading = false;
      final init = widget.initialProductId?.trim();
      if (init != null && init.isNotEmpty) {
        _selected.add(init);
      }
    });
  }

  List<ProductsRow> get _selectedProducts => _products
      .where((p) => p.id != null && _selected.contains(p.id))
      .toList();

  @override
  Widget build(BuildContext context) {
    final totals = calculateBundleTotals(
      products: _selectedProducts,
      tiers: _tiers,
    );
    final savings = totals.discountEur;

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
          'Cria um conjunto',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: FleaberColors.teal))
          : Column(
              children: [
                if (savings > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFE8F5E9),
                    child: Text(
                      '${totals.discountPct.toStringAsFixed(0)}% de desconto aplicado. Poupas ${formatEuros(savings)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                      final thumb = p.imageUrls.isNotEmpty ? p.imageUrls.first : null;
                      return Material(
                        color: FleaberColors.bgTint,
                        borderRadius: FleaberRadius.circularMd,
                        child: InkWell(
                          onTap: id.isEmpty
                              ? null
                              : () => setState(() {
                                    if (selected) {
                                      _selected.remove(id);
                                    } else {
                                      _selected.add(id);
                                    }
                                  }),
                          borderRadius: FleaberRadius.circularMd,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
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
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    const SizedBox(height: 4),
                                    Text(
                                      formatEuros(p.price ?? 0),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: FleaberColors.teal,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton(
                                      onPressed: id.isEmpty
                                          ? null
                                          : () => setState(() {
                                                if (selected) {
                                                  _selected.remove(id);
                                                } else {
                                                  _selected.add(id);
                                                }
                                              }),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: FleaberColors.teal,
                                        side: const BorderSide(
                                          color: FleaberColors.teal,
                                        ),
                                        backgroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        minimumSize: const Size(0, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        selected ? 'Retirar' : 'Adicionar',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
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
                      border: Border(top: BorderSide(color: Color(0xFFE0E3E7))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (totals.subtotal > totals.total)
                                Text(
                                  formatEuros(totals.subtotal),
                                  style: GoogleFonts.inter(
                                    decoration: TextDecoration.lineThrough,
                                    color: const Color(0xFF8A8D93),
                                    fontSize: 12,
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
                        FleaberPrimaryButton(
                          label: 'Ver o conjunto',
                          onPressed: _selected.length < 2
                              ? null
                              : () {
                                  context.pushNamed(
                                    VerConjuntoPageWidget.routeName,
                                    queryParameters: {
                                      'sellerId': serializeParam(
                                        widget.sellerId,
                                        ParamType.String,
                                      ),
                                      'productIds': serializeParam(
                                        _selected.join(','),
                                        ParamType.String,
                                      ),
                                    },
                                  );
                                },
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
