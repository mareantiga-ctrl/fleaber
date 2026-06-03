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
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/utils/seller_staff_permissions.dart';
import '/widgets/seller_staff_gate.dart';

class WalletPageWidget extends StatefulWidget {
  const WalletPageWidget({super.key});

  static const String routeName = 'Wallet';
  static const String routePath = '/wallet';

  @override
  State<WalletPageWidget> createState() => _WalletPageWidgetState();
}

class _WalletPageWidgetState extends State<WalletPageWidget> {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kBackground = FleaberColors.bgTint;
  static const Color _kText = Color(0xFF101518);
  static const Color _kMuted = Color(0xFF57636C);

  late Future<_WalletPayload> _payloadFuture;
  bool _transferBusy = false;

  @override
  void initState() {
    super.initState();
    _payloadFuture = _loadWallet();
  }

  Future<_WalletPayload> _loadWallet() async {
    await WalletService.ensureWallet(currentUserUid);
    final walletRows = await WalletsTable().querySingleRow(
      queryFn: (q) => q.eqOrNull('id', currentUserUid),
    );
    final transactions = await WalletTransactionsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('wallet_id', currentUserUid)
          .order('created_at', ascending: false),
      limit: 80,
    );
    final retainedBalance = await _loadRetainedBalance();
    return _WalletPayload(
      walletRows.isNotEmpty ? walletRows.first : null,
      transactions,
      retainedBalance,
    );
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
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro Stripe: $e'),
                                ),
                              );
                              setModalState(() => submitting = false);
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
      body: SafeArea(
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

            final payload = snapshot.data ?? _WalletPayload(null, const [], 0);
            final availableBalance = payload.wallet?.balance ?? 0;
            return RefreshIndicator(
              color: _kTeal,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  _BalanceCard(
                    availableBalance: _formatEuros(availableBalance),
                    retainedBalance: _formatEuros(payload.retainedBalance),
                    transferBusy: _transferBusy,
                    onTransfer: availableBalance > 0
                        ? () => _openWithdrawalSheet(availableBalance)
                        : null,
                    onRetainedTap: _openRetainedDetailSheet,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        context.pushNamed(ModoFeriasPageWidget.routeName),
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: Text(
                      'Como funciona o saldo e modo de férias',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: _kTeal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Histórico de Movimentos',
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
            );
          },
        ),
      ),
    );
  }
}

class _WalletPayload {
  const _WalletPayload(this.wallet, this.transactions, this.retainedBalance);

  final WalletsRow? wallet;
  final List<WalletTransactionsRow> transactions;
  final double retainedBalance;
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.availableBalance,
    required this.retainedBalance,
    required this.transferBusy,
    required this.onTransfer,
    this.onRetainedTap,
  });

  final String availableBalance;
  final String retainedBalance;
  final bool transferBusy;
  final VoidCallback? onTransfer;
  final VoidCallback? onRetainedTap;

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WalletAmountBlock(
            title: 'Saldo Disponível para Levantamento',
            amount: availableBalance,
            icon: Icons.account_balance_wallet_rounded,
            color: _WalletPageWidgetState._kTeal,
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onRetainedTap,
              borderRadius: BorderRadius.circular(16),
              child: _WalletAmountBlock(
                title: 'Saldo Retido (Aguardando Feedback)',
                amount: retainedBalance,
                icon: Icons.lock_clock_rounded,
                color: const Color(0xFFB7791F),
                trailing: onRetainedTap != null
                    ? const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB7791F),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FleaberPrimaryButton(
            width: double.infinity,
            label: 'Transferir para a conta bancária',
            loading: transferBusy,
            fontWeight: FontWeight.w800,
            backgroundColor: _WalletPageWidgetState._kTeal,
            disabledBackgroundColor:
                _WalletPageWidgetState._kTeal.withOpacity(0.55),
            onPressed: transferBusy ? null : onTransfer,
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
                          'Saldo retido',
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
                'Este valor liberta-se quando o comprador confirma a entrega ou quando não há disputa aberta.',
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
                  'Não há vendas com saldo retido neste momento.',
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
                  transaction.description ?? _labelForType(transaction.type),
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
      case 'levantamento':
        return 'Levantamento';
      case 'compra':
        return 'Compra';
      default:
        return 'Movimento';
    }
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF0)),
      ),
      child: Text(
        'Ainda não existem movimentos na carteira.',
        style: GoogleFonts.inter(
          fontSize: 14,
          color: _WalletPageWidgetState._kMuted,
          fontWeight: FontWeight.w600,
        ),
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
