import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/chat_session_util.dart';
import '/index.dart';
import '/wallet/wallet_retained_orders.dart';
import '/wallet/wallet_service.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_stripe_launch.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/utils/seller_staff_permissions.dart';
import '/widgets/seller_staff_gate.dart';
import '/utils/fleaber_logger.dart';

String _walletFormatEuros(double value) {
  return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(value);
}

class WalletPageWidget extends StatefulWidget {
  const WalletPageWidget({super.key, this.embedded = false});

  final bool embedded;

  static const String routeName = 'Wallet';
  static const String routePath = '/wallet';

  @override
  State<WalletPageWidget> createState() => _WalletPageWidgetState();
}

class _WalletPageWidgetState extends State<WalletPageWidget>
    with WidgetsBindingObserver {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kBackground = FleaberColors.bgTint;
  static const Color _kText = Color(0xFF101518);
  static const Color _kMuted = Color(0xFF57636C);

  late Future<_WalletPayload> _payloadFuture;
  bool _transferBusy = false;
  bool _connectBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _payloadFuture = _loadWallet();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// ZIP 182: ao voltar do onboarding Stripe (browser/Hub), actualizar estado KYC.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refresh();
    }
  }

  Future<_WalletPayload> _loadWallet() async {
    // Web/shell: o UID pode chegar alguns frames depois do login.
    for (var i = 0; i < 25 && currentUserUid.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final uid = currentUserUid;
    if (uid.isEmpty) {
      throw StateError('Sessão em falta — volta a iniciar sessão.');
    }
    try {
      await WalletService.ensureWallet(uid);
    } catch (e) {
      // Continua: a carteira pode já existir mesmo se o RPC falhar.
      debugPrint('WALLET_ENSURE_ERR $e');
    }
    final walletRows = await WalletsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', uid),
    );
    var transactions = <WalletTransactionsRow>[];
    try {
      transactions = await WalletTransactionsTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('wallet_id', uid)
            .order('created_at', ascending: false),
        limit: 80,
      );
    } catch (e) {
      debugPrint('WALLET_TX_ERR $e');
    }
    var retainedBalance = 0.0;
    try {
      retainedBalance = await _loadRetainedBalance();
    } catch (e) {
      debugPrint('WALLET_RETAINED_ERR $e');
    }
    var payouts = <_PayoutLedgerItem>[];
    try {
      payouts = await _loadPayoutLedger(uid);
    } catch (e) {
      debugPrint('WALLET_PAYOUT_LEDGER_ERR $e');
    }
    return _WalletPayload(
      walletRows.isNotEmpty ? walletRows.first : null,
      transactions,
      retainedBalance,
      payouts,
    );
  }

  Future<List<_PayoutLedgerItem>> _loadPayoutLedger(String uid) async {
    final raw = await SupaFlow.client
        .from('wallet_payout_ledger')
        .select(
          'idempotency_key,amount_eur,status,stripe_transfer_id,created_at,updated_at',
        )
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(20);
    final rows = List<dynamic>.from(raw as List);
    return rows
        .whereType<Map>()
        .map((m) => _PayoutLedgerItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<double> _loadRetainedBalance() async {
    final items = await loadWalletRetainedOrders();
    return items.fold<double>(0, (sum, e) => sum + e.amountEur);
  }

  Future<void> _openRetainedDetailSheet() async {
    final items = await loadWalletRetainedOrders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _RetainedOrdersSheet(items: items),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _payloadFuture = _loadWallet();
    });
    await _payloadFuture;
  }

  Future<void> _openConnectOnboarding() async {
    if (_connectBusy) return;
    setState(() => _connectBusy = true);
    try {
      final uri = await WalletService.startConnectOnboarding(
        userId: currentUserUid,
      );
      // ZIP 182: mesmo launcher do Checkout — Hub web = mesmo separador
      // (evita popup blocker); Android = browser externo fiável.
      final opened = await fleaberLaunchStripeCheckout(
        uri.toString(),
        preferExternalBrowser: true,
        context: const {
          'source': 'wallet_connect_onboarding',
        },
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a página Stripe Connect.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stripe Connect: $e')),
      );
    } finally {
      if (mounted) setState(() => _connectBusy = false);
    }
  }

  Future<void> _openWithdrawalSheet(double availableBalance) async {
    if (_transferBusy) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final controller = TextEditingController();
        var requestedAmount = 0.0;
        var submitting = false;

        double parseAmount(String raw) {
          final normalized = raw.trim().replaceAll(',', '.');
          return double.tryParse(normalized) ?? 0.0;
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final canSubmit = !submitting &&
                requestedAmount > 0 &&
                requestedAmount <= availableBalance;
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7E2E5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Transferir para a conta bancária',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Saldo total disponível: ${_formatEuros(availableBalance)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Valor a levantar',
                      hintText: '0,00',
                      prefixText: '€ ',
                      filled: true,
                      fillColor: FleaberColors.bgTint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD7E2E5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD7E2E5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kTeal, width: 2),
                      ),
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        requestedAmount = parseAmount(value);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    requestedAmount > availableBalance
                        ? 'O valor não pode ser superior ao saldo disponível.'
                        : 'Introduz o valor que pretendes levantar.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: requestedAmount > availableBalance
                          ? const Color(0xFFC62828)
                          : _kMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FleaberPrimaryButton(
                    width: double.infinity,
                    label: 'Confirmar Levantamento',
                    loading: submitting,
                    fontWeight: FontWeight.w800,
                    disabledBackgroundColor: _kTeal.withOpacity(0.45),
                    onPressed: canSubmit
                        ? () async {
                            setModalState(() => submitting = true);
                            setState(() => _transferBusy = true);
                            try {
                              final cents = (requestedAmount * 100).round();
                              await WalletService.requestPayout(
                                userId: currentUserUid,
                                amountCents: cents,
                              );
                              if (!mounted) return;
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sucesso! O dinheiro foi transferido para a sua conta bancária.',
                                  ),
                                ),
                              );
                              await _refresh();
                            } catch (e, st) {
                              if (!mounted) return;
                              FleaberLogger.instance.error(
                                'wallet.payout.ui',
                                e,
                                st,
                              );
                              final message = WalletService.payoutErrorMessage(e);
                              setModalState(() => submitting = false);
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Não foi possível transferir'),
                                    content: SingleChildScrollView(
                                      child: SelectableText(message),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _transferBusy = false);
                              }
                            }
                          }
                        : null,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatEuros(double value) {
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return SellerStaffGate(
      permission: SellerStaffPermissions.canViewPayouts,
      child: _buildWalletScaffold(context),
    );
  }

  Widget _buildWalletScaffold(BuildContext context) {
    final body = SafeArea(
        child: FutureBuilder<_WalletPayload>(
          future: _payloadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: _kTeal),
              );
            }
            if (snapshot.hasError) {
              return _WalletError(
                message: 'Não foi possível carregar a carteira.',
                onRetry: _refresh,
              );
            }

            final payload =
                snapshot.data ?? _WalletPayload(null, const [], 0, const []);
            final wallet = payload.wallet;
            final walletBal = wallet?.balance ?? 0;
            final held = wallet?.heldBalance ?? 0;
            // ZIP 128/166: levantável = balance − held (disputas/recovery)
            final availableBalance =
                (walletBal - held) < 0 ? 0.0 : (walletBal - held);
            // Pendente = encomendas ainda sem libertação; Retido = held disputa
            final pendingOrders = payload.retainedBalance;
            final risk = wallet?.riskStatus ?? 'clear';
            final riskBlocks = risk == 'risk_hold' ||
                risk == 'under_review' ||
                risk == 'permanent_ban';
            final canTransfer = availableBalance > 0 && !riskBlocks;
            final blockReason = _withdrawalBlockReason(
              available: availableBalance,
              held: held,
              riskBlocks: riskBlocks,
              riskReason: wallet?.riskHoldReason,
              hasConnectAccount:
                  (wallet?.stripeAccountId ?? '').trim().isNotEmpty,
              connectReady: wallet?.connectReadyForPayout ?? false,
            );
            return RefreshIndicator(
              color: _kTeal,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  if (riskBlocks) ...[
                    _InfoBanner(
                      color: const Color(0xFFFFF1F2),
                      border: const Color(0xFFFECACA),
                      textColor: const Color(0xFF9F1239),
                      text: wallet?.riskHoldReason?.trim().isNotEmpty == true
                          ? wallet!.riskHoldReason!.trim()
                          : 'Levantamentos temporariamente suspensos por revisão de risco. Podes reclamar em geral@fleaber.pt.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _BalanceCard(
                    availableBalance: _formatEuros(availableBalance),
                    pendingBalance: _formatEuros(pendingOrders),
                    heldBalance: _formatEuros(held),
                    showHeld: held > 0.009,
                    transferBusy: _transferBusy,
                    onTransfer: canTransfer
                        ? () => _openWithdrawalSheet(availableBalance)
                        : null,
                    onPendingTap: _openRetainedDetailSheet,
                    blockReason: canTransfer ? null : blockReason,
                  ),
                  const SizedBox(height: 12),
                  _ConnectStatusCard(
                    wallet: wallet,
                    busy: _connectBusy,
                    onConfigure: _openConnectOnboarding,
                  ),
                  if (payload.payouts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Pedidos de levantamento',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...payload.payouts.map((p) => _PayoutLedgerTile(item: p)),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.embedded ? 900 : double.infinity,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Histórico de movimentos',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (payload.transactions.isEmpty)
                            const _EmptyTransactions()
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: payload.transactions.length,
                              itemBuilder: (context, index) {
                                return _TransactionTile(
                                  transaction: payload.transactions[index],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    if (widget.embedded) {
      return ColoredBox(color: _kBackground, child: body);
    }
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        foregroundColor: _kText,
        elevation: 0,
        title: Text(
          'Saldo',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: _kText,
          ),
        ),
      ),
      body: body,
    );
  }
}

