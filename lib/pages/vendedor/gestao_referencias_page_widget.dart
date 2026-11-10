import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/seller_product_form/seller_product_form_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/product_draft_service.dart';
import '/utils/ref_history_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/ref_history_detail_sheet.dart';

class GestaoReferenciasPageWidget extends StatefulWidget {
  const GestaoReferenciasPageWidget({super.key, this.embedded = false});

  final bool embedded;

  static String routeName = 'GestaoReferencias';
  static String routePath = '/gestaoReferencias';

  @override
  State<GestaoReferenciasPageWidget> createState() =>
      _GestaoReferenciasPageWidgetState();
}

class _GestaoReferenciasPageWidgetState extends State<GestaoReferenciasPageWidget> {
  static const _filters = <String, String>{
    'all': 'Todos',
    'active': 'Ativos',
    'pending': 'Com reservas',
    'closed': 'Encerrados',
    'popular': 'Mais vendidos',
    'drafts': 'Rascunhos de anúncios',
  };

  bool _loading = true;
  String _filter = 'all';
  String _search = '';
  String? _loadError;
  List<RefHistoryListEntry> _items = [];
  List<ProductsRow> _drafts = [];
  final _searchCtrl = TextEditingController();

  bool get _showingDrafts => _filter == 'drafts';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sid = effectiveSellerId.trim();
    if (sid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });

    if (_showingDrafts) {
      try {
        var drafts = await ProductDraftService.listForSeller(sid);
        final q = _search.trim().toLowerCase();
        if (q.isNotEmpty) {
          drafts = drafts.where((p) {
            final title = (p.title ?? '').toLowerCase();
            final ref = (p.refCode ?? '').toLowerCase();
            return title.contains(q) || ref.contains(q);
          }).toList();
        }
        if (!mounted) return;
        setState(() {
          _drafts = drafts;
          _items = [];
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _drafts = [];
          _loadError = e.toString();
          _loading = false;
        });
      }
      return;
    }

    final result = await RefHistoryService.listWithMeta(
      sellerId: sid,
      filter: _filter,
      search: _search.trim().isEmpty ? null : _search.trim(),
    );
    if (!mounted) return;
    var items = result.items;
    var loadError = result.error;
    if (items.isEmpty && loadError != null) {
      items = await RefHistoryService.listFallbackFromLiveItems(sid);
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _drafts = [];
      _loadError = loadError;
      _loading = false;
    });
  }

  Future<void> _deleteDraft(ProductsRow draft) async {
    final id = draft.id?.trim() ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Eliminar rascunho?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Esta acção não se pode desfazer.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Eliminar',
              style: GoogleFonts.inter(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProductDraftService.deleteDraft(
      productId: id,
      sellerId: effectiveSellerId,
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const bg = FleaberColors.bgTint;
    final body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cada referência (REF) é um artigo teu no marketplace ou em directo. '
                'Usa os filtros para ver activos, com reservas, encerrados ou '
                'rascunhos — e toca num rascunho para continuar a editar.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: FleaberColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(color: const Color(0xFF101518)),
              decoration: InputDecoration(
                hintText: _showingDrafts
                    ? 'Pesquisar rascunhos…'
                    : 'Pesquisar referência ou título…',
                hintStyle: GoogleFonts.inter(color: FleaberColors.muted),
                prefixIcon: const Icon(Icons.search, color: FleaberColors.muted),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                // Mobile / painel estreito: Wrap — todos os filtros visíveis, sem corte.
                // Desktop largo: fila horizontal com scroll suave.
                final useWrap = c.maxWidth < 720;
                final chips = _filters.entries.map((e) {
                  final selected = _filter == e.key;
                  return ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = e.key);
                      _load();
                    },
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelStyle: GoogleFonts.inter(
                      color:
                          selected ? Colors.white : FleaberColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.25,
                    ),
                    selectedColor: FleaberColors.teal,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: selected
                            ? FleaberColors.teal
                            : const Color(0xFFE0E3E7),
                      ),
                    ),
                    showCheckmark: false,
                  );
                }).toList();
                if (useWrap) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips,
                  );
                }
                return SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 24),
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => chips[i],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  )
                : _showingDrafts
                    ? (_drafts.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _loadError != null
                                    ? 'Não foi possível carregar rascunhos. Tenta novamente.'
                                    : 'Ainda não tens rascunhos. Guarda um anúncio incompleto em Novo anúncio.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: FleaberColors.muted,
                                ),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _drafts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) => _DraftTile(
                                product: _drafts[i],
                                onContinue: () {
                                  context.pushNamed(
                                    SellerProductFormWidget.routeName,
                                    queryParameters: {
                                      'editProductId': _drafts[i].id ?? '',
                                    },
                                  ).then((_) => _load());
                                },
                                onDelete: () => _deleteDraft(_drafts[i]),
                              ),
                            ),
                          ))
                    : _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _loadError != null
                                        ? 'Não foi possível carregar os artigos. Tenta novamente.'
                                        : _filter == 'popular'
                                            ? 'Ainda não há artigos com vendas suficientes para este filtro.'
                                            : _filter == 'pending'
                                                ? 'Não tens artigos com reservas abertas neste momento.'
                                                : 'Ainda não há histórico de referências (REF) de diretos. '
                                                    'Os anúncios a meio estão em «Rascunhos de anúncios».',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      color: FleaberColors.muted,
                                    ),
                                  ),
                                  if (_loadError == null &&
                                      _filter == 'all') ...[
                                    const SizedBox(height: 14),
                                    TextButton(
                                      onPressed: () {
                                        setState(() => _filter = 'drafts');
                                        _load();
                                      },
                                      child: Text(
                                        'Ver rascunhos de anúncios',
                                        style: GoogleFonts.inter(
                                          color: FleaberColors.teal,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) => _HistoryTile(
                                entry: _items[i],
                                sellerId: effectiveSellerId,
                                onRefresh: _load,
                              ),
                            ),
                          ),
          ),
        ],
      );
    if (widget.embedded) {
      return ColoredBox(color: bg, child: body);
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Gestão de referências',
          style: GoogleFonts.inter(
            color: const Color(0xFF101518),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF101518)),
      ),
      body: body,
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.product,
    required this.onContinue,
    required this.onDelete,
  });

  final ProductsRow product;
  final VoidCallback onContinue;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final photos = product.imageUrls;
    final photo = photos.isNotEmpty ? photos.first : null;
    final title = (product.title ?? '').trim();
    final ref = (product.refCode ?? '').trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null && photo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: BatataCachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    placeholderColor: const Color(0xFF243038),
                  ),
                ),
              )
            else
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: FleaberColors.muted),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4F5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Rascunho',
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (ref.isNotEmpty)
                    Text(
                      ref,
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  Text(
                    title.isNotEmpty ? title : 'Sem título',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF101518),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      TextButton(
                        onPressed: onContinue,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Continuar edição',
                          style: GoogleFonts.inter(
                            color: FleaberColors.teal,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Eliminar',
                          style: GoogleFonts.inter(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
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
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.sellerId,
    required this.onRefresh,
  });

  final RefHistoryListEntry entry;
  final String sellerId;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final photo = entry.displayPhotoUrl?.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          RefHistoryDetailSheet.show(
            context,
            sellerId: sellerId,
            historyId: entry.historyId,
            refCode: entry.refCode,
            onChanged: onRefresh,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo != null && photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: BatataCachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      placeholderColor: const Color(0xFF243038),
                    ),
                  ),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tag, color: FleaberColors.muted),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.refCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: FleaberColors.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      entry.displayTitle.isNotEmpty
                          ? entry.displayTitle
                          : 'Sem título',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF101518),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_statusLabel(entry.historyStatus)} · '
                      '${_countLabel(entry.openReservationCount, 'reserva', 'reservas')} · '
                      '${_countLabel(entry.completedPurchaseCount, 'venda', 'vendas')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: FleaberColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: FleaberColors.muted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _countLabel(int n, String singular, String plural) {
    final abs = n < 0 ? 0 : n;
    return '$abs ${abs == 1 ? singular : plural}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'closed':
        return 'Encerrado';
      case 'merged':
        return 'Juntado';
      default:
        return 'Ativo';
    }
  }
}
