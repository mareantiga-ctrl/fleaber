import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '/backend/supabase/supabase.dart';

/// Cliente Edge `dpd-expedition` — obter etiqueta (idempotente).
class DpdExpeditionService {
  DpdExpeditionService._();

  static Future<DpdLabelResult> obtainLabel({required String orderId}) async {
    try {
      final res = await SupaFlow.client.functions.invoke(
        'dpd-expedition',
        body: {
          'action': 'obtain_label',
          'order_id': orderId,
        },
      );
      return _fromMap(res.data);
    } on FunctionException catch (e) {
      return _fromMap(e.details, fallbackError: 'function_exception');
    } catch (_) {
      return const DpdLabelResult(
        ok: false,
        userMessage: 'Etiqueta temporariamente indisponível.',
        error: 'unknown',
      );
    }
  }

  static DpdLabelResult _fromMap(
    Object? data, {
    String? fallbackError,
  }) {
    if (data is! Map) {
      return DpdLabelResult(
        ok: false,
        userMessage: 'Etiqueta temporariamente indisponível.',
        error: fallbackError ?? 'invalid_response',
      );
    }
    final map = Map<String, dynamic>.from(data);
    final ok = map['ok'] == true;
    final err = map['error']?.toString();
    final createDisabled = err == 'create_disabled';
    final userMessage = () {
      final um = (map['user_message'] ?? '').toString().trim();
      if (um.isNotEmpty) return um;
      if (createDisabled) {
        return 'A criação de etiquetas DPD está temporariamente desligada.';
      }
      return ok ? 'Etiqueta pronta' : 'Etiqueta temporariamente indisponível.';
    }();
    return DpdLabelResult(
      ok: ok,
      userMessage: userMessage,
      error: err ?? fallbackError,
      trackingCode: map['dpd_tracking_code']?.toString(),
      labelUrl: map['dpd_label_url']?.toString(),
      expeditionId: map['dpd_expedition_id']?.toString(),
      idempotent: map['idempotent'] == true,
      createDisabled: createDisabled,
      retrySafe: map['retry_safe'] == true || !ok,
      createEnabled: map['create_enabled'] == true,
    );
  }
}

class DpdLabelResult {
  const DpdLabelResult({
    required this.ok,
    required this.userMessage,
    this.error,
    this.trackingCode,
    this.labelUrl,
    this.expeditionId,
    this.idempotent = false,
    this.createDisabled = false,
    this.retrySafe = true,
    this.createEnabled,
  });

  final bool ok;
  final String userMessage;
  final String? error;
  final String? trackingCode;
  final String? labelUrl;
  final String? expeditionId;
  final bool idempotent;
  final bool createDisabled;
  final bool retrySafe;
  final bool? createEnabled;
}
