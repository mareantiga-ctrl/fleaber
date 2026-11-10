import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/widgets/seller_reservation_policy_sheet.dart';

Future<void> _loadInter() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final file = File('tool/fonts_cache/Inter-var.ttf');
  final bytes = await file.readAsBytes();
  final data = ByteData.view(bytes.buffer);
  final loader = FontLoader('Inter')..addFont(Future.value(data));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadInter();
  });

  testWidgets('F5 golden captures A/B/C/D/O', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: const Scaffold(
          body: SellerReservationPolicySheet(
            requireSaveToDismiss: true,
            title: 'Antes do primeiro direto',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await expectLater(
      find.byType(SellerReservationPolicySheet),
      matchesGoldenFile(
        '../14-unified-commerce-phase5-live-seller-studio/screenshots/A_first_live_policy_gate_390.png',
      ),
    );
    await expectLater(
      find.byType(SellerReservationPolicySheet),
      matchesGoldenFile(
        '../14-unified-commerce-phase5-live-seller-studio/screenshots/B_policy_config_complete_390.png',
      ),
    );
    await expectLater(
      find.byType(SellerReservationPolicySheet),
      matchesGoldenFile(
        '../14-unified-commerce-phase5-live-seller-studio/screenshots/C_mode_pedir_autorizacao_390.png',
      ),
    );

    await tester.tap(find.text('Só o pagamento garante'));
    await tester.pump();
    await expectLater(
      find.byType(SellerReservationPolicySheet),
      matchesGoldenFile(
        '../14-unified-commerce-phase5-live-seller-studio/screenshots/D_mode_so_pagamento_garante_390.png',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: Scaffold(
          body: Center(
            child: FleaberBagChangedDialog(
              unavailableCount: 1,
              totalCents: 1236,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(FleaberBagChangedDialog),
      matchesGoldenFile(
        '../14-unified-commerce-phase5-live-seller-studio/screenshots/O_widget_continuar_content_sized_390.png',
      ),
    );
  });
}
