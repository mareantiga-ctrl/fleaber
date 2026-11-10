import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

import 'fleahub_site_chrome.dart';

/// Separador discreto entre o estágio Live e a vitrine Hub (H03 light).
class HubLiveScrollDivider extends StatelessWidget {
  const HubLiveScrollDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(color: Color(0xFFD5DDE3), height: 1, thickness: 1),
          const SizedBox(height: 12),
          Text(
            'Mais desta loja',
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeCaption,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Marketplace e opiniões — mesmos artigos e reservas da Fleaber.',
            style: GoogleFonts.inter(
              color: FleaberColors.muted,
              fontSize: FleaHubSiteLayout.typeSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
