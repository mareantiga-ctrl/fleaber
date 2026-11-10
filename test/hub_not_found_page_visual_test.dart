import 'package:fleaber/hub/pages/hub_not_found_page.dart';
import 'package:fleaber/utils/fleaber_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('H06 mostra título e CTA; Ir para o início → /fleahub',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/x/naoexiste',
      routes: [
        GoRoute(
          path: '/fleahub',
          builder: (_, __) => const Scaffold(body: Text('HOME_OK')),
        ),
        GoRoute(
          path: '/:handle/:invalid',
          builder: (_, __) => const HubNotFoundPage(),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(colorScheme: FleaberColors.lightColorScheme),
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Esta página não existe'), findsOneWidget);
    expect(find.text('Ir para o início'), findsOneWidget);
    // Sem histórico interno → sem «Voltar»
    expect(find.text('Voltar'), findsNothing);

    await tester.tap(find.text('Ir para o início'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HOME_OK'), findsOneWidget);
  });

  testWidgets('H06 fundo claro (bgTint)', (tester) async {
    final router = GoRouter(
      initialLocation: '/x/naoexiste',
      routes: [
        GoRoute(
          path: '/:handle/:invalid',
          builder: (_, __) => const HubNotFoundPage(),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(colorScheme: FleaberColors.lightColorScheme),
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, FleaberColors.bgTint);

    final title = tester.widget<Text>(find.text('Esta página não existe'));
    expect(title.style?.color, FleaberColors.text);
  });
}
