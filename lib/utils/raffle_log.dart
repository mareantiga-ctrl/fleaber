import 'package:flutter/foundation.dart';

/// Logs de diagnóstico da Rifa da Live — filtrar por `[RIFA]` no console / logcat.
abstract final class RaffleLog {
  static const _tag = '[RIFA]';

  static void d(String msg, [Map<String, Object?>? fields]) {
    final extra = fields == null || fields.isEmpty
        ? ''
        : ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('$_tag $msg$extra');
  }

  static void e(String msg, [Object? error, Map<String, Object?>? fields]) {
    final extra = fields == null || fields.isEmpty
        ? ''
        : ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('$_tag ERROR $msg$extra err=$error');
  }
}