String? _withdrawalBlockReason({
  required double available,
  required double held,
  required bool riskBlocks,
  required String? riskReason,
  required bool hasConnectAccount,
  required bool connectReady,
}) {
  if (riskBlocks) {
    final r = riskReason?.trim();
    if (r != null && r.isNotEmpty) return r;
    return 'Levantamento bloqueado: conta em revisão de risco.';
  }
  if (available <= 0) {
    if (held > 0.009) {
      return 'Não há saldo disponível. Parte do saldo está retida por disputa ou recuperação.';
    }
    return 'Ainda não tens saldo disponível para levantamento.';
  }
  if (!hasConnectAccount) {
    return 'Configura a conta bancária (Stripe Connect) antes de levantar.';
  }
  if (!connectReady) {
    return 'A verificação Stripe ainda não está concluída. Abre «Configurar conta bancária» e completa os dados em falta.';
  }
  return null;
}

class _WalletPayload {
  const _WalletPayload(
    this.wallet,
    this.transactions,
    this.retainedBalance,
    this.payouts,
  );

  final WalletsRow? wallet;
  final List<WalletTransactionsRow> transactions;
  final double retainedBalance;
  final List<_PayoutLedgerItem> payouts;
}

class _PayoutLedgerItem {
  const _PayoutLedgerItem({
    required this.amountEur,
    required this.status,
    this.transferId,
    this.createdAt,
  });

