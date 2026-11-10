import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/live_publish_config.dart';
import '/utils/fleaber_logger.dart';

/// Evita cards LIVE fantasmas quando a app fecha sem «Terminar directo».
///
/// Regra de ouro: **só** [finalizeEnded] com `force: true` pode matar um
/// directo com prefs/memória activos — e isso só vem do botão «Terminar».
abstract final class LivePublishCleanup {
  static const _prefLiveId = 'batata_active_broadcast_live_id_v1';
  static const _prefLiveSince = 'batata_active_broadcast_since_v1';

  /// Directos com menos de isto não são fechados por fullSweep.
  /// 2 min era demasiado agressivo (token refresh / Home / espelho USB).
  static const _orphanMinAge = Duration(hours: 2);

  /// Directo activo nesta sessão (memória) — não fechar no [reconcileOnAppStart].
  static String? _inProgressLiveId;

  /// Evita fullSweep em cada emissão do stream de auth (ex. tokenRefreshed).
  static bool _didFullSweepThisProcess = false;

  static bool get isBroadcastInProgress {
    final id = _inProgressLiveId?.trim() ?? '';
    return id.isNotEmpty;
  }

  static void setBroadcastInProgress(String? liveId) {
    final id = liveId?.trim() ?? '';
    _inProgressLiveId = id.isEmpty ? null : id;
  }

  /// Marca directo activo (prefs sobrevivem a kill; memória evita fechar ao retomar).
  static Future<void> registerActiveBroadcast(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return;
    setBroadcastInProgress(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLiveId, id);
    await prefs.setInt(
      _prefLiveSince,
      DateTime.now().millisecondsSinceEpoch,
    );
    unawaited(
      FleaberLogger.instance.event('live_publish.register_broadcast', {
        'live_id': id,
      }),
    );
  }

  static Future<void> clearActiveBroadcast() async {
    final prev = _inProgressLiveId;
    setBroadcastInProgress(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLiveId);
    await prefs.remove(_prefLiveSince);
    unawaited(
      FleaberLogger.instance.event('live_publish.clear_broadcast', {
        'prev_live_id': prev,
      }),
    );
  }

  /// Fecha directo na BD e tenta Mux/LiveKit (best-effort).
  ///
  /// [force] — **apenas** fim explícito («Terminar directo»). Sem force, nunca
  /// mata o liveId marcado em prefs/memória (Perfil / espelho USB / Home /
  /// resume Stripe / dispose).
  static Future<bool> finalizeEnded(
    String liveId, {
    bool runBackendTeardown = true,
    String reason = 'unspecified',
    bool force = false,
  }) async {
    final id = liveId.trim();
    if (id.isEmpty) return false;

    if (!force) {
      final protected = await preferredActiveBroadcastId();
      if (protected != null && protected == id) {
        debugPrint(
          '[LivePublishCleanup] FINALIZE BLOCKED protected id=$id '
          'reason=$reason',
        );
        unawaited(
          FleaberLogger.instance.event('live_publish.finalize_blocked', {
            'live_id': id,
            'reason': reason,
          }),
        );
        return false;
      }
    }

    var closed = false;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final row = rows.first;
      final status = (row.status ?? '').trim().toLowerCase();
      if (status != 'live' || row.isActive != true) {
        if (_inProgressLiveId == id) setBroadcastInProgress(null);
        debugPrint(
          '[LivePublishCleanup] finalizeEnded skip id=$id '
          'status=$status isActive=${row.isActive} reason=$reason',
        );
        return false;
      }

      final stack = StackTrace.current.toString().split('\n').take(8).join(' | ');
      debugPrint(
        '[LivePublishCleanup] FINALIZE→ENDED id=$id reason=$reason '
        'force=$force memBroadcast=$_inProgressLiveId kIsWeb=$kIsWeb '
        'stack=$stack',
      );
      unawaited(
        FleaberLogger.instance.event('live_publish.finalize_ended', {
          'live_id': id,
          'reason': reason,
          'force': force,
          'stack': stack,
        }),
      );

      // ZIP 168: ended_at obrigatório no fecho (antes só status/is_active —
      // deixava Gravados/Hub sem âncora temporal e dificultava sweeps).
      await LivesTable().update(
        data: {
          'status': 'ended',
          'is_active': false,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => q.eqOrNull('id', id),
      );
      closed = true;
      requestLiveFeedRefresh();

      if (runBackendTeardown) {
        unawaited(_runBackendTeardown(id));
      }
    } catch (e) {
      debugPrint('[LivePublishCleanup] finalizeEnded failed: $e');
    }

    if (closed) {
      final prefs = await SharedPreferences.getInstance();
      final prefId = prefs.getString(_prefLiveId)?.trim() ?? '';
      if (prefId == id) {
        await clearActiveBroadcast();
      } else if (_inProgressLiveId == id) {
        setBroadcastInProgress(null);
      }
    }
    return closed;
  }

