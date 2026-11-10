import '../live_ops_staging_client.dart';

/// Bloqueia execução de regressão fora de staging.
class RegressionStagingGuard {
  static StagingCheckResult check(Map<String, String>? env) {
    if (env == null || env.isEmpty) {
      return StagingCheckResult(
        ok: false,
        reason: 'tool/live_ops_staging.env em falta',
      );
    }

    final urlRaw = env['SUPABASE_URL']?.trim() ?? '';
    if (urlRaw.isEmpty) {
      return StagingCheckResult(ok: false, reason: 'SUPABASE_URL em falta');
    }

    final url = normalizeSupabaseProjectUrl(urlRaw);
    final ref = supabaseProjectRefFromUrl(url);
    if (ref.isEmpty) {
      return StagingCheckResult(ok: false, reason: 'SUPABASE_URL inválida');
    }

    final lower = url.toLowerCase();
    const prodHints = ['prod', 'production', 'live-prod', 'fleaber-prod'];
    for (final hint in prodHints) {
      if (lower.contains(hint)) {
        return StagingCheckResult(
          ok: false,
          reason: 'URL parece produção ($hint) — bloqueado',
        );
      }
    }

    final stagingOnly = (env['REGRESSION_STAGING_ONLY'] ?? 'true').toLowerCase() != 'false';
    if (!stagingOnly) {
      return StagingCheckResult(ok: true, projectRef: ref, url: url);
    }

    final allowedRaw = env['BOT_SIM_ALLOWED_PROJECT_REFS']?.trim() ?? '';
    final allowed = allowedRaw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    if (allowed.isNotEmpty) {
      if (!allowed.contains(ref.toLowerCase())) {
        return StagingCheckResult(
          ok: false,
          reason: 'project ref "$ref" não está em BOT_SIM_ALLOWED_PROJECT_REFS',
        );
      }
      return StagingCheckResult(ok: true, projectRef: ref, url: url);
    }

    final allowAny = (env['BOT_SIM_ALLOW_ANY_STAGING'] ?? '').toLowerCase() == 'true';
    if (allowAny) {
      return StagingCheckResult(ok: true, projectRef: ref, url: url);
    }

    // Com .env presente e URL Supabase válida: permitir project ref actual (não-prod).
    return StagingCheckResult(ok: true, projectRef: ref, url: url);
  }
}

class StagingCheckResult {
  StagingCheckResult({required this.ok, this.reason, this.projectRef, this.url});

  final bool ok;
  final String? reason;
  final String? projectRef;
  final String? url;
}