  final double amountEur;
  final String status;
  final String? transferId;
  final DateTime? createdAt;

  factory _PayoutLedgerItem.fromMap(Map<String, dynamic> m) {
    final amt = m['amount_eur'];
    final created = m['created_at'];
    return _PayoutLedgerItem(
      amountEur: amt is num
          ? amt.toDouble()
          : double.tryParse('$amt') ?? 0,
      status: (m['status'] ?? '').toString().trim().toLowerCase(),
      transferId: (m['stripe_transfer_id'] ?? '').toString().trim().isEmpty
          ? null
          : (m['stripe_transfer_id'] as Object).toString().trim(),
      createdAt: created == null
          ? null
          : (created is DateTime
              ? created
              : DateTime.tryParse(created.toString())),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'transferred':
        return 'Enviado para a conta Stripe';
      case 'debited':
        return 'A processar';
      case 'failed':
        return 'Falhou — valor devolvido ao saldo';
      default:
        return 'Estado: $status';
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.availableBalance,
    required this.pendingBalance,
    required this.heldBalance,
    required this.showHeld,
    required this.transferBusy,
    required this.onTransfer,
    this.onPendingTap,
    this.blockReason,
  });

  final String availableBalance;
  final String pendingBalance;
  final String heldBalance;
  final bool showHeld;
  final bool transferBusy;
  final VoidCallback? onTransfer;
  final VoidCallback? onPendingTap;
  final String? blockReason;

