import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/marketplace_product_card.dart';

import '../data/hub_models.dart';
import '../hub_live_reservation_ui.dart';
import '../routing/hub_route_paths.dart';
import 'fleahub_site_chrome.dart';
import 'hub_content_widgets.dart';
import 'hub_facebook_recover_cta.dart';
import 'hub_live_reservations_hub.dart';
import 'hub_reservation_panel.dart';
import 'hub_shared_widgets.dart';

/// Secções Hub abaixo da dobra — reservas, marketplace compacto (desktop H03).
class HubLiveScrollPanel extends StatelessWidget {
  const HubLiveScrollPanel({
    super.key,
    required this.bundle,
    required this.handle,
    required this.summary,
    required this.isLoggedIn,
    required this.onOpenBag,
    required this.onLoginForBag,
    this.onContinueWithFacebook,
    this.needsFacebookLogin = false,
    this.psDemo = false,
    this.loadingReservations = false,
    this.compactMarketplace = false,
    this.showInstallBanner = true,
    this.showGuestRecoverInPanel = true,
  });

  final HubLiveBundle bundle;
  final String handle;
  final HubReservationSummary summary;
  final bool isLoggedIn;
  final VoidCallback onOpenBag;
  final VoidCallback onLoginForBag;
  final VoidCallback? onContinueWithFacebook;
  final bool needsFacebookLogin;
  final bool psDemo;
  final bool loadingReservations;

  /// H03 desktop: carrossel horizontal com cartões pequenos (estilo H02).
  final bool compactMarketplace;

  /// Desktop: Instalar fica na faixa superior — não repetir no fundo.
  final bool showInstallBanner;

  /// false no desktop H03 — o saco/coluna já tem a entrada Facebook.
  final bool showGuestRecoverInPanel;

  @override
  Widget build(BuildContext context) {
    final products = bundle.products;
    final priceFmt =
        NumberFormat.currency(locale: 'pt_PT', symbol: '€', decimalDigits: 2);

    return ColoredBox(
      color: FleaberColors.bgTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HubLiveScrollDivider(),
          if (isLoggedIn && summary.hasAny)
            HubReservationPanel.activeSummary(
              summary: summary,
              loading: loadingReservations,
              onOpenBag: onOpenBag,
            )
          else if (isLoggedIn &&
              needsFacebookLogin &&
              onContinueWithFacebook != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: HubFacebookRecoverCta(
                mode: HubFacebookRecoverMode.needsFacebookLogin,
                compact: false,
                onPressed: onContinueWithFacebook,
              ),
            )
          else if (!isLoggedIn && showGuestRecoverInPanel)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: HubFacebookRecoverCta(
                mode: HubFacebookRecoverMode.guest,
                compact: false,
                onPressed: onLoginForBag,
              ),
            ),
          if (psDemo)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _PsDemoBanner(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Marketplace',
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: FleaHubSiteLayout.typeSection,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (products.isEmpty)
            const HubEmptyState(
              message: 'Esta seller ainda não tem artigos no marketplace.',
              icon: Icons.storefront_outlined,
            )
          else if (compactMarketplace)
            SizedBox(
              height: MarketplaceProductCard.horizontalListHeight(112),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                itemCount: products.length.clamp(0, 24),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = products[i];
                  final price = p.price;
                  return MarketplaceProductCard(
                    width: 112,
                    title: p.title,
                    stateLabel: p.isSold
                        ? 'Vendido'
                        : (p.state?.trim().isNotEmpty == true
                            ? p.state!.trim()
                            : null),
                    priceLabel: price != null ? priceFmt.format(price) : '',
                    imageUrl: p.primaryImage,
                    favoritesCount: 0,
                    isFavorited: false,
                    onTap: () => context.push(
                      '/productDetails?product_id=${p.id}',
                    ),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.58,
                ),
                itemCount: products.length.clamp(0, 12),
                itemBuilder: (context, i) => HubProductTile(
                  product: products[i],
                  onTap: () => context.push(
                    '/productDetails?product_id=${products[i].id}',
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    context.push(HubRoutePaths.reviewsFor(handle)),
                child: Text(
                  'Ver opiniões',
                  style: GoogleFonts.inter(
                    color: FleaberColors.teal,
                    fontWeight: FontWeight.w700,
                    fontSize: FleaHubSiteLayout.typeBody,
                  ),
                ),
              ),
            ),
          ),
          if (showInstallBanner) const HubInstallBanner(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PsDemoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.45)),
      ),
      child: Text(
        'Modo demo Facebook (staging)',
        style: GoogleFonts.inter(
          color: FleaberColors.text,
          fontSize: FleaHubSiteLayout.typeCaption,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
