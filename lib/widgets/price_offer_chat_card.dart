import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/batata_offer_actions.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/product_details/product_details_page_widget.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/product_offer_sheet.dart';

/// Card de proposta de preço no chat (comprador / vendedor).
class PriceOfferChatCard extends StatefulWidget {
  const PriceOfferChatCard({
    super.key,
    required this.payload,
    required this.allMessages,
    required this.messageId,
    this.product,
    required this.onUpdated,
  });

  final Map<String, dynamic> payload;
  final List<ChatMessagesRow> allMessages;
  final String? messageId;
  final ProductsRow? product;
  final VoidCallback onUpdated;

  @override
  State<PriceOfferChatCard> createState() => _PriceOfferChatCardState();
}

class _PriceOfferChatCardState extends State<PriceOfferChatCard> {
  bool _busy = false;
  ProductOffersRow? _offer;

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  Future<void> _loadOffer() async {
    final id = widget.payload['offer_id']?.toString();
    if (id == null || id.isEmpty) return;
    final row = await fetchProductOffer(id);
    if (mounted) setState(() => _offer = row);
  }

  bool get _resolved {
    final offerId = widget.payload['offer_id']?.toString();
    if (offerId == null) return true;
    if (offerOutcomeExistsAfterMessages(
      messages: widget.allMessages,
      afterMessageId: widget.messageId,
      offerId: offerId,
    )) {
      return true;
    }
    final st = _offer?.status;
    return st != null && st != 'pending';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      widget.onUpdated();
      await _loadOffer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counter(String offeredBy) async {
    final p = widget.product;
    if (p == null) return;
    final offer = _offer;
    if (offer == null) return;

    final amount = await showProductOfferAmountSheet(
      context: context,
      product: p,
      title: offeredBy == 'seller' ? 'Contra-proposta' : 'Nova proposta',
      subtitle: offeredBy == 'seller'
          ? 'Envia um preço ao comprador.'
          : 'Envia um novo valor ao vendedor.',
    );
    if (amount == null || !mounted) return;

    await _run(() async {
      await createCounterPriceOffer(
        previous: offer,
        amountEur: amount,
        offeredBy: offeredBy,
      );
    });
  }

  void _openProductCheckout({required double agreedPrice}) {
    final p = widget.product;
    if (p == null) return;
    context.push(
      ProductDetailsPageWidget.routePath,
      extra: {
        ...ProductDetailsPageWidget.routeExtraForProduct(p),
        ProductDetailsPageWidget.routeExtraAgreedOfferPriceKey: agreedPrice,
        ProductDetailsPageWidget.routeExtraOpenCheckoutKey: true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final offerId = widget.payload['offer_id']?.toString();
    final buyerId = widget.payload['buyer_id']?.toString();
    final sellerId = widget.payload['seller_id']?.toString();
    final offeredBy = widget.payload['offered_by']?.toString();
    final amount = (_offer?.amount ?? widget.payload['amount'] as num?)?.toDouble() ??
        0.0;
    final listPrice =
        (_offer?.listPrice ?? widget.payload['list_price'] as num?)?.toDouble();

    final imBuyer = buyerId == currentUserUid;
    final imSeller = sellerId == currentUserUid;
    final pending = !_resolved && (_offer?.status == 'pending' || _offer == null);

    final canRespond = pending &&
        ((offeredBy == 'buyer' && imSeller) ||
            (offeredBy == 'seller' && imBuyer));

    final waiting = pending && !canRespond;

    String headline;
    if (offeredBy == 'seller') {
      headline = imSeller
          ? 'Enviaste uma contra-proposta de ${formatEuros(amount)}.'
          : 'O vendedor propõe ${formatEuros(amount)}.';
    } else {
      headline = imBuyer
          ? 'Enviaste uma proposta de ${formatEuros(amount)}.'
          : 'O comprador propõe ${formatEuros(amount)}.';
    }

    if (_resolved && _offer?.status == 'accepted') {
      headline = 'Proposta aceite — ${formatEuros(amount)}';
    } else if (_resolved && _offer?.status == 'rejected') {
      headline = 'Proposta recusada';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: const Color(0xFFB8D5D8)),
            boxShadow: [
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
                Row(
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 22,
                      color: FleaberColors.teal.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headline,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF101518),
                        ),
                      ),
                    ),
                  ],
                ),
                if (listPrice != null && listPrice > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Preço no anúncio: ${formatEuros(listPrice)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                if (waiting) ...[
                  const SizedBox(height: 10),
                  Text(
                    imBuyer
                        ? 'Aguarda resposta do vendedor.'
                        : 'Aguarda resposta do comprador.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                if (_resolved &&
                    _offer?.status == 'accepted' &&
                    imBuyer &&
                    widget.product != null) ...[
                  const SizedBox(height: 12),
                  FleaberPrimaryButton(
                    label: 'Comprar por ${formatEuros(amount)}',
                    onPressed: _busy
                        ? null
                        : () => _openProductCheckout(agreedPrice: amount),
                  ),
                ],
                if (canRespond && offerId != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    await rejectPriceOffer(offerId: offerId);
                                  }),
                          child: const Text('Recusar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _busy ? null : () => _counter(imSeller ? 'seller' : 'buyer'),
                          child: const Text('Contra-proposta'),
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
                              final accepted =
                                  await acceptPriceOffer(offerId: offerId);
                              if (!mounted) return;
                              final msg = imSeller
                                  ? 'Proposta aceite. O artigo ficou reservado até o comprador pagar.'
                                  : 'Proposta aceite! O artigo está reservado para ti — conclui a compra por ${formatEuros(accepted.amount ?? amount)}.';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg)),
                              );
                            }),
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

/// Resultado final (aceite / recusada).
class PriceOfferOutcomeChatCard extends StatelessWidget {
  const PriceOfferOutcomeChatCard({
    super.key,
    required this.payload,
  });

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final outcome = payload['outcome']?.toString();
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    final accepted = outcome == 'accepted';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accepted
                ? const Color(0xFFE8F6F7)
                : const Color(0xFFF2F4F7),
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(
              color: accepted
                  ? FleaberColors.teal.withValues(alpha: 0.35)
                  : const Color(0xFFDDE2E7),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              accepted
                  ? 'Proposta aceite — ${formatEuros(amount)}. O comprador pode concluir a compra a este preço.'
                  : 'Proposta recusada.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF101518),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
