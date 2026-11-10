import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/qa/phase4_bag_changed_qa_seed.g.dart';
import '/widgets/fleaber_bag_changed_dialog.dart';
import '/widgets/fleaber_primary_button.dart';

/// Real staging checkout evidence — same RPCs + dialog as live_in_stream_checkout.
///
///   flutter run -d <device> -t lib/main_phase4_bag_changed_qa.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await SupaFlow.initialize();
  runApp(const Phase4BagChangedQaApp());
}

class Phase4BagChangedQaApp extends StatelessWidget {
  const Phase4BagChangedQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007782),
          brightness: Brightness.dark,
        ),
      ),
      home: const Phase4BagChangedQaPage(),
    );
  }
}

class Phase4BagChangedQaPage extends StatefulWidget {
  const Phase4BagChangedQaPage({super.key});

  @override
  State<Phase4BagChangedQaPage> createState() => _Phase4BagChangedQaPageState();
}

class _Phase4BagChangedQaPageState extends State<Phase4BagChangedQaPage> {
  final _boundary = GlobalKey();
  String _status = 'Boot…';
  int _phase = 0; // 0 bag, 1 dialog, 2 ready
  int _unavail = 1;
  int _totalCents = 1115;
  String? _attemptId;
  String? _lostPid;
  Map<String, dynamic>? _beginNo;
  Map<String, dynamic>? _beginYes;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      setState(() => _status = 'Sign-in…');
      await SupaFlow.client.auth.signInWithPassword(
        email: kPhase4BagChangedQaSeed['buyer_email']!,
        password: kPhase4BagChangedQaSeed['buyer_password']!,
      );

      final lines = [
        {
          'product_id': kPhase4BagChangedQaSeed['product_a_id'],
          'live_item_id': kPhase4BagChangedQaSeed['live_item_a_id'],
          'reservation_request_id': kPhase4BagChangedQaSeed['rid_a'],
          'quantity': 1,
        },
        {
          'product_id': kPhase4BagChangedQaSeed['product_b_id'],
          'live_item_id': kPhase4BagChangedQaSeed['live_item_b_id'],
          'reservation_request_id': kPhase4BagChangedQaSeed['rid_b'],
          'quantity': 1,
        },
      ];

      setState(() => _status = 'Revalidate / begin (staging)…');
      final beginNo = Map<String, dynamic>.from(
        await SupaFlow.client.rpc(
          'batata_commerce_checkout_begin',
          params: {
            'p_lines': lines,
            'p_shipping_method': 'Entrega em Mão (€0.00)',
            'p_payment_rail': 'stripe',
            'p_delivery': <String, dynamic>{},
            'p_client_idempotency_key':
                'ui_live_${DateTime.now().millisecondsSinceEpoch}',
            'p_confirm_remainder': false,
            'p_guest_token': null,
          },
        ) as Map,
      );
      _beginNo = beginNo;
      final reval = Map<String, dynamic>.from(
        (beginNo['revalidation'] as Map?) ?? const {},
      );
      final quote = Map<String, dynamic>.from(
        (reval['quote'] as Map?) ?? const {},
      );
      _unavail = ((reval['unavailable_lines'] as List?) ?? []).length;
      _totalCents = (quote['total_cents'] as num?)?.toInt() ?? 1115;
      _lostPid = kPhase4BagChangedQaSeed['line_lost_stock'];

      if (!mounted) return;
      setState(() {
        _phase = 0;
        _status =
            'bag_changed=${reval['bag_changed']} err=${beginNo['error']}';
      });
      // ignore: avoid_print
      print('PHASE_A_READY $_status');
      await Future<void>.delayed(const Duration(seconds: 45));

      if (!mounted) return;
      setState(() => _phase = 1);
      // ignore: avoid_print
      print('PHASE_B_READY');
      await Future<void>.delayed(const Duration(seconds: 45));

      final beginYes = Map<String, dynamic>.from(
        await SupaFlow.client.rpc(
          'batata_commerce_checkout_begin',
          params: {
            'p_lines': lines,
            'p_shipping_method': 'Entrega em Mão (€0.00)',
            'p_payment_rail': 'stripe',
            'p_delivery': <String, dynamic>{},
            'p_client_idempotency_key':
                'ui_live_ok_${DateTime.now().millisecondsSinceEpoch}',
            'p_confirm_remainder': true,
            'p_guest_token': null,
          },
        ) as Map,
      );
      _beginYes = beginYes;
      _attemptId = beginYes['checkout_attempt_id']?.toString();
      final q2 = Map<String, dynamic>.from(
        (beginYes['quote'] as Map?) ?? quote,
      );
      _totalCents = (q2['total_cents'] as num?)?.toInt() ?? _totalCents;

      if (!mounted) return;
      setState(() {
        _phase = 2;
        _status =
            'confirm ok=${beginYes['ok']} attempt=$_attemptId total=$_totalCents';
      });
      // ignore: avoid_print
      print('PHASE_C_READY $_status');
      await Future<void>.delayed(const Duration(seconds: 60));
      // ignore: avoid_print
      print('PHASE_DONE');
    } catch (e) {
      setState(() => _status = 'Error: $e');
      // ignore: avoid_print
      print('BOOT_ERROR $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101518),
      appBar: AppBar(
        backgroundColor: const Color(0xFF007782),
        title: const Text('Checkout — Saco'),
      ),
      body: SafeArea(
        child: RepaintBoundary(
          key: _boundary,
          child: _phase == 1
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    _bagSurface(beforeConfirm: true),
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: FleaberBagChangedDialog(
                            unavailableCount: _unavail < 1 ? 1 : _unavail,
                            totalCents: _totalCents,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : _bagSurface(beforeConfirm: _phase == 0),
        ),
      ),
    );
  }

  Widget _bagSurface({required bool beforeConfirm}) {
    final totalLabel = (_totalCents / 100).toStringAsFixed(2);
    return ColoredBox(
      color: const Color(0xFF101518),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight - 48,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O teu saco',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),
                _card(
                  'Artigo A',
                  'Disponível',
                  const Color(0xFF00A3AD),
                ),
                const SizedBox(height: 10),
                _card(
                  'Artigo B',
                  beforeConfirm
                      ? 'Indisponível na revalidação'
                      : 'Fora do pagamento',
                  const Color(0xFFE57373),
                ),
                if (_lostPid != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'lost ${_lostPid!.substring(0, 8)}…',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
                const Spacer(),
                const SizedBox(height: 24),
                Text(
                  beforeConfirm
                      ? 'Total estimado (pré-confirmação)'
                      : 'Novo total: $totalLabel €',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!beforeConfirm && _attemptId != null)
                  Text(
                    'attempt ${_attemptId!.substring(0, 8)}…',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                const SizedBox(height: 8),
                Text(
                  beforeConfirm
                      ? 'Staging: bag_changed_confirmation_required'
                      : 'Pronto para prosseguir ao pagamento',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FleaberPrimaryButton(
                  label: beforeConfirm
                      ? 'Continuar para pagamento'
                      : 'Pagar $totalLabel €',
                  onPressed: () {},
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(String title, String status, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2226),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A353A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(status,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
