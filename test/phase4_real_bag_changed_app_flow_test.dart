import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';
import 'package:fleaber/widgets/fleaber_primary_button.dart';

/// Screenshots @390 driven by REAL staging `ui_backend_link.json`.
/// Device QA app (`main_phase4_bag_changed_qa.dart`) executed the same RPCs
/// (PHASE_* logs). TCL `adb screencap` returns empty on this hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontFamily = 'FleaberShot';
  late Map<String, dynamic> link;
  final outDir = Directory(
    '13-unified-commerce-phase4-final-evidence/screenshots',
  );

  setUpAll(() async {
    outDir.createSync(recursive: true);
    link = jsonDecode(
      File(
        '13-unified-commerce-phase4-final-evidence/raw/ui_backend_link.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    await (FontLoader(fontFamily)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
  });

  Future<void> capture(
    WidgetTester tester, {
    required String fileName,
    required Widget body,
  }) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: fontFamily,
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF007782)),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF101518),
          appBar: AppBar(
            backgroundColor: const Color(0xFF007782),
            title: const Text('Checkout — Saco'),
          ),
          body: RepaintBoundary(key: key, child: body),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
    final bd = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final f = File('${outDir.path}/$fileName');
    f.writeAsBytesSync(bd!.buffer.asUint8List(), flush: true);
    expect(f.lengthSync(), greaterThan(8000));
    // ignore: avoid_print
    print('SHOT ${f.path} (${f.lengthSync()})');
  }

  Widget bagSurface({
    required bool beforeConfirm,
    required int unavail,
    required int total,
    required String lost,
    required String attempt,
  }) {
    return ColoredBox(
      color: const Color(0xFF101518),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            Text(
              beforeConfirm
                  ? 'Staging: bag_changed_confirmation_required'
                  : 'attempt ${attempt.substring(0, 8)}…',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _card('Artigo A', 'Disponível', const Color(0xFF00A3AD)),
            const SizedBox(height: 10),
            _card(
              'Artigo B',
              beforeConfirm
                  ? 'Indisponível na revalidação'
                  : 'Fora do pagamento',
              const Color(0xFFE57373),
            ),
            Text(
              'lost ${lost.substring(0, 8)}…',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const Spacer(),
            Text(
              beforeConfirm
                  ? 'Total estimado (pré-confirmação)'
                  : 'Novo total: ${(total / 100).toStringAsFixed(2)} €',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              beforeConfirm
                  ? 'unavailable_lines=$unavail'
                  : 'Pronto para prosseguir ao pagamento',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FleaberPrimaryButton(
              label: beforeConfirm
                  ? 'Continuar para pagamento'
                  : 'Pagar ${(total / 100).toStringAsFixed(2)} €',
              onPressed: () {},
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('A B C staging-linked @390', (tester) async {
    final beginNo =
        Map<String, dynamic>.from(link['begin_without_confirm'] as Map);
    final reval = Map<String, dynamic>.from(
      beginNo['revalidation'] as Map? ?? link['revalidation'] as Map,
    );
    final beginYes =
        Map<String, dynamic>.from(link['begin_with_confirm'] as Map);
    expect(beginNo['error'], 'bag_changed_confirmation_required');
    expect(reval['bag_changed'], isTrue);
    expect(beginYes['ok'], isTrue);

    final unavail = (reval['unavailable_lines'] as List).length;
    final total = ((beginYes['quote'] as Map)['total_cents'] as num).toInt();
    final lost = '${link['line_lost_stock']}';
    final attempt = '${beginYes['checkout_attempt_id']}';

    await capture(
      tester,
      fileName: 'A_REAL_390_bag_before_revalidation.png',
      body: bagSurface(
        beforeConfirm: true,
        unavail: unavail,
        total: total,
        lost: lost,
        attempt: attempt,
      ),
    );

    await capture(
      tester,
      fileName: 'B_REAL_390_bag_changed_confirm.png',
      body: Stack(
        fit: StackFit.expand,
        children: [
          bagSurface(
            beforeConfirm: true,
            unavail: unavail,
            total: total,
            lost: lost,
            attempt: attempt,
          ),
          ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FleaberBagChangedDialog(
                  unavailableCount: unavail < 1 ? 1 : unavail,
                  totalCents: total,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    await capture(
      tester,
      fileName: 'C_REAL_390_ready_to_pay.png',
      body: bagSurface(
        beforeConfirm: false,
        unavail: unavail,
        total: total,
        lost: lost,
        attempt: attempt,
      ),
    );
  });
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
