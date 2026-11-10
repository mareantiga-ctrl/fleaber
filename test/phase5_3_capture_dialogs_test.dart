import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/widgets/seller_reservation_policy_sheet.dart';

/// Gera PNGs em screenshots/ via --update-goldens (widget real = prova de layout).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('G saco mudou 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: FleaberBagChangedDialog(
              unavailableCount: 2,
              totalCents: 1236,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(FleaberBagChangedDialog),
      matchesGoldenFile(
        '../14-unified-commerce-phase5.3-final-polish/screenshots/G_saco_mudou_390.png',
      ),
    );
  });

  testWidgets('I saco mudou desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: FleaberBagChangedDialog(
                unavailableCount: 1,
                totalCents: 350,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(FleaberBagChangedDialog),
      matchesGoldenFile(
        '../14-unified-commerce-phase5.3-final-polish/screenshots/I_saco_mudou_desktop.png',
      ),
    );
  });

  testWidgets('J politica reservas', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SellerReservationPolicySheet(
            requireSaveToDismiss: false,
            title: 'Política de reservas',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SellerReservationPolicySheet),
      matchesGoldenFile(
        '../14-unified-commerce-phase5.3-final-polish/screenshots/J_politica_reservas_390.png',
      ),
    );
  });
}
