/// Espelha a regra do saco comprador (sem Flutter):
/// - Query app: live_id + buyer_id + source=fleaber_live (`liveBagDisplayRequests`)
/// - Contagem «N no saco»: reservas pending|accepted com live_item_id não vazio
///   (`_sectionFor` → inBag; `_countReservations` = nº de linhas, não unidades)
library;

class BagCrosscheckResult {
  const BagCrosscheckResult({
    required this.bagQueryRowCount,
    required this.inBagRowCount,
    required this.inBagUnitQty,
    required this.skippedEmptyLiveItemId,
    required this.skippedWrongSource,
    required this.pendingAnySource,
    required this.pendingVisibleInBag,
    required this.diagnoses,
  });

  final int bagQueryRowCount;
  final int inBagRowCount;
  final int inBagUnitQty;
  final int skippedEmptyLiveItemId;
  final int skippedWrongSource;
  final int pendingAnySource;
  final int pendingVisibleInBag;
  final List<String> diagnoses;
}

class BagCrosscheckLogic {
  BagCrosscheckLogic._();

  static const bagSource = 'fleaber_live';

  /// [rows] = reservas do mesmo live_id + buyer_id (qualquer source/status).
  static BagCrosscheckResult fromRows(List<Map<String, dynamic>> rows) {
    var bagQuery = 0;
    var inBagRows = 0;
    var inBagUnits = 0;
    var skipItem = 0;
    var skipSource = 0;
    var pendingAny = 0;
    var pendingVisible = 0;
    final diagnoses = <String>[];

    for (final r in rows) {
      final status = (r['status'] ?? '').toString().trim();
      final source = (r['source'] ?? bagSource).toString().trim();
      final itemId = (r['live_item_id'] ?? '').toString().trim();
      final qtyRaw = r['requested_qty'];
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse('$qtyRaw') ?? 1;
      final unitQty = qty < 1 ? 1 : qty;

      if (status == 'pending') pendingAny++;

      if (source != bagSource) {
        skipSource++;
        if (status == 'pending' || status == 'accepted') {
          diagnoses.add(
            'reserva $status ignorada pelo saco: source="$source" '
            '(app filtra só $bagSource)',
          );
        }
        continue;
      }

      bagQuery++;

      if (itemId.isEmpty) {
        skipItem++;
        if (status == 'pending' || status == 'accepted') {
          diagnoses.add(
            'reserva $status ignorada no agrupamento do saco: live_item_id vazio',
          );
        }
        continue;
      }

      // Espelho de _sectionFor: pending|accepted → inBag
      // (rejected/expired/cancelled → não entram no contador «no saco»)
      if (status == 'pending' || status == 'accepted') {
        inBagRows++;
        inBagUnits += unitQty;
        if (status == 'pending') pendingVisible++;
      }
    }

    if (pendingAny > 0 && inBagRows == 0) {
      diagnoses.add(
        'INCONSISTÊNCIA: pending na BD deste buyer mas regra do saco → 0 no saco',
      );
    }

    return BagCrosscheckResult(
      bagQueryRowCount: bagQuery,
      inBagRowCount: inBagRows,
      inBagUnitQty: inBagUnits,
      skippedEmptyLiveItemId: skipItem,
      skippedWrongSource: skipSource,
      pendingAnySource: pendingAny,
      pendingVisibleInBag: pendingVisible,
      diagnoses: diagnoses,
    );
  }
}
