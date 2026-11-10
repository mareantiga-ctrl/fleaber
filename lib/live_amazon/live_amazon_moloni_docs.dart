import '/backend/supabase/supabase.dart';

/// Simulação multiempresa de fatura / NC (ZIP 183) — sem emissão real.
class LiveAmazonMoloniDocs {
  LiveAmazonMoloniDocs._();
  static final instance = LiveAmazonMoloniDocs._();

  Future<Map<String, dynamic>> simulateInvoice({
    required String companyKey,
    required String idempotencyKey,
    String? orderId,
    String? paymentId,
    required List<Map<String, dynamic>> lines,
    double shippingEur = 0,
    double protectionFeeEur = 0,
    String? buyerUserId,
  }) {
    return _rpc(
      companyKey: companyKey,
      docType: 'invoice',
      idempotencyKey: idempotencyKey,
      orderId: orderId,
      paymentId: paymentId,
      lines: lines,
      shippingEur: shippingEur,
      protectionFeeEur: protectionFeeEur,
      buyerUserId: buyerUserId,
    );
  }

  Future<Map<String, dynamic>> simulateCreditNote({
    required String companyKey,
    required String idempotencyKey,
    required String relatedInvoiceJobId,
    String? orderId,
    required List<Map<String, dynamic>> lines,
    bool partial = false,
    double shippingEur = 0,
  }) {
    return _rpc(
      companyKey: companyKey,
      docType: partial ? 'credit_note_partial' : 'credit_note',
      idempotencyKey: idempotencyKey,
      orderId: orderId,
      lines: lines,
      shippingEur: shippingEur,
      relatedInvoiceJobId: relatedInvoiceJobId,
    );
  }

  Future<Map<String, dynamic>> _rpc({
    required String companyKey,
    required String docType,
    required String idempotencyKey,
    String? orderId,
    String? paymentId,
    required List<Map<String, dynamic>> lines,
    double shippingEur = 0,
    double protectionFeeEur = 0,
    String? relatedInvoiceJobId,
    String? buyerUserId,
  }) async {
    final res = await SupaFlow.client.rpc(
      'batata_moloni_simulate_document',
      params: {
        'p_company_key': companyKey,
        'p_doc_type': docType,
        'p_idempotency_key': idempotencyKey,
        if (orderId != null) 'p_order_id': orderId,
        if (paymentId != null) 'p_payment_id': paymentId,
        'p_lines': lines,
        'p_shipping_eur': shippingEur,
        'p_protection_fee_eur': protectionFeeEur,
        if (relatedInvoiceJobId != null)
          'p_related_invoice_job_id': relatedInvoiceJobId,
        if (buyerUserId != null) 'p_buyer_user_id': buyerUserId,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'ok': false, 'raw': res};
  }
}
