import 'package:flutter_test/flutter_test.dart';
import 'package:fleaber/utils/fleaber_dispute_card_title.dart';

void main() {
  test('dispute card title: aberta / análise / fechada', () {
    expect(
      fleaberDisputeCardTitle(status: 'aberta', currentTurn: 'vendedor'),
      'Disputa aberta',
    );
    expect(
      fleaberDisputeCardTitle(
        status: 'respondida_vendedor',
        currentTurn: 'comprador',
      ),
      'Disputa aberta',
    );
    expect(
      fleaberDisputeCardTitle(
        status: 'escalada_fleaber',
        currentTurn: 'administracao',
      ),
      'Disputa em análise',
    );
    expect(
      fleaberDisputeCardTitle(status: 'aberta', currentTurn: 'administracao'),
      'Disputa em análise',
    );
    expect(
      fleaberDisputeCardTitle(
        status: 'resolvida',
        currentTurn: 'administracao',
      ),
      'Disputa fechada',
    );
    expect(
      fleaberDisputeCardTitle(status: 'recusada', currentTurn: 'comprador'),
      'Disputa fechada',
    );
  });
}
