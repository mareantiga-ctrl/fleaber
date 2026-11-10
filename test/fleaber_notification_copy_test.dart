import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/utils/fleaber_notification_copy.dart';

void main() {
  group('fleaberNotificationInboxTitle (D3)', () {
    test('like continua a dizer gostou', () {
      expect(
        fleaberNotificationInboxTitle(
          kind: 'favorite',
          likerName: 'Ana',
          productTitle: 'Camisola',
        ),
        'Ana gostou do seu artigo: Camisola',
      );
    });

    test('bundle_proposal usa título de conjunto', () {
      expect(
        fleaberNotificationInboxTitle(
          kind: 'bundle_proposal',
          inboxTitle: 'Nova proposta de conjunto',
          likerName: 'Bruno',
          productTitle: '3 artigos · 20,00 €',
        ),
        'Nova proposta de conjunto',
      );
      expect(
        fleaberNotificationInboxTitle(
          kind: 'bundle_proposal',
          likerName: 'Bruno',
          productTitle: 'x',
        ),
        'Proposta de conjunto',
      );
    });

    test('price_offer não regressa', () {
      expect(
        fleaberNotificationInboxTitle(
          kind: 'price_offer',
          inboxTitle: 'Proposta de preço',
          likerName: 'C',
          productTitle: 'Item',
        ),
        'Proposta de preço',
      );
    });

    test('bundle counter / purchase request', () {
      expect(
        fleaberNotificationInboxTitle(
          kind: 'bundle_proposal_counter',
          inboxTitle: 'Contraproposta de conjunto',
          likerName: 'D',
          productTitle: 'y',
        ),
        'Contraproposta de conjunto',
      );
      expect(
        fleaberNotificationInboxTitle(
          kind: 'bundle_purchase_request',
          likerName: 'E',
          productTitle: 'z',
        ),
        'Proposta de conjunto',
      );
    });
  });
}
