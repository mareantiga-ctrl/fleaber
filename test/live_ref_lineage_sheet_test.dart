import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_ref_lineage_preview_service.dart';
import 'package:fleaber/widgets/live_ref_lineage_sheet.dart';
import 'package:google_fonts/google_fonts.dart';

LiveRefLineagePreviewReport _overflowReport({int lineageCount = 5}) {
  return LiveRefLineagePreviewReport(
    isOk: true,
    refCode: '#15',
    refNormalized: '15',
    usageWindowMonths: 12,
    hasRelevantHistory: true,
    shouldShowSheet: true,
    summary: LiveRefLineageSummary(
      lineageCount: lineageCount,
      openReservationCount: lineageCount,
      openReservedUnits: lineageCount,
      completedPurchaseCount: 0,
      completedUnits: 0,
    ),
    lineages: List.generate(
      lineageCount,
      (i) => LiveRefLineageEntry(
        logicalItemId: 'uuid-$i',
        displayTitle: 'Artigo histórico $i com título longo',
        canContinue: true,
        lastOrigin: 'Gravado',
        openReservationCount: 1,
        openReservedUnits: 1,
        completedPurchaseCount: 0,
        completedUnits: 0,
        lastUsedAt: DateTime.utc(2026, 1, 1),
      ),
    ),
    draft: const LiveRefLineageDraftState(needsLineageDecision: true),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('conteúdo longo é scrollável até Cancelar e novo artigo',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 640)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LiveRefLineageSheet(report: _overflowReport()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Começar novo histórico'), findsOneWidget);
    expect(find.text('Continuar histórico'), findsNWidgets(5));

    final cancelar = find.text('Cancelar');
    await tester.scrollUntilVisible(
      cancelar,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(cancelar).bottom, lessThanOrEqualTo(640));
    expect(tester.getRect(cancelar).top, greaterThanOrEqualTo(0));
  });
}
