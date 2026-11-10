import 'dart:async';

import 'package:flutter/foundation.dart';

import '/utils/fleaber_logger.dart';

/// Logs densos do Pagar no saco (Hub web) → `app_logs` category `hub.bag.pay`
/// + consola do browser (`[hub.bag.pay] …`).
///
/// Não altera fluxo de pagamento — só diagnóstico.
abstract final class HubBagPayDiag {
  static const _cat = 'hub.bag.pay';

  static void log(String step, [Map<String, dynamic>? data]) {
    final payload = <String, dynamic>{
      'step': step,
      'k_is_web': kIsWeb,
      if (data != null) ...data,
    };
    unawaited(FleaberLogger.instance.event(_cat, payload));
    debugPrint('[$_cat] $step ${data ?? {}}');
    if (kIsWeb) {
      // ignore: avoid_print
      print('[$_cat] $step ${data ?? {}}');
    }
  }

  static void fail(String step, Object error, [Map<String, dynamic>? data]) {
    final payload = <String, dynamic>{
      'step': step,
      'k_is_web': kIsWeb,
      'error': error.toString(),
      if (data != null) ...data,
    };
    FleaberLogger.instance.error(_cat, error, null, payload);
    debugPrint('[$_cat] FAIL $step $error ${data ?? {}}');
    if (kIsWeb) {
      // ignore: avoid_print
      print('[$_cat] FAIL $step $error ${data ?? {}}');
    }
  }
}
