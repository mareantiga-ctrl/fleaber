// ignore_for_file: avoid_print
/// Testes do espelho da regra do saco (tooling — sem Flutter).
///   dart run tool/bag_crosscheck_logic_test.dart
library;

import 'bag_crosscheck_logic.dart';

void main() {
  var failed = 0;

  void check(String name, bool ok, [String detail = '']) {
    if (ok) {
      print('PASS $name');
    } else {
      print('FAIL $name ${detail.isEmpty ? '' : '— $detail'}');
      failed++;
    }
  }

  // pending fleaber_live + live_item_id → 1 no saco
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'pending',
        'source': 'fleaber_live',
        'live_item_id': 'item-1',
        'requested_qty': 1,
      },
    ]);
    check('pending_visible_in_bag', r.inBagRowCount == 1 && r.inBagUnitQty == 1);
    check('label_1_no_saco', r.inBagRowCount == 1);
  }

  // qty 2 → 1 linha no contador UI, 2 unidades
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'pending',
        'source': 'fleaber_live',
        'live_item_id': 'item-1',
        'requested_qty': 2,
      },
    ]);
    check('qty2_rows_1', r.inBagRowCount == 1);
    check('qty2_units_2', r.inBagUnitQty == 2);
  }

  // source errada → 0 no saco apesar de pending (causa F5 candidata)
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'pending',
        'source': 'facebook_manual',
        'live_item_id': 'item-1',
        'requested_qty': 1,
      },
    ]);
    check('wrong_source_zero_bag', r.inBagRowCount == 0 && r.pendingAnySource == 1);
    check('wrong_source_diag', r.diagnoses.isNotEmpty);
  }

  // live_item_id vazio → 0 no saco
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'pending',
        'source': 'fleaber_live',
        'live_item_id': '',
        'requested_qty': 1,
      },
    ]);
    check('empty_item_zero_bag', r.inBagRowCount == 0 && r.skippedEmptyLiveItemId == 1);
  }

  // accepted também conta
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'accepted',
        'source': 'fleaber_live',
        'live_item_id': 'item-1',
        'requested_qty': 1,
      },
    ]);
    check('accepted_in_bag', r.inBagRowCount == 1);
  }

  // rejected não conta em «no saco»
  {
    final r = BagCrosscheckLogic.fromRows([
      {
        'status': 'rejected',
        'source': 'fleaber_live',
        'live_item_id': 'item-1',
        'requested_qty': 1,
        'notes': 'bag_removed',
      },
    ]);
    check('rejected_not_in_bag', r.inBagRowCount == 0);
  }

  if (failed > 0) {
    print('FAILED $failed');
    throw StateError('bag_crosscheck_logic_test failed: $failed');
  }
  print('ALL PASS');
}
