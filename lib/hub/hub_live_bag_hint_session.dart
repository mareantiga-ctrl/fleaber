/// Tooltip saco Hub — uma vez por sessão de app (por liveId).
abstract final class HubLiveBagHintSession {
  static final Set<String> _dismissedLiveIds = {};

  static bool shouldShow(String liveId) =>
      liveId.isNotEmpty && !_dismissedLiveIds.contains(liveId);

  static void dismiss(String liveId) {
    if (liveId.isEmpty) return;
    _dismissedLiveIds.add(liveId);
  }
}
