import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import 'legal_document_page_widget.dart';
import 'legal_texts.dart';

/// Índice «Informação legal» — apenas os cinco documentos legais.
/// Como funciona / FAQ / Sobre vivem na sidebar «Ajuda e informação».
///
/// Embebido no H11 (`embedded: true`): o painel já tem [SingleChildScrollView].
/// Usar [Column] (não [ListView]) — ListView com altura ilimitada colapsa a 0
/// (regressão 119.4: página «Informação legal» vazia).
class LegalHubPageWidget extends StatelessWidget {
  const LegalHubPageWidget({
    super.key,
    this.embedded = false,
    this.onOpenDocument,
  });

  final bool embedded;

  /// Quando definido (shell H11), abre o documento no painel em vez de navegar.
  final ValueChanged<String>? onOpenDocument;

  static String routeName = 'LegalHub';
  static String routePath = '/legalHub';

  @override
  Widget build(BuildContext context) {
    const bg = FleaberColors.bgTint;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Text(
          LegalTexts.updatedLabel,
          style: GoogleFonts.inter(
            color: const Color(0xFF57636C),
            fontSize: 13,
          ),
        ),
      ),
      _sectionLabel('Documentos legais'),
      _tile(
        context,
        'Política de Privacidade',
        () => _open(context, 'privacy'),
      ),
      _tile(
        context,
        'Termos e Condições',
        () => _open(context, 'terms'),
      ),
      _tile(
        context,
        'Reembolsos e Disputas',
        () => _open(context, 'refunds'),
      ),
      _tile(
        context,
        'Política de Cookies',
        () => _open(context, 'cookies'),
      ),
      _tile(
        context,
        'Eliminação de conta e dados',
        () => _open(context, 'data-deletion'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          'Página pública (sem login, útil para Meta/Facebook): '
          '${LegalTexts.publicDataDeletionUrl}\n'
          'A eliminação autenticada continua em Definições de conta.',
          style: GoogleFonts.inter(
            color: const Color(0xFF57636C),
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];

    final body = SelectionArea(
      child: embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: children,
            ),
    );

    if (embedded) {
      return ColoredBox(
        color: bg,
        child: Align(alignment: Alignment.topLeft, child: body),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
        title: Text(
          'Informação legal',
          style: GoogleFonts.inter(
            color: const Color(0xFF101518),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          color: const Color(0xFF57636C),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  void _open(BuildContext context, String kind) {
    if (onOpenDocument != null) {
      onOpenDocument!(kind);
      return;
    }
    context.pushNamed(
      LegalDocumentPageWidget.routeName,
      queryParameters: {'kind': kind},
    );
  }

  Widget _tile(BuildContext context, String label, VoidCallback onTap) {
    return ListTile(
      title: Text(
        label,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          color: const Color(0xFF101518),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF57636C),
      ),
      onTap: onTap,
    );
  }
}
