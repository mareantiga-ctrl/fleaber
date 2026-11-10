import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/flutter_flow/nav/nav.dart';
import '/hub/pages/how_it_works_body.dart';
import '/utils/fleaber_colors.dart';
import 'legal_texts.dart';

/// Página legal/informativa reutilizável (perfil → termos, privacidade, FAQ, etc.).
class LegalDocumentPageWidget extends StatelessWidget {
  const LegalDocumentPageWidget({
    super.key,
    required this.title,
    required this.sections,
    this.updatedLabel = LegalTexts.updatedLabel,
    this.useFaqAccordion = false,
    this.embedded = false,
    this.useHowItWorksBody = false,
  });

  final String title;
  final List<LegalSection> sections;
  final String updatedLabel;
  final bool useFaqAccordion;
  final bool embedded;

  /// H15 canónico (4 passos) — mesmo corpo do FleaHub público.
  final bool useHowItWorksBody;

  static String routeName = 'LegalDocument';
  static String routePath = '/legalDocument';

  factory LegalDocumentPageWidget.fromKind(
    String? kind, {
    bool embedded = false,
  }) {
    switch (kind) {
      case 'terms':
        return LegalDocumentPageWidget(
          title: LegalTexts.termsTitle,
          sections: LegalTexts.terms,
          embedded: embedded,
        );
      case 'refunds':
        return LegalDocumentPageWidget(
          title: LegalTexts.refundsTitle,
          sections: LegalTexts.refunds,
          embedded: embedded,
        );
      case 'faq':
        return LegalDocumentPageWidget(
          title: LegalTexts.faqTitle,
          sections: LegalTexts.faq,
          useFaqAccordion: true,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
        );
      case 'how':
        return LegalDocumentPageWidget(
          title: LegalTexts.howItWorksTitle,
          sections: LegalTexts.howItWorks,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
          useHowItWorksBody: true,
        );
      case 'buy-safe':
      case 'buy_safe':
      case 'comprar':
        return LegalDocumentPageWidget(
          title: LegalTexts.buySafeTitle,
          sections: LegalTexts.buySafe,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
        );
      case 'sell':
      case 'vender':
        return LegalDocumentPageWidget(
          title: LegalTexts.sellTitle,
          sections: LegalTexts.sell,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
        );
      case 'contacts':
      case 'contactos':
        return LegalDocumentPageWidget(
          title: LegalTexts.contactsTitle,
          sections: LegalTexts.contactsInfo,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
        );
      case 'about':
        return LegalDocumentPageWidget(
          title: LegalTexts.aboutTitle,
          sections: LegalTexts.about,
          updatedLabel: LegalTexts.updatedLabelInfoOct2026,
          embedded: embedded,
        );
      case 'cookies':
        return LegalDocumentPageWidget(
          title: LegalTexts.cookiesTitle,
          sections: LegalTexts.cookies,
          embedded: embedded,
        );
      case 'data-deletion':
      case 'data_deletion':
        return LegalDocumentPageWidget(
          title: LegalTexts.dataDeletionTitle,
          sections: LegalTexts.dataDeletion,
          embedded: embedded,
        );
      case 'privacy':
      default:
        return LegalDocumentPageWidget(
          title: LegalTexts.privacyTitle,
          sections: LegalTexts.privacy,
          embedded: embedded,
        );
    }
  }

  /// Desktop H11 (≥768): tipografia e espaçamento mais confortáveis.
  /// Mobile / estreito: mantém proporções próximas da app nativa.
  bool _isWide(BuildContext context) =>
      embedded && MediaQuery.sizeOf(context).width >= 768;

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openKind(BuildContext context, String kind) {
    if (embedded) return;
    context.pushNamed(
      LegalDocumentPageWidget.routeName,
      queryParameters: {'kind': kind},
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = FleaberColors.bgTint;
    final wide = _isWide(context);
    final pad = EdgeInsets.fromLTRB(
      embedded ? (wide ? 4 : 8) : 20,
      wide ? 4 : 8,
      embedded ? (wide ? 4 : 8) : 20,
      32,
    );

    if (useHowItWorksBody) {
      final how = Padding(
        padding: pad,
        child: HowItWorksBody(
          embedded: embedded,
          compactPadding: true,
          onBuySafe: embedded ? null : () => _openKind(context, 'buy-safe'),
          onSell: embedded ? null : () => _openKind(context, 'sell'),
          onFaq: embedded ? null : () => _openKind(context, 'faq'),
        ),
      );
      if (embedded) {
        return ColoredBox(
          color: bg,
          child: Align(alignment: Alignment.topLeft, child: how),
        );
      }
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF101518)),
          title: Text(
            title,
            style: GoogleFonts.inter(
              color: const Color(0xFF101518),
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ),
        body: SelectionArea(
          child: ListView(children: [how]),
        ),
      );
    }

