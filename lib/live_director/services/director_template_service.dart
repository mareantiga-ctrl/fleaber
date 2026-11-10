import '/live_director/models/director_beat.dart';
import '/live_director/models/director_script.dart';

/// Duplicar scripts e remap produtos/bots.
class DirectorTemplateService {
  const DirectorTemplateService();

  DirectorScript duplicate({
    required DirectorScript source,
    required String newName,
    String? newLiveId,
    Map<String, String>? productIdMap,
    Map<String, String>? actorTagMap,
    int timeShiftSec = 0,
  }) {
    final newProducts = source.targetProducts.map((p) {
      final mapped = productIdMap?[p.liveItemId];
      return DirectorTargetProduct(
        liveItemId: mapped ?? p.liveItemId,
        refCode: p.refCode,
        title: p.title,
        allowReserve: p.allowReserve,
        allowPurchase: p.allowPurchase,
      );
    }).toList();

    final newCast = source.castPool.map((c) {
      final tag = actorTagMap?[c.internalTag] ?? c.internalTag;
      return DirectorCastMember(
        internalTag: tag,
        profileId: c.profileId,
        displayName: c.displayName,
        persona: c.persona,
        email: c.email,
      );
    }).toList();

    final newBeats = source.beats.map((b) {
      final mappedItem = b.liveItemId != null
          ? (productIdMap?[b.liveItemId!] ?? b.liveItemId)
          : null;
      final mappedActor =
          b.actorTag != null ? (actorTagMap?[b.actorTag!] ?? b.actorTag) : null;
      return DirectorBeat(
        beatId: b.beatId,
        momentType: b.momentType,
        action: b.action,
        windowStartSec: b.windowStartSec != null
            ? b.windowStartSec! + timeShiftSec
            : null,
        windowEndSec:
            b.windowEndSec != null ? b.windowEndSec! + timeShiftSec : null,
        approxSec: b.approxSec != null ? b.approxSec! + timeShiftSec : null,
        afterEvent: b.afterEvent,
        afterSilentSec: b.afterSilentSec,
        actorTag: mappedActor,
        actorPersona: b.actorPersona,
        liveItemId: mappedItem,
        productRef: b.productRef,
        qty: b.qty,
        messageText: b.messageText,
        phraseTag: b.phraseTag,
        enabled: b.enabled,
        fixedTime: b.fixedTime,
        maxSlipSec: b.maxSlipSec,
        confidence: b.confidence,
        affectStock: b.affectStock,
        paymentMode: b.paymentMode,
        notes: b.notes,
        likeBurstMax: b.likeBurstMax,
        likeBurstWindowSec: b.likeBurstWindowSec,
      );
    }).toList();

    return DirectorScript(
      name: newName,
      version: 1,
      description: 'Duplicado de ${source.name} v${source.version}',
      mode: source.mode,
      liveId: newLiveId ?? source.liveId,
      sellerId: source.sellerId,
      operatorId: source.operatorId,
      operatorLabel: source.operatorLabel,
      targetProducts: newProducts,
      castPool: newCast,
      beats: newBeats,
      policy: source.policy,
      status: 'draft',
      parentScriptId: source.id,
      tags: [...source.tags, 'duplicado'],
    );
  }
}
