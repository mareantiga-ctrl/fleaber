import '/live_director/models/director_beat.dart';
import '/live_director/models/director_manifest.dart';
import '/live_director/models/director_script.dart';
import '/live_director/models/director_types.dart';

/// Validação pré-run e pré-flight.
class DirectorScriptValidator {
  const DirectorScriptValidator();

  Future<PreflightResult> validate({
    required DirectorScript script,
    required Map<String, dynamic>? liveRow,
    required List<Map<String, dynamic>> liveItems,
    required List<Map<String, dynamic>> simProfiles,
    required bool killSwitchOk,
    required Map<String, bool> confirmations,
    bool requireAllConfirmations = true,
  }) async {
    final issues = <PreflightIssue>[];
    final stockBefore = <String, int>{};
    final stockAfter = <String, int>{};
    final payments = <String, String>{};
    final risks = <String>[];

    if (script.name.trim().isEmpty) {
      issues.add(const PreflightIssue(
        level: 'error',
        code: 'script_name',
        message: 'Nome do script em falta.',
      ));
    }
    if (script.version < 1) {
      issues.add(const PreflightIssue(
        level: 'error',
        code: 'script_version',
        message: 'Versão inválida.',
      ));
    }
    if ((script.operatorLabel ?? '').trim().isEmpty &&
        (script.operatorId ?? '').isEmpty) {
      issues.add(const PreflightIssue(
        level: 'error',
        code: 'operator',
        message: 'Operador em falta.',
      ));
    }
    if ((script.liveId ?? '').isEmpty) {
      issues.add(const PreflightIssue(
        level: 'error',
        code: 'live_id',
        message: 'Live alvo em falta.',
      ));
    }
    if (liveRow == null && (script.liveId ?? '').isNotEmpty) {
      issues.add(const PreflightIssue(
        level: 'error',
        code: 'live_missing',
        message: 'Live não encontrada.',
      ));
    }
    if (liveRow != null && script.sellerId != null) {
      final sid = (liveRow['seller_id'] ?? liveRow['vendedor_id'])?.toString();
      if (sid != null && sid.isNotEmpty && sid != script.sellerId) {
        issues.add(const PreflightIssue(
          level: 'error',
          code: 'seller_mismatch',
          message: 'Seller do script não coincide com a live.',
        ));
      }
    }
    if (!killSwitchOk) {
      issues.add(const PreflightIssue(
        level: 'warning',
        code: 'kill_switch',
        message: 'Kill switch RPC não respondeu (verificar SQL aplicado).',
      ));
    }

    final itemById = {for (final i in liveItems) i['id']?.toString() ?? '': i};
    final allowedIds = script.targetProducts.map((e) => e.liveItemId).toSet();

    for (final tp in script.targetProducts) {
      final item = itemById[tp.liveItemId];
      if (item == null) {
        issues.add(PreflightIssue(
          level: 'error',
          code: 'product_missing',
          message: 'Produto alvo ${tp.liveItemId} não existe na live.',
        ));
      } else {
        final avail = _stockAvail(item);
        stockBefore[tp.liveItemId] = avail;
        stockAfter[tp.liveItemId] = avail;
      }
    }

    final castTags = script.castPool.map((e) => e.internalTag).toSet();
    final simByProfile = {
      for (final s in simProfiles) s['profile_id']?.toString() ?? '': s,
    };

    for (final m in script.castPool) {
      if (m.profileId.isEmpty) {
        issues.add(PreflightIssue(
          level: 'error',
          code: 'cast_profile',
          message: 'Elenco ${m.internalTag} sem profile_id.',
        ));
      }
      final sim = simByProfile[m.profileId];
      if (sim == null) {
        issues.add(PreflightIssue(
          level: 'warning',
          code: 'cast_not_sim',
          message: '${m.internalTag} não está em live_director_sim_profiles.',
        ));
      }
    }

    var reservations = 0;
    var purchases = 0;
    var messages = 0;
    var likes = 0;
    var enters = 0;
    var exits = 0;
    var raffleJoins = 0;

    for (final beat in script.beats) {
      if (!beat.enabled) continue;

      switch (beat.action) {
        case DirectorActionType.chat:
          messages++;
        case DirectorActionType.like:
        case DirectorActionType.likeBurst:
          likes++;
        case DirectorActionType.enter:
          enters++;
        case DirectorActionType.exit:
          exits++;
        case DirectorActionType.reserve:
          reservations++;
        case DirectorActionType.purchase:
          purchases++;
        case DirectorActionType.raffleJoin:
          raffleJoins++;
        default:
          break;
      }

      if (beat.isCommercial) {
        final itemId = beat.liveItemId ?? '';
        if (itemId.isEmpty) {
          issues.add(PreflightIssue(
            level: 'error',
            code: 'commercial_no_product',
            message: 'Beat ${beat.beatId}: reserva/compra sem produto.',
            beatId: beat.beatId,
          ));
        } else if (!allowedIds.contains(itemId)) {
          issues.add(PreflightIssue(
            level: 'error',
            code: 'product_not_allowed',
            message: 'Beat ${beat.beatId}: produto não está na lista alvo.',
            beatId: beat.beatId,
          ));
        }
        if (beat.actorTag != null && !castTags.contains(beat.actorTag)) {
          issues.add(PreflightIssue(
            level: 'error',
            code: 'actor_unknown',
            message: 'Beat ${beat.beatId}: actor ${beat.actorTag} não no elenco.',
            beatId: beat.beatId,
          ));
        }
        if (beat.paymentMode == DirectorPaymentMode.real) {
          if (script.mode != DirectorScriptMode.qa &&
              script.mode != DirectorScriptMode.productionControlled) {
            issues.add(PreflightIssue(
              level: 'error',
              code: 'real_payment_demo',
              message: 'Beat ${beat.beatId}: pagamento real bloqueado em Demo.',
              beatId: beat.beatId,
            ));
          }
          if (!script.policy.allowRealPayments) {
            issues.add(PreflightIssue(
              level: 'error',
              code: 'real_payment_policy',
              message: 'Beat ${beat.beatId}: policy não autoriza pagamento real.',
              beatId: beat.beatId,
            ));
          }
          payments[beat.beatId] = 'real';
          risks.add('Pagamento real no beat ${beat.beatId}');
        } else if (beat.paymentMode == DirectorPaymentMode.simulated) {
          payments[beat.beatId] = 'simulated';
        }

        final cur = stockAfter[itemId] ?? 0;
        stockAfter[itemId] = cur - beat.qty;
        if ((stockAfter[itemId] ?? 0) < 0) {
          issues.add(PreflightIssue(
            level: 'error',
            code: 'stock_insufficient',
            message: 'Stock insuficiente para beat ${beat.beatId}.',
            beatId: beat.beatId,
          ));
        }
      }
    }

    if (reservations > script.policy.maxReservationsPerLive) {
      issues.add(PreflightIssue(
        level: 'error',
        code: 'limit_reservations',
        message: 'Reservas planeadas ($reservations) > limite ${script.policy.maxReservationsPerLive}.',
      ));
    }
    if (purchases > script.policy.maxPurchasesPerLive) {
      issues.add(PreflightIssue(
        level: 'error',
        code: 'limit_purchases',
        message: 'Compras planeadas ($purchases) > limite ${script.policy.maxPurchasesPerLive}.',
      ));
    }

    if (requireAllConfirmations) {
      if (confirmations['products_stock'] != true) {
        issues.add(const PreflightIssue(
          level: 'error',
          code: 'confirm_products',
          message: 'Confirmação «Revisei produtos e stock» em falta.',
        ));
      }
      if ((reservations + purchases) > 0 &&
          confirmations['intentional_commerce'] != true) {
        issues.add(const PreflightIssue(
          level: 'error',
          code: 'confirm_commerce',
          message: 'Confirmação «Reservas/compras intencionais» em falta.',
        ));
      }
      if (stockAfter.values.any((v) => v < (stockBefore.values.fold(0, (a, b) => a))) &&
          confirmations['affect_stock'] != true) {
        issues.add(const PreflightIssue(
          level: 'error',
          code: 'confirm_stock',
          message: 'Confirmação «Pode afectar stock real» em falta.',
        ));
      }
      if (payments.containsValue('real') &&
          confirmations['real_payments'] != true) {
        issues.add(const PreflightIssue(
          level: 'error',
          code: 'confirm_real_pay',
          message: 'Confirmação «Pagamentos reais autorizados» em falta.',
        ));
      }
    }

    final checksum = DirectorManifest.computeChecksum(script);
    final passed = !issues.any((i) => i.level == 'error');

    return PreflightResult(
      passed: passed,
      issues: issues,
      summary: PreflightSummary(
        totalBeats: script.beats.where((b) => b.enabled).length,
        messages: messages,
        likes: likes,
        enters: enters,
        exits: exits,
        reservations: reservations,
        purchases: purchases,
        raffleJoins: raffleJoins,
        productsAffected: allowedIds.toList(),
        stockBefore: stockBefore,
        stockAfterProjected: stockAfter,
        paymentsProjected: payments,
        risks: risks,
      ),
      validationToken: passed ? checksum.substring(0, 16) : null,
      checksum: checksum,
    );
  }

  int _stockAvail(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?)?.toInt();
    if (qty != null) return qty;
    return (item['available_qty'] as num?)?.toInt() ?? 0;
  }
}
