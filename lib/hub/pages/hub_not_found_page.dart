import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';
import '../hub_navigation.dart';
import '../routing/hub_route_paths.dart';
import '../seo/hub_seo_meta.dart';
import '../widgets/fleahub_site_chrome.dart';
import '../widgets/hub_seo_scope.dart';

/// 404 genérico Hub — não revela se handle existe ou está unpublished.
/// H06: chrome claro alinhado a H01/H02 (paleta Fleaber + FleaHubSiteScaffold).
class HubNotFoundPage extends StatefulWidget {
  const HubNotFoundPage({super.key});

  static const routeName = 'HubNotFound';

  @override
  State<HubNotFoundPage> createState() => _HubNotFoundPageState();
}

class _HubNotFoundPageState extends State<HubNotFoundPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchSubmitted(String raw) {
    final q = raw.trim();
    if (q.length < 2) {
      HubNavigation.goFleahubLanding(context);
      return;
    }
    context.go(
      '${HubRoutePaths.landing}?q=${Uri.encodeQueryComponent(q)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBack = HubNavigation.hasInternalBack(context);
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final pad = FleaHubSiteLayout.pagePadding(context);

    return HubSeoScope(
      meta: HubSeoMeta.notFound(),
      child: FleaHubSiteScaffold(
        searchController: _searchCtrl,
        onSearchSubmitted: _onSearchSubmitted,
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            pad.left,
            FleaHubSiteLayout.contentTopGap(context) + (wide ? 24 : 12),
            pad.right,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 520 : 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '404',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: FleaberColors.teal.withValues(alpha: 0.65),
                      fontSize: wide ? 14 : 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3.2,
                    ),
                  ),
                  SizedBox(height: wide ? 20 : 16),
                  Text(
                    'Esta página não existe',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: FleaberColors.text,
                      fontSize: wide ? 32 : 26,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A página que procuras não foi encontrada ou já não está '
                    'disponível. Volta ao início e continua a explorar.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: FleaberColors.muted,
                      fontSize: wide ? 16 : 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: wide ? 36 : 28),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: FleaberPrimaryButton(
                        label: 'Ir para o início',
                        width: double.infinity,
                        onPressed: () =>
                            HubNavigation.goFleahubLanding(context),
                      ),
                    ),
                  ),
                  if (hasBack) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => HubNavigation.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: FleaberColors.teal,
                        ),
                        child: Text(
                          'Voltar',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
