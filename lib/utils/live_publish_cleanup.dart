import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/marketplace_feed_refresh.dart';
import '/utils/live_publish_config.dart';

/// Evita cards LIVE fantasmas quando a app fecha sem «Terminar directo».
abstract final class LivePublishCleanup {
  static const _prefLiveId = 'batata_active_broadcast_live_id_v1';
  static const _prefLiveSince = 'batata_active_broadcast_since_v1';

  /// Directo activo nesta sessão (memória) — não fechar no [reconcileOnAppStart].
  static String? _inProgressLiveId;

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
  }

  static Future<void> clearActiveBroadcast() async {
    setBroadcastInProgress(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLiveId);
    await prefs.remove(_prefLiveSince);
  }

  /// Fecha directo na BD e tenta Mux/LiveKit (best-effort).
  static Future<bool> finalizeEnded(
    String liveId, {
    bool runBackendTeardown = true,
  }) async {
    final id = liveId.trim();
    if (id.isEmpty) return false;

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
        return false;
      }

      await LivesTable().update(
        data: {'status': 'ended', 'is_active': false},
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

  /// Ao abrir a app: fecha directos órfãos (kill no Android / recentes).
  ///
  /// [fullSweep] — no arranque/login/home: fecha todos os `live` do vendedor
  /// sem sessão activa. Em [resumed] usar `false` para não afectar outro device.
  static Future<int> reconcileOnAppStart({bool fullSweep = false}) async {
    if (isBroadcastInProgress) return 0;

    final uid = currentUserUid.trim();
    if (uid.isEmpty) return 0;

    var closed = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final orphanId = prefs.getString(_prefLiveId)?.trim() ?? '';
      if (orphanId.isNotEmpty) {
        if (await finalizeEnded(orphanId)) closed++;
        await clearActiveBroadcast();
      }

      if (fullSweep) {
        closed += await _closeOrphanSellerLives(uid);
      }
      if (closed > 0) requestLiveFeedRefresh();
    } catch (e) {
      debugPrint('[LivePublishCleanup] reconcile failed: $e');
    }
    return closed;
  }

  /// Qualquer live «live» do vendedor sem sessão activa na app = órfã.
  static Future<int> _closeOrphanSellerLives(String sellerId) async {
    final rows = await LivesTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('status', 'live')
          .eqOrNull('is_active', true)
          .order('created_at', ascending: false),
      limit: 30,
    );

    var n = 0;
    for (final row in rows) {
      final sid = row.sellerId?.trim() ?? '';
      if (sid != sellerId) continue;
      final id = row.id?.trim();
      if (id == null || id.isEmpty) continue;
      if (id == _inProgressLiveId) continue;
      if (await finalizeEnded(id)) n++;
    }
    return n;
  }
}
