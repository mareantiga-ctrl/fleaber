import 'package:fleaber/backend/supabase/fleaber_supabase_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stagingUrl = kFleaberStagingSupabaseUrl;
  const stagingAnon = 'staging-anon-test-key';
  const prodUrl = 'https://bpmpkzwnrbmuqnhgdscf.supabase.co';
  const prodAnon = 'prod-anon-test-key';

  group('resolveFleaberSupabaseEnv debug/profile', () {
    test('sem defines → staging', () {
      final r = resolveFleaberSupabaseEnv(
        fleaberEnv: 'staging',
        envUrl: '',
        envAnon: '',
        isReleaseBuild: false,
        allowStagingRelease: false,
        stagingUrl: stagingUrl,
        stagingAnonKey: stagingAnon,
      );
      expect(r.envLabel, 'staging');
      expect(r.url, stagingUrl);
      expect(r.anonKey, stagingAnon);
    });

    test('defaultValue staging implícito (env staging)', () {
      final r = resolveFleaberSupabaseEnv(
        fleaberEnv: 'staging',
        envUrl: '',
        envAnon: '',
        isReleaseBuild: false,
        allowStagingRelease: false,
        stagingUrl: stagingUrl,
        stagingAnonKey: stagingAnon,
      );
      expect(r.url.contains(kFleaberStagingProjectRef), isTrue);
    });
  });

  group('resolveFleaberSupabaseEnv production', () {
    test('production com URL+anon → prod', () {
      final r = resolveFleaberSupabaseEnv(
        fleaberEnv: 'production',
        envUrl: prodUrl,
        envAnon: prodAnon,
        isReleaseBuild: true,
        allowStagingRelease: false,
        stagingUrl: stagingUrl,
        stagingAnonKey: stagingAnon,
      );
      expect(r.envLabel, 'production');
      expect(r.url, prodUrl);
      expect(r.anonKey, prodAnon);
    });

    test('production sem URL → erro (não cai em staging)', () {
      expect(
        () => resolveFleaberSupabaseEnv(
          fleaberEnv: 'production',
          envUrl: '',
          envAnon: prodAnon,
          isReleaseBuild: false,
          allowStagingRelease: false,
          stagingUrl: stagingUrl,
          stagingAnonKey: stagingAnon,
        ),
        throwsA(isA<FleaberSupabaseEnvError>()),
      );
    });

    test('production com URL staging → erro', () {
      expect(
        () => resolveFleaberSupabaseEnv(
          fleaberEnv: 'production',
          envUrl: stagingUrl,
          envAnon: prodAnon,
          isReleaseBuild: true,
          allowStagingRelease: false,
          stagingUrl: stagingUrl,
          stagingAnonKey: stagingAnon,
        ),
        throwsA(isA<FleaberSupabaseEnvError>()),
      );
    });
  });

  group('resolveFleaberSupabaseEnv release fail-closed', () {
    test('release sem FLEABER_ENV=production → erro (não staging silencioso)',
        () {
      expect(
        () => resolveFleaberSupabaseEnv(
          fleaberEnv: 'staging',
          envUrl: '',
          envAnon: '',
          isReleaseBuild: true,
          allowStagingRelease: false,
          stagingUrl: stagingUrl,
          stagingAnonKey: stagingAnon,
        ),
        throwsA(isA<FleaberSupabaseEnvError>()),
      );
    });

    test('release staging com FLEABER_ALLOW_STAGING_RELEASE → OK', () {
      final r = resolveFleaberSupabaseEnv(
        fleaberEnv: 'staging',
        envUrl: '',
        envAnon: '',
        isReleaseBuild: true,
        allowStagingRelease: true,
        stagingUrl: stagingUrl,
        stagingAnonKey: stagingAnon,
      );
      expect(r.envLabel, 'staging');
      expect(r.url, stagingUrl);
    });

    test('release env vazio/invalid → erro', () {
      expect(
        () => resolveFleaberSupabaseEnv(
          fleaberEnv: '',
          envUrl: '',
          envAnon: '',
          isReleaseBuild: true,
          allowStagingRelease: false,
          stagingUrl: stagingUrl,
          stagingAnonKey: stagingAnon,
        ),
        throwsA(isA<FleaberSupabaseEnvError>()),
      );
    });
  });
}