  @override
  Widget build(BuildContext context) {
    final available = _WalletAmountBlock(
      title: 'Disponível para levantamento',
      amount: availableBalance,
      icon: Icons.account_balance_wallet_rounded,
      color: _WalletPageWidgetState._kTeal,
    );
    final pending = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPendingTap,
        borderRadius: BorderRadius.circular(16),
        child: _WalletAmountBlock(
          title: 'Pendente (vendas a aguardar libertação)',
          amount: pendingBalance,
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFB7791F),
          trailing: onPendingTap != null
              ? const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB7791F),
                )
              : null,
        ),
      ),
    );
    final held = showHeld
        ? _WalletAmountBlock(
            title: 'Retido por disputa / risco',
            amount: heldBalance,
            icon: Icons.gavel_rounded,
            color: const Color(0xFF9F1239),
          )
        : null;
    final transfer = Align(
      alignment: Alignment.centerLeft,
      child: FleaberPrimaryButton(
        width: 280,
        label: 'Transferir para a conta bancária',
        loading: transferBusy,
        fontWeight: FontWeight.w700,
        backgroundColor: _WalletPageWidgetState._kTeal,
        disabledBackgroundColor:
            _WalletPageWidgetState._kTeal.withOpacity(0.55),
        onPressed: transferBusy ? null : onTransfer,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final sideBySide = c.maxWidth >= 640;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sideBySide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: available),
                      const SizedBox(width: 14),
                      Expanded(child: pending),
                    ],
                  ),
                )
              else ...[
                available,
                const SizedBox(height: 14),
                pending,
              ],
              if (held != null) ...[
                const SizedBox(height: 14),
                held,
              ],
              const SizedBox(height: 18),
              transfer,
              if (blockReason != null && blockReason!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  blockReason!.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF9F1239),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.border,
    required this.textColor,
    required this.text,
  });

  final Color color;
  final Color border;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.35,
          color: textColor,
        ),
      ),
    );
  }
}

class _ConnectStatusCard extends StatelessWidget {
  const _ConnectStatusCard({
    required this.wallet,
    required this.busy,
    required this.onConfigure,
  });

