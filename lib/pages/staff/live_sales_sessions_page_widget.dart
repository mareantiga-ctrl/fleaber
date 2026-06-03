import 'dart:async';



import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:intl/intl.dart';



import '/auth/supabase_auth/auth_util.dart';

import '/backend/supabase/supabase.dart';

import '/flutter_flow/flutter_flow_util.dart';

import '/pages/staff/live_sales_session_detail_page_widget.dart';

import '/utils/fleaber_radius.dart';

import '/utils/live_session_results_service.dart';

import '/utils/seller_staff_permissions.dart';

import '/utils/seller_staff_service.dart';

import '/widgets/account_context_badge.dart';

import '/widgets/fleaber_primary_button.dart';

import '/widgets/seller_staff_gate.dart';



class LiveSalesSessionsPageWidget extends StatefulWidget {

  const LiveSalesSessionsPageWidget({super.key});



  static String routeName = 'LiveSalesSessions';

  static String routePath = '/operacoesLive';



  @override

  State<LiveSalesSessionsPageWidget> createState() =>

      _LiveSalesSessionsPageWidgetState();

}



class _LiveSalesSessionsPageWidgetState extends State<LiveSalesSessionsPageWidget> {

  bool _loading = true;

  bool _initialLoadDone = false;

  List<LiveSessionSummary> _cards = const [];

  StreamSubscription<List<Map<String, dynamic>>>? _requestsSub;

  StreamSubscription<List<Map<String, dynamic>>>? _logsSub;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersSub;

  Timer? _reloadDebounce;

  bool _reloadInFlight = false;



  @override

  void initState() {

    super.initState();

    unawaited(_load());

    _subscribeRealtime();

  }



  void _subscribeRealtime() {

    final sellerId = effectiveSellerId.trim();

    if (sellerId.isEmpty) return;

    if (_requestsSub != null || _logsSub != null || _ordersSub != null) return;

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



      final cards = await LiveSessionResultsService.summariesForSeller(sellerId);

      if (!mounted) return;

      setState(() {

        _cards = cards;

        _loading = false;

        _initialLoadDone = true;

      });

    } catch (_) {

      if (mounted) {

        setState(() {

          _loading = false;

          _initialLoadDone = true;

        });

      }

    } finally {

      _reloadInFlight = false;

    }

  }



  String _formatSessionDate(LivesRow live) {

    final at = live.createdAt?.toLocal();

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

      child: Scaffold(

        backgroundColor: const Color(0xFFF3F6F7),

        appBar: AppBar(

          backgroundColor: Colors.white,

          elevation: 0,

          title: Text(

            'Centro de resultados',

            style: GoogleFonts.inter(

              color: const Color(0xFF101518),

              fontWeight: FontWeight.w700,

            ),

          ),

        ),

        body: _loading && !_initialLoadDone

            ? const Center(child: CircularProgressIndicator())

            : RefreshIndicator(

                onRefresh: () => _load(),

                child: ListView(

                  padding: const EdgeInsets.all(16),

                  children: [

                    const AccountContextBadge(),

                    const SizedBox(height: 10),

                    Text(

                      'Resultados por sessão live',

                      style: GoogleFonts.inter(

                        fontSize: 12,

                        color: const Color(0xFF57636C),

                        fontWeight: FontWeight.w600,

                      ),

                    ),

                    const SizedBox(height: 10),

                    for (final c in _cards) _sessionCard(c),

                    if (_cards.isEmpty)

                      Text(

                        'Sem sessões live para mostrar.',

                        style: GoogleFonts.inter(color: const Color(0xFF57636C)),

                      ),

                  ],

                ),

              ),

      ),

    );

  }



  Widget _sessionCard(LiveSessionSummary c) {

    final title = (c.live.title ?? '').trim().isNotEmpty

        ? c.live.title!.trim()

        : 'LIVE';

    return Container(

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: FleaberRadius.circularMd,

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          Text(

            title,

            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),

          ),

          const SizedBox(height: 4),

          Text(

            _formatSessionDate(c.live),

            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF57636C)),

          ),

          const SizedBox(height: 10),

          _metricLine('${c.articlesSold} artigos vendidos'),

          _metricLine('${c.reservationsCount} reservas'),

          _metricLine('${_formatMoney(c.revenueEur)} vendido'),

          _metricLine('${c.pendingPayments} pagamentos pendentes'),

          if (c.hasAlerts) ...[

            const SizedBox(height: 8),

            Text(

              'Alerta: existem pendências ou conflitos nesta sessão.',

              style: GoogleFonts.inter(

                fontSize: 11,

                color: const Color(0xFF9C4A00),

                fontWeight: FontWeight.w700,

              ),

            ),

          ],

          const SizedBox(height: 12),

          FleaberPrimaryButton(

            label: 'Abrir resumo',

            height: 44,

            borderRadius: 14,

            onPressed: () => _openDetail(c),

          ),

        ],

      ),

    );

  }



  Widget _metricLine(String text) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 4),

      child: Text(

        text,

        style: GoogleFonts.inter(

          fontSize: 12,

          fontWeight: FontWeight.w600,

          color: const Color(0xFF3D4A55),

        ),

      ),

    );

  }



  @override

  void dispose() {

    _reloadDebounce?.cancel();

    unawaited(_requestsSub?.cancel());

    unawaited(_logsSub?.cancel());

    unawaited(_ordersSub?.cancel());

    super.dispose();

  }

}


