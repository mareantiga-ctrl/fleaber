import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/utils/fleaber_colors.dart';
import '/utils/ref_history_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/ref_history_detail_sheet.dart';

class GestaoReferenciasPageWidget extends StatefulWidget {
  const GestaoReferenciasPageWidget({super.key});

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
  };

  bool _loading = true;
  String _filter = 'all';
  String _search = '';
  String? _loadError;
  List<RefHistoryListEntry> _items = [];
  final _searchCtrl = TextEditingController();

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
      _loadError = loadError;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(color: const Color(0xFF101518)),
              decoration: InputDecoration(
                hintText: 'Pesquisar referência ou título…',
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
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _filters.entries.map((e) {
                final selected = _filter == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = e.key);
                      _load();
                    },
                    labelStyle: GoogleFonts.inter(
                      color: selected ? Colors.white : FleaberColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    selectedColor: FleaberColors.teal,
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    side: BorderSide.none,
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: FleaberColors.teal),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _loadError != null
                                ? 'Não foi possível carregar históricos ($_loadError).'
                                : 'Sem históricos para mostrar.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: FleaberColors.muted),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) => _HistoryTile(
                            entry: _items[i],
                            sellerId: effectiveSellerId,
                            onRefresh: _load,
                          ),
                        ),
                      ),
          ),
        ],
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
                    color: Colors.white12,
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
                      style: GoogleFonts.inter(
                        color: const Color(0xFF101518),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_statusLabel(entry.historyStatus)} · '
                      '${entry.openReservationCount} reservas · '
                      '${entry.completedPurchaseCount} vendas',
                      style: GoogleFonts.inter(
                        color: FleaberColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
