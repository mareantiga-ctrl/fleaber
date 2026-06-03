import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';



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

  });



  final String title;

  final List<LegalSection> sections;

  final String updatedLabel;

  final bool useFaqAccordion;



  static String routeName = 'LegalDocument';

  static String routePath = '/legalDocument';



  factory LegalDocumentPageWidget.fromKind(String? kind) {

    switch (kind) {

      case 'terms':

        return LegalDocumentPageWidget(

          title: LegalTexts.termsTitle,

          sections: LegalTexts.terms,

        );

      case 'refunds':

        return LegalDocumentPageWidget(

          title: LegalTexts.refundsTitle,

          sections: LegalTexts.refunds,

        );

      case 'faq':

        return LegalDocumentPageWidget(

          title: LegalTexts.faqTitle,

          sections: LegalTexts.faq,

          useFaqAccordion: true,

        );

      case 'how':

        return LegalDocumentPageWidget(

          title: LegalTexts.howItWorksTitle,

          sections: LegalTexts.howItWorks,

        );

      case 'about':

        return LegalDocumentPageWidget(

          title: LegalTexts.aboutTitle,

          sections: LegalTexts.about,

        );

      case 'privacy':

      default:

        return LegalDocumentPageWidget(

          title: LegalTexts.privacyTitle,

          sections: LegalTexts.privacy,

        );

    }

  }



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: FleaberColors.bgTint,

      appBar: AppBar(

        backgroundColor: FleaberColors.bgTint,

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

      body: ListView(

        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),

        children: [

          Text(

            updatedLabel,

            style: GoogleFonts.inter(

              color: const Color(0xFF57636C),

              fontSize: 13,

            ),

          ),

          const SizedBox(height: 20),

          if (useFaqAccordion)

            ...sections.map((s) => _faqTile(s))

          else

            ...sections.expand((s) => _sectionBlocks(s)),

        ],

      ),

    );

  }



  List<Widget> _sectionBlocks(LegalSection s) {

    return [

      Text(

        s.title,

        style: GoogleFonts.inter(

          color: const Color(0xFF007782),

          fontWeight: FontWeight.w800,

          fontSize: 16,

        ),

      ),

      const SizedBox(height: 8),

      Text(

        s.body,

        style: GoogleFonts.inter(

          color: const Color(0xFF101518),

          fontSize: 14,

          height: 1.55,

        ),

      ),

      const SizedBox(height: 24),

    ];

  }



  Widget _faqTile(LegalSection s) {

    return Theme(

      data: ThemeData(dividerColor: Colors.transparent),

      child: Card(

        margin: const EdgeInsets.only(bottom: 10),

        elevation: 0,

        color: Colors.white,

        shape: RoundedRectangleBorder(

          borderRadius: BorderRadius.circular(12),

          side: const BorderSide(color: Color(0xFFE0E3E7)),

        ),

        child: ExpansionTile(

          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

          title: Text(

            s.title,

            style: GoogleFonts.inter(

              fontWeight: FontWeight.w600,

              fontSize: 15,

              color: const Color(0xFF101518),

            ),

          ),

          iconColor: const Color(0xFF007782),

          collapsedIconColor: const Color(0xFF57636C),

          children: [

            Align(

              alignment: Alignment.centerLeft,

              child: Text(

                s.body,

                style: GoogleFonts.inter(

                  color: const Color(0xFF101518),

                  fontSize: 14,

                  height: 1.55,

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

}


