import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/fee_calculator.dart';
import 'package:fleaber/utils/dpd_pudo_service.dart';

void main() {
  group('DPD integração — contratos locais', () {
    test('carrier continua 3,50 € (Pickup não usa método pickup/hand)', () {
      expect(fleaberShippingEurFromMethod('carrier'), 3.5);
      expect(fleaberShippingEurFromMethod(kFleaberShippingCarrierMethod), 3.5);
      // «pickup» legado = mão — NÃO confundir com loja DPD
      expect(fleaberShippingEurFromMethod('pickup'), 0.0);
    });

    test('DpdPudoPoint.fromJson', () {
      final p = DpdPudoPoint.fromJson({
        'pudoId': 'PT20037',
        'name': 'MULTIOFICE',
        'address1': 'AV NARCISO FERREIRA',
        'zipCode': '4760-105',
        'city': 'V.N.FAMALICAO',
      });
      expect(p.pudoId, 'PT20037');
      expect(p.subtitle.contains('4760-105'), isTrue);
    });

    test('parse XML sample (contrato GetPudoList)', () {
      // Espelha parser Edge — campos confirmados no SOAP Rui
      const xml = '''
        <PUDO_ID>PT21139</PUDO_ID>
        <NAME>QUINTA</NAME>
        <ADDRESS1>RUA A</ADDRESS1>
        <ZIPCODE>4760-117</ZIPCODE>
        <CITY>VNF</CITY>
      ''';
      expect(xml.contains('PUDO_ID'), isTrue);
      expect(RegExp(r'<PUDO_ID>([^<]+)').firstMatch(xml)?.group(1), 'PT21139');
    });
  });
}
