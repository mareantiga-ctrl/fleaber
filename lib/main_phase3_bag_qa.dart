import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/qa/phase3_qa_seed.g.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/live_bag_sheet.dart';

/// Staging QA entry — real LiveBagSheet wired to seller bag (full-page embed).
///
///   flutter run -d chrome --web-port=7361 -t lib/main_phase3_bag_qa.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupaFlow.initialize();
  runApp(const Phase3BagQaApp());
}

class Phase3BagQaApp extends StatelessWidget {
  const Phase3BagQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Phase3BagQaPage(),
    );
  }
}

class Phase3BagQaPage extends StatefulWidget {
  const Phase3BagQaPage({super.key});

  @override
  State<Phase3BagQaPage> createState() => _Phase3BagQaPageState();
}

class _Phase3BagQaPageState extends State<Phase3BagQaPage> {
  String _status = 'Starting…';
  Widget? _bag;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      setState(() => _status = 'Signing in…');
      final res = await SupaFlow.client.auth.signInWithPassword(
        email: kPhase3QaSeed['buyer_email']!,
        password: kPhase3QaSeed['buyer_password']!,
      );
      final uid = res.user?.id ?? SupaFlow.client.auth.currentUser?.id ?? '';
      if (uid.isEmpty) {
        setState(() => _status = 'Sign-in returned empty user');
        return;
      }
      setState(() => _status = 'Signed in — loading seller bag…');
      await _loadBag(buyerIdOverride: uid);
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _loadBag({String? buyerIdOverride}) async {
    final sellerId = kPhase3QaSeed['seller_id']!;
    final liveId = kPhase3QaSeed['live_id']!;
    final buyerId = (buyerIdOverride ??
            SupaFlow.client.auth.currentUser?.id ??
            currentUserUid)
        .trim();
    if (buyerId.isEmpty) {
      setState(() => _status = 'No buyer session');
      return;
    }

    final items = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', liveId),
      limit: 100,
    );
    final byId = {
      for (final i in items)
        if ((i.id ?? '').isNotEmpty) i.id!: i,
    };

    if (!mounted) return;
    setState(() {
      _status = 'Seller bag loaded';
      _bag = Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          child: LiveBagSheet.embed(
            liveId: liveId,
            buyerId: buyerId,
            catalogByItemId: byId,
            liveSellerId: sellerId,
            isLive: true,
            loadRows: () => LiveReservationQueueService().sellerBagDisplayRequests(
              sellerId: sellerId,
              buyerId: buyerId,
            ),
            loadSellerBagMeta: () =>
                LiveReservationQueueService().loadSellerBag(sellerId: sellerId),
            fetchStock: (item) async {
              final id = item.id?.trim() ?? '';
              if (id.isEmpty) return null;
              return LiveCatalogStockService.fetch(id);
            },
            resolveProduct: (item) async {
              final pid = (item.productId ?? item.checkoutProductId ?? '').trim();
              if (pid.isEmpty) return null;
              final rows = await ProductsTable().queryRows(
                queryFn: (q) => q.eqOrNull('id', pid),
                limit: 1,
              );
              return rows.isEmpty ? null : rows.first;
            },
            openSingleCheckout:
                (_, {liveItemId, reservationRequestId, payQty = 1}) async {},
            openMultiCheckout: (_) async {},
            focusReservationRequestId: kPhase3QaSeed['guaranteed_request_id'],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11181C),
      body: _bag ??
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Phase 3 — Seller bag QA',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
          ),
    );
  }
}
