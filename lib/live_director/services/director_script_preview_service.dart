import '/live_director/models/director_beat.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';

/// Pré-visualização temporal — sem BD.
class DirectorScriptPreviewService {
  const DirectorScriptPreviewService();

  List<PreviewLine> buildPreview(DirectorScript script) {
    final lines = <PreviewLine>[];
    final castByTag = {for (final c in script.castPool) c.internalTag: c};
    final productById = {
      for (final p in script.targetProducts) p.liveItemId: p,
    };

    for (final beat in script.beats) {
      if (!beat.enabled) continue;
      final offset = _resolvePreviewOffset(beat);
      final actor = beat.actorTag != null
          ? (castByTag[beat.actorTag]?.displayName ?? beat.actorTag)
          : _personaLabel(beat.actorPersona);
      final product = beat.liveItemId != null
          ? (productById[beat.liveItemId]?.title ??
              productById[beat.liveItemId]?.refCode ??
              beat.productRef ??
              'Produto')
          : null;

      lines.add(PreviewLine(
        offsetSec: offset,
        beatId: beat.beatId,
        confidence: beat.confidence,
        label: _formatLabel(beat, actor, product),
      ));
    }

    lines.sort((a, b) => a.offsetSec.compareTo(b.offsetSec));
    return lines;
  }

  int _resolvePreviewOffset(DirectorBeat beat) {
    switch (beat.momentType) {
      case DirectorMomentType.window:
        return beat.windowStartSec ?? beat.approxSec ?? 0;
      case DirectorMomentType.approx:
        return beat.approxSec ?? 0;
      case DirectorMomentType.afterSellerSilent:
        return beat.approxSec ?? 180;
      case DirectorMomentType.immediateOnRun:
        return 0;
      default:
        return beat.approxSec ?? beat.windowStartSec ?? 0;
    }
  }

  String _personaLabel(String? persona) {
    switch (persona) {
      case 'curious':
        return 'Curioso';
      case 'buyer':
        return 'Comprador';
      case 'fan':
        return 'Fã';
      default:
        return 'Observador';
    }
  }

  String _formatLabel(
    DirectorBeat beat,
    String? actor,
    String? product,
  ) {
    final who = actor ?? 'Director';
    switch (beat.action) {
      case DirectorActionType.enter:
        return '$who entra na live';
      case DirectorActionType.exit:
        return '$who sai da live';
      case DirectorActionType.like:
        return '$who dá like';
      case DirectorActionType.likeBurst:
        return 'Burst de likes (max ${beat.likeBurstMax})';
      case DirectorActionType.chat:
        final msg = beat.messageText ?? beat.phraseTag ?? 'mensagem';
        return '$who: «$msg»';
      case DirectorActionType.reserve:
        return '$who reserva $product ×${beat.qty}';
      case DirectorActionType.purchase:
        return '$who compra $product ×${beat.qty} (${beat.paymentMode.name})';
      case DirectorActionType.raffleJoin:
        return '$who inscreve-se na rifa';
      case DirectorActionType.silence:
        return 'Silêncio planeado';
      case DirectorActionType.wait:
        return 'Espera';
    }
  }
}

String formatOffsetMmSs(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
