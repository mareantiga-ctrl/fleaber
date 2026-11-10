/// Estado live/gravado derivado de `lives` — alinhado a [HubLive.isEnded].
///
/// `is_active` null + status live → **não** ended (evita forçar VOD em live activa).
bool liveRowIsEnded({required String? status, required bool? isActive}) {
  final s = (status ?? '').trim().toLowerCase();
  if (s == 'ended' || s == 'cancelled') return true;
  if (s == 'live') return isActive == false;
  return isActive == false;
}

bool liveRowIsLiveNow({required String? status, required bool? isActive}) {
  if (liveRowIsEnded(status: status, isActive: isActive)) return false;
  return (status ?? '').trim().toLowerCase() == 'live' && isActive != false;
}
