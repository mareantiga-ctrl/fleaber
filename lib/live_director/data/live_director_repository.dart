import '/backend/supabase/supabase.dart';
import '/live_director/models/director_manifest.dart';
import '/live_director/models/director_run.dart';
import '/live_director/models/director_script.dart';

/// Repositório Live Director — isolado; só tabelas `live_director_*`.
class LiveDirectorRepository {
  LiveDirectorRepository({SupabaseClient? client})
      : _client = client ?? SupaFlow.client;

  final SupabaseClient _client;

  Future<List<DirectorScript>> listScripts({int limit = 50}) async {
    final rows = await _client
        .from('live_director_scripts')
        .select()
        .order('updated_at', ascending: false)
        .limit(limit);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => DirectorScript.fromRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DirectorScript?> getScript(String id) async {
    final row = await _client
        .from('live_director_scripts')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row is! Map) return null;
    return DirectorScript.fromRow(Map<String, dynamic>.from(row as Map));
  }

  Future<DirectorScript> upsertScript(DirectorScript script) async {
    final row = script.toRow();
    if (script.id == null || script.id!.isEmpty) {
      row.remove('id');
      final inserted = await _client
          .from('live_director_scripts')
          .insert(row)
          .select()
          .single();
      return DirectorScript.fromRow(
          Map<String, dynamic>.from(inserted as Map));
    }
    final updated = await _client
        .from('live_director_scripts')
        .update(row)
        .eq('id', script.id!)
        .select()
        .single();
    return DirectorScript.fromRow(Map<String, dynamic>.from(updated as Map));
  }

  Future<void> deleteScript(String id) async {
    await _client.from('live_director_scripts').delete().eq('id', id);
  }

  Future<DirectorRun> createRun({
    required DirectorManifest manifest,
    required String scriptId,
    required String checksum,
    required String operatorId,
  }) async {
    final inserted = await _client
        .from('live_director_runs')
        .insert({
          'script_id': scriptId,
          'script_checksum': checksum,
          'manifest': manifest.toJson(),
          'live_id': manifest.liveId,
          'seller_id': manifest.sellerId,
          'operator_id': operatorId,
          'mode': manifest.mode.name == 'productionControlled'
              ? 'production_controlled'
              : manifest.mode.name,
          'status': 'preflight_ok',
        })
        .select()
        .single();
    return DirectorRun.fromRow(Map<String, dynamic>.from(inserted as Map));
  }

