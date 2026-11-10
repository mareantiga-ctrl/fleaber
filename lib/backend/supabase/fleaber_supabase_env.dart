/// Resolução fail-safe de URL/anon Supabase (testável sem dart-defines reais).
///
/// Regras:
/// - `production` → exige URL + anon; recusa staging ref na URL.
/// - release (`isReleaseBuild`) → exige `production` **ou**
///   `allowStagingRelease` com `fleaberEnv == staging` (QA intencional).
/// - debug/profile sem defines → staging hardcoded (dev OK).
library;

const String kFleaberStagingProjectRef = 'fxdknzrqjenzqcvnwqqq';
const String kFleaberStagingSupabaseUrl =
    'https://fxdknzrqjenzqcvnwqqq.supabase.co';

/// Resultado resolvido ou erro legível (nunca fallback silencioso a staging em release).
class FleaberSupabaseEnvResolved {
  const FleaberSupabaseEnvResolved({
    required this.envLabel,
    required this.url,
    required this.anonKey,
  });

  final String envLabel;
  final String url;
  final String anonKey;
}

class FleaberSupabaseEnvError implements Exception {
  FleaberSupabaseEnvError(this.message);
  final String message;
  @override
  String toString() => 'FleaberSupabaseEnvError: $message';
}

/// Resolve URL + anon. [stagingAnonKey] só usado quando o ambiente efectivo é staging.
FleaberSupabaseEnvResolved resolveFleaberSupabaseEnv({
  required String fleaberEnv,
  required String envUrl,
  required String envAnon,
  required bool isReleaseBuild,
  required bool allowStagingRelease,
  required String stagingUrl,
  required String stagingAnonKey,
  String stagingProjectRef = kFleaberStagingProjectRef,
}) {
  final env = fleaberEnv.trim().toLowerCase();
  final urlOverride = envUrl.trim();
  final anonOverride = envAnon.trim();

  if (isReleaseBuild) {
    final stagingReleaseOk =
        env == 'staging' && allowStagingRelease;
    final productionOk = env == 'production';
    if (!productionOk && !stagingReleaseOk) {
      throw FleaberSupabaseEnvError(
        'Release build exige --dart-define=FLEABER_ENV=production '
        '(com FLEABER_SUPABASE_URL + FLEABER_SUPABASE_ANON_KEY) '
        'ou FLEABER_ALLOW_STAGING_RELEASE=true com FLEABER_ENV=staging. '
        'Default silencioso para staging em release está bloqueado.',
      );
    }
  }

  if (env == 'production') {
    if (urlOverride.isEmpty) {
      throw FleaberSupabaseEnvError(
        'FLEABER_ENV=production exige FLEABER_SUPABASE_URL '
        '(não usar staging por omissão).',
      );
    }
    if (anonOverride.isEmpty) {
      throw FleaberSupabaseEnvError(
        'FLEABER_ENV=production exige FLEABER_SUPABASE_ANON_KEY.',
      );
    }
    if (urlOverride.toLowerCase().contains(stagingProjectRef)) {
      throw FleaberSupabaseEnvError(
        'Recusado: FLEABER_ENV=production mas URL aponta para staging '
        '($stagingProjectRef).',
      );
    }
    return FleaberSupabaseEnvResolved(
      envLabel: 'production',
      url: urlOverride,
      anonKey: anonOverride,
    );
  }

  // staging (ou label desconhecido tratado como staging só em non-release)
  if (env != 'staging' && env.isNotEmpty && env != 'production') {
    throw FleaberSupabaseEnvError(
      'FLEABER_ENV inválido "$fleaberEnv". Use staging ou production.',
    );
  }

  final url = urlOverride.isNotEmpty ? urlOverride : stagingUrl;
  final anon = anonOverride.isNotEmpty ? anonOverride : stagingAnonKey;
  if (url.isEmpty || anon.isEmpty) {
    throw FleaberSupabaseEnvError(
      'Staging URL/anon em falta na configuração do cliente.',
    );
  }
  return FleaberSupabaseEnvResolved(
    envLabel: 'staging',
    url: url,
    anonKey: anon,
  );
}
