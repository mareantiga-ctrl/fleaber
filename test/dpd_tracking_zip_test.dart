import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/dpd_tracking_service.dart';
import 'package:fleaber/utils/fee_calculator.dart';

void main() {
  group('DPD tracking ZIP 130 — contratos locais', () {
    test('carrier continua 3,50 € com Pickup (não muda método)', () {
      expect(fleaberShippingEurFromMethod('carrier'), 3.5);
      expect(fleaberShippingEurFromMethod(kFleaberShippingCarrierMethod), 3.5);
    });

    test('DpdTrackEvent.fromJson flexível', () {
      final e = DpdTrackEvent.fromJson({
        'description': 'Em trânsito',
        'at': '2026-11-02T10:00:00Z',
        'code': 'IT',
        'location': 'Lisboa',
      });
      expect(e.description, 'Em trânsito');
      expect(e.at, '2026-11-02T10:00:00Z');
      expect(e.code, 'IT');
      expect(e.location, 'Lisboa');
    });

    test('DpdTrackEvent descrição vazia → fallback', () {
      final e = DpdTrackEvent.fromJson({'description': '  '});
      expect(e.description, 'Atualização DPD');
    });

    test('DpdTrackingResult empty/missing', () {
      const empty = DpdTrackingResult(
        ok: true,
        status: 'empty',
        events: [],
        message: 'sem eventos',
      );
      expect(empty.isEmptyEvents, isTrue);

      const ok = DpdTrackingResult(
        ok: true,
        status: 'ok',
        events: [
          DpdTrackEvent(description: 'Recebido'),
        ],
      );
      expect(ok.isEmptyEvents, isFalse);
    });
  });
}
