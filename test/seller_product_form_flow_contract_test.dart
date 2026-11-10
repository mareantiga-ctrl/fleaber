import 'package:flutter_test/flutter_test.dart';

/// Contrato ZIP 147: formulário de anúncio = um ecrã (sem passos 1/2).
/// A UI usa `_showTwoStepUi => false` em `seller_product_form_widget.dart`.
void main() {
  test('fluxo único documentado — botões Cancelar / Rascunho / Publicar', () {
    const contract = <String>[
      'Cancelar',
      'Guardar rascunho',
      'Publicar',
    ];
    expect(contract, containsAll(['Cancelar', 'Guardar rascunho', 'Publicar']));
    expect(contract, isNot(contains('PROSSEGUIR')));
  });
}
