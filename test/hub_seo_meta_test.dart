import 'package:fleaber/hub/data/hub_models.dart';
import 'package:fleaber/hub/seo/hub_seo_meta.dart';
import 'package:fleaber/hub/seo/hub_seo_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HubSeoPolicy', () {
    test('staging supabase nunca indexa', () {
      expect(
        HubSeoPolicy.isStagingSupabaseProject(
          'https://fxdknzrqjenzqcvnwqqq.supabase.co',
        ),
        isTrue,
      );
      expect(HubSeoPolicy.allowHubIndexing(host: 'fleaber.pt'), isFalse);
    });

    test('localhost nunca indexa', () {
      expect(HubSeoPolicy.allowHubIndexing(host: 'localhost'), isFalse);
    });

    test('fleaber.pt é host produção; prod supabase não é staging', () {
      expect(HubSeoPolicy.isProductionHubHost('fleaber.pt'), isTrue);
      expect(
        HubSeoPolicy.isStagingSupabaseProject('https://prodref.supabase.co'),
        isFalse,
      );
    });

    test('robots directive', () {
      expect(
        HubSeoPolicy.robotsDirective(indexable: true),
        contains('index,follow'),
      );
      expect(
        HubSeoPolicy.robotsDirective(indexable: false),
        'noindex,nofollow',
      );
    });
  });

  group('HubSeoMeta', () {
    final profile = HubProfile(
      id: 'p1',
      handle: 'maria-silva',
      fullName: 'Maria Silva',
      photoUrl: 'https://cdn.example/photo.jpg',
      location: 'Porto',
      phoneVerified: true,
    );

    test('notFound sem leak e noindex', () {
      final m = HubSeoMeta.notFound();
      expect(m.robots, contains('noindex'));
      expect(m.title, contains('não encontrada'));
      expect(m.description, isNot(contains('maria')));
    });

    test('profile meta canonical e og:image absoluto', () {
      final m = HubSeoMeta.forProfile(
        profile: profile,
        bundle: HubProfileBundle(
          profile: profile,
          lives: const [],
          products: const [],
          reviews: const [],
        ),
        indexable: false,
      );
      expect(m.canonicalUrl, 'https://fleaber.pt/maria-silva');
      expect(m.ogImage, startsWith('https://'));
      expect(m.title, contains('Maria Silva'));
      expect(m.title, contains('@maria-silva'));
      expect(m.description, contains('Porto'));
      expect(m.robots, contains('noindex'));
    });

    test('profile indexable em prod', () {
      final m = HubSeoMeta.forProfile(
        profile: profile,
        bundle: HubProfileBundle(
          profile: profile,
          lives: const [],
          products: const [],
          reviews: const [],
        ),
        indexable: true,
      );
      expect(m.robots, contains('index,follow'));
    });

    test('live AO VIVO og:type video.other', () {
      final live = HubLive(
        id: 'l1',
        sellerId: 'p1',
        sellerHandle: 'maria-silva',
        title: 'Roupa nova',
        status: 'live',
        isActive: true,
        muxPlaybackId: 'abc123',
      );
      final m = HubSeoMeta.forLive(
        profile: profile,
        bundle: HubLiveBundle(
          profile: profile,
          live: live,
          items: const [],
          messages: const [],
          products: const [],
          fomo: null,
        ),
        indexable: false,
      );
      expect(m.canonicalUrl, 'https://fleaber.pt/maria-silva/live');
      expect(m.ogType, 'video.other');
      expect(m.title, contains('AO VIVO'));
      expect(m.ogImage, contains('image.mux.com'));
    });

    test('live description não inclui stream keys', () {
      final live = HubLive(
        id: 'l1',
        sellerId: 'p1',
        sellerHandle: 'maria-silva',
        muxPlaybackId: 'secret-playback-id',
      );
      final m = HubSeoMeta.forLive(
        profile: profile,
        bundle: HubLiveBundle(
          profile: profile,
          live: live,
          items: const [],
          messages: const [],
          products: const [],
          fomo: null,
        ),
      );
      expect(m.description.toLowerCase(), isNot(contains('stream_key')));
      expect(m.description, isNot(contains('secret-playback-id')));
    });
  });
}
