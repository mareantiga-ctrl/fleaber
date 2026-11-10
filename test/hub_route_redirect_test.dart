import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/routing/hub_route_redirect.dart';

void main() {
  group('HubRouteRedirect.rebuildPath', () {
    test('preserva suffix live e query', () {
      final uri = Uri.parse('/old-handle/live?utm=fb&ref=1');
      expect(
        HubRouteRedirect.rebuildPath(uri: uri, newHandle: 'new-handle'),
        '/new-handle/live?utm=fb&ref=1',
      );
    });

    test('perfil raiz sem suffix', () {
      final uri = Uri.parse('/old-handle');
      expect(
        HubRouteRedirect.rebuildPath(uri: uri, newHandle: 'maria'),
        '/maria',
      );
    });

    test('shop e reviews', () {
      expect(
        HubRouteRedirect.rebuildPath(
          uri: Uri.parse('/x/shop'),
          newHandle: 'y',
        ),
        '/y/shop',
      );
      expect(
        HubRouteRedirect.rebuildPath(
          uri: Uri.parse('/x/reviews'),
          newHandle: 'y',
        ),
        '/y/reviews',
      );
    });
  });
}
