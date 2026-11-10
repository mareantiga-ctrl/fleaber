import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/seller/hub_seller_copy.dart';
import 'package:fleaber/hub/seller/hub_seller_share.dart';
import 'package:fleaber/hub/seller/hub_seller_state.dart';

void main() {
  group('HubSellerCopy', () {
    test('strings MVP fechadas', () {
      expect(HubSellerCopy.sheetSubtitle, 'O teu espaço público na Fleaber.');
      expect(HubSellerCopy.personalizeTitle, 'Personalizar endereço');
      expect(HubSellerCopy.hideFleaHub, 'Ocultar FleaHub');
      expect(HubSellerCopy.profileLineCreate, 'Criar FleaHub');
      expect(HubSellerCopy.profileLineManage, 'FleaHub');
      expect(HubSellerCopy.accountMenuTitle, 'FleaHub');
      expect(HubSellerCopy.visitorLineLabel, 'Ver FleaHub');
    });

    test('sem jargão técnico visível', () {
      for (final value in [
        HubSellerCopy.sheetSubtitle,
        HubSellerCopy.setupPrompt,
        HubSellerCopy.personalizeTitle,
        HubSellerCopy.inactiveHint,
        HubSellerCopy.personalizeFooter,
        HubSellerCopy.linkCopiedFeedback,
        HubSellerCopy.shareCopiedFeedback,
      ]) {
        expect(value.toLowerCase(), isNot(contains('handle')));
        expect(value.toLowerCase(), isNot(contains('url')));
        expect(value.toLowerCase(), isNot(contains('redirect')));
        expect(value.toLowerCase(), isNot(contains('página pública')));
        expect(value.toLowerCase(), isNot(contains('link público')));
      }
    });
  });

  group('FleaHub estados perfil (linha compacta)', () {
    test('criar vs gerir', () {
      final create = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': null,
        'handle_suggested': 'maria-silva',
        'hub_published': false,
        'phone_verified_at': '2026-01-01',
      });
      expect(create.profilePublicLineLabel, HubSellerCopy.profileLineCreate);
      expect(create.hasClaimedFleaHub, isFalse);
      expect(create.phase, HubSellerPhase.suggestedOnly);

      final manage = create.copyWith(handle: 'maria-silva');
      expect(manage.profilePublicLineLabel, HubSellerCopy.profileLineManage);
      expect(manage.hasClaimedFleaHub, isTrue);
    });

    test('APP-308 ciclo publicado → oculto → publicado (RPC + estado)', () {
      var status = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': 'maria-silva',
        'hub_published': true,
        'phone_verified_at': '2026-01-01',
      });
      expect(status.hasPublicHub, isTrue);
      expect(status.phase, HubSellerPhase.handleClaimedPublished);

      final hide = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': false,
        'handle': 'maria-silva',
      });
      expect(hide.ok, isTrue);
      expect(hide.hubPublished, isFalse);
      status = status.copyWith(hubPublished: hide.hubPublished);
      expect(status.hasPublicHub, isFalse);
      expect(status.phase, HubSellerPhase.handleClaimedHidden);

      final publish = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': true,
        'handle': 'maria-silva',
      });
      expect(publish.ok, isTrue);
      expect(publish.hubPublished, isTrue);
      status = status.copyWith(hubPublished: publish.hubPublished);
      expect(status.hasPublicHub, isTrue);
      expect(status.phase, HubSellerPhase.handleClaimedPublished);
    });
  });

  group('NAV-004 / Z1 âncora de voltar', () {
    test('1 voltar assenta no Perfil, não no Início', () {
      expect(HubSellerShare.isHubReturnAnchor('/perfil'), isTrue);
      expect(
        HubSellerShare.isHubReturnAnchor('/perfilVendedor?sellerID=abc'),
        isFalse,
      );
      expect(HubSellerShare.isHubReturnAnchor('/opinioes'), isFalse);
      expect(HubSellerShare.isHubReturnAnchor('/homePage'), isTrue);
    });

    test('locationPath ignora query', () {
      expect(
        HubSellerShare.locationPath('/perfilVendedor?sellerID=x'),
        '/perfilVendedor',
      );
      expect(HubSellerShare.locationPath('/perfil'), '/perfil');
    });
  });
}
