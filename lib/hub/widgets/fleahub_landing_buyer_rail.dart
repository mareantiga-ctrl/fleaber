import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_reservation_queue_service.dart';

import '/perfil/perfil_desktop_nav.dart';

import '../hub_account_routes.dart';
import '../hub_actions.dart';
import '../hub_live_reservation_ui.dart';
import '../routing/hub_route_paths.dart';
import 'fleahub_site_chrome.dart';

/// Lateral direita da homepage: saco, encomendas, Facebook, logos, vendedores.
class FleaHubLandingBuyerRail extends StatefulWidget {
  const FleaHubLandingBuyerRail({
    super.key,
    this.onOpenBag,
  });

  final VoidCallback? onOpenBag;

  @override
  State<FleaHubLandingBuyerRail> createState() =>
      _FleaHubLandingBuyerRailState();
}

class _FleaHubLandingBuyerRailState extends State<FleaHubLandingBuyerRail> {
  late Future<_BuyerRailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppStateNotifier.instance.addListener(_onAuth);
  }

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    setState(() => _future = _load());
  }

  Future<_BuyerRailData> _load() async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      return const _BuyerRailData.guest();
    }
    final queue = LiveReservationQueueService();
    final rows = await queue.buyerRequests(buyerId: uid, limit: 80);
    final summary = HubReservationSummary.fromRows(rows);
    final active = rows.where((r) {
      final s = r.status;
      if (LiveReservationQueueService.isBuyerCancelledReservation(
        status: s,
        notes: r.notes,
      )) {
        return false;
      }
      return s == 'pending' || s == 'accepted';
    }).toList();

    List<OrdersRow> orders = const [];
    try {
      orders = await OrdersTable().queryRows(
        queryFn: (q) => q
            .eq('buyer_id', uid)
            .order('created_at', ascending: false),
        limit: 5,
      );
    } catch (_) {
      orders = const [];
    }

    return _BuyerRailData(
      loggedIn: true,
      summary: summary,
      activeRows: active,
      recentOrders: orders,
      loading: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        return FutureBuilder<_BuyerRailData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data ??
                (currentUserUid.isEmpty
                    ? const _BuyerRailData.guest()
                    : const _BuyerRailData.loading());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BagCard(
                  data: data,
                  onOpenBag: widget.onOpenBag,
                ),
                const SizedBox(height: 12),
                _OrdersCard(data: data),
                const SizedBox(height: 12),
                const _FacebookCard(),
                const SizedBox(height: 12),
                const _PaymentsStrip(),
                const SizedBox(height: 12),
                const _SellerPitchCard(),
              ],
            );
          },
        );
      },
    );
  }
}

class _BuyerRailData {
  const _BuyerRailData({
    required this.loggedIn,
    required this.summary,
    required this.activeRows,
    required this.recentOrders,
    required this.loading,
  });

  const _BuyerRailData.guest()
      : loggedIn = false,
        summary = const HubReservationSummary(
          total: 0,
          inQueue: 0,
          confirmed: 0,
          pendingAwaiting: 0,
        ),
        activeRows = const [],
        recentOrders = const [],
        loading = false;

  const _BuyerRailData.loading()
      : loggedIn = true,
        summary = const HubReservationSummary(
          total: 0,
          inQueue: 0,
          confirmed: 0,
          pendingAwaiting: 0,
        ),
        activeRows = const [],
        recentOrders = const [],
        loading = true;

  final bool loggedIn;
  final HubReservationSummary summary;
  final List<LiveReservationRequestsRow> activeRows;
  final List<OrdersRow> recentOrders;
  final bool loading;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: FleaberColors.surface,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FleaberRadius.md),
        child: box,
      ),
    );
  }
}

class _BagCard extends StatelessWidget {
  const _BagCard({required this.data, this.onOpenBag});

