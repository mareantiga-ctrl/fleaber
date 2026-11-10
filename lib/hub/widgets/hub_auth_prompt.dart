import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/widgets/fleaber_primary_button.dart';

import '../theme/hub_theme.dart';

/// Modal contextual FleaHub para acções protegidas (B20).
abstract final class HubAuthPrompt {
  static const bodyCopy =
      'Entra na tua conta Fleaber para continuares no FleaHub.';

  /// Título do modal — genérico ou específico (ex. gorjeta).
  static String resolveTitle({
    String? intentLabel,
    String? titleOverride,
  }) {
    if (titleOverride != null && titleOverride.trim().isNotEmpty) {
      return titleOverride.trim();
    }
    final intent = intentLabel?.trim().toLowerCase() ?? '';
    if (intent == 'enviar uma gorjeta') {
      return 'Inicia sessão para enviar uma gorjeta';
    }
    return 'Inicia sessão para continuar';
  }

  /// `true` = Entrar; `false` = dismiss; `null` = dismiss externo.
  static Future<bool?> show(
    BuildContext context, {
    String? intentLabel,
    String? titleOverride,
    String dismissLabel = 'Agora não',
  }) {
    final title = resolveTitle(
      intentLabel: intentLabel,
      titleOverride: titleOverride,
    );

    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            decoration: BoxDecoration(
              color: HubTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: HubTheme.teal.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: HubTheme.teal.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: HubTheme.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              bodyCopy,
                              style: HubTheme.body.copyWith(
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FleaberPrimaryButton(
                    label: 'Entrar',
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      dismissLabel,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
