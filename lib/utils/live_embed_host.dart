import 'package:flutter/material.dart';

/// Host neutro — liga camada embed (ex. FleaHub) ao saco real do live player.
abstract final class LiveEmbedHost {
  static Future<void> Function()? _openBag;
  static String? _focusReservationRequestId;

  static void registerOpenBag(Future<void> Function() openBag) {
    _openBag = openBag;
  }

  static void unregisterOpenBag(Future<void> Function() openBag) {
    if (identical(_openBag, openBag)) {
      _openBag = null;
    }
  }

  static bool get hasOpenBag => _openBag != null;

  /// Consumido pelo player ao abrir o saco (scroll/highlight Hub).
  static String? takeFocusReservationRequestId() {
    final id = _focusReservationRequestId;
    _focusReservationRequestId = null;
    return id;
  }

  static Future<void> openBag(
    BuildContext context, {
    String? focusReservationRequestId,
  }) async {
    final open = _openBag;
    if (open == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abre o saco pelo ícone na barra lateral da live.'),
          ),
        );
      }
      return;
    }
    _focusReservationRequestId = focusReservationRequestId;
    try {
      await open();
    } finally {
      _focusReservationRequestId = null;
    }
  }
}
