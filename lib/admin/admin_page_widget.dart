import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import 'admin_dispute_sheet.dart';
import 'admin_dpd_tab.dart';
import 'admin_ops_env_tab.dart';
import 'admin_seller_trade_tab.dart';

class AdminPageWidget extends StatefulWidget {
  const AdminPageWidget({super.key});

  static const String routeName = 'Admin';
  static const String routePath = '/admin';

  @override
  State<AdminPageWidget> createState() => _AdminPageWidgetState();
}

class _AdminPageWidgetState extends State<AdminPageWidget> {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kBg = FleaberColors.bgTint;
  static const Color _kText = Color(0xFF101518);
  static const Color _kMuted = Color(0xFF57636C);

  late Future<_AdminPayload> _payloadFuture;
  String _commissionRange = 'today';
  DateTime? _customCommissionStart;
  DateTime? _customCommissionEnd;

  @override
  void initState() {
    super.initState();
    _payloadFuture = _loadPayload();
  }

  bool _isAdminProfile(ProfilesRow? profile) {
    final type = (profile?.userType ?? '').trim().toLowerCase();
    return const {
      'admin',
      'admim',
      'administrador',
      'administracao',
    }.contains(type);
  }

  Future<_AdminPayload> _loadPayload() async {
    final meRows = await ProfilesTable().queryRows(
      queryFn: (q) => q.eqOrNull('id', currentUserUid),
      limit: 1,
    );
    final me = meRows.isEmpty ? null : meRows.first;
    final isAdmin = _isAdminProfile(me);
    if (!isAdmin) {
      return _AdminPayload(
        currentProfile: me,
        isAdmin: false,
        disputes: const [],
        orders: const [],
        profiles: const [],
        walletTransactions: const [],
        commissions: const [],
      );
    }

    final results = await Future.wait<Object>([
      OrderDisputesTable().queryRows(
        queryFn: (q) => q.order('created_at', ascending: false),
        limit: 80,
      ),
      OrdersTable().queryRows(
        queryFn: (q) => q.order('created_at', ascending: false),
        limit: 120,
      ),
      () async {
        final raw = await SupaFlow.client.rpc(
          'batata_admin_list_profiles',
          params: {'p_limit': 120},
        );
        if (raw is! List) return <ProfilesRow>[];
        return raw
            .map((e) => ProfilesRow(Map<String, dynamic>.from(e as Map)))
            .toList();
      }(),
      WalletTransactionsTable().queryRows(
        queryFn: (q) => q.order('created_at', ascending: false),
        limit: 120,
      ),
      FleaberCommissionsTable().queryRows(
        queryFn: (q) => q.order('created_at', ascending: false),
        limit: 500,
      ),
    ]);

    return _AdminPayload(
      currentProfile: me,
      isAdmin: true,
      disputes: results[0] as List<OrderDisputesRow>,
      orders: results[1] as List<OrdersRow>,
      profiles: results[2] as List<ProfilesRow>,
      walletTransactions: results[3] as List<WalletTransactionsRow>,
      commissions: results[4] as List<FleaberCommissionsRow>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _payloadFuture = _loadPayload());
    await _payloadFuture;
  }

  String _money(num value) {
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(value);
  }

