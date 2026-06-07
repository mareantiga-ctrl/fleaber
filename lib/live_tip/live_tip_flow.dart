import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fee_calculator.dart';
import '/utils/fleaber_stripe_tip_context.dart';
import '/wallet/wallet_service.dart';
import '/widgets/fleaber_primary_button.dart';

const Color _kTeal = Color(0xFF007782);

/// Taxa de processamento: 2,9% + 0,40 € (sobre o valor da gorjeta).
double liveTipProcessingFeeEur(double amountEur) {
  final fee = amountEur * 0.029 + 0.40;
  return (fee * 100).roundToDouble() / 100;
}

double liveTipSellerReceivesEur(double amountEur) {
  final net = amountEur - liveTipProcessingFeeEur(amountEur);
  return net < 0 ? 0 : ((net * 100).roundToDouble() / 100);
}

class LiveTipPreset {
  const LiveTipPreset(this.emoji, this.amountEur);

  final String emoji;
  final double amountEur;
}

const List<LiveTipPreset> kLiveTipPresets = [
  LiveTipPreset('👋', 1),
  LiveTipPreset('😊', 5),
  LiveTipPreset('😁', 10),
  LiveTipPreset('🥰', 20),
  LiveTipPreset('🤩', 50),
  LiveTipPreset('🤑', 100),
];

class LiveTipLaunchArgs {
  const LiveTipLaunchArgs({
    required this.liveId,
    required this.sellerId,
    this.playbackId,
    this.isLive = true,
    this.sellerName,
  });

  final String liveId;
  final String sellerId;
  final String? playbackId;
  final bool isLive;
  final String? sellerName;
}

/// Abre o ecrã de gorjeta (estilo Whatnot) e processa carteira ou Stripe.
Future<LiveTipResult?> showLiveTipSheet(
  BuildContext context,
  LiveTipLaunchArgs args,
) {
  return showModalBottomSheet<LiveTipResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _LiveTipSheet(args: args),
  );
}

class LiveTipResult {
  const LiveTipResult({
    required this.success,
    this.amountEur,
    this.message,
    this.usedWallet = false,
  });

  final bool success;
  final double? amountEur;
  final String? message;
  final bool usedWallet;
}

class _LiveTipSheet extends StatefulWidget {
  const _LiveTipSheet({required this.args});

  final LiveTipLaunchArgs args;

  @override
  State<_LiveTipSheet> createState() => _LiveTipSheetState();
}

class _LiveTipSheetState extends State<_LiveTipSheet> {
  int _selectedIndex = 0;
  bool _includeNote = false;
  final _noteController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  LiveTipPreset get _selected => kLiveTipPresets[_selectedIndex];

  String? get _note =>
      _includeNote ? _noteController.text.trim() : null;

  Future<void> _onNext() async {
    if (_busy || currentUserUid.isEmpty) return;
    setState(() => _busy = true);
    try {
      await WalletService.ensureWallet(currentUserUid);
      final balance = await WalletService.fetchAvailableBalance(currentUserUid);
      final amount = _selected.amountEur;

      if (balance + 0.001 >= amount) {
        final tipId = await WalletService.sendLiveTipFromWallet(
          liveId: widget.args.liveId,
          sellerId: widget.args.sellerId,
          amountEur: amount,
          message: _note,
        );
        if (!mounted) return;
        Navigator.of(context).pop(
          LiveTipResult(
            success: tipId != null,
            amountEur: amount,
            message: _note,
            usedWallet: true,
          ),
        );
        return;
      }

      if (!mounted) return;
      final proceed = await _showInsufficientBalanceDialog(amount, balance);
      if (proceed != true || !mounted) return;

      final checkout = await WalletService.openLiveTipStripeCheckout(
        liveId: widget.args.liveId,
        sellerId: widget.args.sellerId,
        amountEur: amount,
        message: _note,
        playbackId: widget.args.playbackId,
        isLive: widget.args.isLive,
      );
      if (!mounted) return;
      await FleaberStripeTipContext.save(
        liveId: widget.args.liveId,
        sellerId: widget.args.sellerId,
        tipId: checkout.tipId,
        playbackId: widget.args.playbackId,
        isLive: widget.args.isLive,
        checkoutSessionId: checkout.checkoutSessionId,
      );
      final uri = Uri.parse(checkout.checkoutUrl);
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableDomStorage: true,
        ),
      );
      if (!opened) {
        await FleaberStripeTipContext.clear();
        throw Exception('Não foi possível abrir o pagamento.');
      }
      Navigator.of(context).pop(
        LiveTipResult(success: false, amountEur: amount, message: _note),
      );
      unawaited(FleaberStripeTipContext.trySettlePendingTip());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showInsufficientBalanceDialog(
    double needed,
    double balance,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Saldo insuficiente',
          style: GoogleFonts.interTight(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Tens ${formatEuros(balance)} na carteira Fleaber e a gorjeta é de '
          '${formatEuros(needed)}.\n\n'
          'Queres continuar para pagar com cartão? Depois do pagamento voltas '
          'automaticamente ao direto.',
          style: GoogleFonts.inter(height: 1.45, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FleaberPrimaryButton.compact(
            label: 'Pagar',
            backgroundColor: _kTeal,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final seller = widget.args.sellerName?.trim();
    final fee = liveTipProcessingFeeEur(_selected.amountEur);
    final sellerGets = liveTipSellerReceivesEur(_selected.amountEur);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 14),
          Text(
            'Enviar gorjeta',
            textAlign: TextAlign.center,
            style: GoogleFonts.interTight(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            seller == null || seller.isEmpty
                ? 'Agradece ao vendedor durante o direto. O valor entra na carteira dele (menos taxa de processamento).'
                : 'Agradece a $seller durante o direto. O valor entra na carteira dele (menos taxa de processamento).',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF57636C),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Escolhe o valor',
            style: GoogleFonts.interTight(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'O vendedor recebe ${formatEuros(sellerGets)} (taxa ${formatEuros(fee)}).',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF57636C),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: List.generate(kLiveTipPresets.length, (i) {
              final preset = kLiveTipPresets[i];
              final selected = i == _selectedIndex;
              return InkWell(
                onTap: _busy ? null : () => setState(() => _selectedIndex = i),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? Colors.black : const Color(0xFFE0E8EB),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(preset.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(
                        '${preset.amountEur.toStringAsFixed(0)} €',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mensagem de agradecimento',
                      style: GoogleFonts.interTight(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Aparece no chat do direto.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF57636C),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _includeNote,
                activeColor: _kTeal,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _includeNote = v),
              ),
            ],
          ),
          if (_includeNote) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLength: 120,
              decoration: InputDecoration(
                hintText: 'Obrigado pelo direto!',
                filled: true,
                fillColor: const Color(0xFFF3F6F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FleaberPrimaryButton(
                  label: 'Seguinte',
                  loading: _busy,
                  backgroundColor: _kTeal,
                  onPressed: _busy ? null : _onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