    final children = <Widget>[
      Text(
        updatedLabel,
        style: GoogleFonts.inter(
          color: const Color(0xFF57636C),
          fontSize: wide ? 14 : 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(height: wide ? 22 : 20),
      if (useFaqAccordion)
        ...sections.map((s) => _faqTile(s, wide: wide))
      else
        ...sections.expand((s) => _sectionBlocks(s, wide: wide)),
    ];

    // Embebido no H11: Column que cresce com os acordeões — o scroll é o do
    // painel (SingleChildScrollView no shell), sem barra interna na lista.
    final Widget content;
    if (embedded) {
      content = Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
    } else {
      content = ListView(padding: pad, children: children);
    }

    final selectable = SelectionArea(child: content);

    if (embedded) {
      return ColoredBox(
        color: bg,
        child: Align(alignment: Alignment.topLeft, child: selectable),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: const Color(0xFF101518),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: selectable,
    );
  }

  List<Widget> _sectionBlocks(LegalSection s, {required bool wide}) {
    final titleStyle = GoogleFonts.inter(
      color: const Color(0xFF007782),
      fontWeight: FontWeight.w800,
      fontSize: wide ? 19 : 17,
      height: 1.25,
    );
    final bodyStyle = GoogleFonts.inter(
      color: const Color(0xFF101518),
      fontSize: wide ? 16 : 15,
      height: wide ? 1.65 : 1.55,
      fontWeight: FontWeight.w400,
    );

    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title, style: titleStyle),
        SizedBox(height: wide ? 12 : 10),
        LegalLinkedText(text: s.body, style: bodyStyle),
        if (s.linkUrl != null && s.linkLabel != null) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _openExternal(s.linkUrl!),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: FleaberColors.teal,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      s.linkLabel!,
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: wide ? 15 : 14,
                        decoration: TextDecoration.underline,
                        decorationColor: FleaberColors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    if (!wide) {
      return [
        block,
        const SizedBox(height: 22),
      ];
    }

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EEF0)),
        ),
        child: block,
      ),
      const SizedBox(height: 14),
    ];
  }

  Widget _faqTile(LegalSection s, {required bool wide}) {
    // Body vazio = cabeçalho de tema (H18).
    if (s.body.trim().isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(4, wide ? 18 : 14, 4, wide ? 8 : 6),
        child: Text(
          s.title,
          style: GoogleFonts.inter(
            color: FleaberColors.teal,
            fontWeight: FontWeight.w800,
            fontSize: wide ? 15 : 14,
            letterSpacing: 0.2,
          ),
        ),
      );
    }
    final bodyStyle = GoogleFonts.inter(
      color: const Color(0xFF2B3438),
      fontSize: wide ? 15 : 14,
      height: wide ? 1.6 : 1.55,
    );
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: Card(
        margin: EdgeInsets.only(bottom: wide ? 12 : 10),
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE0E3E7)),
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(
            horizontal: wide ? 18 : 16,
            vertical: wide ? 6 : 4,
          ),
          childrenPadding: EdgeInsets.fromLTRB(
            wide ? 18 : 16,
            0,
            wide ? 18 : 16,
            wide ? 18 : 16,
          ),
          title: Text(
            s.title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: wide ? 16 : 15,
              height: 1.3,
              color: const Color(0xFF101518),
            ),
          ),
          iconColor: const Color(0xFF007782),
          collapsedIconColor: const Color(0xFF57636C),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: LegalLinkedText(text: s.body, style: bodyStyle),
            ),
            if (s.linkUrl != null && s.linkLabel != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _openExternal(s.linkUrl!),
                  style: TextButton.styleFrom(
                    foregroundColor: FleaberColors.teal,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    s.linkLabel!,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Corpo seleccionável com URLs/emails clicáveis (recognizers com dispose).
class LegalLinkedText extends StatefulWidget {
  const LegalLinkedText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<LegalLinkedText> createState() => _LegalLinkedTextState();
}

class _LegalLinkedTextState extends State<LegalLinkedText> {
  static final RegExp _linkPattern = RegExp(
    r'(https?://[^\s]+|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}|www\.[^\s]+)',
    caseSensitive: false,
  );

  List<TapGestureRecognizer> _recognizers = [];
  TextSpan? _span;

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant LegalLinkedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _rebuildSpans();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
  }

  String _normalizeHref(String raw) {
    final t = raw.replaceAll(RegExp(r'[.,;:)\]]+$'), '');
    if (t.contains('@') && !t.toLowerCase().startsWith('http')) {
      return 'mailto:$t';
    }
    if (t.toLowerCase().startsWith('www.')) {
      return 'https://$t';
    }
    return t;
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _rebuildSpans() {
    _disposeRecognizers();
    final style = widget.style;
    final text = widget.text;
    final spans = <TextSpan>[];
    var start = 0;
    for (final match in _linkPattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final raw = match.group(0)!;
      final href = _normalizeHref(raw);
      final display = raw.replaceAll(RegExp(r'[.,;:)\]]+$'), '');
      final trailing = raw.substring(display.length);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openExternal(href);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: display,
          style: style.copyWith(
            color: FleaberColors.teal,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: FleaberColors.teal,
          ),
          recognizer: recognizer,
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    _span = TextSpan(style: style, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(_span!);
  }
}
