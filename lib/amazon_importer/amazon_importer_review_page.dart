import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import 'amazon_importer_product_page.dart';
import 'amazon_importer_service.dart';

/// Revisão e aprovação em massa — aprovação ≠ publicação.
class AmazonImporterReviewPage extends StatefulWidget {
  const AmazonImporterReviewPage({super.key});

  static const routeName = 'AmazonImporterReview';
  static const routePath = '/amazonImporter/review';

  @override
  State<AmazonImporterReviewPage> createState() =>
      _AmazonImporterReviewPageState();
}

class _AmazonImporterReviewPageState extends State<AmazonImporterReviewPage> {
  String _filter = 'all';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _selected = {};
  bool _busy = false;

  static const _filters = <(String, String)>[
    ('all', 'Todos'),
    ('ready', 'Prontos'),
    ('incomplete', 'Incompletos'),
    ('missing_price', 'Sem preço'),
    ('missing_photo', 'Sem foto'),
    ('missing_weight', 'Sem peso'),
    ('approved', 'Aprovados'),
  ];

  static const _reasonLabel = <String, String>{
    'missing_price': 'Falta preço',
    'missing_title': 'Falta título',
    'missing_description': 'Falta descrição',
    'missing_photo': 'Falta foto',
    'missing_weight': 'Falta peso',
    'not_found': 'Artigo não encontrado',
  };

  String _humanReasons(List<String> codes) =>
      codes.map((c) => _reasonLabel[c] ?? c).join(' · ');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await AmazonImporterService.instance.listReadiness(filter: _filter);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _selected.removeWhere((id) => !_rows.any((r) => r['id'] == id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _bulkApprove() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar seleccionados'),
        content: Text(
          'Vais aprovar ${_selected.length} ficha(s).\n\n'
          'Isto NÃO publica na Fleaber nem sincroniza Moloni.',
          style: GoogleFonts.inter(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await AmazonImporterService.instance.bulkApprove(
      productIds: _selected.toList(),
      note: 'ZIP 166.1 revisão em massa',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final rejected = (res['rejected'] as List?) ?? const [];
    final skipped = (res['skipped_already_approved'] as num?)?.toInt() ?? 0;
    final reasonsSummary = rejected.isEmpty
        ? ''
        : ' Bloqueados: ${rejected.map((e) {
            if (e is! Map) return '$e';
            final asin = e['asin']?.toString() ?? e['product_id']?.toString() ?? '?';
            final r = e['reasons'];
            final codes = r is List
                ? r.map((x) => x.toString()).toList()
                : <String>['$r'];
            return '$asin (${_humanReasons(codes)})';
          }).join(' · ')}';
    final skipTxt = skipped > 0 ? ' Já aprovados (ignorados): $skipped.' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Aprovados ${res['approved']}; bloqueados ${res['blocked']}.'
          '$skipTxt Sem publicação.$reasonsSummary',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
    _selected.clear();
    await _load();
  }

  Future<void> _simulate(String productId, {required bool moloni}) async {
    final label = moloni ? 'Moloni' : 'Fleaber (rascunho)';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Simular $label'),
        content: Text(
          'Confirma simulação $label?\n\n'
          'Nenhuma chamada real à API / nenhum anúncio criado.',
          style: GoogleFonts.inter(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = moloni
        ? await AmazonImporterService.instance.simulateMoloni(
            productId: productId,
            confirm: true,
          )
        : await AmazonImporterService.instance.simulateFleaberDraft(
            productId: productId,
            confirm: true,
          );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['message']?.toString() ?? '$res')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        title: Text(
          'Revisão e aprovação',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: FleaberColors.text,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Aprovar ficha ≠ publicar. Fleaber/Moloni só por simulação '
              'com confirmação (ZIP 166).',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: FleaberColors.muted,
                height: 1.35,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (id, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == id,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() => _filter = id);
                              _load();
                            },
                    ),
                  ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FleaberPrimaryButton(
                width: double.infinity,
                label: _busy
                    ? 'A aprovar…'
                    : 'Aprovar ${_selected.length} seleccionados',
                onPressed: _busy ? null : _bulkApprove,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF007782)),
                  )
                : _error != null
                    ? Center(child: Text(_error!))
                    : _rows.isEmpty
                        ? Center(
                            child: Text(
                              'Sem resultados neste filtro.',
                              style: GoogleFonts.inter(color: FleaberColors.muted),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final r = _rows[i];
                              final id = r['id']?.toString() ?? '';
                              final reasons =
                                  (r['missing_reasons'] as List?)
                                          ?.map((e) => e.toString())
                                          .toList() ??
                                      const <String>[];
                              final ready = r['is_ready_to_approve'] == true;
                              final approved = r['approved_at'] != null;
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            AmazonImporterProductPage(
                                          productId: id,
                                        ),
                                      ),
                                    );
                                    await _load();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Checkbox(
                                          value: _selected.contains(id),
                                          // Só seleccionáveis os prontos; incompletos
                                          // ficam bloqueados na UI (RPC também bloqueia).
                                          onChanged: (approved || !ready)
                                              ? null
                                              : (v) {
                                                  setState(() {
                                                    if (v == true) {
                                                      _selected.add(id);
                                                    } else {
                                                      _selected.remove(id);
                                                    }
                                                  });
                                                },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r['title']?.toString() ??
                                                    r['asin']?.toString() ??
                                                    '—',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'ASIN ${r['asin']} · '
                                                '${r['unit_count'] ?? 0} un. · '
                                                '${approved ? 'APROVADO' : ready ? 'PRONTO' : 'INCOMPLETO'}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: FleaberColors.muted,
                                                ),
                                              ),
                                              if (reasons.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Não pode aprovar: ${_humanReasons(reasons)}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: Colors.orange.shade800,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  TextButton(
                                                    onPressed: () => _simulate(
                                                      id,
                                                      moloni: false,
                                                    ),
                                                    child: const Text(
                                                      'Simular Fleaber',
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => _simulate(
                                                      id,
                                                      moloni: true,
                                                    ),
                                                    child: const Text(
                                                      'Simular Moloni',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
