import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/widgets/fleaber_bag_changed_dialog.dart';

/// Real Flutter UI screenshots of Phase 4 bag_changed dialog @ 390×844.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontFamily = 'FleaberShot';
  final packDir = Directory(
    '13-unified-commerce-phase4-final-correction/screenshots',
  );

  setUpAll(() async {
    packDir.createSync(recursive: true);
    Directory('test/goldens/phase4_bag_changed').createSync(recursive: true);
    final candidates = <String>[
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
      r'C:\Windows\Fonts\calibri.ttf',
    ];
    Uint8List? bytes;
    for (final p in candidates) {
      final f = File(p);
      if (f.existsSync()) {
        bytes = f.readAsBytesSync();
        break;
      }
    }
    expect(bytes, isNotNull, reason: 'Need a system TTF for readable screenshots');
    final loader = FontLoader(fontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes!)));
    await loader.load();
  });

  Future<void> capture(
    WidgetTester tester, {
    required String fileName,
    required FleaberBagChangedDialog dialog,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF007782)),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF101518),
          body: Center(child: SizedBox(width: 390, child: dialog)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final goldenRel = 'goldens/phase4_bag_changed/$fileName';
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenRel));

    final goldenFile = File('test/$goldenRel');
    final dest = File('${packDir.path}/$fileName');
    try {
      dest.writeAsBytesSync(goldenFile.readAsBytesSync(), flush: true);
    } on PathAccessException {
      File('${packDir.path}/ok_$fileName')
          .writeAsBytesSync(goldenFile.readAsBytesSync(), flush: true);
    }
    expect(File('${packDir.path}/$fileName').existsSync() ||
            File('${packDir.path}/ok_$fileName').existsSync(),
        isTrue);
    // ignore: avoid_print
    print('SCREENSHOT pack/$fileName (${goldenFile.lengthSync()} bytes)');
  }

  testWidgets('A — bag_changed unavailable @390', (tester) async {
    await capture(
      tester,
      fileName: 'A_bag_changed_unavailable_390.png',
      dialog: const FleaberBagChangedDialog(
        unavailableCount: 1,
        totalCents: 1065,
      ),
    );
    expect(find.text('O saco mudou'), findsOneWidget);
  });

  testWidgets('B — confirm continue remainder @390', (tester) async {
    await capture(
      tester,
      fileName: 'B_confirm_continue_remainder_390.png',
      dialog: const FleaberBagChangedDialog(
        unavailableCount: 1,
        totalCents: 1065,
      ),
    );
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('C — recalculated total before pay @390', (tester) async {
    await capture(
      tester,
      fileName: 'C_recalculated_total_before_pay_390.png',
      dialog: const FleaberBagChangedDialog(
        unavailableCount: 2,
        totalCents: 2548,
      ),
    );
    expect(find.textContaining('Novo total: 25.48 €'), findsOneWidget);
  });
}
