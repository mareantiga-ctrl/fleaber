import 'package:flutter_test/flutter_test.dart';

import 'package:fleaber/hub/hub_urls.dart';
import 'package:fleaber/hub/routing/hub_handle_resolver.dart';
import 'package:fleaber/hub/seller/hub_seller_copy.dart';
import 'package:fleaber/hub/seller/hub_seller_state.dart';

void main() {
  group('HubUrls', () {
    test('profile and live canonical URLs (hash Hub — P12)', () {
      expect(
        HubUrls.profile('Maria-Silva'),
        'https://fleaber.pt/fleahub/index.html#/maria-silva',
      );
      expect(
        HubUrls.live('hub-staging-axinoquaa'),
        'https://fleaber.pt/fleahub/index.html#/hub-staging-axinoquaa/live',
      );
      expect(
        HubUrls.liveCleanPath('hub-staging-axinoquaa'),
        'https://fleaber.pt/hub-staging-axinoquaa/live',
      );
      expect(HubUrls.displayPath('Maria-Silva'), 'fleaber.pt/maria-silva');
      expect(HubUrls.displayPath(''), 'fleaber.pt/…');
    });
  });

  group('HubSellerPhase', () {
    test('no handle', () {
      final s = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': null,
        'handle_suggested': null,
        'hub_published': false,
        'phone_verified_at': null,
      });
      expect(s.phase, HubSellerPhase.noHandle);
      expect(s.hasPublicHub, isFalse);
    });

    test('suggested only', () {
      final s = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': null,
        'handle_suggested': 'maria-silva',
        'hub_published': false,
        'phone_verified_at': '2026-01-01',
      });
      expect(s.phase, HubSellerPhase.suggestedOnly);
      expect(s.effectiveHandlePreview, 'maria-silva');
    });

    test('claimed hidden vs published', () {
      final hidden = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': 'maria-silva',
        'hub_published': false,
        'phone_verified_at': '2026-01-01',
      });
      expect(hidden.phase, HubSellerPhase.handleClaimedHidden);
      expect(hidden.hasPublicHub, isFalse);
      expect(hidden.profilePublicLineLabel, HubSellerCopy.profileLineManage);
      expect(hidden.hasClaimedFleaHub, isTrue);

      final pub = hidden.copyWith(hubPublished: true);
      expect(pub.phase, HubSellerPhase.handleClaimedPublished);
      expect(pub.hasPublicHub, isTrue);
      expect(pub.profilePublicLineLabel, HubSellerCopy.profileLineManage);
    });

    test('APP-308 resolve: publicado vs oculto', () {
      final published = HubHandleResolveResult.fromRpc({
        'found': true,
        'http_status': 200,
        'handle': 'maria-silva',
        'hub_published': true,
      });
      expect(published.isPublished, isTrue);

      final hidden = HubHandleResolveResult.fromRpc({
        'found': true,
        'http_status': 200,
        'handle': 'maria-silva',
        'hub_published': false,
      });
      expect(hidden.isPublished, isFalse);
    });

    test('profile line label without handle', () {
      final s = HubSellerStatus.fromMap({
        'id': 'u1',
        'full_name': 'Maria',
        'handle': null,
        'handle_suggested': null,
        'hub_published': false,
        'phone_verified_at': null,
      });
      expect(s.profilePublicLineLabel, HubSellerCopy.profileLineCreate);
      expect(s.hasClaimedFleaHub, isFalse);
    });
  });

  group('HubSellerErrorMessages', () {
    test('validation reasons', () {
      expect(
        HubSellerErrorMessages.fromCode(
          'handle_invalid',
          validationReasons: ['taken'],
        ),
        'Este endereço já está a ser usado.',
      );
      expect(
        HubSellerErrorMessages.fromCode(
          'handle_invalid',
          validationReasons: ['reserved'],
        ),
        'Este endereço está reservado. Escolhe outro.',
      );
    });

    test('phone and seller_not_ready', () {
      expect(
        HubSellerErrorMessages.fromCode('phone_not_verified'),
        contains('telemóvel'),
      );
      expect(
        HubSellerErrorMessages.fromCode('seller_not_ready'),
        contains('produto'),
      );
    });

    test('codeFromException parses RPC errors', () {
      expect(
        HubSellerErrorMessages.codeFromException(
          Exception('handle_change_cooldown'),
        ),
        'handle_change_cooldown',
      );
    });
  });

  group('HubSellerActionResult', () {
    test('APP-308 RPC publicado → oculto → publicado', () {
      final published = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': true,
      });
      expect(published.ok, isTrue);
      expect(published.hubPublished, isTrue);

      final hidden = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': false,
      });
      expect(hidden.ok, isTrue);
      expect(hidden.hubPublished, isFalse);

      final again = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': true,
      });
      expect(again.hubPublished, isTrue);
    });

    test('success publish RPC', () {
      final r = HubSellerActionResult.fromRpc({
        'ok': true,
        'hub_published': true,
      });
      expect(r.ok, isTrue);
      expect(r.hubPublished, isTrue);
    });

    test('failure with validation', () {
      final r = HubSellerActionResult.fromRpc({
        'ok': false,
        'error': 'handle_invalid',
        'validation': {'reasons': ['too_short']},
      });
      expect(r.ok, isFalse);
      expect(r.validationReasons, ['too_short']);
    });
  });
}
