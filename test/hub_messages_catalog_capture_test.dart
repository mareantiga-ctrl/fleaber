import 'dart:io';
import 'dart:ui' as ui;

import 'package:fleaber/hub/pages/hub_messages_visual_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNGs distintos F01–F17 a partir do catálogo (componentes reais).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('H10 catalog family captures', (tester) async {
    final outDir = Directory(
      'tool/reports/fleahub_h10_mensagens_polish_115_1_2026-10-26/captures/families',
    );
    outDir.createSync(recursive: true);

    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: HubMessagesVisualCatalogPage()),
    );
    await tester.pumpAndSettle();

    const ids = [
      'F01',
      'F02',
      'F03',
      'F04',
      'F05',
      'F06',
      'F07',
      'F08',
      'F09',
      'F10',
      'F11',
      'F12',
      'F13',
      'F14',
      'F15',
      'F16',
      'F17',
      'F07b',
    ];

    for (final id in ids) {
      final finder = find.byKey(ValueKey('h10_family_$id'));
      expect(finder, findsOneWidget, reason: 'missing $id');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();

      final element = tester.element(finder);
      final padding = element.findRenderObject() as RenderBox;
      RenderRepaintBoundary? boundary;
      padding.visitChildren((child) {
        if (child is RenderRepaintBoundary) boundary = child;
      });
      expect(boundary, isNotNull, reason: 'no RepaintBoundary for $id');

      final image = await boundary!.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final file = File('${outDir.path}/$id.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path} bytes=${file.lengthSync()}');
    }
  });
}
