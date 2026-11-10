import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_catalog_page.dart';
import 'amazon_importer_import_page.dart';
import 'amazon_importer_research_page.dart';
import 'amazon_importer_review_page.dart';
import 'amazon_importer_scan_page.dart';
import 'amazon_importer_service.dart';

/// Entrada do Importador Amazon (só admin).
class AmazonImporterHubPage extends StatefulWidget {
  const AmazonImporterHubPage({super.key});

  static const routeName = 'AmazonImporterHub';
  static const routePath = '/amazonImporter';

  @override
  State<AmazonImporterHubPage> createState() => _AmazonImporterHubPageState();
}

class _AmazonImporterHubPageState extends State<AmazonImporterHubPage> {
  bool _loading = true;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await AmazonImporterService.instance.isAuthorized();
      if (!mounted) return;
      setState(() {
        _allowed = ok;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Importador Amazon',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007782)))
          : !_allowed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ??
                          'Esta área é exclusiva da administração Fleaber.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 15),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    Text(
                      'Módulo privado — manifesto → pesquisa → revisão → '
                      'simulação Moloni / Fleaber (sem publicação automática).',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.4,
                        color: FleaberColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preparação para ~584 ASIN / 625 unidades: importação com '
                      'pausa/retoma, aprovação em massa e sync só com confirmação. '
                      'CAPTCHA não é contornado.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        color: FleaberColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Importar manifesto (CSV)',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AmazonImporterImportPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    FleaberPrimaryButton(
                      width: double.infinity,
                      label: 'Revisão e aprovação',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AmazonImporterReviewPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _HubOutline(
                      label: 'Catálogo privado',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AmazonImporterCatalogPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _HubOutline(
                      label: 'Leitor de códigos',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AmazonImporterScanPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _HubOutline(
                      label: 'Pesquisa Amazon em lote',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AmazonImporterResearchPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
    );
  }
}

class _HubOutline extends StatelessWidget {
  const _HubOutline({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: const Color(0xFF007782),
        side: const BorderSide(color: Color(0xFF007782)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      ),
    );
  }
}
