import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/hub_actions.dart';
import 'package:fleaber/hub/routing/hub_route_paths.dart';

void main() {
  group('FleaHub auth returnTo', () {
    test('landing /fleahub', () {
      expect(HubActions.isFleaHubReturnPath(HubRoutePaths.landing), isTrue);
    });

    test('perfil /maria', () {
      expect(HubActions.isFleaHubReturnPath('/maria'), isTrue);
    });

    test('live /maria/live e query liveId', () {
      expect(HubActions.isFleaHubReturnPath('/maria/live'), isTrue);
      expect(
        HubActions.isFleaHubReturnPath('/maria/live?liveId=abc'),
        isTrue,
      );
    });

    test('shop e reviews', () {
      expect(HubActions.isFleaHubReturnPath('/maria/shop'), isTrue);
      expect(HubActions.isFleaHubReturnPath('/maria/reviews'), isTrue);
    });

    test('rotas app não são FleaHub', () {
      expect(HubActions.isFleaHubReturnPath('/login'), isFalse);
      expect(HubActions.isFleaHubReturnPath('/wallet'), isFalse);
      expect(HubActions.isFleaHubReturnPath(null), isFalse);
      expect(HubActions.isFleaHubReturnPath(''), isFalse);
    });

    test('normalizeReturnTo preserva query', () {
      final uri = Uri.parse('/maria/live?liveId=x');
      expect(HubActions.normalizeReturnTo(uri), '/maria/live?liveId=x');
    });

    test('resolveAuthDestination prioriza valor capturado', () {
      expect(
        HubActions.resolveAuthDestination(
          _FakeBuildContext(),
          captured: '/fleahub',
        ),
        '/fleahub',
      );
    });
  });
}

/// Stub mínimo — resolveAuthDestination só usa [captured] neste teste.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
