import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_models.dart';
import 'amazon_importer_service.dart';
import 'amazon_manifest_parser.dart';

class AmazonImporterImportPage extends StatefulWidget {
  const AmazonImporterImportPage({super.key});

  static const routeName = 'AmazonImporterImport';
  static const routePath = '/amazonImporter/import';

  @override
  State<AmazonImporterImportPage> createState() =>
      _AmazonImporterImportPageState();
}

class _AmazonImporterImportPageState extends State<AmazonImporterImportPage> {
  String? _filename;
  String? _csvText;
  AmazonManifestPreview? _preview;
  bool _busy = false;
  String? _status;
  double _progress = 0;
  String? _activeLotId;
  List<Map<String, dynamic>> _lots = const [];

  @override
  void initState() {
    super.initState();
    _loadLots();
  }

  Future<void> _loadLots() async {
    try {
      final lots = await AmazonImporterService.instance.listLots(limit: 12);
      if (!mounted) return;
      setState(() => _lots = lots);
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final name = f.name;
    if (name.toLowerCase().endsWith('.xlsx') ||
        name.toLowerCase().endsWith('.xls')) {
      setState(() {
        _filename = name;
        _csvText = null;
        _preview = null;
        _status =
            'Excel detectado: converte para CSV (UTF-8) nesta fase, ou cola o conteúdo CSV. '
            'Parser XLSX completo fica na fase seguinte.';
      });
      return;
    }
    String? text;
    if (f.bytes != null) {
      text = utf8.decode(f.bytes!, allowMalformed: true);
    } else if (!kIsWeb && f.path != null) {
      try {
        text = await File(f.path!).readAsString();
      } catch (_) {
        setState(() {
          _status = 'Não foi possível ler o ficheiro. Tenta de novo.';
        });
        return;
      }
    }
    if (text == null || text.isEmpty) {
      setState(() => _status = 'Ficheiro vazio.');
      return;
    }
    final preview = AmazonManifestParser.preview(text);
    setState(() {
      _filename = name;
      _csvText = text;
      _preview = preview;
      _status = preview.isValid
          ? 'Pronto a importar: ${preview.totalRows} linhas, '
              '${preview.distinctAsin} ASIN.'
          : _previewInvalidReason(preview);
    });
  }

  String _previewInvalidReason(AmazonManifestPreview preview) {
    final parts = <String>[];
    if (preview.missingRequired.isNotEmpty) {
      parts.add('faltam colunas ${preview.missingRequired.join(', ')}');
    }
    if (preview.rowsMissingLpn > 0) {
      parts.add('${preview.rowsMissingLpn} linha(s) sem LPN');
    }
    if (preview.rowsMissingAsin > 0) {
      parts.add('${preview.rowsMissingAsin} linha(s) sem ASIN');
    }
    if (preview.duplicateLpnCount > 0) {
      parts.add('${preview.duplicateLpnCount} LPN duplicado(s) no ficheiro');
    }
    if (parts.isEmpty) return 'Validação falhou.';
    return 'Validação: ${parts.join('; ')}.';
  }

  Future<void> _import({String? resumeLotId}) async {
    final text = _csvText;
    final name = _filename;
    final preview = _preview;
    if (resumeLotId == null &&
        (text == null || name == null || preview == null || !preview.isValid)) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = resumeLotId == null ? 'A criar lote…' : 'A retomar lote…';
    });
    try {
      Map<String, dynamic> lot;
      String csv;
      if (resumeLotId != null) {
        final existing =
            await AmazonImporterService.instance.getLot(resumeLotId);
        if (existing == null) throw StateError('Lote em falta');
        lot = existing;
        csv = existing['source_csv_text']?.toString() ?? '';
        if (csv.isEmpty) {
          throw StateError('CSV do lote em falta — escolhe o ficheiro de novo.');
        }
      } else {
        lot = await AmazonImporterService.instance.createLot(
          filename: name!,
          csvText: text!,
        );
        csv = text;
      }
      final lotId = lot['id'].toString();
      _activeLotId = lotId;
      final rows = AmazonManifestParser.rowsAsMaps(csv);
      final result = await AmazonImporterService.instance.importManifestRows(
        lotId: lotId,
        rows: rows,
        onProgress: (done, total, msg) {
          if (!mounted) return;
          setState(() {
            _progress = total == 0 ? 1 : done / total;
            _status = 'A importar $done / $total${msg != null ? ' · $msg' : ''}';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _activeLotId = null;
        final paused = result['paused'] == true || result['status'] == 'paused';
        _status = paused
            ? 'Pausado: ${result['imported_units']} importadas · '
                'podes retomar este lote.'
            : 'Concluído: ${result['imported_units']} importadas, '
                '${result['duplicate_units']} duplicadas (LPN), '
                '${result['error_count']} erros.';
        _progress = paused ? _progress : 1;
      });
      await _loadLots();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _activeLotId = null;
        _status = 'Falha: $e';
      });
    }
  }

  Future<void> _pause() async {
    final id = _activeLotId;
    if (id == null) return;
    await AmazonImporterService.instance.requestLotPause(id);
    setState(() => _status = 'A pedir pausa…');
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Importar manifesto',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'ASIN = produto · LPN = unidade física. Condições diferentes '
            'não são fundidas. O COST do manifesto não é o custo real do lote.',
            style: GoogleFonts.inter(fontSize: 13, color: FleaberColors.muted),
          ),
          const SizedBox(height: 16),
          FleaberPrimaryButton(
            width: double.infinity,
            label: _busy ? 'A processar…' : 'Escolher CSV / Excel',
            onPressed: _busy ? null : _pickFile,
          ),
          if (_filename != null) ...[
            const SizedBox(height: 12),
            Text(
              'Ficheiro: $_filename',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: GoogleFonts.inter(fontSize: 13)),
          ],
          if (_busy || _progress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _busy ? _progress : (_progress >= 1 ? 1 : null),
              color: const Color(0xFF007782),
            ),
          ],
          if (_busy && _activeLotId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pause,
              child: const Text('Pausar importação'),
            ),
          ],
          if (_lots.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Lotes recentes (retoma)',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ..._lots.take(6).map((l) {
              final st = l['status']?.toString() ?? '';
              final canResume = st == 'paused' || st == 'failed';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    l['source_filename']?.toString() ?? 'lote',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '$st · ${l['imported_units']}/${l['row_count']} · '
                    '${l['distinct_asin_count']} ASIN · '
                    'cursor ${l['cursor_row']}',
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  trailing: canResume && !_busy
                      ? TextButton(
                          onPressed: () => _import(
                            resumeLotId: l['id']?.toString(),
                          ),
                          child: const Text('Retomar'),
                        )
                      : null,
                ),
              );
            }),
          ],
          if (p != null) ...[
            const SizedBox(height: 20),
            Text(
              'Pré-visualização',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${p.headers.length} colunas · ${p.totalRows} linhas · '
              '${p.distinctAsin} ASIN',
              style: GoogleFonts.inter(fontSize: 12.5, color: FleaberColors.muted),
            ),
            if (!p.isValid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _previewInvalidReason(p),
                  style: GoogleFonts.inter(
                    color: const Color(0xFFB00020),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ...p.sampleRows.take(5).map((r) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    r['Item Desc'] ?? r['ASIN'] ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  subtitle: Text(
                    'ASIN ${r['ASIN']} · LPN ${r['LPN']} · '
                    '${r['CONDITION']} · COST ${r['COST']} ${r['CURRENCY CODE']}',
                    style: GoogleFonts.inter(fontSize: 11.5),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            FleaberPrimaryButton(
              width: double.infinity,
              label: _busy ? 'A importar…' : 'Importar lote',
              onPressed: (_busy || !p.isValid) ? null : () => _import(),
            ),
          ],
        ],
      ),
    );
  }
}
