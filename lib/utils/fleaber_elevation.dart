import 'package:flutter/material.dart';

/// Sombras Fleaber — usar via [FleaberElevation] ou `FlutterFlowTheme.of(context).shadow`.
abstract final class FleaberElevation {
  /// elevation-sm — chips, badges de produto (para baixo).
  static const BoxShadow sm = BoxShadow(
    blurRadius: 12,
    color: Color(0x1A000000),
    offset: Offset(0, 4),
  );

  /// elevation-sm — bottom navigation (sombra para cima).
  static const BoxShadow smNav = BoxShadow(
    blurRadius: 16,
    color: Color(0x1A000000),
    offset: Offset(0, -4),
  );

  /// elevation-md — cards de live, superfícies destacadas.
  static const BoxShadow md = BoxShadow(
    blurRadius: 14,
    color: Color(0x33000000),
    offset: Offset(0, 6),
  );

  /// elevation-md — FAB central (teal, Home «Criar»).
  static const BoxShadow mdFab = BoxShadow(
    blurRadius: 8,
    color: Color(0x40007782),
    offset: Offset(0, 2),
  );

  /// Chip/badge com cor de marca (variante sm).
  static BoxShadow smAccent(Color accent) => BoxShadow(
        color: accent.withValues(alpha: 0.35),
        blurRadius: 12,
        offset: const Offset(0, 4),
      );
}