  final WalletsRow? wallet;
  final bool busy;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final hasAccount = (wallet?.stripeAccountId ?? '').trim().isNotEmpty;
    final transfers =
        (wallet?.stripeConnectTransfersStatus ?? '').toLowerCase();
    final submitted = wallet?.stripeConnectDetailsSubmitted;
    late final String title;
    late final String body;
    late final Color accent;
    late final String cta;
    if (!hasAccount) {
      title = 'Ativa a tua carteira Fleaber';
      body =
          'A Fleaber utiliza a Stripe, uma das principais plataformas mundiais de processamento de pagamentos, para garantir transações seguras.\n\n'
          'Para receberes o dinheiro das tuas vendas, precisas de ativar a tua carteira. É um processo simples e seguro, realizado diretamente com a Stripe.\n\n'
          'Os teus dados bancários são tratados de forma segura pela Stripe.';
      accent = const Color(0xFFB7791F);
      cta = 'Ativar a minha carteira';
    } else if (transfers == 'active' ||
        (transfers.isEmpty && submitted == true)) {
      title = 'Carteira activa';
      body = submitted == true
          ? 'A tua carteira está pronta. Podes pedir levantamentos quando houver saldo disponível.'
          : 'A tua carteira está associada. Se faltarem dados, completa a verificação.';
      accent = _WalletPageWidgetState._kTeal;
      cta = 'Gerir carteira';
    } else if (transfers == 'pending' || submitted == false) {
      title = 'Verificação em curso';
      body =
          'Estamos a validar a tua identidade e conta bancária com a Stripe. Completa o que faltar e volta aqui.';
      accent = const Color(0xFFB7791F);
      cta = 'Completar verificação';
    } else {
      title = 'Completa a verificação da carteira';
      body =
          'Falta confirmar alguns dados (por exemplo IBAN ou documentos) para poderes receber os teus pagamentos.';
      accent = const Color(0xFF9F1239);
      cta = 'Completar verificação';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _WalletPageWidgetState._kText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              color: _WalletPageWidgetState._kMuted,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onConfigure,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_outlined, size: 18),
            label: Text(
              cta,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: _WalletPageWidgetState._kTeal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _WalletPageWidgetState._kTeal,
              side: const BorderSide(color: Color(0xFFB7D4D8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutLedgerTile extends StatelessWidget {
  const _PayoutLedgerTile({required this.item});

  final _PayoutLedgerItem item;

  @override
  Widget build(BuildContext context) {
    final created = item.createdAt;
    final when = created == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(created.toLocal());
    Color statusColor;
    switch (item.status) {
      case 'transferred':
        statusColor = _WalletPageWidgetState._kTeal;
        break;
      case 'failed':
        statusColor = const Color(0xFFC62828);
        break;
      default:
        statusColor = const Color(0xFFB7791F);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _WalletPageWidgetState._kMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            _walletFormatEuros(item.amountEur),
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _WalletPageWidgetState._kText,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletAmountBlock extends StatelessWidget {
  const _WalletAmountBlock({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.trailing,
  });

  final String title;
  final String amount;
  final IconData icon;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _WalletPageWidgetState._kMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  amount,
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    height: 1,
                    color: _WalletPageWidgetState._kText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _RetainedOrdersSheet extends StatelessWidget {
  const _RetainedOrdersSheet({required this.items});

  final List<WalletRetainedOrder> items;

  String _formatEuros(double value) {
    return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(value);
  }

  Future<void> _openSaleChat(BuildContext context, WalletRetainedOrder item) async {
    final order = item.order;
    final productId = order.productId;
    final buyerId = order.buyerId;
    if (productId == null ||
        productId.isEmpty ||
        buyerId == null ||
        buyerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o chat desta venda.'),
        ),
      );
      return;
    }
    try {
      final chat = await ensureSellerChat(
        otherUserId: buyerId,
        productId: productId,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      context.pushNamed(
        ChatPageWidget.routeName,
        queryParameters: <String, String?>{
          'chatId': serializeParam(chat.id, ParamType.String),
          'otherUserId': serializeParam(buyerId, ParamType.String),
        }.withoutNulls,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o chat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (s, e) => s + e.amountEur);
    final maxH = MediaQuery.sizeOf(context).height * 0.75;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD7E2E5),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo pendente',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF101518),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${items.length} venda${items.length == 1 ? '' : 's'} · ${_formatEuros(total)}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF57636C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Liberta-se após confirmação do comprador (C2C) ou no fim da retenção Proteção (B2C). Disputas abertas bloqueiam a libertação.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: const Color(0xFF57636C),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Não há vendas com saldo pendente neste momento.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF57636C),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final thumb = item.thumbUrl;
                    return Material(
                      color: FleaberColors.bgTint,
                      borderRadius: FleaberRadius.circularMd,
                      child: InkWell(
                        borderRadius: FleaberRadius.circularMd,
                        onTap: () => _openSaleChat(context, item),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: FleaberRadius.circularMd,
                            border: Border.all(color: const Color(0xFFE6EEF0)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: FleaberRadius.circularSm,
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: thumb != null
                                      ? BatataCachedNetworkImage(
                                          imageUrl: thumb,
                                          fit: BoxFit.cover,
                                        )
                                      : const ColoredBox(
                                          color: Color(0xFFE0E3E7),
                                          child: Icon(
                                            Icons.inventory_2_outlined,
                                            color: Color(0xFF8A8D93),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: const Color(0xFF101518),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.statusLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF57636C),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Abrir chat da venda',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: FleaberColors.teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatEuros(item.amountEur),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: const Color(0xFFB7791F),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF57636C),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final WalletTransactionsRow transaction;

  @override
  Widget build(BuildContext context) {
    final amount = transaction.amount;
    final positive = amount >= 0;
    final amountText = NumberFormat.currency(locale: 'pt_PT', symbol: '€')
        .format(amount.abs());
    final date = transaction.createdAt == null
        ? ''
        : DateFormat('dd MMM yyyy, HH:mm', 'pt_PT').format(
            transaction.createdAt!,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: positive
                  ? const Color(0xFFE6F7F5)
                  : const Color(0xFFFFEBEE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              positive
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: positive
                  ? _WalletPageWidgetState._kTeal
                  : const Color(0xFFC62828),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayDescription(transaction),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _WalletPageWidgetState._kText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _WalletPageWidgetState._kMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${positive ? '+' : '-'}$amountText',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: positive
                  ? _WalletPageWidgetState._kTeal
                  : const Color(0xFFC62828),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _displayDescription(WalletTransactionsRow tx) {
    final typeLabel = _labelForType(tx.type);
    final raw = (tx.description ?? '').trim();
    final hint = _statusHint(tx);
    if (raw.isEmpty) return '$typeLabel$hint';
    if (_looksTechnical(raw)) return '$typeLabel$hint';
    return '$raw$hint';
  }

  /// Oculta UUIDs, seeds QA e identificadores de teste no histórico.
  bool _looksTechnical(String value) {
    final lower = value.toLowerCase();
    if (RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    ).hasMatch(value)) {
      return true;
    }
    if (RegExp(r'\b(test|seed|qa[-_]|staging|mock|dummy)\b', caseSensitive: false)
        .hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^[0-9a-f]{16,}$', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    return false;
  }

  String _labelForType(String? type) {
    switch (type) {
      case 'venda':
        return 'Venda';
      case 'gorjeta_enviada':
        return 'Gorjeta enviada';
      case 'gorjeta_recebida':
        return 'Gorjeta recebida';
      case 'reembolso':
        return 'Reembolso';
      case 'estorno':
        return 'Estorno';
      case 'levantamento':
        return 'Levantamento';
      case 'compra':
        return 'Compra';
      default:
        return 'Movimento';
    }
  }

  String _statusHint(WalletTransactionsRow tx) {
    final raw = (tx.description ?? '').toLowerCase();
    if (tx.type == 'levantamento' && raw.contains('pendente')) {
      return ' · a processar';
    }
    if (tx.type == 'reembolso' &&
        (raw.contains('reversão') || raw.contains('falhado'))) {
      return ' · levantamento falhado';
    }
    return '';
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 36,
            color: _WalletPageWidgetState._kTeal.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            'Ainda não há movimentos',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: _WalletPageWidgetState._kText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Quando receberes vendas ou fizeres transferências, o histórico aparece aqui.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: _WalletPageWidgetState._kMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletError extends StatelessWidget {
  const _WalletError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    color: _WalletPageWidgetState._kMuted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
