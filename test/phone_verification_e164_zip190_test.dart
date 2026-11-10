import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/phone_verification_service.dart';

void main() {
  group('PhoneVerificationService.toE164 ZIP190', () {
    test('9 dígitos PT → +351', () {
      expect(PhoneVerificationService.toE164('912345678'), '+351912345678');
    });

    test('+351 já normalizado', () {
      expect(PhoneVerificationService.toE164('+351912345678'), '+351912345678');
    });

    test('351 sem plus', () {
      expect(PhoneVerificationService.toE164('351912345678'), '+351912345678');
    });

    test('espaços e hífenes', () {
      expect(
        PhoneVerificationService.toE164('+351 912 345 678'),
        '+351912345678',
      );
    });

    test('vazio inválido', () {
      expect(PhoneVerificationService.toE164(''), isNull);
      expect(PhoneVerificationService.toE164('abc'), isNull);
    });
  });
}
