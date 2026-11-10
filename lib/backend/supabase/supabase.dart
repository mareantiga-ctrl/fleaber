import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

import 'fleaber_supabase_env.dart';

export 'database/database.dart';
export 'fleaber_supabase_env.dart'
    show kFleaberStagingProjectRef, kFleaberStagingSupabaseUrl;

/// Anon de staging embutida (só builds debug/profile ou release com
/// `FLEABER_ALLOW_STAGING_RELEASE=true`). Nunca service_role.
const String _kStagingAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ4ZGtuenJxamVuenFjdm53cXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3ODA1NTgsImV4cCI6MjA5MjM1NjU1OH0.cmnPjM0YxNbT6RcSurFEnexzLaN6sJsQrjodCz2Wf5I';

/// Compilar produção:
/// `--dart-define=FLEABER_ENV=production`
/// `--dart-define=FLEABER_SUPABASE_URL=https://<prod>.supabase.co`
/// `--dart-define=FLEABER_SUPABASE_ANON_KEY=<anon>`
///
/// Release QA contra staging (explícito):
/// `--dart-define=FLEABER_ENV=staging`
/// `--dart-define=FLEABER_ALLOW_STAGING_RELEASE=true`
const String _kFleaberEnv =
    String.fromEnvironment('FLEABER_ENV', defaultValue: 'staging');
const String _kEnvUrl =
    String.fromEnvironment('FLEABER_SUPABASE_URL', defaultValue: '');
const String _kEnvAnon =
    String.fromEnvironment('FLEABER_SUPABASE_ANON_KEY', defaultValue: '');
const bool _kAllowStagingRelease = bool.fromEnvironment(
  'FLEABER_ALLOW_STAGING_RELEASE',
  defaultValue: false,
);

FleaberSupabaseEnvResolved get _resolved {
  return resolveFleaberSupabaseEnv(
    fleaberEnv: _kFleaberEnv,
    envUrl: _kEnvUrl,
    envAnon: _kEnvAnon,
    isReleaseBuild: kReleaseMode,
    allowStagingRelease: _kAllowStagingRelease,
    stagingUrl: kFleaberStagingSupabaseUrl,
    stagingAnonKey: _kStagingAnonKey,
  );
}

class SupaFlow {
  SupaFlow._();

  static SupaFlow? _instance;
  static SupaFlow get instance => _instance ??= SupaFlow._();

  final _supabase = Supabase.instance.client;
  static SupabaseClient get client => instance._supabase;

  static String get supabaseUrl => _resolved.url;

  static String get anonKey => _resolved.anonKey;

  static String get fleaberEnv => _resolved.envLabel;

  static Future initialize() {
    final cfg = _resolved;
    return Supabase.initialize(
      url: cfg.url,
      headers: {
        'X-Client-Info': 'flutterflow',
        'X-Fleaber-Env': cfg.envLabel,
      },
      anonKey: cfg.anonKey,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
    );
  }
}
