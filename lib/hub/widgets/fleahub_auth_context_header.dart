import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/fleaber_colors.dart';

/// Cabeçalho partilhado login/registo quando o destino pós-auth é FleaHub.
class FleahubAuthContextHeader extends StatelessWidget {
  const FleahubAuthContextHeader({
    super.key,
    required this.fleaHubContext,
    required this.defaultSubtitle,
    this.logoSize = 110,
    this.logoFontSize = 48,
    this.logoBorderWidth = 3,
    this.titleFontSize = 32,
    this.subtitlePaddingBottom = 40,
    /// Login split desktop: logo mais compacto; defaults do registo intactos.
    this.compact = false,
    /// Quando o painel de marca já mostra o texto FleaHub longo.
    this.suppressFleaHubBodyCopy = false,
  });

  final bool fleaHubContext;
  final String defaultSubtitle;
  final double logoSize;
  final double logoFontSize;
  final double logoBorderWidth;
  final double titleFontSize;
  final double subtitlePaddingBottom;
  final bool compact;
  final bool suppressFleaHubBodyCopy;

  static const _teal = Color(0xFF007782);
  static const _muted = Color(0xFF888888);

  @override
  Widget build(BuildContext context) {
    final size = compact ? 72.0 : logoSize;
    final fSize = compact ? 32.0 : logoFontSize;
    final tSize = compact ? 26.0 : titleFontSize;
    final subPad = compact ? 20.0 : subtitlePaddingBottom;
    final borderW = compact ? 2.0 : logoBorderWidth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: FleaberColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: _teal,
              width: borderW,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'F',
            style: FlutterFlowTheme.of(context).headlineLarge.override(
                  font: GoogleFonts.readexPro(
                    fontWeight: FontWeight.bold,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                  ),
                  color: _teal,
                  fontSize: fSize,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.bold,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, compact ? 12 : 20, 0, 4),
          child: Text(
            'Fleaber',
            style: FlutterFlowTheme.of(context).headlineLarge.override(
                  font: GoogleFonts.readexPro(
                    fontWeight: FontWeight.bold,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                  ),
                  color: _teal,
                  fontSize: tSize,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.bold,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                ),
          ),
        ),
        if (fleaHubContext) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 0, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x14007882),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x59007882)),
              ),
              child: Text(
                'Acesso ao FleaHub',
                style: GoogleFonts.inter(
                  color: _teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, subPad),
            child: Text(
              suppressFleaHubBodyCopy
                  ? defaultSubtitle
                  : 'Entra para continuares para o FleaHub.\n\n'
                      'Poderás acompanhar reservas, compras, gravados e marketplace.',
              textAlign: TextAlign.center,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.normal,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    color: _muted,
                    fontSize: compact ? 15 : 16,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.normal,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    lineHeight: 1.5,
                  ),
            ),
          ),
        ] else
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(0, 0, 0, subPad),
            child: Text(
              defaultSubtitle,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.normal,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    color: _muted,
                    fontSize: compact ? 15 : 16,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.normal,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    lineHeight: 1.5,
                  ),
            ),
          ),
      ],
    );
  }
}