  static Future<void> _runBackendTeardown(String liveId) async {
    try {
      if (kPublishUsesLiveKit) {
        try {
          await SupaFlow.client.functions
              .invoke(
                'livekit-mux-publish',
                body: {'step': 'stop_egress', 'live_id': liveId},
              )
              .timeout(const Duration(seconds: 12));
        } catch (_) {}
      }
      try {
        await SupaFlow.client.functions
            .invoke(
              'complete-mux-live',
              body: {'live_id': liveId},
            )
            .timeout(const Duration(seconds: 20));
      } catch (_) {}
    } catch (e) {
      debugPrint('[LivePublishCleanup] backend teardown: $e');
    }
  }

  /// Restaura o liveId das prefs para memória (sobrevive a navegação Perfil/Home
  /// sem perder a protecção «broadcast em curso»).
  static Future<String?> restoreBroadcastFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefLiveId)?.trim() ?? '';
      if (id.isEmpty) return null;
      setBroadcastInProgress(id);
      debugPrint(
        '[LivePublishCleanup] restoreBroadcastFromPrefs liveId=$id',
      );
      return id;
    } catch (e) {
      debugPrint('[LivePublishCleanup] restoreBroadcastFromPrefs failed: $e');
      return null;
    }
  }

  static Future<String?> preferredActiveBroadcastId() async {
    final mem = _inProgressLiveId?.trim() ?? '';
    if (mem.isNotEmpty) {
      if (await _isStillLiveInDb(mem)) return mem;
      await clearActiveBroadcast();
      return null;
    }
    final restored = await restoreBroadcastFromPrefs();
    if (restored == null || restored.isEmpty) return null;
    // Prefs antigas de um directo já ended deixavam badge AO VIVO fantasma.
    if (!await _isStillLiveInDb(restored)) {
      await clearActiveBroadcast();
      return null;
    }
    return restored;
  }

  static Future<bool> _isStillLiveInDb(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return false;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final row = rows.first;
      final st = (row.status ?? '').trim().toLowerCase();
      return st == 'live' && row.isActive == true;
    } catch (_) {
      return true; // fail-open: não matar protecção se a query falhar
    }
  }

  /// Ao abrir a app: fecha directos órfãos (kill no Android / recentes).
  ///
  /// [fullSweep] — no arranque/login: fecha `live` antigos do vendedor sem
  /// sessão activa. Em [resumed] usar `false`. No **web** nunca faz fullSweep.
  ///
  /// FullSweep corre **no máximo uma vez por processo** (tokenRefreshed
  /// não pode voltar a varrer a meio do directo).
  static Future<int> reconcileOnAppStart({bool fullSweep = false}) async {
    final restored = await preferredActiveBroadcastId();
    if (restored != null && restored.isNotEmpty) {
      debugPrint(
        '[LivePublishCleanup] reconcile skip — broadcast activo '
        'liveId=$restored fullSweep=$fullSweep kIsWeb=$kIsWeb',
      );
      return 0;
    }

    final uid = currentUserUid.trim();
    if (uid.isEmpty) return 0;

    final allowFullSweep =
        fullSweep && !kIsWeb && !_didFullSweepThisProcess;
    if (fullSweep && !allowFullSweep && !kIsWeb) {
      debugPrint(
        '[LivePublishCleanup] reconcile skip fullSweep — already ran this process',
      );
    }

    var closed = 0;
    try {
      debugPrint(
        '[LivePublishCleanup] reconcile start uid=${uid.substring(0, uid.length > 8 ? 8 : uid.length)}… '
        'fullSweep=$fullSweep allowFullSweep=$allowFullSweep',
      );
      if (allowFullSweep) {
        _didFullSweepThisProcess = true;
        closed += await _closeOrphanSellerLives(uid);
      }
      if (closed > 0) {
        debugPrint(
          '[LivePublishCleanup] reconcile closed=$closed (orphan sweep)',
        );
        requestLiveFeedRefresh();
      }
    } catch (e) {
      debugPrint('[LivePublishCleanup] reconcile failed: $e');
    }
    return closed;
  }

  /// Qualquer live «live» do vendedor sem sessão activa na app = órfã.
  /// Só fecha se tiver ≥ [_orphanMinAge].
  static Future<int> _closeOrphanSellerLives(String sellerId) async {
    final rows = await LivesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('status', 'live')
          .eqOrNull('is_active', true)
          .order('created_at', ascending: false),
      limit: 30,
    );

    final now = DateTime.now().toUtc();
    var n = 0;
    for (final row in rows) {
      final sid = row.sellerId?.trim() ?? '';
      if (sid != sellerId) continue;
      final id = row.id?.trim();
      if (id == null || id.isEmpty) continue;
      if (id == _inProgressLiveId) continue;
      if (!kReleaseMode) {
        final title = (row.title ?? '').trim();
        if (title == 'MAESTRO_SMOKE_LIVE') continue;
      }
      final anchor = row.wentLiveAt ?? row.createdAt;
      if (anchor != null && now.difference(anchor.toUtc()) < _orphanMinAge) {
        continue;
      }
      debugPrint(
        '[LivePublishCleanup] orphanSweep candidate id=$id '
        'ageMin=${anchor == null ? "?" : now.difference(anchor.toUtc()).inMinutes}',
      );
      if (await finalizeEnded(id, reason: 'orphan_seller_sweep')) n++;
    }
    return n;
  }
}
