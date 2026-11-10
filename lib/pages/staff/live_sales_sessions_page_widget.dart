import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/pages/staff/live_sales_session_detail_page_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_session_results_service.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/account_context_badge.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/seller_staff_gate.dart';

class LiveSalesSessionsPageWidget extends StatefulWidget {
  const LiveSalesSessionsPageWidget({
    super.key,
    this.embedded = false,
    this.onOpenLiveId,
  });

  final bool embedded;

  /// H11 shell: abrir detalhe no painel (em vez de rota standalone).
  final ValueChanged<String>? onOpenLiveId;

  static String routeName = 'LiveSalesSessions';
  static String routePath = '/operacoesLive';

  @override
  State<LiveSalesSessionsPageWidget> createState() =>
      _LiveSalesSessionsPageWidgetState();
}

class _LiveSalesSessionsPageWidgetState
    extends State<LiveSalesSessionsPageWidget> {
  bool _loading = true;
  bool _initialLoadDone = false;
  String? _loadError;
  List<LiveSessionSummary> _cards = const [];
  StreamSubscription<List<Map<String, dynamic>>>? _requestsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _logsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSub;
  Timer? _reloadDebounce;
  bool _reloadInFlight = false;

  @override
  void initState() {
    super.initState();
    SellerStaffContext.instance.addListener(_onStaffContextChanged);
    unawaited(_load());
    _subscribeRealtime();
  }

  void _onStaffContextChanged() {
    _teardownRealtime();
    _scheduleReload();
  }

  void _teardownRealtime() {
    unawaited(_requestsSub?.cancel());
    unawaited(_logsSub?.cancel());
    unawaited(_ordersSub?.cancel());
    _requestsSub = null;
    _logsSub = null;
    _ordersSub = null;
  }

  void _subscribeRealtime() {
    final sellerId = effectiveSellerId.trim();
    if (sellerId.isEmpty) return;
    if (_requestsSub != null || _logsSub != null || _ordersSub != null) {
      return;
    }
    try {
      _requestsSub = SupaFlow.client
          .from('live_reservation_requests')
          .stream(primaryKey: ['id'])
          .eq('seller_id', sellerId)
          .listen((_) => _scheduleReload());
      _logsSub = SupaFlow.client
          .from('staff_action_logs')
          .stream(primaryKey: ['id'])
          .eq('seller_id', sellerId)
          .listen((_) => _scheduleReload());
      _ordersSub = SupaFlow.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('seller_id', sellerId)
          .listen((_) => _scheduleReload());
    } catch (_) {}
  }

  void _scheduleReload() {
    if (!mounted || !_initialLoadDone) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_load(silent: true));
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (_reloadInFlight) return;
    _reloadInFlight = true;
    if (!silent && !_initialLoadDone) {
      setState(() => _loading = true);
    }
    try {
      if (!silent) {
        await SellerStaffContext.instance.refresh();
      }
      if (!mounted) return;
      final sellerId = effectiveSellerId;
      _subscribeRealtime();
      final cards =
          await LiveSessionResultsService.summariesForSeller(sellerId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _initialLoadDone = true;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _initialLoadDone = true;
          _loadError =
              'Não foi possível carregar as sessões. Puxa para tentar outra vez.';
        });
      }
    } finally {
      _reloadInFlight = false;
    }
  }

  String _formatSessionDate(LiveSessionSummary summary) {
    final at = (summary.sessionAt ??
            summary.live.wentLiveAt ??
            summary.live.createdAt)
        ?.toLocal();
    if (at == null) return '—';
    final d = DateFormat('dd/MM/yyyy').format(at);
    final t = DateFormat('HH:mm').format(at);
    return '$d · $t';
  }

  String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return '${NumberFormat('#,##0', 'pt_PT').format(value.toInt())}€';
    }
    return '${NumberFormat('#,##0.00', 'pt_PT').format(value).replaceAll('.', ',')}€';
  }

  void _openDetail(LiveSessionSummary summary) {
    final liveId = summary.live.id?.trim() ?? '';
    if (liveId.isEmpty) return;
    if (widget.embedded && widget.onOpenLiveId != null) {
      widget.onOpenLiveId!(liveId);
      return;
    }
    context.pushNamed(
      LiveSalesSessionDetailPageWidget.routeName,
      queryParameters: {
        'liveId': serializeParam(liveId, ParamType.String),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SellerStaffGate(
      permission: SellerStaffPermissions.canManageReservations,
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    const bg = FleaberColors.bgTint;
    final body = _loading && !_initialLoadDone
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.embedded ? 4 : 16,
                16,
                16,
              ),
              children: [
                if (!widget.embedded) ...[
                  const AccountContextBadge(),
                  const SizedBox(height: 10),
                ],
                if (_loadError != null) ...[
                  Text(
                    _loadError!,
                    style: GoogleFonts.inter(
                      fontSize: FleaHubSiteLayout.typeSecondary,
                      color: const Color(0xFF9C4A00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!widget.embedded) ...[
                  Text(
                    'Resultados por sessão',
                    style: GoogleFonts.inter(
                      fontSize: FleaHubSiteLayout.typeCaption,
                      color: FleaberColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                    child: Text(
                      'Resultados por sessão',
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeSection,
                        color: FleaberColors.text,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
                for (final c in _cards) _sessionCard(c),
                if (_cards.isEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: FleaberRadius.circularMd,
                      border: Border.all(color: FleaberColors.alternate),
                    ),
                    child: Text(
                      'Sem sessões de directo para mostrar.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeBody,
                        color: FleaberColors.muted,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          );

    if (widget.embedded) {
      return ColoredBox(color: bg, child: body);
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Resultados dos diretos',
          style: GoogleFonts.inter(
            color: FleaberColors.text,
            fontWeight: FontWeight.w700,
            fontSize: FleaHubSiteLayout.typeNavTitle,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _sessionCard(LiveSessionSummary c) {
    final title = (c.live.title ?? '').trim().isNotEmpty
        ? c.live.title!.trim()
        : 'Directo';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: FleaberColors.alternate),
        boxShadow: const [FleaberElevation.sm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: FleaHubSiteLayout.typeNavTitle,
              color: FleaberColors.text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatSessionDate(c),
            style: GoogleFonts.inter(
              fontSize: FleaHubSiteLayout.typeBody,
              color: FleaberColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 420;
              final metrics = <(String, String)>[
                ('${c.articlesSold}', 'Vendidos'),
                ('${c.reservationsCount}', 'Reservas'),
                (_formatMoney(c.revenueEur), 'Receita'),
                ('${c.pendingPayments}', 'Pendentes'),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _metricChip(metrics[i].$1, metrics[i].$2),
                      ),
                    ],
                  ],
                );
              }
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.85,
                children: [
                  for (final m in metrics) _metricChip(m.$1, m.$2),
                ],
              );
            },
          ),
          if (c.hasAlerts) ...[
            const SizedBox(height: 12),
            Text(
              'Há pendências ou conflitos nesta sessão.',
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeBody,
                color: const Color(0xFF9C4A00),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: FleaberPrimaryButton(
                label: 'Abrir resumo',
                height: 40,
                borderRadius: 12,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                onPressed: () => _openDetail(c),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String value, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EBEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: widget.embedded ? 20 : 18,
              fontWeight: FontWeight.w800,
              color: FleaberColors.text,
              height: 1.1,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: FleaberColors.muted,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    SellerStaffContext.instance.removeListener(_onStaffContextChanged);
    _reloadDebounce?.cancel();
    _teardownRealtime();
    super.dispose();
  }
}
