import '/utils/live_reservation_queue_service.dart';

/// FOMO publico no chat: apenas «ultima unidade» quando stock desce de >1 para 1.
class LiveFomoBroadcaster {
  LiveFomoBroadcaster({required this.liveId});

  final String liveId;
  final Map<String, DateTime> _lastSent = {};

  bool _cooldownOk(String key, Duration minGap) {
    final now = DateTime.now();
    final last = _lastSent[key];
    if (last != null && now.difference(last) < minGap) return false;
    _lastSent[key] = now;
    return true;
  }

  /// Chat: so quando [previousAvailableQty] > 1 e ficou exactamente 1.
  Future<void> notifyCrossedToLastUnit({
    required String liveItemId,
    required String refLabel,
    required int previousAvailableQty,
    required int availableQty,
  }) async {
    if (previousAvailableQty <= 1 || availableQty != 1) return;
    final key = 'last1:$liveItemId';
    if (!_cooldownOk(key, const Duration(minutes: 4))) return;
    final ref = refLabel.trim().isEmpty ? 'este artigo' : refLabel.trim();
    await LiveReservationQueueService().postSystemMessage(
      liveId: liveId,
      body: '🔥 Ultima unidade — $ref',
    );
  }

  Future<void> maybeSoldOut({
    required String liveItemId,
    required String refLabel,
  }) async {
    final key = 'sold:$liveItemId';
    if (!_cooldownOk(key, const Duration(hours: 12))) return;
    final ref = refLabel.trim().isEmpty ? 'Artigo' : refLabel.trim();
    await LiveReservationQueueService().postSystemMessage(
      liveId: liveId,
      body: '🔴 $ref esgotado',
    );
  }
}
