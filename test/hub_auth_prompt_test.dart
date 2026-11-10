import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/widgets/hub_auth_prompt.dart';

void main() {
  group('HubAuthPrompt (B20)', () {
    test('título genérico', () {
      expect(
        HubAuthPrompt.resolveTitle(intentLabel: 'reservar este artigo'),
        'Inicia sessão para continuar',
      );
    });

    test('título gorjeta', () {
      expect(
        HubAuthPrompt.resolveTitle(intentLabel: 'enviar uma gorjeta'),
        'Inicia sessão para enviar uma gorjeta',
      );
    });

    test('titleOverride tem prioridade', () {
      expect(
        HubAuthPrompt.resolveTitle(
          intentLabel: 'enviar uma gorjeta',
          titleOverride: 'Título custom',
        ),
        'Título custom',
      );
    });

    test('copy corporativo FleaHub', () {
      expect(
        HubAuthPrompt.bodyCopy,
        'Entra na tua conta Fleaber para continuares no FleaHub.',
      );
    });
  });
}
