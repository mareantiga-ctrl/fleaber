import '/live_director/models/director_beat.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';
import '/live_director/services/director_script_validator.dart';

/// Dry run — valida e simula sem escrever na BD.
class DirectorDryRunService {
  const DirectorDryRunService();

  Future<DryRunResult> run({
    required DirectorScript script,
    required Map<String, dynamic>? liveRow,
    required List<Map<String, dynamic>> liveItems,
    required List<Map<String, dynamic>> simProfiles,
  }) async {
    final validator = DirectorScriptValidator();
    final preflight = await validator.validate(
      script: script,
      liveRow: liveRow,
      liveItems: liveItems,
      simProfiles: simProfiles,
      killSwitchOk: true,
      confirmations: const {
        'products_stock': true,
        'intentional_commerce': true,
        'affect_stock': true,
        'real_payments': true,
      },
      requireAllConfirmations: false,
    );

    final beatResults = <DryRunBeatResult>[];
    final allowedProducts =
        script.targetProducts.map((e) => e.liveItemId).toSet();
    final castTags = script.castPool.map((e) => e.internalTag).toSet();
    final seenCommercial = <String, int>{};

    for (final beat in script.beats) {
      if (!beat.enabled) {
        beatResults.add(DryRunBeatResult(
          beatId: beat.beatId,
          status: 'skipped',
          reason: 'disabled',
        ));
        continue;
      }

      String? blockReason;
      if (beat.isCommercial) {
        final itemId = beat.liveItemId ?? '';
        if (!allowedProducts.contains(itemId)) {
          blockReason = 'produto não autorizado';
        }
        if (beat.actorTag != null && !castTags.contains(beat.actorTag)) {
          blockReason = 'actor desconhecido';
        }
        if (beat.paymentMode == DirectorPaymentMode.real &&
            script.mode == DirectorScriptMode.demo) {
          blockReason = 'pagamento real bloqueado em demo';
        }
        final key = '${beat.actorTag}:${itemId}:${beat.action.name}';
        seenCommercial[key] = (seenCommercial[key] ?? 0) + beat.qty;
      }

      if (blockReason != null) {
        beatResults.add(DryRunBeatResult(
          beatId: beat.beatId,
          status: 'blocked',
          reason: blockReason,
        ));
      } else {
        beatResults.add(DryRunBeatResult(
          beatId: beat.beatId,
          status: 'executable',
        ));
      }
    }

    final passed = preflight.passed &&
        !beatResults.any((b) => b.status == 'blocked');

    return DryRunResult(
      passed: passed,
      beats: beatResults,
      issues: preflight.issues,
    );
  }
}
