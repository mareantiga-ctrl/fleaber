import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/index.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_product_qty_stepper.dart';
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
  static const double _kHubBreakpoint = 1024;
  static const double _kCompactCardMinWidth = 700;
  static const double _kDesktopMaxWidth = 1100;
  static const double _kCardWidth = 156;
  /// Slot fixo do stepper — evita saltos de altura ao seleccionar.
  static const double _kQtySlotHeight = 34;
  static const double _kActionBtnHeight = 34;

  bool _loading = true;
  BundleDiscountTiers _tiers = const BundleDiscountTiers();
  List<ProductsRow> _products = [];
  final Set<String> _selected = {};
  final Map<String, int> _quantities = {};

  bool get _useHubChrome =>
      kIsWeb && MediaQuery.sizeOf(context).width >= _kHubBreakpoint;

  bool get _useFixedCardGrid =>
      kIsWeb && MediaQuery.sizeOf(context).width >= _kCompactCardMinWidth;

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
        ProductsRow? match;
        for (final r in rows) {
          if (r.id == init) {
            match = r;
            break;
          }
        }
        final maxQ = (match?.quantity ?? 1).clamp(1, 999);
        _quantities[init] = maxQ >= 1 ? 1 : 1;
      }
    });
  }

  List<ProductsRow> get _selectedProducts => _products
      .where((p) => p.id != null && _selected.contains(p.id))
      .toList();

  int _stockFor(ProductsRow p) {
    final q = p.quantity;
    if (q < 1) return 1;
    return q.clamp(1, 999);
  }

  int _qtyFor(String id, ProductsRow p) {
    final maxQ = _stockFor(p);
    return (_quantities[id] ?? 1).clamp(1, maxQ);
  }

  /// Primeira URL de imagem utilizável (normalizada no web).
  String? _thumbUrl(ProductsRow p) {
    for (final raw in p.imageUrls) {
      final n = normalizeProductImageUrl(raw);
      if (n != null && n.trim().isNotEmpty) return n;
    }
    return null;
  }

  static Widget _photoPlaceholder() {
    return const ColoredBox(
      color: Color(0xFFF1F4F8),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Color(0xFF9AA5B1),
          size: 32,
        ),
      ),
    );
  }

  BundleProductQuantities _quantitiesForSelected() {
    final out = <String, int>{};
    for (final p in _selectedProducts) {
      final id = p.id;
      if (id == null || id.isEmpty) continue;
      out[id] = _qtyFor(id, p);
    }
    return out;
  }

  int get _selectedUnitCount {
    var n = 0;
    for (final p in _selectedProducts) {
      final id = p.id;
      if (id == null) continue;
      n += _qtyFor(id, p);
    }
    return n;
  }

  void _addProduct(String id, ProductsRow p) {
    if (id.isEmpty) return;
    setState(() {
      _selected.add(id);
      // Sempre começa em 1 ao adicionar (nunca herda 0).
      _quantities[id] = 1.clamp(1, _stockFor(p));
    });
  }

  void _removeProduct(String id) {
    if (id.isEmpty) return;
    setState(() {
      _selected.remove(id);
      _quantities.remove(id);
    });
  }

  /// Qty unificada: 0 = retirar (igual a «Retirar»); 1..stock = actualizar.
  void _setQty(String id, ProductsRow p, int qty) {
    if (id.isEmpty) return;
    if (qty <= 0) {
      _removeProduct(id);
      return;
    }
    final maxQ = _stockFor(p);
    setState(() {
      if (!_selected.contains(id)) _selected.add(id);
      _quantities[id] = qty.clamp(1, maxQ);
    });
  }

  Future<void> _openVerConjunto() async {
    if (_selected.length < 2) return;
    final result = await context.pushNamed(
      VerConjuntoPageWidget.routeName,
      queryParameters: {
        'sellerId': serializeParam(widget.sellerId, ParamType.String),
        'productIds': serializeParam(_selected.join(','), ParamType.String),
        'quantities': serializeParam(
          encodeBundleQuantitiesCsv(_quantitiesForSelected()),
          ParamType.String,
        ),
      },
    );
    if (!mounted || result is! Map) return;
    final idsCsv = result['productIds']?.toString() ?? '';
    final qtyCsv = result['quantities']?.toString();
    final ids = idsCsv
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final parsed = parseBundleQuantitiesCsv(qtyCsv);
    setState(() {
      _selected
        ..clear()
        ..addAll(ids);
      _quantities
        ..clear()
        ..addAll(parsed);
      for (final id in ids) {
        _quantities.putIfAbsent(id, () => 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateBundleTotals(
      products: _selectedProducts,
      tiers: _tiers,
      quantitiesByProductId: _quantitiesForSelected(),
    );

    if (_useHubChrome) {
      return FleaHubSiteScaffold(
        body: _loading
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: CircularProgressIndicator(color: FleaberColors.teal),
                ),
              )
            : _buildWideBody(totals, hub: true),
      );
    }

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
          ? const Center(
              child: CircularProgressIndicator(color: FleaberColors.teal),
            )
          : (_useFixedCardGrid
              ? _buildWideBody(totals, hub: false)
              : _buildPhoneBody(totals)),
    );
  }

  Widget _buildPhoneBody(
    ({double subtotal, double discountPct, double discountEur, double total})
        totals,
  ) {
    return Column(
      children: [
        if (totals.discountEur > 0) _savingsBanner(totals),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              // Folga para título 2 linhas + preço + slot qty + botão.
              childAspectRatio: 0.48,
            ),
            itemCount: _products.length,
            itemBuilder: (context, i) => _buildProductTile(
              _products[i],
              fixedWidth: false,
            ),
          ),
        ),
        _bottomBar(totals),
      ],
    );
  }

  Widget _buildWideBody(
    ({double subtotal, double discountPct, double discountEur, double total})
        totals, {
    required bool hub,
  }) {
    final pad = hub
        ? FleaHubSiteLayout.pagePadding(context)
        : const EdgeInsets.symmetric(horizontal: 16);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad.left, hub ? 8 : 4, pad.right, 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDesktopMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hub) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => context.safePop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          Text(
                            'Cria um conjunto',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              color: const Color(0xFF101518),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '· ${_selected.length} seleccionados'
                            '${_selectedUnitCount > _selected.length ? ' ($_selectedUnitCount un.)' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: const Color(0xFF57636C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${_selected.length} seleccionados'
                          '${_selectedUnitCount > _selected.length ? ' · $_selectedUnitCount un.' : ''}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF57636C),
                          ),
                        ),
                      ),
                    if (totals.discountEur > 0) ...[
                      _savingsBanner(totals),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      'Escolhe pelo menos 2 artigos do mesmo vendedor.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          'Sem artigos disponíveis para conjunto.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF57636C),
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 14,
                        alignment: WrapAlignment.start,
                        children: [
                          for (final p in _products)
                            SizedBox(
                              width: _kCardWidth,
                              child: _buildProductTile(p, fixedWidth: true),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _bottomBar(totals),
      ],
    );
  }

  Widget _savingsBanner(
    ({double subtotal, double discountPct, double discountEur, double total})
        totals,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE8F5E9),
      child: Text(
        '${totals.discountPct.toStringAsFixed(0)}% de desconto aplicado. Poupas ${formatEuros(totals.discountEur)}',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2E7D32),
        ),
      ),
    );
  }

  Widget _bottomBar(
    ({double subtotal, double discountPct, double discountEur, double total})
        totals,
  ) {
    return SafeArea(
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
                  Text(
                    'Subtotal dos artigos',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                  const SizedBox(height: 2),
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
                      color: const Color(0xFF101518),
                    ),
                  ),
                  if (_selected.length < 2) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Selecciona pelo menos 2 artigos',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF8A8D93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            FleaberPrimaryButton(
              label: 'Ver conjunto',
              maxLines: 1,
              width: 148,
              fontSize: 14,
              onPressed: _selected.length < 2 ? null : _openVerConjunto,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTile(ProductsRow p, {required bool fixedWidth}) {
    final id = p.id ?? '';
    final selected = _selected.contains(id);
    final thumb = _thumbUrl(p);
    final maxQ = _stockFor(p);
    final qty = selected ? _qtyFor(id, p) : 0;

    final photo = AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(fixedWidth ? 10 : 12),
            child: thumb != null
                ? BatataCachedNetworkImage(
                    imageUrl: thumb,
                    fit: BoxFit.cover,
                    maxWidth: 480,
                    errorWidget: _photoPlaceholder(),
                  )
                : _photoPlaceholder(),
          ),
          // Só a foto selecciona / adiciona — não envolve o stepper.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: id.isEmpty
                    ? null
                    : () {
                        if (selected) {
                          // Foto com seleccionado: não remove (só «Retirar»).
                          return;
                        }
                        _addProduct(id, p);
                      },
                borderRadius: BorderRadius.circular(fixedWidth ? 10 : 12),
              ),
            ),
          ),
          if (selected)
            const Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: FleaberColors.teal,
                ),
              ),
            ),
        ],
      ),
    );

    final details = Padding(
      padding: EdgeInsets.fromLTRB(fixedWidth ? 6 : 8, 8, fixedWidth ? 6 : 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                p.title ?? 'Artigo',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                formatEuros(p.price ?? 0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.2,
                  color: FleaberColors.teal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _kQtySlotHeight,
            child: Center(
              child: BundleProductQtyStepper(
                compact: true,
                quantity: qty,
                maxQuantity: maxQ,
                // qty 0 + stock → `+` activo (sem precisar de «Adicionar»).
                enabled: maxQ >= 1 && id.isNotEmpty,
                allowZero: true,
                onChanged: (v) => _setQty(id, p, v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _kActionBtnHeight,
            child: OutlinedButton(
              onPressed: id.isEmpty
                  ? null
                  : () {
                      if (selected) {
                        _removeProduct(id);
                      } else {
                        _addProduct(id, p);
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: FleaberColors.teal,
                side: const BorderSide(color: FleaberColors.teal),
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, _kActionBtnHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: FleaberRadius.circularMd,
                ),
              ),
              child: Text(
                selected ? 'Retirar' : 'Adicionar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final card = Material(
      color: FleaberColors.bgTint,
      borderRadius: FleaberRadius.circularMd,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fixedWidth)
            photo
          else
            Expanded(child: photo),
          details,
        ],
      ),
    );

    // Largura de borda fixa (2) — evita salto de layout ao seleccionar.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: selected ? FleaberColors.teal : const Color(0xFFE0E6EB),
          width: 2,
        ),
      ),
      child: card,
    );
  }
}
