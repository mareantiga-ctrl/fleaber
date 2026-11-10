import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/hub/widgets/fleahub_site_chrome.dart';
import '/utils/fee_calculator.dart';
import '/widgets/fleaber_checkout_ui.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/seller_consumer_rights_notice.dart';
import '/utils/seller_professional.dart';

/// Catálogo visual E83 — Checkout (só UI, sem pagamentos / sem encomendas).
///
/// Gate: `--dart-define=FLEABER_E83_CHECKOUT_VISUAL=true` ou debug/profile.
class HubCheckoutVisualCatalogPage extends StatelessWidget {
  const HubCheckoutVisualCatalogPage({super.key});

  static const routeName = 'E83CheckoutCatalog';
  static const routePath = '/e83CheckoutCatalog';

  static bool get isEnabled {
    const viaDefine = bool.fromEnvironment(
      'FLEABER_E83_CHECKOUT_VISUAL',
      defaultValue: false,
    );
    return viaDefine || kDebugMode || kProfileMode;
  }

  @override
  Widget build(BuildContext context) {
    if (!isEnabled) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7F8),
        body: Center(
          child: Text(
            'Catálogo E83 Checkout indisponível neste build.',
            style: GoogleFonts.inter(color: const Color(0xFF57636C)),
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;

    // Column (não ListView): o SiteScaffold já faz scroll via CustomScrollView.
    return FleaHubSiteScaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 32 : 16,
          24,
          wide ? 32 : 16,
          48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'E83 — Checkout (catálogo visual)',
              style: GoogleFonts.interTight(
                color: const Color(0xFF101518),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pré-visualização das etapas do Checkout marketplace. '
              'Demonstração — sem Stripe, sem criar encomendas.',
              style: GoogleFonts.inter(
                color: const Color(0xFF57636C),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FleaberPrimaryButton.compact(
                  label: 'Abrir checkout artigo (demo)',
                  onPressed: () => _openArticleDemo(context),
                ),
                FleaberPrimaryButton.compact(
                  label: 'Abrir checkout conjunto (demo)',
                  onPressed: () => _openBundleDemo(context),
                ),
                FleaberPrimaryButton.compact(
                  label: 'Dados pagamento directo (demo)',
                  onPressed: () => _openDirectDemo(context),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _section('1 · Resumo do artigo'),
            const SizedBox(height: 10),
            const FleaberCheckoutProductSummary(
              title: 'Cachecol de lã cinzento',
              sellerName: 'Ana Marques',
              quantityLabel: '2 un.',
              priceLabel: '12,00 €',
            ),
            const SizedBox(height: 22),
            _section('2 · Morada de entrega'),
            const SizedBox(height: 10),
            const FleaberCheckoutAddressCard(
              complete: true,
              lines: [
                'Maria Silva',
                'Rua das Flores 12, 3º Esq.',
                '1000-001 Lisboa',
                'PT',
              ],
            ),
            const SizedBox(height: 12),
            const FleaberCheckoutAddressCard(
              complete: false,
              lines: [],
            ),
            const SizedBox(height: 22),
            _section('3 · Envio e pagamento'),
            const SizedBox(height: 10),
            FleaberCheckoutChoiceCard<String>(
              value: 'carrier',
              groupValue: 'carrier',
              title: kFleaberShippingCarrierLabel,
              subtitle: 'Etiqueta e seguimento na app',
              onChanged: (_) {},
            ),
            const SizedBox(height: 8),
            FleaberCheckoutChoiceCard<String>(
              value: 'hand',
              groupValue: 'carrier',
              title: kFleaberShippingHandLabel,
              subtitle: 'Combinas o encontro com o vendedor',
              onChanged: (_) {},
            ),
            const SizedBox(height: 8),
            FleaberCheckoutChoiceCard<String>(
              value: 'inapp',
              groupValue: 'inapp',
              title: 'Pagamento na app',
              subtitle: 'Cartão com Protecção Fleaber',
              onChanged: (_) {},
            ),
            const SizedBox(height: 22),
            _section('4 · Resumo e total'),
            const SizedBox(height: 10),
            FleaberCheckoutTotalsCard(
              lines: [
                FleaberCheckoutPriceLine(
                  label: 'Artigos (12,00 € × 2)',
                  value: formatEuros(24),
                ),
                FleaberCheckoutPriceLine(
                  label: 'Envio',
                  value: formatEuros(2.99),
                ),
                FleaberCheckoutPriceLine(
                  label: 'Protecção Fleaber',
                  value: formatEuros(
                    calculateFleaberProtectionFee(24, shippingEur: 2.99),
                  ),
                ),
                FleaberCheckoutPriceLine(
                  label: 'Total a pagar',
                  value: formatEuros(
                    calculateFleaberBuyerTotal(
                      itemPriceEur: 24,
                      shippingEur: 2.99,
                      includeProtectionFee: true,
                    ),
                  ),
                  isTotal: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SellerConsumerRightsNotice(
              info: SellerTradePublicInfo.particular('demo-seller'),
              sellerDisplayName: 'Ana Marques',
            ),
            const SizedBox(height: 28),
            _section('5 · Conjunto (desconto)'),
            const SizedBox(height: 10),
            FleaberCheckoutTotalsCard(
              lines: [
                const FleaberCheckoutPriceLine(
                  label: 'Subtotal artigos',
                  value: '40,00 €',
                ),
                const FleaberCheckoutPriceLine(
                  label: 'Desconto de conjunto (10%)',
                  value: '− 4,00 €',
                  emphasis: true,
                ),
                const FleaberCheckoutPriceLine(
                  label: 'Artigos (após desconto)',
                  value: '36,00 €',
                ),
                FleaberCheckoutPriceLine(
                  label: 'Envio',
                  value: formatEuros(2.99),
                ),
                FleaberCheckoutPriceLine(
                  label: 'Protecção Fleaber',
                  value: formatEuros(
                    calculateFleaberProtectionFee(36, shippingEur: 2.99),
                  ),
                ),
                FleaberCheckoutPriceLine(
                  label: 'Total a pagar',
                  value: formatEuros(
                    calculateFleaberBuyerTotal(
                      itemPriceEur: 36,
                      shippingEur: 2.99,
                      includeProtectionFee: true,
                    ),
                  ),
                  isTotal: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Nota: o checkout do saco live mantém o tema escuro do player '
              '(contexto live). Marketplace / conjuntos usam este chrome claro.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.4,
                color: const Color(0xFF57636C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _section(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF101518),
      ),
    );
  }

  static Future<void> _openArticleDemo(BuildContext context) {
    var shipping = kFleaberShippingCarrierMethod;
    var payment = 'Pagamento na app';
    return FleaberCheckoutUi.showHost<void>(
      context: context,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (context, setState) {
                final shippingEur =
                    fleaberShippingEurFromMethod(shipping);
                final items = 24.0;
                final isDirect = payment.contains('Direto');
                final protection = isDirect
                    ? 0.0
                    : calculateFleaberProtectionFee(
                        items,
                        shippingEur: shippingEur,
                      );
                final total = calculateFleaberBuyerTotal(
                  itemPriceEur: items,
                  shippingEur: shippingEur,
                  includeProtectionFee: !isDirect,
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                      child: Column(
                        children: [
                          const FleaberCheckoutHandle(),
                          FleaberCheckoutTitleBar(
                            title: 'Checkout',
                            subtitle: 'Demonstração visual — sem pagamento.',
                            onClose: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FleaberCheckoutBody(
                        primaryLabel: 'Confirmar compra (demo)',
                        onPrimary: () {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Demo visual — nenhum pagamento foi iniciado.',
                              ),
                            ),
                          );
                        },
                        footerNote:
                            'Pré-visualização E83. Não cria encomendas.',
                        children: [
                          const FleaberCheckoutProductSummary(
                            title: 'Cachecol de lã cinzento',
                            sellerName: 'Ana Marques',
                            quantityLabel: '2 un.',
                            priceLabel: '12,00 €',
                          ),
                          const SizedBox(height: 14),
                          const FleaberCheckoutSectionLabel(
                              'Morada de entrega'),
                          const SizedBox(height: 8),
                          const FleaberCheckoutAddressCard(
                            complete: true,
                            lines: [
                              'Maria Silva',
                              'Rua das Flores 12',
                              '1000-001 Lisboa',
                              'PT',
                            ],
                          ),
                          const SizedBox(height: 16),
                          const FleaberCheckoutSectionLabel('Envio'),
                          const SizedBox(height: 8),
                          FleaberCheckoutChoiceCard<String>(
                            value: kFleaberShippingCarrierMethod,
                            groupValue: shipping,
                            title: kFleaberShippingCarrierLabel,
                            onChanged: (v) =>
                                setState(() => shipping = v),
                          ),
                          const SizedBox(height: 8),
                          FleaberCheckoutChoiceCard<String>(
                            value: kFleaberShippingHandMethod,
                            groupValue: shipping,
                            title: kFleaberShippingHandLabel,
                            onChanged: (v) =>
                                setState(() => shipping = v),
                          ),
                          const SizedBox(height: 16),
                          const FleaberCheckoutSectionLabel('Pagamento'),
                          const SizedBox(height: 8),
                          FleaberCheckoutChoiceCard<String>(
                            value: 'Pagamento na app',
                            groupValue: payment,
                            title: 'Pagamento na app',
                            onChanged: (v) =>
                                setState(() => payment = v),
                          ),
                          const SizedBox(height: 8),
                          FleaberCheckoutChoiceCard<String>(
                            value:
                                'Pagamento Direto ao Vendedor (MB WAY/Transf)',
                            groupValue: payment,
                            title:
                                'Pagamento Direto ao Vendedor (MB WAY/Transf)',
                            onChanged: (v) =>
                                setState(() => payment = v),
                          ),
                          const SizedBox(height: 16),
                          const FleaberCheckoutSectionLabel('Resumo'),
                          const SizedBox(height: 8),
                          FleaberCheckoutTotalsCard(
                            lines: [
                              FleaberCheckoutPriceLine(
                                label: 'Artigos',
                                value: formatEuros(items),
                              ),
                              FleaberCheckoutPriceLine(
                                label: 'Envio',
                                value: formatEuros(shippingEur),
                              ),
                              FleaberCheckoutPriceLine(
                                label: 'Protecção Fleaber',
                                value: formatEuros(protection),
                              ),
                              FleaberCheckoutPriceLine(
                                label: 'Total a pagar',
                                value: formatEuros(total),
                                isTotal: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openBundleDemo(BuildContext context) {
    return FleaberCheckoutUi.showHost<void>(
      context: context,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Column(
                    children: [
                      const FleaberCheckoutHandle(),
                      FleaberCheckoutTitleBar(
                        title: 'Concluir compra do conjunto',
                        subtitle: 'Demonstração visual — sem pagamento.',
                        onClose: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FleaberCheckoutBody(
                    primaryLabel: 'Pagar com Seguro Fleaber (demo)',
                    onPrimary: () {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Demo visual — nenhum pagamento foi iniciado.',
                          ),
                        ),
                      );
                    },
                    children: [
                      FleaberCheckoutTotalsCard(
                        lines: [
                          const FleaberCheckoutPriceLine(
                            label: 'Subtotal artigos',
                            value: '40,00 €',
                          ),
                          const FleaberCheckoutPriceLine(
                            label: 'Desconto de conjunto (10%)',
                            value: '− 4,00 €',
                            emphasis: true,
                          ),
                          const FleaberCheckoutPriceLine(
                            label: 'Artigos (após desconto)',
                            value: '36,00 €',
                          ),
                          FleaberCheckoutPriceLine(
                            label: 'Envio',
                            value: formatEuros(2.99),
                          ),
                          FleaberCheckoutPriceLine(
                            label: 'Protecção Fleaber',
                            value: formatEuros(
                              calculateFleaberProtectionFee(
                                36,
                                shippingEur: 2.99,
                              ),
                            ),
                          ),
                          FleaberCheckoutPriceLine(
                            label: 'Total a pagar',
                            value: formatEuros(
                              calculateFleaberBuyerTotal(
                                itemPriceEur: 36,
                                shippingEur: 2.99,
                                includeProtectionFee: true,
                              ),
                            ),
                            isTotal: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openDirectDemo(BuildContext context) {
    return FleaberCheckoutUi.showHost<void>(
      context: context,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Column(
                    children: [
                      const FleaberCheckoutHandle(),
                      FleaberCheckoutTitleBar(
                        title: 'Dados de pagamento',
                        subtitle: 'Demonstração visual.',
                        onClose: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FleaberCheckoutBody(
                    primaryLabel: 'Fechar',
                    onPrimary: () => Navigator.of(ctx).pop(),
                    children: [
                      FleaberCheckoutTotalsCard(
                        lines: const [
                          FleaberCheckoutPriceLine(
                            label: 'Valor a pagar',
                            value: '28,00 €',
                            isTotal: true,
                          ),
                          FleaberCheckoutPriceLine(
                            label: 'Artigos',
                            value: '24,50 €',
                          ),
                          FleaberCheckoutPriceLine(
                            label: 'Envio',
                            value: '2,99 €',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const FleaberCheckoutSectionLabel('MB WAY'),
                      const SizedBox(height: 6),
                      Text(
                        '912 345 678',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: FleaberCheckoutUi.teal,
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
    );
  }
}
