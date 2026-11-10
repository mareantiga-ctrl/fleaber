import 'package:flutter/material.dart';

/// Raios Fleaber — 3 valores + pill. Usar em vez de números soltos.
abstract final class FleaberRadius {
  /// Chips, badges, bolhas pequenas.
  static const double sm = 8;

  /// Cards marketplace, inputs, botões principais.
  static const double md = 16;

  /// Media, live cards, sheets «Criar».
  static const double lg = 20;

  /// Handle / pill circular.
  static const double pill = 999;

  static BorderRadius circularSm = BorderRadius.circular(sm);
  static BorderRadius circularMd = BorderRadius.circular(md);
  static BorderRadius circularLg = BorderRadius.circular(lg);
  static BorderRadius circularPill = BorderRadius.circular(pill);
}
