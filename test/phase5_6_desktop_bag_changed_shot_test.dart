import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/widgets/fleaber_primary_button.dart';

/// Captures a TRUE landscape (width > height) PNG of the bag-changed dialog
/// over a checkout-like surface using real product widgets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('I2 desktop landscape bag_changed shot', (tester) async {
    const size = Size(1280, 800);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget moneyRow(String label, double eur, {bool total = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: total ? Colors.white : Colors.white70,
                  fontWeight: total ? FontWeight.w800 : FontWeight.w400,
                  fontSize: total ? 14 : 12,
                ),
              ),
            ),
            Text(
              formatEuros(eur),
              style: TextStyle(
                color: total ? const Color(0xFF6ED8DE) : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: total ? 16 : 12,
              ),
            ),
          ],
        ),
      );
    }

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0E1418),
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Material(
                        color: const Color(0xFF1A2329),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Finalizar compra',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Escolhe o que queres pagar agora. Pagamento na app (cartão).',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Camisa branca · Calças ganga',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              moneyRow('Artigos (2)', 42.5),
                              moneyRow('Portes (entrega em mão)', 0),
                              moneyRow('Seguro Fleaber', 2.78),
                              const Divider(height: 16, color: Colors.white24),
                              moneyRow('Total', 45.28, total: true),
                              const SizedBox(height: 14),
                              FleaberPrimaryButton(
                                label: 'Pagar',
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const ColoredBox(color: Color(0x66000000)),
                  const Center(
                    child: FleaberBagChangedDialog(
                      unavailableCount: 1,
                      totalCents: 2638,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('O saco mudou'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    final out = File(
      '14-unified-commerce-phase5.6-visual-final/screenshots/'
      'I2_bag_changed_DESKTOP_FINAL.png',
    );
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(byteData!.buffer.asUint8List());
    expect(image.width, greaterThan(image.height));
    expect(image.width, 1280);
    expect(image.height, 800);
    File(
      '14-unified-commerce-phase5.6-visual-final/raw/I2_dimensions.txt',
    )
      ..createSync(recursive: true)
      ..writeAsStringSync('${image.width}x${image.height}');
  });
}