  Future<List<DirectorRun>> listRuns({String? liveId, int limit = 40}) async {
    var q = _client.from('live_director_runs').select();
    if (liveId != null && liveId.isNotEmpty) {
      q = q.eq('live_id', liveId);
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => DirectorRun.fromRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DirectorRun?> getRun(String runId) async {
    final row = await _client
        .from('live_director_runs')
        .select()
        .eq('id', runId)
        .maybeSingle();
    if (row is! Map) return null;
    return DirectorRun.fromRow(Map<String, dynamic>.from(row as Map));
  }

  Future<void> updateRunStatus(
    String runId, {
    required String status,
    String? killReason,
    Map<String, dynamic>? stats,
    Map<String, dynamic>? report,
    bool? timelineSealed,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? liveStartedAt,
  }) async {
    final patch = <String, dynamic>{'status': status};
    if (killReason != null) patch['kill_reason'] = killReason;
    if (stats != null) patch['stats'] = stats;
    if (report != null) patch['report'] = report;
    if (timelineSealed != null) patch['timeline_sealed'] = timelineSealed;
    if (startedAt != null) {
      patch['started_at'] = startedAt.toUtc().toIso8601String();
    }
    if (endedAt != null) {
      patch['ended_at'] = endedAt.toUtc().toIso8601String();
    }
    if (liveStartedAt != null) {
      patch['live_started_at'] = liveStartedAt.toUtc().toIso8601String();
    }
    await _client.from('live_director_runs').update(patch).eq('id', runId);
  }

  Future<void> patchManifestControl(
    String runId,
    Map<String, dynamic> control,
  ) async {
    final run = await getRun(runId);
    if (run == null) return;
    final m = Map<String, dynamic>.from(run.manifest);
    m['control'] = control;
    await _client
        .from('live_director_runs')
        .update({'manifest': m})
        .eq('id', runId);
  }

  Future<void> appendAudit({
    required String runId,
    required String liveId,
    required String eventType,
    required String outcome,
    String? beatId,
    int? liveOffsetMs,
    String? actorId,
    String? productId,
    String? reason,
    Map<String, dynamic>? payload,
    required int seq,
  }) async {
    await _client.from('live_director_audit_log').insert({
      'run_id': runId,
      'live_id': liveId,
      'beat_id': beatId,
      'seq': seq,
      'live_offset_ms': liveOffsetMs,
      'event_type': eventType,
      'actor_id': actorId,
      'product_id': productId,
      'outcome': outcome,
      'reason': reason,
      'payload': payload ?? {},
    });
  }

  Future<void> appendTimeline({
    required String runId,
    required String liveId,
    required String manifestId,
    required int liveOffsetMs,
    required String kind,
    required String origin,
    String? actorId,
    String? beatId,
    Map<String, dynamic>? payload,
    bool replayVisible = true,
    String? refTable,
    String? refId,
  }) async {
    await _client.from('live_director_timeline_events').insert({
      'run_id': runId,
      'live_id': liveId,
      'manifest_id': manifestId,
      'live_offset_ms': liveOffsetMs,
      'kind': kind,
      'origin': origin,
      'actor_id': actorId,
      'beat_id': beatId,
      'payload': payload ?? {},
      'replay_visible': replayVisible,
      'ref_table': refTable,
      'ref_id': refId,
    });
  }

  Future<List<Map<String, dynamic>>> listTimeline(
    String liveId, {
    int? fromOffsetMs,
  }) async {
    var q = _client
        .from('live_director_timeline_events')
        .select()
        .eq('live_id', liveId);
    if (fromOffsetMs != null) {
      q = q.gte('live_offset_ms', fromOffsetMs);
    }
    final rows = await q.order('live_offset_ms');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listAudit(String runId) async {
    final rows = await _client
        .from('live_director_audit_log')
        .select()
        .eq('run_id', runId)
        .order('seq');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<bool> killSwitchActive(String scope, [String scopeKey = '']) async {
    try {
      final res = await _client.rpc(
        'batata_director_kill_switch_active',
        params: {'p_scope': scope, 'p_scope_key': scopeKey},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> activateKillSwitch(
    String scope,
    String scopeKey,
    String reason,
  ) async {
    await _client.rpc(
      'batata_director_activate_kill_switch',
      params: {
        'p_scope': scope,
        'p_scope_key': scopeKey,
        'p_reason': reason,
      },
    );
  }

  Future<void> deactivateKillSwitch(String scope, String scopeKey) async {
    await _client.rpc(
      'batata_director_deactivate_kill_switch',
      params: {'p_scope': scope, 'p_scope_key': scopeKey},
    );
  }

  Future<Map<String, dynamic>?> getLive(String liveId) async {
    final row = await _client
        .from('lives')
        .select(LivesTable().selectColumns!)
        .eq('id', liveId)
        .maybeSingle();
    if (row is! Map) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> getLiveItems(String liveId) async {
    final rows = await _client
        .from('live_items')
        .select()
        .eq('live_id', liveId);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listSimProfiles() async {
    final rows = await _client
        .from('live_director_sim_profiles')
        .select()
        .eq('is_active', true)
        .order('internal_tag');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> linkLiveToRun(String liveId, String runId, String mode) async {
    await _client.from('lives').update({
      'director_run_id': runId,
      'director_sim_mode': mode,
    }).eq('id', liveId);
  }
}
