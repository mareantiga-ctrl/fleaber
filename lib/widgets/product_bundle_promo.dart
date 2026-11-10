import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

/// Secção «Comprar conjuntos» (estilo Vinted) no detalhe do artigo.
class ProductBundlePromo extends StatelessWidget {
  const ProductBundlePromo({
    super.key,
    required this.sellerId,
    required this.currentProductId,
  });

  final String sellerId;
  final String currentProductId;

  @override
  Widget build(BuildContext context) {
    if (sellerId.isEmpty || sellerId == currentUserUid) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<({BundleDiscountTiers tiers, int count})>(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data = snap.data!;
        if (!data.tiers.enabled || data.count < 2) {
          return const SizedBox.shrink();
        }
        final maxPct = maxDiscountPercent(data.tiers);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comprar conjuntos',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: const Color(0xFF101518),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      maxPct != null
                          ? 'Obtém até $maxPct% de desconto'
                          : 'Desconto ao comprar vários artigos',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  context.pushNamed(
                    CriarConjuntoPageWidget.routeName,
                    queryParameters: {
                      'sellerId': serializeParam(sellerId, ParamType.String),
                      'initialProductId': serializeParam(
                        currentProductId,
                        ParamType.String,
                      ),
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
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<({BundleDiscountTiers tiers, int count})> _load() async {
    final tiers = await fetchSellerBundleDiscounts(sellerId);
    final rows = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sellerId)
          .eq('list_on_marketplace', true)
          .eq('is_sold', false),
      limit: 5,
    );
    return (tiers: tiers, count: rows.length);
  }
}
