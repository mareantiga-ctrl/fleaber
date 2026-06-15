import '../live_ops_staging_client.dart';

/// Bloqueia execução fora de staging permitido.
void assertBotSimStagingAllowed({
  required String projectUrl,
  required Map<String, String> env,
  bool force = false,
}) {
  if (force) return;

  final ref = supabaseProjectRefFromUrl(projectUrl);
  if (ref.isEmpty) {
    throw StateError(
      'BOT_SIM: URL Supabase inválida. Usa --i-know-this-is-staging só se tiveres a certeza.',
    );
  }

  final allowAny = (env['BOT_SIM_ALLOW_ANY_STAGING'] ?? '').toLowerCase() == 'true';
  final allowedRaw = env['BOT_SIM_ALLOWED_PROJECT_REFS']?.trim() ?? '';
  final allowed = allowedRaw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  if (allowed.isNotEmpty) {
    if (!allowed.contains(ref.toLowerCase())) {
      throw StateError(
        'BOT_SIM BLOQUEADO: project ref "$ref" não está em BOT_SIM_ALLOWED_PROJECT_REFS. '
        'Adiciona o ref de staging ao tool/live_ops_staging.env ou usa --i-know-this-is-staging.',
      );
    }
    return;
  }

  if (!allowAny) {
    throw StateError(
      'BOT_SIM BLOQUEADO: define BOT_SIM_ALLOWED_PROJECT_REFS=$ref '
      'em tool/live_ops_staging.env (staging apenas). '
      'Ou BOT_SIM_ALLOW_ANY_STAGING=true para dev local.',
    );
  }

  // Heurística extra: recusar refs que parecem prod genérico (opcional)
  final blockProd = (env['BOT_SIM_BLOCK_PRODUCTION'] ?? 'true').toLowerCase() != 'false';
  if (blockProd) {
    final lower = projectUrl.toLowerCase();
    const blockedHints = ['prod', 'production', 'live-prod'];
    for (final hint in blockedHints) {
      if (lower.contains(hint)) {
        throw StateError(
          'BOT_SIM BLOQUEADO: URL parece produção ($hint).',
        );
      }
    }
  }
}
