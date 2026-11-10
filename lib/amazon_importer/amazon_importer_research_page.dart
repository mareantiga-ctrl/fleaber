import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_service.dart';

/// Pesquisa em lote ES→IT→DE→FR com throttle, progresso, pausa e retoma.
class AmazonImporterResearchPage extends StatefulWidget {
  const AmazonImporterResearchPage({super.key, this.lotId});

  final String? lotId;

  static const routeName = 'AmazonImporterResearch';
  static const routePath = '/amazonImporter/research';

  @override
  State<AmazonImporterResearchPage> createState() =>
      _AmazonImporterResearchPageState();
}

class _AmazonImporterResearchPageState
    extends State<AmazonImporterResearchPage> {
  bool _loading = true;
  bool _running = false;
  bool _pauseRequested = false;
  String? _runId;
  List<Map<String, dynamic>> _products = [];
  int _cursor = 0;
  int _throttleMs = 2500;
  String _status = 'Pronto.';
  double _progress = 0;
  String? _error;
  late final TextEditingController _throttleCtrl;

  @override
  void initState() {
    super.initState();
    _throttleCtrl = TextEditingController(text: '$_throttleMs');
    _bootstrap();
  }

  @override
  void dispose() {
    _throttleCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products =
          await AmazonImporterService.instance.listProductsForResearch(
        lotId: widget.lotId,
      );
      final last = await AmazonImporterService.instance.latestResearchRun();
      if (!mounted) return;
      setState(() {
        _products = products;
        if (last != null &&
            (last['status'] == 'paused' || last['status'] == 'blocked')) {
          _runId = last['id']?.toString();
          _cursor = (last['cursor_index'] as num?)?.toInt() ?? 0;
          _throttleMs = (last['throttle_ms'] as num?)?.toInt() ?? 2500;
          _status =
              'Última corrida: ${last['status']} · cursor $_cursor / ${last['asin_count']}';
        } else {
          _status = '${products.length} ASIN por pesquisar.';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _start({bool resume = false}) async {
    if (_products.isEmpty) return;
    setState(() {
      _running = true;
      _pauseRequested = false;
      _error = null;
    });
    try {
      String runId = _runId ?? '';
      var start = resume ? _cursor : 0;
      if (!resume || runId.isEmpty) {
        final run = await AmazonImporterService.instance.createResearchRun(
          lotId: widget.lotId,
          asinCount: _products.length,
          throttleMs: _throttleMs,
        );
        runId = run['id'].toString();
        start = 0;
        _runId = runId;
      } else {
        await AmazonImporterService.instance.updateResearchRun(runId, {
          'status': 'running',
          'pause_requested': false,
        });
      }
      final result = await AmazonImporterService.instance.runBatchResearch(
        runId: runId,
        products: _products,
        startIndex: start,
        throttleMs: _throttleMs,
        shouldPause: () => _pauseRequested,
        onProgress: (i, total, asin, msg) {
          if (!mounted) return;
          setState(() {
            _cursor = i;
            _progress = total == 0 ? 0 : i / total;
            _status = '$msg $i / $total · $asin';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _cursor = (result['cursor_index'] as num?)?.toInt() ?? _cursor;
        final st = result['status']?.toString() ?? '';
        if (st == 'blocked') {
          _status =
              'Bloqueio Amazon em ${result['asin']}. Sem contornar. '
              'OK ${result['ok']} · erros ${result['errors']}. Aguarda instruções.';
          _error = 'blocked';
        } else if (st == 'paused') {
          _status =
              'Pausado em $_cursor / ${_products.length}. Podes retomar.';
        } else {
          _status =
              'Concluído. Com preço ${result['ok']} · sem preço/erro ${result['errors']} · '
              'bloqueios ${result['blocked']}.';
          _progress = 1;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString();
        _status = 'Falha: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Pesquisa Amazon (lote)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF007782)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Text(
                  'Ordem: ES → IT → DE → FR. Throttle entre ASIN. '
                  'Cache em amazon_market_offers. Para em CAPTCHA.',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    color: FleaberColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                Text(_status, style: GoogleFonts.inter(fontSize: 14)),
                if (_error == 'blocked') ...[
                  const SizedBox(height: 8),
                  Text(
                    'Resultado bloqueado — não contornámos. Diz «feito» com instruções.',
                    style: GoogleFonts.inter(
                      color: FleaberColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress,
                  color: const Color(0xFF007782),
                  backgroundColor: FleaberColors.alternate,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _throttleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Throttle entre ASIN (ms)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_running,
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n >= 800) _throttleMs = n;
                  },
                ),
                const SizedBox(height: 16),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: _running
                      ? 'A correr…'
                      : (_cursor > 0 && _cursor < _products.length
                          ? 'Retomar pesquisa'
                          : 'Iniciar pesquisa em lote'),
                  onPressed: _running
                      ? null
                      : () => _start(resume: _cursor > 0 && _cursor < _products.length),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: !_running
                      ? null
                      : () {
                          setState(() {
                            _pauseRequested = true;
                            _status = 'A pausar após o ASIN actual…';
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFF007782),
                    side: const BorderSide(color: Color(0xFF007782)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Pausar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_products.length} produtos na fila · cursor $_cursor',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: FleaberColors.muted,
                  ),
                ),
              ],
            ),
    );
  }
}
