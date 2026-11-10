import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

/// Hierarquia tipográfica Fleaber — título vs metadata.
abstract final class FleaberTypography {
  static const double metaSize = 12.5;
  static const double titleSm = 14.5;
  static const double titleMd = 15.5;
  static const double titleLg = 16.5;

  /// Título em cards (marketplace, listas).
  static TextStyle cardTitle({Color? color}) => GoogleFonts.inter(
        fontSize: titleSm,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color ?? const Color(0xFF101518),
      );

  /// Estado, subtítulos, contadores — nunca competir com o título.
  static TextStyle cardMeta({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: metaSize,
        fontWeight: fontWeight,
        height: 1.2,
        color: color ?? FleaberColors.muted,
      );

  /// Título de linha (ex. encomendas).
  static TextStyle listTitle({Color? color}) => GoogleFonts.inter(
        fontSize: titleLg,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: color ?? const Color(0xFF101518),
      );

  /// Estado de encomenda — legível no painel H11.
  static TextStyle orderStatus(Color color) => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: color,
      );
}
