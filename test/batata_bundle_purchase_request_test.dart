import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/batata_bundle_actions.dart';

void main() {
  group('Bundle purchase request (B1-017)', () {
    test('formatBundlePurchaseRequestText lista artigos', () {
      final text = formatBundlePurchaseRequestText(
        buyerName: 'João',
        products: [
          ProductsRow({'title': 'Escova Vintage A'}),
          ProductsRow({'title': 'Lâminas Premium B'}),
        ],
      );
      expect(text, contains('João pretende comprar estes artigos em conjunto.'));
      expect(text, contains('• Escova Vintage A'));
      expect(text, contains('• Lâminas Premium B'));
    });
  });
}
