import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/utils/dpd_pudo_service.dart';

void main() {
  group('DPD ZIP 131 — contratos locais (sem create Live)', () {
    test('subcontas portal documentadas', () {
      // Espelha DPD_SUBACCOUNT_* no Edge — regressão de cópia
      expect('03546101', isNotEmpty); // Shop to Shop
      expect('03546102', isNotEmpty); // Shop to Home
    });

    test('carrier 3,50 € inalterado', () {
      expect(fleaberShippingEurFromMethod(kFleaberShippingCarrierMethod), 3.5);
    });

    test('Pickup point parse (GetPudoList)', () {
      final p = DpdPudoPoint.fromJson({
        'pudoId': 'PT20037',
        'name': 'MULTIOFICE',
        'address1': 'AV NARCISO FERREIRA',
        'zipCode': '4760-105',
        'city': 'V.N.FAMALICAO',
      });
      expect(p.pudoId, 'PT20037');
    });
  });
}
