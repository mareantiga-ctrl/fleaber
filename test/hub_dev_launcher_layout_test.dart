import 'package:fleaber/hub/pages/hub_dev_launcher_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const HubDevLauncherPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('P07 mobile mostra launcher', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.textContaining('Hub'), findsWidgets);
    expect(find.text('Abrir perfil Hub'), findsOneWidget);
    expect(find.text('Abrir marketplace'), findsOneWidget);
    expect(find.text('Ferramenta interna'), findsNothing);
  });

  testWidgets('P07 desktop mostra atalhos e badge QA', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    expect(find.text('Abrir perfil Hub'), findsOneWidget);
    expect(find.text('Ferramenta interna'), findsOneWidget);
    expect(find.textContaining('QA'), findsWidgets);
    expect(find.text('Abrir FleaHub landing'), findsOneWidget);
  });
}