  String _date(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'pt_PT').format(value.toLocal());
  }

  DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);

  ({DateTime start, DateTime end}) _commissionWindow() {
    final now = DateTime.now();
    final today = _startOfDay(now);
    switch (_commissionRange) {
      case '7d':
        return (start: today.subtract(const Duration(days: 6)), end: now);
      case '30d':
        return (start: today.subtract(const Duration(days: 29)), end: now);
      case 'custom':
        return (
          start: _customCommissionStart ?? today,
          end: _customCommissionEnd?.add(const Duration(days: 1)) ?? now,
        );
      case 'today':
      default:
        return (start: today, end: now);
    }
  }

  double _commissionTotal(
    List<FleaberCommissionsRow> commissions,
    DateTime start,
    DateTime end,
  ) {
    return commissions.where((c) {
      final created = c.createdAt?.toLocal();
      if (created == null) return false;
      return !created.isBefore(start) && created.isBefore(end);
    }).fold<double>(0, (sum, c) => sum + c.amount);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          foregroundColor: _kText,
          elevation: 0,
          title: Text(
            'Administração',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/admin/live-director'),
              icon: const Icon(Icons.live_tv_outlined, size: 20),
              label: const Text('Live Director'),
            ),
          ],
          bottom: const TabBar(
            labelColor: _kTeal,
            unselectedLabelColor: _kMuted,
            indicatorColor: _kTeal,
            isScrollable: true,
            tabs: [
              Tab(text: 'Resumo'),
              Tab(text: 'Disputas'),
              Tab(text: 'Encomendas'),
              Tab(text: 'Utilizadores'),
              Tab(text: 'Comissões'),
              Tab(text: 'Profissionais'),
              Tab(text: 'DPD'),
              Tab(text: 'Ambientes'),
            ],
          ),
        ),
        body: FutureBuilder<_AdminPayload>(
          future: _payloadFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _kTeal),
              );
            }
            final payload = snapshot.data!;
            if (!payload.isAdmin) {
              return _AdminDenied(profile: payload.currentProfile);
            }
            return TabBarView(
              children: [
                RefreshIndicator(
                  color: _kTeal,
                  onRefresh: _refresh,
                  child: _buildSummary(payload),
                ),
                RefreshIndicator(
                  color: _kTeal,
                  onRefresh: _refresh,
                  child: _buildDisputes(payload),
                ),
                RefreshIndicator(
                  color: _kTeal,
                  onRefresh: _refresh,
                  child: _buildOrders(payload),
                ),
                RefreshIndicator(
                  color: _kTeal,
                  onRefresh: _refresh,
                  child: _buildUsers(payload),
                ),
                RefreshIndicator(
                  color: _kTeal,
                  onRefresh: _refresh,
                  child: _buildCommissions(payload),
                ),
                const AdminSellerTradeTab(),
                const AdminDpdTab(),
                const AdminOpsEnvTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummary(_AdminPayload payload) {
    final activeDisputes = payload.disputes
        .where((d) => const {
              'aberta',
              'respondida_vendedor',
              'respondida_comprador',
              'escalada_fleaber',
            }.contains(d.status))
        .length;
    final escalated =
        payload.disputes.where((d) => d.status == 'escalada_fleaber').length;
    final retained = payload.orders
        .where((o) => const {'pago', 'enviado', 'em_devolucao'}
            .contains((o.status ?? '').toLowerCase()))
        .fold<double>(0, (sum, o) => sum + (o.priceTotal ?? 0));
    final withdrawals = payload.walletTransactions
        .where((t) => t.type == 'levantamento')
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final today = _startOfDay(DateTime.now());
    final commissionToday = _commissionTotal(
      payload.commissions,
      today,
      DateTime.now(),
    );
    final commission7d = _commissionTotal(
      payload.commissions,
      today.subtract(const Duration(days: 6)),
      DateTime.now(),
    );
    final commission30d = _commissionTotal(
      payload.commissions,
      today.subtract(const Duration(days: 29)),
      DateTime.now(),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AdminMetricCard(
              title: 'Disputas ativas',
              value: '$activeDisputes',
              icon: Icons.report_problem_rounded,
              color: const Color(0xFFB45309),
            ),
            _AdminMetricCard(
              title: 'Escaladas',
              value: '$escalated',
              icon: Icons.admin_panel_settings_rounded,
              color: const Color(0xFF7B1FA2),
            ),
            _AdminMetricCard(
              title: 'Saldo retido',
              value: _money(retained),
              icon: Icons.lock_clock_rounded,
              color: _kTeal,
            ),
            _AdminMetricCard(
              title: 'Levantamentos',
              value: _money(withdrawals),
              icon: Icons.account_balance_rounded,
              color: const Color(0xFF1565C0),
            ),
            _AdminMetricCard(
              title: 'Comissões hoje',
              value: _money(commissionToday),
              icon: Icons.payments_rounded,
              color: const Color(0xFF2E7D32),
            ),
            _AdminMetricCard(
              title: 'Comissões 7 dias',
              value: _money(commission7d),
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF2E7D32),
            ),
            _AdminMetricCard(
              title: 'Comissões 30 dias',
              value: _money(commission30d),
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFF2E7D32),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AdminInfoPanel(
          title: 'O que faz sentido gerir aqui',
          lines: const [
            'Disputas escaladas e abertas, com prazos e turnos.',
            'Encomendas pagas/enviadas/devoluções com dinheiro retido.',
            'Utilizadores recentes e identificação de contas admin.',
            'Movimentos de carteira, reembolsos e levantamentos.',
          ],
        ),
      ],
    );
  }

  Widget _buildDisputes(_AdminPayload payload) {
    if (payload.disputes.isEmpty) {
      return const _AdminEmpty(message: 'Ainda não existem disputas.');
    }
    final sorted = [...payload.disputes]..sort((a, b) {
        final aEsc = a.status == 'escalada_fleaber' ? 0 : 1;
        final bEsc = b.status == 'escalada_fleaber' ? 0 : 1;
        if (aEsc != bEsc) return aEsc.compareTo(bEsc);
        return (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      });
    final orderById = {
      for (final o in payload.orders)
        if (o.id != null) o.id!: o,
    };
    final profileById = {
      for (final p in payload.profiles)
        if (p.id != null) p.id!: p,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminInfoPanel(
          title: 'Disputas para o Fleaber',
          lines: [
            'Toca numa disputa para ver detalhes e intervir.',
            '${sorted.where((d) => d.status == 'escalada_fleaber').length} escalada(s) aguardam decisão.',
          ],
        ),
        const SizedBox(height: 12),
        for (final d in sorted) ...[
          InkWell(
            onTap: () {
              final order = d.orderId == null ? null : orderById[d.orderId];
              AdminDisputeSheet.show(
                context,
                dispute: d,
                order: order,
                buyer: order?.buyerId == null ? null : profileById[order!.buyerId],
                seller:
                    order?.sellerId == null ? null : profileById[order!.sellerId],
                onResolved: _refresh,
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: _AdminTile(
              icon: d.status == 'escalada_fleaber'
                  ? Icons.admin_panel_settings_rounded
                  : Icons.report_problem_rounded,
              title: 'Disputa ${_shortId(d.id)}',
              subtitle:
                  'Estado: ${d.status ?? '-'} | Turno: ${d.currentTurn}\nMotivo: ${_reasonLabel(d.reason)}\nPrazo: ${_date(d.nextDeadline)}',
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _date(d.createdAt),
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
                  ),
                  if (d.status == 'escalada_fleaber') ...[
                    const SizedBox(height: 4),
                    Text(
                      'Intervir',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _kTeal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildOrders(_AdminPayload payload) {
    if (payload.orders.isEmpty) {
      return const _AdminEmpty(message: 'Ainda não existem encomendas visíveis.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: payload.orders.length,
      itemBuilder: (context, index) {
        final o = payload.orders[index];
        return _AdminTile(
          icon: Icons.receipt_long_rounded,
          title: 'Encomenda ${_shortId(o.id)}',
          subtitle:
              'Estado: ${o.status ?? '-'} | Total: ${_money(o.priceTotal ?? 0)}\nComprador: ${_shortId(o.buyerId)} | Vendedor: ${_shortId(o.sellerId)}',
          trailing: Text(
            _date(o.createdAt),
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
          ),
        );
      },
    );
  }

  Widget _buildUsers(_AdminPayload payload) {
    if (payload.profiles.isEmpty) {
      return const _AdminEmpty(message: 'Ainda não existem utilizadores visíveis.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: payload.profiles.length,
      itemBuilder: (context, index) {
        final p = payload.profiles[index];
        return _AdminTile(
          icon: Icons.person_rounded,
          title: p.fullName?.trim().isNotEmpty == true
              ? p.fullName!.trim()
              : 'Utilizador Fleaber',
          subtitle:
              'Tipo: ${p.userType ?? '-'}\nLocalização: ${p.location ?? '-'}\nID: ${p.id ?? '-'}',
          trailing: Text(
            _date(p.createdAt),
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
          ),
        );
      },
    );
  }

  Widget _buildCommissions(_AdminPayload payload) {
    final window = _commissionWindow();
    final visible = payload.commissions.where((c) {
      final created = c.createdAt?.toLocal();
      if (created == null) return false;
      return !created.isBefore(window.start) && created.isBefore(window.end);
    }).toList();
    final total = visible.fold<double>(0, (sum, c) => sum + c.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminInfoPanel(
          title: 'Faturação Fleaber em comissões',
          lines: [
            'Total no período selecionado: ${_money(total)}',
            'Registos encontrados: ${visible.length}',
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _rangeChip('Hoje', 'today'),
            _rangeChip('Últimos 7 dias', '7d'),
            _rangeChip('Último mês', '30d'),
            _rangeChip('Datas custom', 'custom'),
          ],
        ),
        if (_commissionRange == 'custom') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customCommissionStart ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked == null) return;
                    setState(() => _customCommissionStart = picked);
                  },
                  child: Text(
                    _customCommissionStart == null
                        ? 'Data início'
                        : DateFormat('dd/MM/yyyy').format(_customCommissionStart!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customCommissionEnd ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked == null) return;
                    setState(() => _customCommissionEnd = picked);
                  },
                  child: Text(
                    _customCommissionEnd == null
                        ? 'Data fim'
                        : DateFormat('dd/MM/yyyy').format(_customCommissionEnd!),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6EEF0)),
            ),
            child: Text(
              'Sem comissões neste período.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _kMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          for (final commission in visible)
            _AdminTile(
              icon: Icons.payments_rounded,
              title: _money(commission.amount),
              subtitle:
                  '${commission.description ?? 'Taxa de Proteção Fleaber'}\nEncomenda: ${_shortId(commission.orderId)}',
              trailing: Text(
                _date(commission.createdAt),
                textAlign: TextAlign.end,
                style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
              ),
            ),
      ],
    );
  }

  Widget _rangeChip(String label, String value) {
    final selected = _commissionRange == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _kTeal.withOpacity(0.16),
      onSelected: (_) => setState(() => _commissionRange = value),
      labelStyle: GoogleFonts.inter(
        color: selected ? _kTeal : _kMuted,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  String _shortId(String? id) {
    if (id == null || id.isEmpty) return '-';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  String _reasonLabel(String? reason) {
    switch (reason) {
      case 'danificado':
        return 'Artigo danificado';
      case 'nao_corresponde':
        return 'Não corresponde';
      case 'em_falta':
        return 'Em falta';
      case 'outro':
        return 'Outro';
      default:
        return reason ?? '-';
    }
  }
}

class _AdminPayload {
  const _AdminPayload({
    required this.currentProfile,
    required this.isAdmin,
    required this.disputes,
    required this.orders,
    required this.profiles,
    required this.walletTransactions,
    required this.commissions,
  });

  final ProfilesRow? currentProfile;
  final bool isAdmin;
  final List<OrderDisputesRow> disputes;
  final List<OrdersRow> orders;
  final List<ProfilesRow> profiles;
  final List<WalletTransactionsRow> walletTransactions;
  final List<FleaberCommissionsRow> commissions;
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 165,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 10),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF101518),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF57636C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminInfoPanel extends StatelessWidget {
  const _AdminInfoPanel({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF101518),
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '- $line',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.35,
                    color: const Color(0xFF57636C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _AdminPageWidgetState._kTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF101518),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF57636C),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _AdminEmpty extends StatelessWidget {
  const _AdminEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Icon(
          Icons.admin_panel_settings_outlined,
          size: 64,
          color: Color(0x55007782),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: const Color(0xFF57636C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AdminDenied extends StatelessWidget {
  const _AdminDenied({required this.profile});

  final ProfilesRow? profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Esta área é apenas para perfis admin.\nTipo atual: ${profile?.userType ?? '-'}',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 15,
            height: 1.4,
            color: const Color(0xFF57636C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
