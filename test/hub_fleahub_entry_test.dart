import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fleaber/hub/data/hub_models.dart';
import 'package:fleaber/hub/routing/hub_route_paths.dart';
import 'package:fleaber/hub/seller/hub_seller_copy.dart';
import 'package:fleaber/hub/seller/hub_seller_sheet.dart';

void main() {
  group('FleaHub entradas app — copy gestão vs visita', () {
    test('conta privada seller — gestão', () {
      expect(HubSellerCopy.accountMenuTitle, 'FleaHub');
      expect(
        HubSellerCopy.accountMenuSubtitle,
        'Gerir e partilhar o teu FleaHub',
      );
    });

    test('visitante — só navegação', () {
      expect(HubSellerCopy.visitorLineLabel, 'Ver FleaHub');
      expect(
        HubRoutePaths.profileFor('maria-silva'),
        '/maria-silva',
      );
    });
  });

  group('HubVisitorFleaHubLine', () {
    testWidgets('sem hub publicado — não mostra entrada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HubVisitorFleaHubLine(
              sellerId: 'seller-1',
              profileLoader: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(HubSellerCopy.visitorLineLabel), findsNothing);
    });

    testWidgets('com hub publicado — Ver FleaHub navega para /{handle}',
        (tester) async {
      const handle = 'fleahub-demo-ux';
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: HubVisitorFleaHubLine(
                sellerId: 'seller-1',
                profileLoader: (_) async => const HubProfile(
                  id: 'seller-1',
                  handle: handle,
                  fullName: 'Demo',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/:handle',
            builder: (_, state) => Text('hub:${state.pathParameters['handle']}'),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text(HubSellerCopy.visitorLineLabel), findsOneWidget);

      await tester.tap(find.text(HubSellerCopy.visitorLineLabel));
      await tester.pumpAndSettle();

      expect(find.text('hub:$handle'), findsOneWidget);
    });
  });
}
