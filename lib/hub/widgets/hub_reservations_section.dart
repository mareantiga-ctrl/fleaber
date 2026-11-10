import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/live_reservation_queue_service.dart';

import '/flutter_flow/nav/nav.dart';

import '../data/hub_models.dart';
import '../hub_actions.dart';
import '../hub_ps_claim.dart';
import 'hub_reservation_panel.dart';
import 'hub_shared_widgets.dart';

/// Reservas do comprador autenticado (tabela `live_reservation_requests` — pós-login).
class HubMyReservationsSection extends StatefulWidget {
  const HubMyReservationsSection({
    super.key,
    required this.liveId,
    required this.sellerId,
  });

  final String liveId;
  final String sellerId;

  @override
  State<HubMyReservationsSection> createState() =>
      _HubMyReservationsSectionState();
}

class _HubMyReservationsSectionState extends State<HubMyReservationsSection> {
  late Future<List<LiveReservationRequestsRow>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
    AppStateNotifier.instance.addListener(_onAuthSessionChanged);
  }

  @override
  void dispose() {
    AppStateNotifier.instance.removeListener(_onAuthSessionChanged);
    super.dispose();
  }

  void _onAuthSessionChanged() {
    _reload();
    if (mounted) setState(() {});
  }

  void _reload() {
    if (currentUserUid.isEmpty) {
      _future = Future.value(const []);
    } else {
      _future = _loadWithClaim();
    }
  }

  Future<List<LiveReservationRequestsRow>> _loadWithClaim() async {
    await HubPsClaim.claimForLive(widget.liveId);
    return LiveReservationRequestsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('live_id', widget.liveId)
          .eqOrNull('buyer_id', currentUserUid)
          .order('created_at', ascending: false),
      limit: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        if (currentUserUid.isEmpty) {
          return HubReservationPanel.loginPrompt(
            onLogin: () => HubActions.requireAuth(
              context,
              intentLabel: 'ver as tuas reservas',
              inLivePlayer: true,
            ),
          );
        }

        return FutureBuilder<List<LiveReservationRequestsRow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return HubReservationPanel.loading();
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return HubReservationPanel.empty(
                message: 'Ainda não tens reservas neste directo.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HubSectionHeader(title: 'As minhas reservas'),
                ...rows.take(6).map(
                  (r) => HubReservationPanel.row(reservation: r),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Acções de reserva/compra pós-login (reutiliza serviço existente).
abstract final class HubLiveCommerceActions {
  static Future<void> reserveItem(
    BuildContext context, {
    required HubLive live,
    required HubLiveItem item,
    VoidCallback? onChanged,
  }) async {
    final ok = await HubActions.requireAuth(
      context,
      intentLabel: 'reservar este artigo',
    );
    if (!ok || !context.mounted) return;
    try {
      final row = await LiveReservationQueueService().createRequest(
        liveId: live.id,
        liveItemId: item.id,
        sellerId: item.sellerId,
      );
      if (!context.mounted) return;
      if (row != null) {
        onChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              // Phase 3: buyer never sees queue position.
              'Pedido de reserva enviado',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível reservar.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao reservar. Tenta outra vez.')),
      );
    }
  }

  static Future<void> buyNow(
    BuildContext context, {
    required HubLive live,
    required HubLiveItem item,
  }) async {
    final ok = await HubActions.requireAuth(
      context,
      intentLabel: 'comprar este artigo',
    );
    if (!ok || !context.mounted) return;
    // Sem product_id na view hub_live_items — funil para app/checkout completo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Checkout completo disponível na app Fleaber. '
          'Ref. ${item.refCode ?? item.title ?? 'artigo'} · '
          '${item.price != null ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(item.price) : ''}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    await HubActions.openInstallApp();
  }
}
