import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/product_details/product_details_page_widget.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/bundle_thumb_stack.dart';

/// Resumo «Conjunto · N artigos» com thumbs empilhadas e lista expandível clicável.
class BundleExpandableSummary extends StatefulWidget {
  const BundleExpandableSummary({
    super.key,
    required this.orders,
    required this.productsById,
    required this.totalLabel,
    this.totalCaption = 'Total pago',
    this.statusPhrase,
    this.subtitle,
    this.expanded,
    this.onExpandedChanged,
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFE0E3E7),
    this.padding = const EdgeInsets.all(12),
  });

  final List<OrdersRow> orders;
  final Map<String, ProductsRow> productsById;
  final String totalLabel;
  final String totalCaption;
  final String? statusPhrase;
  final String? subtitle;
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsets padding;

  @override
  State<BundleExpandableSummary> createState() =>
      _BundleExpandableSummaryState();
}

class _BundleExpandableSummaryState extends State<BundleExpandableSummary> {
  bool _internalExpanded = false;

  bool get _expanded => widget.expanded ?? _internalExpanded;

  void _toggleExpanded() {
    final next = !_expanded;
    if (widget.onExpandedChanged != null) {
      widget.onExpandedChanged!(next);
    } else {
      setState(() => _internalExpanded = next);
    }
  }

  List<String> get _thumbUrls {
    final urls = <String>[];
    for (final o in widget.orders) {
      final p =
          o.productId != null ? widget.productsById[o.productId!] : null;
      final list = p?.imageUrls ?? const <String>[];
      if (list.isNotEmpty && list.first.isNotEmpty) urls.add(list.first);
    }
    return urls;
  }

  Future<void> _openProduct(ProductsRow? product, String? productId) async {
    final pid = (product?.id ?? productId)?.trim();
    if (pid == null || pid.isEmpty) return;
    final p = product;
    if (p != null && (p.id ?? '').trim().isNotEmpty) {
      await context.push(
        ProductDetailsPageWidget.routePath,
        extra: ProductDetailsPageWidget.routeExtraForProduct(p),
      );
      return;
    }
    await context.push(
      '${ProductDetailsPageWidget.routePath}?product_id=${Uri.encodeComponent(pid)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.orders.fold<int>(
      0,
      (sum, o) => sum + (o.quantity ?? 1),
    );
    const teal = Color(0xFF007782);

    return Material(
      color: widget.backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FleaberRadius.circularMd,
        side: BorderSide(color: widget.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: FleaberRadius.circularMd,
            child: Padding(
              padding: widget.padding,
              child: Row(
                children: [
                  BundleThumbStack(imageUrls: _thumbUrls),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conjunto · $count artigos',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: const Color(0xFF101518),
                          ),
                        ),
                        if (widget.statusPhrase != null &&
                            widget.statusPhrase!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.statusPhrase!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF007782),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${widget.totalCaption}: ${widget.totalLabel}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: teal,
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF57636C),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF57636C),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Container(
              color: const Color(0xFFF4F7F8),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: widget.orders.map((o) {
                  final product = o.productId != null
                      ? widget.productsById[o.productId!]
                      : null;
                  final title = product?.title ?? 'Artigo';
                  final lineQty = o.quantity ?? 1;
                  final displayTitle = lineQty > 1 ? '$title ×$lineQty' : title;
                  final url = product?.imageUrls.isNotEmpty == true
                      ? product!.imageUrls.first
                      : null;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: FleaberRadius.circularSm,
                        border: Border.all(color: const Color(0xFFE8ECF0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openProduct(product, o.productId),
                              child: ClipRRect(
                                borderRadius: FleaberRadius.circularSm,
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: url != null
                                      ? BatataCachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.cover,
                                          placeholderColor:
                                              const Color(0xFFF1F4F8),
                                        )
                                      : ColoredBox(
                                          color: const Color(0xFFF1F4F8),
                                          child: Icon(
                                            Icons.inventory_2_outlined,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      _openProduct(product, o.productId),
                                  child: Text(
                                    displayTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: const Color(0xFF101518),
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
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
