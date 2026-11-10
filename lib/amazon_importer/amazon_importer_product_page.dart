import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_export_adapters.dart';
import 'amazon_importer_models.dart';
import 'amazon_importer_service.dart';
import 'amazon_llm_local.dart';
import 'amazon_photo_cdn.dart';
import 'amazon_pt_copy.dart';
import 'amazon_weight.dart';

class AmazonImporterProductPage extends StatefulWidget {
  const AmazonImporterProductPage({super.key, required this.productId});

  final String productId;

  static const routeName = 'AmazonImporterProduct';
  static const routePath = '/amazonImporter/product/:productId';

  @override
  State<AmazonImporterProductPage> createState() =>
      _AmazonImporterProductPageState();
}

class _AmazonImporterProductPageState extends State<AmazonImporterProductPage> {
  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _photos = [];
  List<AmazonOfferView> _offers = [];
  bool _loading = true;
  bool _busy = false;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _discount = TextEditingController(text: '50');
  final _approved = TextEditingController();
  final _realCost = TextEditingController();
  final _notes = TextEditingController();
  final _manualPrice = TextEditingController();
  final _shipKg = TextEditingController();

  static const _saleStates = <String>[
    'Novo',
    'Usado / recondicionado',
    'Danificado (armazém)',
    'Danificado (transporte)',
    'Danificado (cliente)',
    'Com defeito',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _discount.dispose();
    _approved.dispose();
    _realCost.dispose();
    _notes.dispose();
    _manualPrice.dispose();
    _shipKg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await SupaFlow.client
          .from('amazon_catalog_products')
          .select()
          .eq('id', widget.productId)
          .maybeSingle();
      final units = await SupaFlow.client
          .from('amazon_catalog_units')
          .select()
          .eq('product_id', widget.productId)
          .order('created_at');
      final offers =
          await AmazonImporterService.instance.offersForProduct(widget.productId);
      final photos =
          await AmazonImporterService.instance.photosForProduct(widget.productId);
      if (!mounted) return;
      final map = p == null ? null : Map<String, dynamic>.from(p as Map);
      setState(() {
        _product = map;
        _units = (units as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _offers = offers;
        _photos = photos;
        _loading = false;
        if (map != null) {
          _title.text = map['title']?.toString() ?? '';
          _desc.text = map['description']?.toString() ?? '';
          _discount.text =
              (map['discount_pct'] as num?)?.toStringAsFixed(0) ?? '50';
          _approved.text =
              (map['approved_sale_eur'] as num?)?.toStringAsFixed(2) ?? '';
          _realCost.text =
              (map['real_acquisition_cost_eur'] as num?)?.toStringAsFixed(2) ??
                  '';
          _notes.text = map['prep_notes']?.toString() ?? '';
          final ship = (map['shipping_weight_kg'] as num?)?.toDouble();
          _shipKg.text = ship == null
              ? ''
              : ship.toStringAsFixed(ship >= 10 ? 1 : 3);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _sourceTitleForPt() {
    for (final o in _offers) {
      final t = (o.title ?? '').trim();
      if (o.isAmazonMarket && t.isNotEmpty) return t;
    }
    final t = _title.text.trim();
    if (t.isNotEmpty) return t;
    return _product?['title']?.toString() ?? '';
  }

  Future<void> _generatePtCopy() async {
    final source = _sourceTitleForPt();
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem texto de origem para gerar título/descrição.'),
        ),
      );
      return;
    }
    final brand = _product?['brand']?.toString();
    String? condNote;
    if (_units.isNotEmpty) {
      final label = (_units.first['condition_label']?.toString() ?? '').trim();
      condNote = saleConditionFromManifest(
        label.isNotEmpty ? label : _units.first['condition_code']?.toString(),
      );
    }

    setState(() => _busy = true);
    try {
      final llm = AmazonLlmLocal();
      if (await llm.isAvailable()) {
        final amazonOffers = _offers.where((o) => o.isAmazonMarket).toList();
        final ref = hasSuspiciousAmazonPriceSpread(amazonOffers)
            ? null
            : pickAmazonReferenceOffer(amazonOffers);
        final priceNote = ref == null
            ? null
            : '${ref.priceAmount!.toStringAsFixed(2)} € Amazon.${ref.marketplace}';
        final res = await llm.generateCommercialPt(
          sourceTitle: source,
          brand: brand,
          conditionNote: condNote,
          amazonPriceNote: priceNote,
        );
        if (!mounted) return;
        setState(() {
          _title.text = res.title;
          _desc.text = res.description;
        });
        await AmazonImporterService.instance.updateProductSale(
          productId: widget.productId,
          title: res.title,
          description: res.description,
          catalogStatus:
              res.pass ? 'prepared' : 'needs_review',
          prepNotes:
              '${_notes.text.trim()}\nLLM ${res.model} ${res.copyStatus} '
                      'tries=${res.attempts}'
                  .trim(),
        );
        await SupaFlow.client.from('amazon_catalog_products').update({
          'title_original': source,
          'llm_model': res.model,
          'llm_generated_at': DateTime.now().toUtc().toIso8601String(),
          'copy_status': res.copyStatus,
        }).eq('id', widget.productId);
        if (!mounted) return;
        final msg = res.pass
            ? 'PT-PT OK (${res.model}, ${res.attempts}x). Editável.'
            : 'Revisão necessária: ${res.issues.join('; ')}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      // Fallback heurístico se Ollama não estiver no PC.
      setState(() {
        _title.text = buildCommercialTitlePt(
          sourceTitle: source,
          brandHint: brand,
        );
        _desc.text = buildCommercialDescriptionPt(
          sourceTitle: source,
          sourceDescription: _desc.text.trim().isEmpty ? null : _desc.text,
          brand: brand,
          conditionNote: condNote,
        );
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ollama indisponível neste dispositivo — usado gerador local simples. '
            'No PC admin: python tool/amazon_importer_local_enrich.py',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _research() async {
    final asin = _product?['asin']?.toString() ?? '';
    if (asin.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await AmazonImporterService.instance.researchAsin(
        productId: widget.productId,
        asin: asin,
      );
      await AmazonImporterService.instance.refreshSuggestedPrice(widget.productId);
      if (!mounted) return;
      final note = res['note']?.toString() ?? 'Pesquisa concluída.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
      await _load();
      // Após pesquisa: se título ainda for inglês/cru, sugerir PT (editável).
      if (_title.text.trim().isNotEmpty &&
          (_desc.text.trim().isEmpty ||
              RegExp(r'\b(the|with|and|for)\b', caseSensitive: false)
                  .hasMatch(_title.text))) {
        _generatePtCopy();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pesquisa indisponível ($e). Podes definir preços manualmente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveManualPrice() async {
    final v = double.tryParse(_manualPrice.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    final discount =
        double.tryParse(_discount.text.replaceAll(',', '.')) ?? 50;
    final suggested =
        double.parse((v * (1 - discount.clamp(0, 95) / 100)).toStringAsFixed(2));
    setState(() => _busy = true);
    try {
      await AmazonImporterService.instance.updateProductSale(
        productId: widget.productId,
        approvedSaleEur: v,
        discountPct: discount,
        catalogStatus: 'needs_review',
        prepNotes:
            '${_notes.text.trim()}\nPreço introduzido manualmente: ${v.toStringAsFixed(2)} €'
                .trim(),
      );
      await SupaFlow.client.from('amazon_catalog_products').update({
        'suggested_sale_eur': suggested,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preço manual guardado.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await AmazonImporterService.instance.updateProductSale(
        productId: widget.productId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        discountPct: double.tryParse(_discount.text.replaceAll(',', '.')),
        approvedSaleEur: double.tryParse(_approved.text.replaceAll(',', '.')),
        realAcquisitionCostEur:
            double.tryParse(_realCost.text.replaceAll(',', '.')),
        prepNotes: _notes.text.trim(),
        catalogStatus: 'prepared',
        shippingWeightKgManual:
            double.tryParse(_shipKg.text.replaceAll(',', '.')),
      );
      await AmazonImporterService.instance.refreshSuggestedPrice(widget.productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardado.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeUnitCondition(Map<String, dynamic> unit) async {
    final current = saleConditionFromManifest(
      unit['condition_label']?.toString() ?? unit['condition_code']?.toString(),
    );
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(
            'Estado da unidade LPN ${unit['lpn']}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          children: _saleStates
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(
                    s == current ? '$s  ✓' : s,
                    style: GoogleFonts.inter(
                      fontWeight:
                          s == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
    if (chosen == null || chosen == current) return;
    final id = unit['id']?.toString();
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await AmazonImporterService.instance.updateUnitSaleCondition(
        unitId: id,
        conditionLabel: chosen,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _missingFields({
    required AmazonOfferView? ref,
    required bool suspicious,
  }) {
    final missing = <String>[];
    if (_title.text.trim().isEmpty) missing.add('Título');
    if (_desc.text.trim().isEmpty) missing.add('Descrição');
    if (_photos.isEmpty) missing.add('Fotografias');
    if (suspicious) {
      missing.add('Preço Amazon (por confirmar)');
    } else if (ref == null) {
      missing.add('Preço Amazon');
    }
    if (_product?['suggested_sale_eur'] == null && ref == null) {
      missing.add('Preço sugerido Fleaber');
    }
    return missing;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF007782))),
      );
    }
    final p = _product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Artigo')),
        body: const Center(child: Text('Artigo não encontrado.')),
      );
    }

    final amazonOffers = _offers.where((o) => o.isAmazonMarket).toList();
    final suspicious = hasSuspiciousAmazonPriceSpread(amazonOffers);
    final ref = suspicious ? null : pickAmazonReferenceOffer(amazonOffers);
    final discount =
        double.tryParse(_discount.text.replaceAll(',', '.')) ?? 50.0;
    final suggested = p['suggested_sale_eur'];
    final noAmazon = ref == null;
    final missing = _missingFields(ref: ref, suspicious: suspicious);
    final publishable = missing.isEmpty;

    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'ASIN ${p['asin']}',
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
            _title.text.isEmpty ? 'Sem título' : _title.text,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'EAN ${p['ean'] ?? '—'} · ${_units.length} unidade(s) LPN · '
            'estado catálogo ${p['catalog_status']}',
            style: GoogleFonts.inter(fontSize: 12.5, color: FleaberColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            'Estado de venda Fleaber: Novo (decisão comercial). '
            'A condição do manifesto Amazon fica só como nota interna.',
            style: GoogleFonts.inter(fontSize: 12, color: FleaberColors.muted),
          ),
          if (!publishable) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Text(
                'Ficha incompleta — em falta: ${missing.join(', ')}. '
                'Não classificar como completo até preencher.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A3412),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Fotografias',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 6),
          if (_photos.isEmpty)
            Text(
              'Fotografias em falta',
              style: GoogleFonts.inter(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            SizedBox(
              height: 112,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final next = List<Map<String, dynamic>>.from(_photos);
                  final item = next.removeAt(oldIndex);
                  next.insert(newIndex, item);
                  setState(() => _photos = next);
                  await AmazonImporterService.instance.reorderPhotos(next);
                },
                itemCount: _photos.length,
                itemBuilder: (ctx, i) {
                  final ph = _photos[i];
                  final url = ph['public_url']?.toString() ?? '';
                  final src = ph['source']?.toString() ?? 'upload';
                  final pending = src == 'amazon_ref_pending_rights' ||
                      src == 'amazon_cdn_pending_rights' ||
                      src == 'amazon_dp_html' ||
                      src == 'amazon_browser_pending_rights';
                  String badge;
                  if (!pending) {
                    badge = 'Própria';
                  } else if (src == 'amazon_cdn_pending_rights') {
                    badge = 'CDN*';
                  } else if (src == 'amazon_browser_pending_rights') {
                    badge = 'Browser*';
                  } else if (src == 'amazon_dp_html') {
                    badge = 'HTML*';
                  } else {
                    badge = 'Ref.*';
                  }
                  return Container(
                    key: ValueKey(ph['id']?.toString() ?? '$i'),
                    width: 100,
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: url.isEmpty
                                ? Container(color: Colors.black12)
                                : Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.black12,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: Text(
                            badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final id = ph['id']?.toString();
                                    if (id == null) return;
                                    setState(() => _busy = true);
                                    try {
                                      await AmazonImporterService.instance
                                          .deletePhoto(id);
                                      await _load();
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_photos.any((ph) {
            final s = ph['source']?.toString();
            return s == 'amazon_ref_pending_rights' ||
                s == 'amazon_cdn_pending_rights' ||
                s == 'amazon_dp_html' ||
                s == 'amazon_browser_pending_rights';
          })) ...[
            const SizedBox(height: 6),
            Text(
              '* ${photoRightsLabel('amazon_cdn_pending_rights')}',
              style: GoogleFonts.inter(fontSize: 11.5, color: FleaberColors.muted),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    final asin = _product?['asin']?.toString() ?? '';
                    if (asin.isEmpty) return;
                    setState(() => _busy = true);
                    try {
                      final n = await AmazonImporterService.instance
                          .fetchAmazonCdnPhotos(widget.productId, asin);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            n > 0
                                ? '$n fotografia(s) CDN obtida(s). Direitos pendentes — não publicar sem autorização.'
                                : 'Fotografias em falta (CDN sem JPEG válido).',
                          ),
                        ),
                      );
                      await _load();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: const Color(0xFF007782),
              side: const BorderSide(color: Color(0xFF007782)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Obter fotografias Amazon (CDN automático)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await AmazonImporterService.instance
                          .pickAndUploadPhoto(widget.productId);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fotografia adicionada.')),
                      );
                      await _load();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: const Color(0xFF007782),
              side: const BorderSide(color: Color(0xFF007782)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Adicionar fotografia própria'),
          ),
          const SizedBox(height: 20),
          Text(
            'Preço Amazon (ES → IT → DE → FR)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 6),
          if (amazonOffers.isEmpty)
            Text(
              'Preço não encontrado na Amazon',
              style: GoogleFonts.inter(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            ...amazonOffers.map((o) {
              final sellable = isOfferAvailabilitySellable(o.availability);
              final chosen = ref != null &&
                  o.marketplace == ref.marketplace &&
                  o.priceAmount == ref.priceAmount;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${o.marketplace.toUpperCase()}: '
                  '${o.priceAmount != null ? '${o.priceAmount!.toStringAsFixed(2)} ${o.currency ?? 'EUR'}' : '—'}'
                  '${o.status != 'ok' ? ' · ${o.status}' : ''}'
                  '${!sellable ? ' · indisponível (ignorado)' : ''}'
                  '${chosen ? ' · referência' : ''}'
                  '${o.fetchedAt != null ? ' · ${o.fetchedAt!.toLocal()}' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
                    color: !sellable ? FleaberColors.muted : FleaberColors.text,
                  ),
                ),
              );
            }),
          ],
          if (suspicious) ...[
            const SizedBox(height: 8),
            Text(
              'Por confirmar — divergência anormal entre países. '
              'Não aprovar automaticamente.',
              style: GoogleFonts.inter(
                color: FleaberColors.danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (noAmazon && !suspicious)
            Text(
              'Preço não encontrado na Amazon — introduza manualmente ou '
              'volte a pesquisar mais tarde.',
              style: GoogleFonts.inter(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            )
          else if (ref != null) ...[
            Text(
              'Referência Amazon: ${ref.marketplace.toUpperCase()} · '
              '${ref.priceAmount!.toStringAsFixed(2)} €'
              ' · origem Amazon.${ref.marketplace}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            Text(
              'Preço sugerido Fleaber (−${discount.toStringAsFixed(0)}%): '
              '${suggested != null ? '${(suggested as num).toStringAsFixed(2)} €' : '—'}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          FleaberPrimaryButton(
            width: double.infinity,
            label: _busy ? 'A pesquisar…' : 'Pesquisar Amazon (ES→IT→DE→FR)',
            onPressed: _busy ? null : _research,
          ),
          const SizedBox(height: 16),
          Text(
            'Preço introduzido manualmente',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preço referência manual €',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _saveManualPrice,
                child: const Text('Aplicar'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Preparação (PT-PT)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _generatePtCopy,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: const Color(0xFF007782),
              side: const BorderSide(color: Color(0xFF007782)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _busy ? 'A gerar…' : 'Gerar com LLM local (Ollama PT-PT)',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Título comercial (editável)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Descrição comercial PT-PT (editável)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Desconto %',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _approved,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preço venda final €',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _realCost,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custo real aquisição € (não é o COST do manifesto)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Peso manifesto: ${AmazonWeight.formatManifestLabel((_product?['manifest_weight_kg'] as num?)?.toDouble())}',
            style: GoogleFonts.inter(fontSize: 13, color: FleaberColors.muted),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _shipKg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Peso expedição kg (DPD) — editável',
              helperText: 'Predefinido = manifesto + 10% embalagem',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notas de preparação',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          FleaberPrimaryButton(
            width: double.infinity,
            label: _busy ? 'A guardar…' : 'Guardar preparação',
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: 20),
          Text(
            'Unidades (LPN) — estado de venda',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ..._units.map((u) {
            final label = (u['condition_label']?.toString() ?? '').trim();
            final sale = saleConditionFromManifest(
              label.isNotEmpty ? label : u['condition_code']?.toString(),
            );
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'LPN ${u['lpn']}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Estado: $sale · manifesto ${u['condition_code'] ?? '—'} · '
                'COST ${u['manifesto_cost_eur']} €',
                style: GoogleFonts.inter(fontSize: 11.5),
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _changeUnitCondition(u),
                child: const Text('Alterar'),
              ),
            );
          }),
          const SizedBox(height: 20),
          Text(
            'Exportação',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            AmazonExportAdapters.moloniBlockedReason,
            style: GoogleFonts.inter(fontSize: 12, color: FleaberColors.muted),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final r = await AmazonExportAdapters.enqueueMoloni(
                productId: widget.productId,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(r['message']?.toString() ?? 'Registado')),
              );
            },
            child: const Text('Preparar envio Moloni (sem publicar)'),
          ),
          OutlinedButton(
            onPressed: () async {
              final r = await AmazonExportAdapters.enqueueFleaberDraft(
                productId: widget.productId,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(r['message']?.toString() ?? 'Registado')),
              );
            },
            child: const Text('Preparar rascunho Fleaber (sem publicar)'),
          ),
        ],
      ),
    );
  }
}
