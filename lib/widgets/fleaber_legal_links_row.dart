import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/legal/legal_document_page_widget.dart';
import '/legal/legal_texts.dart';

/// Links legais compactos (login / registo / Hub).
class FleaberLegalLinksRow extends StatelessWidget {
  const FleaberLegalLinksRow({
    super.key,
    this.compact = true,
    this.center = true,
    this.openExternalOnWeb = true,
  });

  final bool compact;
  final bool center;
  final bool openExternalOnWeb;

  Future<void> _open(BuildContext context, String kind) async {
    if (openExternalOnWeb && isWeb) {
      final url = switch (kind) {
        'terms' => LegalTexts.publicTermsUrl,
        'cookies' => LegalTexts.publicCookiesUrl,
        'data-deletion' => LegalTexts.publicDataDeletionUrl,
        _ => LegalTexts.publicPrivacyUrl,
      };
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (!context.mounted) return;
    context.pushNamed(
      LegalDocumentPageWidget.routeName,
      queryParameters: {'kind': kind},
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF007782),
      height: 1.3,
    );
    final sep = Text(
      ' · ',
      style: GoogleFonts.inter(
        fontSize: compact ? 12 : 13,
        color: const Color(0xFF57636C),
      ),
    );

    final row = Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () => _open(context, 'terms'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Termos', style: style),
        ),
        sep,
        TextButton(
          onPressed: () => _open(context, 'privacy'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Privacidade', style: style),
        ),
        sep,
        TextButton(
          onPressed: () => _open(context, 'cookies'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Cookies', style: style),
        ),
      ],
    );

    return Column(
      children: [
        if (!compact)
          Text(
            'Ao continuar, aceita os nossos',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF57636C),
            ),
          ),
        row,
      ],
    );
  }
}
