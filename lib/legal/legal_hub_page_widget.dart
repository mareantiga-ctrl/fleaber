import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';



import '/flutter_flow/flutter_flow_util.dart';

import '/utils/fleaber_colors.dart';

import 'legal_document_page_widget.dart';

import 'legal_texts.dart';



/// Menu Termos, Privacidade e informação no perfil.

class LegalHubPageWidget extends StatelessWidget {

  const LegalHubPageWidget({super.key});



  static String routeName = 'LegalHub';

  static String routePath = '/legalHub';



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: FleaberColors.bgTint,

      appBar: AppBar(

        backgroundColor: FleaberColors.bgTint,

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

      body: ListView(

        padding: const EdgeInsets.only(bottom: 24),

        children: [

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

          _sectionLabel('Informação'),

          _tile(context, 'Como funciona o Fleaber', () => _open(context, 'how')),

          _tile(context, 'Perguntas Frequentes', () => _open(context, 'faq')),

          _tile(context, 'Sobre a nossa plataforma', () => _open(context, 'about')),

          _sectionLabel('Documentos legais'),

          _tile(context, 'Política de Privacidade', () => _open(context, 'privacy')),

          _tile(context, 'Termos e Condições', () => _open(context, 'terms')),

          _tile(context, 'Reembolsos e Disputas', () => _open(context, 'refunds')),

        ],

      ),

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

      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF57636C)),

      onTap: onTap,

    );

  }

}