  final _BuyerRailData data;
  final VoidCallback? onOpenBag;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'O teu saco',
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: FleaHubSiteLayout.typeSection,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (!data.loggedIn)
            _guestPrompt(
              context,
              'Entra na tua conta para ver o saco e pagar. '
              'O checkout no Hub exige autenticação — não há pagamento anónimo.',
            )
          else if (data.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                color: FleaberColors.teal,
                minHeight: 2,
              ),
            )
          else if (!data.summary.hasAny) ...[
            Text(
              'Ainda não tens reservas activas.',
              style: GoogleFonts.inter(
                color: FleaberColors.muted,
                fontSize: FleaHubSiteLayout.typeBody,
                height: 1.4,
              ),
            ),
            // E86.1: saco vazio também abre o painel H14 (não só SnackBar/texto).
            if (onOpenBag != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onOpenBag,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FleaberColors.teal,
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: FleaberColors.teal),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Ver saco',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: FleaHubSiteLayout.typeBody,
                    ),
                  ),
                ),
              ),
            ],
          ] else ...[
            Text(
              data.summary.hubCardTitle,
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: FleaHubSiteLayout.typeBody,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (data.summary.hubCardSubline.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                data.summary.hubCardSubline,
                style: GoogleFonts.inter(
                  color: FleaberColors.muted,
                  fontSize: FleaHubSiteLayout.typeSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpenBag,
                style: FilledButton.styleFrom(
                  backgroundColor: FleaberColors.teal,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  data.summary.hubCardCta,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: FleaHubSiteLayout.typeBody,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrdersCard extends StatelessWidget {
  const _OrdersCard({required this.data});

  final _BuyerRailData data;

  @override
  Widget build(BuildContext context) {
    void openOrders() {
      if (currentUserUid.isEmpty) {
        HubActions.openLoginForReturn(
          context,
          returnTo: HubAccountRoutes.perfilPath(PerfilDesktopPane.encomendas),
        );
        return;
      }
      HubAccountRoutes.openEncomendas(context);
    }

    return _SectionCard(
      onTap: data.loggedIn ? openOrders : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'As tuas encomendas',
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: FleaHubSiteLayout.typeSection,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (!data.loggedIn)
            _guestPrompt(
              context,
              'Entra na tua conta para ver encomendas e estados. '
              'Sem sessão não há checkout no Hub.',
            )
          else if (data.loading)
            const SizedBox.shrink()
          else if (data.recentOrders.isEmpty)
            Text(
              'Ainda não tens encomendas recentes.',
              style: GoogleFonts.inter(
                color: FleaberColors.muted,
                fontSize: FleaHubSiteLayout.typeBody,
                height: 1.4,
              ),
            )
          else ...[
            for (final o in data.recentOrders.take(3)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _orderLine(o),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: FleaberColors.text,
                    fontSize: FleaHubSiteLayout.typeSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
          if (data.loggedIn) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: openOrders,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Ver encomendas',
                  style: GoogleFonts.inter(
                    color: FleaberColors.teal,
                    fontWeight: FontWeight.w800,
                    fontSize: FleaHubSiteLayout.typeBody,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _orderLine(OrdersRow o) {
    final status = o.status?.trim() ?? '';
    final id = o.id?.trim() ?? '';
    final short = id.length > 8 ? id.substring(0, 8) : id;
    if (status.isEmpty) return 'Encomenda $short';
    return '$status · $short';
  }
}

class _FacebookCard extends StatelessWidget {
  const _FacebookCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.facebook,
                size: 22,
                color: FleaberColors.teal.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Compras dos diretos Facebook',
                  style: GoogleFonts.inter(
                    color: FleaberColors.text,
                    fontSize: FleaHubSiteLayout.typeBody,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Compraste num directo do Facebook? Encontra aqui as tuas '
            'reservas, confirma as compras e acompanha as encomendas.',
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeSecondary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              if (currentUserUid.isEmpty) {
                HubActions.openLoginForReturn(
                  context,
                  returnTo: HubRoutePaths.landing,
                );
                return;
              }
              HubAccountRoutes.openEncomendas(context);
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              currentUserUid.isEmpty
                  ? 'Entrar para ver reservas'
                  : 'Ver reservas e encomendas',
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontWeight: FontWeight.w800,
                fontSize: FleaHubSiteLayout.typeBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsStrip extends StatelessWidget {
  const _PaymentsStrip();

  @override
  Widget build(BuildContext context) {
    Widget pill(Widget child) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: FleaberColors.bgTint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FleaberColors.alternate),
        ),
        child: child,
      );
    }

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pagamentos e envios',
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: FleaHubSiteLayout.typeSection,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(
                const FleaHubBrandMark(
                  asset: 'assets/images/hub_landing/brands/visa.png',
                  semanticLabel: 'Visa',
                  height: 16,
                  maxWidth: 44,
                ),
              ),
              pill(
                const FleaHubBrandMark(
                  asset: 'assets/images/hub_landing/brands/mastercard.png',
                  semanticLabel: 'Mastercard',
                  height: 22,
                  maxWidth: 36,
                ),
              ),
              pill(
                Text(
                  'MB WAY',
                  style: GoogleFonts.inter(
                    fontSize: FleaHubSiteLayout.typeCaption,
                    fontWeight: FontWeight.w800,
                    color: FleaberColors.text,
                  ),
                ),
              ),
              pill(
                const FleaHubBrandMark(
                  asset: 'assets/images/hub_landing/brands/dpd.png',
                  semanticLabel: 'DPD',
                  height: 18,
                  maxWidth: 44,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.push(HubRoutePaths.buySafe),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Comprar com segurança',
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontWeight: FontWeight.w700,
                fontSize: FleaHubSiteLayout.typeSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerPitchCard extends StatelessWidget {
  const _SellerPitchCard();

  @override
  Widget build(BuildContext context) {
    Widget channel(IconData icon, String label) {
      return Expanded(
        child: Column(
          children: [
            Icon(icon, size: 24, color: FleaberColors.teal),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeCaption,
                fontWeight: FontWeight.w700,
                color: FleaberColors.text,
              ),
            ),
          ],
        ),
      );
    }

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vende no Facebook, na Fleaber e no FleaHub. '
            'Gere tudo num só lugar.',
            style: GoogleFonts.inter(
              color: FleaberColors.text,
              fontSize: FleaHubSiteLayout.typeBody,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              channel(Icons.facebook, 'Facebook'),
              channel(Icons.phone_android_rounded, 'Fleaber'),
              channel(Icons.storefront_rounded, 'FleaHub'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sem comissões, taxas ou subscrições à Fleaber.',
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeSecondary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(HubRoutePaths.sell),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Saber mais',
                style: GoogleFonts.inter(
                  color: FleaberColors.teal,
                  fontWeight: FontWeight.w800,
                  fontSize: FleaHubSiteLayout.typeBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _guestPrompt(BuildContext context, String body) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        body,
        style: GoogleFonts.inter(
          color: FleaberColors.muted,
          fontSize: FleaHubSiteLayout.typeSecondary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () => HubActions.openLoginForReturn(
          context,
          returnTo: HubRoutePaths.landing,
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 42),
          side: const BorderSide(color: FleaberColors.teal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Entrar',
          style: GoogleFonts.inter(
            color: FleaberColors.teal,
            fontWeight: FontWeight.w700,
            fontSize: FleaHubSiteLayout.typeBody,
          ),
        ),
      ),
    ],
  );
}
