import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';

/// Tokens visuais **só** para H10 Mensagens (lista + chat Hub web).
///
/// Não altera [HubTheme] (live / H03). Tema branco alinhado a H01–H09.
abstract final class HubMessagesTheme {
  static const Color bg = FleaberColors.bgTint;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF7FAFB);
  static const Color teal = FleaberColors.teal;
  static const Color accent = FleaberColors.teal;
  static const Color textPrimary = Color(0xFF101518);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color divider = Color(0xFFF1F4F8);
  static const Color border = Color(0xFFE0E3E7);
  static const Color borderSoft = Color(0xFFE8ECEE);
  static const Color selectedBg = Color(0x1A007782); // ~10% teal
  static const Color unreadBg = Color(0xFFEFF9FA);
  static const Color hoverBg = Color(0xFFF7FAFB);
  static const Color bubbleSent = FleaberColors.teal;
  static const Color bubbleReceived = Color(0xFFFFFFFF);
  static const Color systemChipBg = Color(0xFFF2F4F7);
  static const Color systemChipText = Color(0xFF3F4A53);
  /// Confirmações / operações concluídas (turquesa suave).
  static const Color successBg = Color(0xFFE6F7F5);
  static const Color successBorder = Color(0xFF8EC9C5);
  static const Color successText = Color(0xFF0F5C63);
  /// Informação / acompanhamento (azul suave).
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoBorder = Color(0xFFB8CFE8);
  static const Color infoText = Color(0xFF1E4A7A);
  /// Avisos e prazos (amarelo suave).
  static const Color warningBg = Color(0xFFFFF8E6);
  static const Color warningBorder = Color(0xFFE6D49A);
  static const Color warningText = Color(0xFF6B4E00);
  /// Erros / recusas / atenção (vermelho suave).
  static const Color errorBg = Color(0xFFFDECEC);
  static const Color errorBorder = Color(0xFFF1B0B0);
  static const Color errorText = Color(0xFF8A1F1F);
  /// Acontecimentos informativos (cinzento neutro).
  static const Color neutralBg = Color(0xFFF2F4F7);
  static const Color neutralBorder = Color(0xFFDDE2E7);
  static const Color paymentBg = Color(0xFFEFF6FF);
  static const Color commerceBorder = Color(0xFFB8D5D8);

  static TextStyle get titleMd => GoogleFonts.inter(
        color: textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get body => GoogleFonts.inter(
        color: textSecondary,
        fontSize: 14,
        height: 1.4,
      );

  static TextStyle get label => GoogleFonts.inter(
        color: textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );

  static List<BoxShadow> get cardShadow => const [FleaberElevation.sm];
}
