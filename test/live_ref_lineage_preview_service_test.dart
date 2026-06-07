import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/live_ref_lineage_preview_service.dart';

void main() {
  group('lineageEntryHasRelevantHistory (L1/L2/L3)', () {
    final now = DateTime.utc(2026, 6, 1);

    test('L1 — reservas abertas', () {
      expect(
        lineageEntryHasRelevantHistory(
          openReservationCount: 2,
          completedPurchaseCount: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('L2 — vendas concluídas (18 meses)', () {
      expect(
        lineageEntryHasRelevantHistory(
          openReservationCount: 0,
          completedPurchaseCount: 1,
          lastUsedAt: DateTime.utc(2024, 12, 1),
          now: now,
        ),
        isTrue,
      );
    });

    test('L3 — só uso recente (<12 meses)', () {
      expect(
        lineageEntryHasRelevantHistory(
          openReservationCount: 0,
          completedPurchaseCount: 0,
          lastUsedAt: DateTime.utc(2026, 1, 1),
          now: now,
        ),
        isTrue,
      );
    });

    test('L3 — uso antigo sem actividade (20 meses) → false', () {
      expect(
        lineageEntryHasRelevantHistory(
          openReservationCount: 0,
          completedPurchaseCount: 0,
          lastUsedAt: DateTime.utc(2024, 10, 1),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('computeShouldShowSheetFromLineages', () {
    test('Caso C — reservas abertas há 3 anos', () {
      final lineages = [
        LiveRefLineageEntry(
          logicalItemId: 'uuid-a',
          displayTitle: 'Puzzle',
          lastOrigin: 'Gravado',
          openReservationCount: 2,
          openReservedUnits: 2,
          completedPurchaseCount: 0,
          completedUnits: 0,
          lastUsedAt: DateTime.utc(2023, 1, 1),
        ),
      ];
      expect(computeShouldShowSheetFromLineages(lineages), isTrue);
    });
  });

  group('LiveRefLineagePreviewReport.fromRpc', () {
    test('parse payload com linhagens e draft', () {
      final report = LiveRefLineagePreviewReport.fromRpc({
        'ok': true,
        'ref_code': '#15',
        'ref_normalized': '15',
        'usage_window_months': 12,
        'has_relevant_history': true,
        'should_show_sheet': true,
        'summary': {
          'lineage_count': 2,
          'open_reservation_count': 2,
          'open_reserved_units': 3,
          'completed_purchase_count': 5,
          'completed_units': 6,
        },
        'lineages': [
          {
            'logical_item_id': 'uuid-puzzle',
            'display_title': 'Puzzle Star Wars',
            'open_reservation_count': 2,
            'open_reserved_units': 3,
            'completed_purchase_count': 0,
            'completed_units': 0,
            'last_origin': 'Gravado',
          },
          {
            'logical_item_id': 'uuid-boneca',
            'display_title': 'Boneca Barbie',
            'open_reservation_count': 0,
            'open_reserved_units': 0,
            'completed_purchase_count': 5,
            'completed_units': 6,
            'last_origin': 'Direto anterior',
          },
        ],
        'draft': {
          'live_item_id': null,
          'logical_item_id': null,
          'needs_lineage_decision': true,
        },
      });

      expect(report.refCode, '#15');
      expect(report.lineages.length, 2);
      expect(report.needsSheetForDraft, isTrue);
      expect(report.lineages.first.badgeLabel(), contains('reservas abertas'));
      expect(report.lineages[1].badgeLabel(), contains('vendas concluídas'));
    });

    test('draft com logical_item_id → sem sheet', () {
      final report = LiveRefLineagePreviewReport.fromRpc({
        'ok': true,
        'ref_code': '#15',
        'should_show_sheet': true,
        'summary': {'lineage_count': 1},
        'lineages': [],
        'draft': {
          'logical_item_id': 'uuid-existing',
          'needs_lineage_decision': false,
        },
      });
      expect(report.needsSheetForDraft, isFalse);
    });
  });

  group('LiveOnlyUpsertResult.fromRpc', () {
    test('parse jsonb upsert', () {
      final r = LiveOnlyUpsertResult.fromRpc({
        'ok': true,
        'live_item_id': 'item-1',
        'logical_item_id': 'lineage-1',
        'lineage_mode': 'inherit',
      });
      expect(r.liveItemId, 'item-1');
      expect(r.logicalItemId, 'lineage-1');
      expect(r.lineageMode, 'inherit');
    });

    test('keep mode após re-gravação draft', () {
      final r = LiveOnlyUpsertResult.fromRpc({
        'ok': true,
        'live_item_id': 'item-1',
        'logical_item_id': 'lineage-1',
        'lineage_mode': 'keep',
      });
      expect(r.lineageMode, 'keep');
    });
  });
}
