import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_product_page.dart';
import 'amazon_importer_service.dart';

class AmazonImporterCatalogPage extends StatefulWidget {
  const AmazonImporterCatalogPage({super.key});

  static const routeName = 'AmazonImporterCatalog';
  static const routePath = '/amazonImporter/catalog';

  @override
  State<AmazonImporterCatalogPage> createState() =>
      _AmazonImporterCatalogPageState();
}

class _AmazonImporterCatalogPageState extends State<AmazonImporterCatalogPage> {
  final _search = TextEditingController();
  final _barcodeFocus = FocusNode();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Leitor USB/Bluetooth: foco no campo; Enter confirma.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AmazonImporterService.instance.searchCatalog(
        query: _search.text,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
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

  Future<void> _onBarcodeSubmit(String code) async {
    final c = code.trim();
    if (c.isEmpty) return;
    final hit = await AmazonImporterService.instance.findByBarcode(c);
    if (!mounted) return;
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sem resultados para «$c».')),
      );
      return;
    }
    final productId = hit['product_id']?.toString() ??
        hit['id']?.toString() ??
        hit['amazon_catalog_products']?['id']?.toString();
    // nested select may return map
    String? pid = productId;
    final nested = hit['amazon_catalog_products'];
    if (nested is Map && nested['id'] != null) {
      pid = nested['id'].toString();
    }
    if (pid == null || pid.isEmpty) {
      setState(() {
        _search.text = c;
      });
      await _load();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AmazonImporterProductPage(productId: pid!),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Catálogo Amazon',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  focusNode: _barcodeFocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ASIN, EAN, LPN, título ou código de barras',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                  ),
                  onSubmitted: (v) async {
                    if (RegExp(r'^[A-Z0-9]{8,}$', caseSensitive: false)
                        .hasMatch(v.trim())) {
                      await _onBarcodeSubmit(v);
                    } else {
                      await _load();
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _statusFilter.isEmpty ? null : _statusFilter,
                  decoration: InputDecoration(
                    labelText: 'Estado',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem(
                      value: 'imported',
                      child: Text('Importado'),
                    ),
                    DropdownMenuItem(
                      value: 'researched',
                      child: Text('Pesquisado'),
                    ),
                    DropdownMenuItem(
                      value: 'needs_review',
                      child: Text('Revisão'),
                    ),
                    DropdownMenuItem(
                      value: 'prepared',
                      child: Text('Preparados'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Aprovados'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v ?? '');
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020))),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF007782)),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'Sem artigos. Importa um manifesto primeiro.',
                          style: GoogleFonts.inter(color: FleaberColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final p = _items[i];
                          final title =
                              (p['title']?.toString() ?? '').trim().isEmpty
                                  ? 'ASIN ${p['asin']}'
                                  : p['title'].toString();
                          final suggested = p['suggested_sale_eur'];
                          final approved = p['approved_sale_eur'];
                          return Card(
                            child: ListTile(
                              leading: (p['primary_image_url']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true)
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        p['primary_image_url'].toString(),
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.image_not_supported),
                                      ),
                                    )
                                  : const Icon(Icons.inventory_2_outlined),
                              title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Text(
                                'ASIN ${p['asin']}'
                                '${(p['ean']?.toString() ?? '').isNotEmpty ? ' · EAN ${p['ean']}' : ''}\n'
                                'Estado: ${p['catalog_status']}'
                                '${suggested != null ? ' · Sugerido ${suggested} €' : ' · Preço atual não disponível'}'
                                '${approved != null ? ' · Venda ${approved} €' : ''}',
                                style: GoogleFonts.inter(fontSize: 11.5),
                              ),
                              isThreeLine: true,
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AmazonImporterProductPage(
                                      productId: p['id'].toString(),
                                    ),
                                  ),
                                );
                                await _load();
                              },
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FleaberPrimaryButton(
              width: double.infinity,
              label: 'Ler código (foco no campo)',
              onPressed: () {
                _barcodeFocus.requestFocus();
                SystemChannels.textInput.invokeMethod('TextInput.show');
              },
            ),
          ),
        ],
      ),
    );
  }
}
