import 'package:flutter/material.dart';

/// Paleta Fleaber — referência única para tema Material e [FlutterFlowTheme].
abstract final class FleaberColors {
  /// Marca principal (botões, tabs, ícones de acção).
  static const Color teal = Color(0xFF007782);

  /// ~8% mais claro que [teal] — cursor, focus, pressed, retry.
  static const Color tealHighlight = Color(0xFF14828C);

  static const Color tealDark = Color(0xFF005A66);
  /// Fundo de páginas (scaffold) — único tint Fleaber.
  static const Color bgTint = Color(0xFFF5FBFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF14181B);
  static const Color muted = Color(0xFF57636C);
  static const Color alternate = Color(0xFFE0E3E7);

  /// Contorno de inputs em repouso (pesquisa Home, etc.) — baixo contraste.
  static const Color inputBorderIdle = Color(0xFFE8ECEE);
  static const Color success = Color(0xFF249689);
  static const Color warning = Color(0xFFF9CF58);

  /// LIVE, erros de formulário, badges não lidos, acções destrutivas no chat.
  static const Color danger = Color(0xFFE53935);

  /// [ColorScheme.error] / [FlutterFlowTheme.error] — mesmo tom que [danger].
  static const Color error = danger;

  static const Color accent1 = Color(0x4C007782);
  static const Color accent2 = Color(0x4D14828C);
  static const Color accent3 = Color(0x4D005A66);
  static const Color accent4 = Color(0xCCFFFFFF);

  static ColorScheme get lightColorScheme => ColorScheme.light(
        primary: teal,
        onPrimary: surface,
        secondary: tealHighlight,
        onSecondary: text,
        tertiary: tealDark,
        onTertiary: surface,
        error: danger,
        onError: surface,
        surface: surface,
        onSurface: text,
      );
}
