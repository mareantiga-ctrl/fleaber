import "package:flutter/material.dart";
import "package:fleaber/widgets/fleaber_bag_changed_dialog.dart";
import "package:fleaber/utils/fee_calculator.dart";
import "package:fleaber/widgets/fleaber_primary_button.dart";
import "package:google_fonts/google_fonts.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _Host(),
  ));
}

class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1418),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: const Color(0xFF1A2329),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Finalizar compra",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text("Camisa branca · Calças ganga",
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      Text("Artigos (2)  ${formatEuros(42.5)}", style: const TextStyle(color: Colors.white)),
                      Text("Total  ${formatEuros(45.28)}", style: const TextStyle(color: Color(0xFF6ED8DE), fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      FleaberPrimaryButton(label: "Pagar", onPressed: () {}),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const ColoredBox(color: Color(0x66000000)),
          const Center(
            child: FleaberBagChangedDialog(unavailableCount: 1, totalCents: 2638),
          ),
        ],
      ),
    );
  }
}
