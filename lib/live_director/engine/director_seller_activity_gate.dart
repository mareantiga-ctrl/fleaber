import '/live_director/engine/director_world_model.dart';

/// Seller Activity Gate — SELLER_ACTIVE pausa beats sociais.
class DirectorSellerActivityGate {
  static const sellerActiveHoldSec = 120;
  static const sellerOpenAfterSilentSec = 90;

  bool isSellerActive(DirectorWorldModel world, DateTime now) {
    if (world.sellerAmbiencePaused) return true;
    if (world.sellerPresentingManual) return true;
    final last = world.lastSellerSignalAt;
    if (last == null) return false;
    return now.difference(last).inSeconds < sellerOpenAfterSilentSec;
  }

  DirectorWorldModel recordSellerSignal(DirectorWorldModel world) =>
      world.copyWith(lastSellerSignalAt: DateTime.now().toUtc());

  bool shouldDeferCommercial(DirectorWorldModel world, DateTime now) =>
      isSellerActive(world, now);

  bool shouldBlockSocial(DirectorWorldModel world, DateTime now) =>
      isSellerActive(world, now);
}
