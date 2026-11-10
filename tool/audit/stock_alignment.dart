// Compara quantidades BD vs UI (seller/buyer).

import 'models.dart';



final _fieldMap = <String, int? Function(QtySnapshot)>{

  'total_qty': (QtySnapshot s) => s.totalQty,

  'available_qty': (QtySnapshot s) => s.availableQty,

  'reserved_qty': (QtySnapshot s) => s.reservedQty,

  'sold_qty': (QtySnapshot s) => s.soldQty ?? s.soldConvertedQty,

  'blocked_qty': (QtySnapshot s) => s.blockedQty,

  'cross_reserved_qty': (QtySnapshot s) => s.crossReservedQty,

  'sold_converted_qty': (QtySnapshot s) => s.soldConvertedQty ?? s.soldQty,

};



class StockAlignment {

  static List<StockMismatch> compare({

    required List<QtySnapshot> bdSnapshots,

    required List<QtySnapshot> sellerUi,

    required List<QtySnapshot> buyerUi,

    String query = 'rpc batata_live_item_stock',

    String screenshot = '',

    String scenario = '',

    List<String> sellerTexts = const [],

  }) {

    final mismatches = <StockMismatch>[];

    if (bdSnapshots.isEmpty) return mismatches;



    final bd = bdSnapshots.first;

    final sellerSnap = _pickUiSnapshot(sellerUi);

    final buyerSnap = _pickUiSnapshot(buyerUi);

    final scen = scenario.toLowerCase();

    final soldScenario = scen.contains('vendid') || scen.contains('cs06');



    for (final entry in _fieldMap.entries) {

      final field = entry.key;

      final getter = entry.value;

      final bdVal = getter(bd);

      if (bdVal == null) continue;



      if (soldScenario &&

          field == 'available_qty' &&

          bdVal == 0 &&

          _sellerShowsSoldState(sellerTexts)) {

        continue;

      }



      for (final uiList in [

        ('seller_ui', sellerSnap),

        ('buyer_ui', buyerSnap),

      ]) {

        final label = uiList.$1;

        final snap = uiList.$2;

        if (snap == null) continue;

        final uiVal = getter(snap);

        if (uiVal == null) continue;

        if (uiVal != bdVal) {

          mismatches.add(StockMismatch(

            field: field,

            expected: bdVal,

            found: uiVal,

            sourceA: 'bd_rpc',

            sourceB: label,

            query: query,

            screenshot: screenshot,

            probableCause:

                'UI mostra $uiVal mas BD tem $bdVal em $field ($label)',

          ));

        }

      }

    }

    return mismatches;

  }



  static QtySnapshot? _pickUiSnapshot(List<QtySnapshot> snaps) {

    if (snaps.isEmpty) return null;

    for (var i = snaps.length - 1; i >= 0; i--) {

      final s = snaps[i];

      if (s.source.contains('catalog_metrics')) return s;

    }

    return snaps.last;

  }



  static bool _sellerShowsSoldState(List<String> texts) {

    final blob = texts.join('\n').toLowerCase();

    return blob.contains('vendido') ||

        blob.contains('esgotado') ||

        blob.contains('reserved_full');

  }



  static bool requiresStockAudit(String testId, String scenario, String layer) {

    final id = '${testId}_$scenario'.toLowerCase();

    const keys = [

      'stock',

      'qty',

      'a3',

      'r32',

      'cross',

      'pool',

      'reserv',

      'vendid',

      'catalog',

      'saco',

      'bag',

      'gravado',

      'marketplace',

      'cs02',

      'cs03',

      'cs04',

      'cs05',

      'cs06',

      't07b',

      't08d',

      't09',

    ];

    if (layer.contains('BD') && !layer.contains('UX')) {

      return keys.any((k) => id.contains(k));

    }

    return keys.any((k) => id.contains(k));

  }

}

