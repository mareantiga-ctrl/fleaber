import 'package:flutter/material.dart';

import '/utils/live_catalog_prep_service.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_ref_lineage_preview_service.dart';
import '/utils/live_ref_scheme.dart';
import '/widgets/live_ref_lineage_sheet.dart';

/// Gate V1.5 — sheet de linhagem antes de gravar live_only no draft.
abstract final class LiveRefLineagePrepGate {
  /// Refs individuais que o sync de catálogo criaria (espelha [LiveCatalogSync]).
  static List<String> refsFromSchemes(
    List<LiveRefScheme> schemes, {
    required bool Function(String ref) skipRef,
  }) {
    final out = <String>[];
    final seen = <String>{};

    for (final scheme in schemes) {
      if (scheme.spanCount <= 0) continue;
      final max = scheme.spanCount <= 15 ? 100 : 40;
      for (final ref in scheme.expandRefs(max: max)) {
        if (skipRef(ref)) continue;
        final key = LivePrepRefDetails.normalizeRefKey(ref);
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(ref);
      }
    }
    return out;
  }

  /// Garante draft + sheet (se necessário) + upsert por ref. `false` = cancelado/erro.
  static Future<bool> resolveRef({
    required BuildContext context,
    required String sellerId,
    required String refCode,
    required LiveRefChipDetail detail,
    String? draftLiveId,
  }) async {
    final sid = sellerId.trim();
    final ref = refCode.trim();
    if (sid.isEmpty || ref.isEmpty) return false;

    final liveId =
        draftLiveId ?? await LiveCatalogPrepService.ensureDraftLive(sellerId: sid);
    if (liveId == null || liveId.isEmpty) {
      if (context.mounted) {
        _snack(
          context,
          'Não foi possível preparar o rascunho do directo.',
        );
      }
      return false;
    }

    final preview = await LiveRefLineagePreviewService.fetch(
      sellerId: sid,
      refCode: ref,
      liveId: liveId,
    );
    if (!context.mounted) return false;

    if (preview == null) {
      _snack(
        context,
        'Não foi possível verificar o histórico de $ref. Tenta outra vez.',
      );
      return false;
    }
    if (!preview.isOk) {
      final err = preview.error?.trim();
      _snack(
        context,
        err != null && err.isNotEmpty
            ? 'Histórico de $ref indisponível: $err.'
            : 'Histórico de $ref indisponível.',
      );
      return false;
    }

    var lineageMode = 'new';
    String? inheritLogicalId;
    LiveRefLineageEntry? inheritSnapshot;

    if (preview.shouldPromptLineageDecision) {
      final decision = await LiveRefLineageSheet.show(
        context,
        report: preview,
        sellerId: sid,
        draftLiveId: liveId,
      );
      if (!context.mounted || decision == null) return false;
      switch (decision) {
        case LiveRefLineageInherit(:final logicalItemId, :final inheritFrom):
          lineageMode = 'inherit';
          inheritLogicalId = logicalItemId;
          inheritSnapshot = inheritFrom;
        case LiveRefLineageNewArticle():
          lineageMode = 'new';
      }
    } else if (preview.continuableLineages.length == 1) {
      lineageMode = 'inherit';
      inheritSnapshot = preview.continuableLineages.first;
      inheritLogicalId = inheritSnapshot.logicalItemId;
    }

    final fallback = 'Ref ${ref.startsWith('#') ? ref.substring(1) : ref}';
    var price = detail.price;
    if (price == null || price <= 0) {
      final snapPrice = inheritSnapshot?.displayPrice;
      if (snapPrice != null && snapPrice > 0) {
        price = snapPrice;
      }
      if ((price == null || price <= 0) && inheritLogicalId != null) {
        for (final e in preview.lineages) {
          if (e.logicalItemId == inheritLogicalId &&
              e.displayPrice != null &&
              e.displayPrice! > 0) {
            price = e.displayPrice;
            break;
          }
        }
      }
      if (price == null || price <= 0) {
        for (final e in preview.lineages) {
          if (e.displayPrice != null && e.displayPrice! > 0) {
            price = e.displayPrice;
            break;
          }
        }
      }
    }

    String? title;
    int? quantity;
    String? clothingSize;
    String? gender;
    String? photoUrl;
    if (lineageMode == 'inherit') {
      // Z10: preço/título do sheet; qty calculada no SQL (vendas + reservas).
      if (price != null && price <= 0) price = null;
      final snapTitle = inheritSnapshot?.displayTitle.trim() ?? '';
      if (snapTitle.isNotEmpty) title = snapTitle;
      quantity = null;
      final snapPhoto = inheritSnapshot?.displayPhotoUrl?.trim() ?? '';
      if (snapPhoto.isNotEmpty) photoUrl = snapPhoto;
      if (detail.clothingSize?.trim().isNotEmpty == true) {
        clothingSize = detail.clothingSize!.trim();
        gender = detail.clothingColor?.trim();
      } else if (detail.isClothing) {
        clothingSize = detail.clothingSize;
        gender = detail.clothingColor;
      }
    } else {
      title = detail.buildLiveItemTitle(fallback);
      quantity = detail.quantity;
      if (detail.isClothing) {
        clothingSize = detail.clothingSize;
        gender = detail.clothingColor;
      }
    }

    try {
      await LiveCatalogStockService.upsertLiveOnlyItem(
        sellerId: sid,
        refCode: ref,
        title: title,
        price: price,
        quantity: quantity,
        clothingSize: clothingSize,
        gender: gender,
        photoUrl: photoUrl,
        liveId: liveId,
        lineageMode: lineageMode,
        logicalItemId: inheritLogicalId,
      );
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString();
        if (msg.contains('history_not_active')) {
          _snack(
            context,
            'Este histórico está encerrado. Escolhe outro ou começa um novo.',
          );
        } else if (msg.contains('lineage_not_found')) {
          _snack(
            context,
            'Não foi possível continuar esse histórico. Tenta «Começar novo histórico».',
          );
        } else {
          _snack(context, 'Erro ao gravar $ref no servidor: $e');
        }
      }
      return false;
    }
    return true;
  }

  /// Resolve todas as refs do prep antes de «Continuar para o directo».
  static Future<bool> resolveRefsForPrep({
    required BuildContext context,
    required String sellerId,
    required List<String> refCodes,
    Map<String, LiveRefChipDetail>? refDetails,
  }) async {
    if (refCodes.isEmpty) return true;

    final sid = sellerId.trim();
    if (sid.isEmpty) return false;

    final details = refDetails ?? await LivePrepRefDetails.readAll();
    final draftLiveId = await LiveCatalogPrepService.ensureDraftLive(sellerId: sid);
    if (draftLiveId == null || draftLiveId.isEmpty) {
      if (context.mounted) {
        _snack(
          context,
          'Não foi possível preparar o rascunho do directo.',
        );
      }
      return false;
    }

    for (final ref in refCodes) {
      final key = LivePrepRefDetails.normalizeRefKey(ref);
      final detail = details[key] ?? const LiveRefChipDetail();
      final ok = await resolveRef(
        context: context,
        sellerId: sid,
        refCode: ref,
        detail: detail,
        draftLiveId: draftLiveId,
      );
      if (!ok) return false;
    }
    return true;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
