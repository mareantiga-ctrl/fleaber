import '/backend/supabase/supabase.dart';

import 'amazon_importer_service.dart';

/// Adaptadores Moloni / Fleaber — ZIP 166: só simulação com confirmação.
abstract final class AmazonExportAdapters {
  static const moloniBlockedReason =
      'Moloni auto-create (ZIP 176.1): LIVE activo no publish AMZ-*. '
      'Sequência FLB###### (após FLB000036), stock 0, Amzeu/Unidade. '
      'Sem compras/faturas; falha Moloni não afecta o anúncio Fleaber.';

  static const fleaberDraftNote =
      'Fleaber: rascunhos reais só após GO explícito. '
      'ZIP 166 regista simulação em amazon_export_links (sem is_draft real).';

  /// Mapa documentado para futura API Moloni.
  static Map<String, dynamic> moloniFieldMap(Map<String, dynamic> product) =>
      AmazonMoloniFieldMap.fromProduct(product);

  /// Após publicar anúncio Fleaber AMZ-*: enfileira sync Moloni (não bloqueia publish).
  static Future<Map<String, dynamic>> enqueueAfterFleaberPublish({
    required String fleaberProductId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_moloni_enqueue_fleaber_product',
        params: {'p_product_id': fleaberProductId},
      );
      return {
        'ok': true,
        'enqueue': res,
        'message':
            'Moloni sync enfileirado (ZIP 176). Falha Moloni não afecta o anúncio.',
      };
    } catch (e) {
      // Nunca reverter publicação Fleaber por erro Moloni.
      return {
        'ok': false,
        'fleaber_preserved': true,
        'error': e.toString(),
        'message':
            'Enqueue Moloni falhou — anúncio Fleaber mantém-se; retry possível.',
      };
    }
  }

  static Future<Map<String, dynamic>> enqueueMoloni({
    required String productId,
    bool confirmSimulation = false,
  }) async {
    if (confirmSimulation) {
      return AmazonImporterService.instance.simulateMoloni(
        productId: productId,
        confirm: true,
      );
    }
    await SupaFlow.client.from('amazon_export_links').insert({
      'product_id': productId,
      'target': 'moloni',
      'status': 'skipped',
      'last_error': moloniBlockedReason,
      'meta': {
        'phase': '176',
        'action': 'prepare_only',
        'simulated': false,
        'sequence': 'FLB######',
      },
    });
    return {
      'ok': true,
      'blocked': true,
      'message': moloniBlockedReason,
    };
  }

  static Future<Map<String, dynamic>> enqueueFleaberDraft({
    required String productId,
    bool confirmSimulation = false,
  }) async {
    if (confirmSimulation) {
      return AmazonImporterService.instance.simulateFleaberDraft(
        productId: productId,
        confirm: true,
      );
    }
    await SupaFlow.client.from('amazon_export_links').insert({
      'product_id': productId,
      'target': 'fleaber_draft',
      'status': 'pending',
      'meta': {'phase': '166', 'action': 'awaiting_go'},
    });
    return {
      'ok': true,
      'blocked': true,
      'message': fleaberDraftNote,
    };
  }
}
