import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/amazon_importer/amazon_importer_camera_scan_page.dart';
import '/live_amazon/live_amazon_lookup_service.dart';
import '/live_amazon/live_amazon_models.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

/// Fluxo leitura → lookup local → overlay → montra (ZIP 183).
class LiveAmazonScanSheet {
  LiveAmazonScanSheet._();

  /// Devolve o artigo escolhido (ou null). O caller mostra o overlay no directo.
  static Future<LiveAmazonPresentItem?> open(BuildContext context) async {
    return showModalBottomSheet<LiveAmazonPresentItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _SheetBody(),
    );
  }
}

class _SheetBody extends StatefulWidget {
  const _SheetBody();

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  final _manual = TextEditingController();
  bool _busy = false;
  String? _status;
  LiveAmazonLookupResult? _result;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _runLookup(String code) async {
    setState(() {
      _busy = true;
      _status = 'A procurar no catálogo…';
      _result = null;
    });
    try {
      final res = await LiveAmazonLookupService.instance.lookup(code);
      if (!mounted) return;
      setState(() {
        _result = res;
        _status = res.found
            ? '${res.hits.length} resultado(s)'
            : 'Artigo não encontrado no catálogo preparado.';
      });
      if (res.hits.length == 1) {
        await _present(res.hits.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AmazonImporterCameraScanPage()),
    );
    if (code == null || code.trim().isEmpty) return;
    _manual.text = code.trim();
    await _runLookup(code.trim());
  }

  Future<void> _present(LiveAmazonPresentItem item) async {
    if (!mounted) return;
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final hits = _result?.hits ?? const <LiveAmazonPresentItem>[];
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ler artigo Amazon (catálogo local)',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'EAN, ASIN, LPN ou FLB. Sem nova pesquisa na Amazon.',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FleaberPrimaryButton(
            width: double.infinity,
            label: _busy ? 'A ler…' : 'Abrir câmara / leitor',
            onPressed: _busy ? null : _scanCamera,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _manual,
            style: GoogleFonts.inter(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Ou escrever código',
              labelStyle: GoogleFonts.inter(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1A2329),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (v) => _runLookup(v),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _runLookup(_manual.text.trim()),
            style: OutlinedButton.styleFrom(
              foregroundColor: FleaberColors.teal,
              side: const BorderSide(color: FleaberColors.teal),
            ),
            child: const Text('Procurar'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (hits.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: ListView.separated(
                itemCount: hits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) {
                  final h = hits[i];
                  return ListTile(
                    tileColor: const Color(0xFF1A2329),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      h.titlePt,
                      maxLines: 2,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    subtitle: Text(
                      '${h.refLabel} · ${h.fleaberPriceEur.toStringAsFixed(2)} € · '
                      'stock ${h.availableQty}',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () => _present(h),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
