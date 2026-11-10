import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_camera_scan_page.dart';
import 'amazon_importer_product_page.dart';
import 'amazon_importer_service.dart';
import 'amazon_scan_models.dart';
import 'amazon_weight.dart';

/// Leitor privado EAN / LPN / ASIN (admin) — Hub teclado + Android câmara.
class AmazonImporterScanPage extends StatefulWidget {
  const AmazonImporterScanPage({super.key, this.initialCode});

  /// Código opcional (deep-link Hub `?code=` ou testes).
  final String? initialCode;

  static const routeName = 'AmazonImporterScan';
  static const routePath = '/amazonImporterScan';

  @override
  State<AmazonImporterScanPage> createState() => _AmazonImporterScanPageState();
}

class _AmazonImporterScanPageState extends State<AmazonImporterScanPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _loading = false;
  bool _cameraBusy = false;
  String? _error;
  String? _lastScanned;
  DateTime? _lastScanAt;
  List<AmazonScanHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _applyInitialCode(widget.initialCode);
    });
  }

  @override
  void didUpdateWidget(covariant AmazonImporterScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCode != oldWidget.initialCode) {
      _applyInitialCode(widget.initialCode);
    }
  }

  void _applyInitialCode(String? raw) {
    final seed = (raw ?? '').trim();
    if (seed.isEmpty) return;
    _lastScanned = null;
    _ctrl.text = seed;
    _lookup(seed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _isDuplicateScan(String code) {
    final now = DateTime.now();
    if (_lastScanned == code &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 3)) {
      return true;
    }
    _lastScanned = code;
    _lastScanAt = now;
    return false;
  }

  Future<void> _lookup([String? raw]) async {
    final code = (raw ?? _ctrl.text).trim();
    if (code.isEmpty) return;
    if (_isDuplicateScan(code) && raw != null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _hits = const [];
    });
    try {
      final hits = await AmazonImporterService.instance.lookupByCode(code);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
        if (hits.isEmpty) {
          _error = 'Código não encontrado: $code';
        }
      });
      _ctrl.clear();
      _focus.requestFocus();

      if (hits.isEmpty && code.toUpperCase().startsWith('LPN')) {
        await _offerAssociateUnknownLpn(code);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _offerAssociateUnknownLpn(String lpn) async {
    final asinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Associar LPN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LPN $lpn não está associado. Indica o ASIN da unidade correcta '
              '(confirmação obrigatória — sem associação automática).',
              style: GoogleFonts.inter(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: asinCtrl,
              decoration: const InputDecoration(
                labelText: 'ASIN',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Associar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final asin = asinCtrl.text.trim().toUpperCase();
    asinCtrl.dispose();
    if (asin.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar associação'),
        content: Text('Associar LPN $lpn ao ASIN $asin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, associar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final products = await AmazonImporterService.instance.lookupByCode(asin);
      if (products.isEmpty) {
        throw StateError('ASIN não encontrado no catálogo');
      }
      final p = products.first;
      await AmazonImporterService.instance.associateLpn(
        lpn: lpn,
        catalogProductId: p.catalogProductId,
        asin: p.asin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LPN $lpn associado a ${p.asin}')),
      );
      await _lookup(lpn);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No Hub usa leitor USB/Bluetooth (modo teclado) ou introdução manual.',
          ),
        ),
      );
      return;
    }
    setState(() => _cameraBusy = true);
    try {
      final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const AmazonImporterCameraScanPage(),
        ),
      );
      if (!mounted) return;
      if (code != null && code.trim().isNotEmpty) {
        _lastScanned = null;
        await _lookup(code.trim());
      }
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Leitor de códigos',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'Ler com câmara',
              onPressed: _cameraBusy ? null : _openCamera,
              icon: const Icon(Icons.qr_code_scanner),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            kIsWeb
                ? 'Lê com leitor USB/Bluetooth (modo teclado) ou escreve EAN, LPN ou ASIN e Enter.'
                : 'Câmara, leitor Bluetooth (modo teclado) ou introdução manual de EAN, LPN ou ASIN.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: FleaberColors.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Código (EAN / LPN / ASIN)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onSubmitted: _lookup,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
            ],
          ),
          const SizedBox(height: 12),
          FleaberPrimaryButton(
            width: double.infinity,
            label: _loading ? 'A procurar…' : 'Procurar',
            onPressed: _loading
                ? null
                : () {
                    _lastScanned = null;
                    _lookup();
                  },
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _cameraBusy ? null : _openCamera,
              icon: const Icon(Icons.photo_camera),
              label: Text(_cameraBusy ? 'A abrir câmara…' : 'Abrir câmara'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: const Color(0xFF007782),
                side: const BorderSide(color: Color(0xFF007782)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: GoogleFonts.inter(color: Colors.red.shade700)),
          ],
          if (_hits.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              '${_hits.length} unidades com este código — escolhe a correcta.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: FleaberColors.text,
              ),
            ),
          ],
          const SizedBox(height: 20),
          for (final h in _hits) ...[
            _HitCard(hit: h),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit});
  final AmazonScanHit hit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: hit.imageUrl == null || hit.imageUrl!.isEmpty
                        ? Container(color: const Color(0xFFE8EEF0))
                        : BatataCachedNetworkImage(
                            imageUrl: hit.imageUrl!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title ?? hit.asin,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          'ASIN ${hit.asin}',
                          if ((hit.ean ?? '').isNotEmpty) 'EAN ${hit.ean}',
                          if ((hit.lpn ?? '').isNotEmpty) 'LPN ${hit.lpn}',
                        ].join(' · '),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: FleaberColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (hit.saleEur != null)
                  'Preço ${hit.saleEur!.toStringAsFixed(2).replaceAll('.', ',')} €',
                'Peso orig. ${AmazonWeight.formatManifestLabel(hit.manifestKg)}',
                'Expedição ${AmazonWeight.formatShippingLabel(hit.shippingKg)}',
                if (hit.qty != null) 'Qtd ${hit.qty}',
                if ((hit.condition ?? '').isNotEmpty) hit.condition!,
                if ((hit.storageLocation ?? '').isNotEmpty)
                  'Local ${hit.storageLocation}',
              ].join('\n'),
              style: GoogleFonts.inter(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.pushNamed(
                        AmazonImporterProductPage.routeName,
                        pathParameters: {'productId': hit.catalogProductId},
                      );
                    },
                    child: const Text('Ficha catálogo'),
                  ),
                ),
                if ((hit.fleaberProductId ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FleaberPrimaryButton(
                      label: 'Anúncio',
                      onPressed: () {
                        context.pushNamed(
                          'ProductDetails',
                          queryParameters: {
                            'product_id': hit.fleaberProductId!,
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
