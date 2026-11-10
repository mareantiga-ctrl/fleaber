import 'package:flutter/material.dart';

/// Snackbars com dedupe e fila limpa — evita spam ao clicar repetidamente.
abstract final class FleaberSnack {
  static String? _lastMsg;
  static DateTime? _lastAt;

  static ScaffoldMessengerState? _messenger(BuildContext context) {
    return ScaffoldMessenger.maybeOf(context) ??
        context.findRootAncestorStateOfType<ScaffoldMessengerState>();
  }

  static bool _shouldSkip(String message, Duration cooldown) {
    final msg = message.trim();
    if (msg.isEmpty) return true;
    final now = DateTime.now();
    if (_lastMsg == msg &&
        _lastAt != null &&
        now.difference(_lastAt!) < cooldown) {
      return true;
    }
    _lastMsg = msg;
    _lastAt = now;
    return false;
  }

  static void show(
    BuildContext context,
    String message, {
    Duration cooldown = const Duration(milliseconds: 2000),
    Duration duration = const Duration(seconds: 3),
  }) {
    if (_shouldSkip(message, cooldown)) return;
    final messenger = _messenger(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.trim()),
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  /// Mensagem visível dentro de modal bottom sheet (não fica atrás do popup).
  static void showAboveSheet(
    BuildContext hostContext,
    String message, {
    Duration cooldown = const Duration(milliseconds: 2000),
  }) {
    if (_shouldSkip(message, cooldown)) return;
    final messenger = _messenger(hostContext);
    if (messenger == null) return;
    final bottom = MediaQuery.viewPaddingOf(hostContext).bottom;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.trim()),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
