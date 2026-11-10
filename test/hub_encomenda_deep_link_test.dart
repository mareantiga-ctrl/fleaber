import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/hub_account_routes.dart';
import 'package:fleaber/perfil/perfil_desktop_nav.dart';
import 'package:fleaber/utils/fleaber_deep_link_service.dart';

void main() {
  group('HubAccountRoutes encomenda deep link', () {
    test('perfilPath inclui orderId', () {
      final path = HubAccountRoutes.perfilPath(
        PerfilDesktopPane.encomendas,
        orderId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(path, contains('secao=encomendas'));
      expect(
        path,
        contains('orderId=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'),
      );
    });

    test('encomendaAbsoluteUrl aponta Hub hash com orderId', () {
      const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final url = HubAccountRoutes.encomendaAbsoluteUrl(id);
      expect(url, startsWith('https://fleaber.pt/fleahub/#/perfil?'));
      expect(url, contains('secao=encomendas'));
      expect(url, contains('orderId=$id'));
      expect(url, isNot(equals('https://fleaber.pt/fleahub/#/perfil?secao=encomendas')));
    });

    test('encomendaPath in-app', () {
      expect(
        HubAccountRoutes.encomendaPath('abc-123'),
        '/perfil?secao=encomendas&orderId=abc-123',
      );
    });
  });

  group('FleaberDeepLinkService email Hub → app', () {
    test('hash Hub com orderId → /minhasEncomendas?orderId= (nativo)', () {
      const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final loc = FleaberDeepLinkService.fleahubOrderEmailGoLocation(
        Uri.parse(
          'https://fleaber.pt/fleahub/#/perfil?secao=encomendas&orderId=$id',
        ),
      );
      // Em testes unitários kIsWeb=false → rota nativa.
      expect(loc, '/minhasEncomendas?orderId=$id');
    });

    test('sem orderId mas secao encomendas → lista', () {
      final loc = FleaberDeepLinkService.fleahubOrderEmailGoLocation(
        Uri.parse('https://fleaber.pt/fleahub/#/perfil?secao=encomendas'),
      );
      expect(loc, '/minhasEncomendas');
    });
  });
}
