import 'package:fleaber/pages/staff/helper_access_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HelperAccessCopy', () {
    test('dono não vê «A trabalhar para»', () {
      expect(
        HelperAccessCopy.storeEyebrow(isOwnerContext: true),
        'A tua loja',
      );
      expect(
        HelperAccessCopy.storeEyebrow(isOwnerContext: false),
        'A trabalhar para',
      );
    });

    test('lista vazia distingue dono vs colaborador sem loja', () {
      expect(
        HelperAccessCopy.associatedEmpty(isOwnerContext: true),
        contains('outra loja'),
      );
      expect(
        HelperAccessCopy.associatedEmpty(isOwnerContext: false),
        contains('loja aceite'),
      );
    });

    test('explicação de dono não lista permissões de helper', () {
      expect(HelperAccessCopy.ownerPermissionsTitle(), 'Modo pessoal');
      expect(
        HelperAccessCopy.ownerPermissionsBody(),
        contains('aceitares um convite'),
      );
    });
  });
}
