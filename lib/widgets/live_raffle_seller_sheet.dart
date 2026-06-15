import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_raffle_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_raffle_prize_edit_sheet.dart';
import '/widgets/live_vendor_ops_ui.dart';

enum _PrizeSource { liveCatalog, marketplaceCatalog, manual }

/// Criar rifa — fluxo vendedora (selecção de artigo como principal).
class LiveRaffleSellerSheet extends StatefulWidget {
  const LiveRaffleSellerSheet({
    super.key,
    required this.liveId,
    this.activeItem,
    this.liveCatalogRows = const [],
    this.marketplaceProducts = const [],
    this.onOpenQuickEdit,
  });

  final String liveId;
  final LiveItemsRow? activeItem;
  final List<LiveItemsRow> liveCatalogRows;
  final List<ProductsRow> marketplaceProducts;
  final VoidCallback? onOpenQuickEdit;

  static Future<void> show(
    BuildContext context, {
    required String liveId,
    LiveItemsRow? activeItem,
    List<LiveItemsRow> liveCatalogRows = const [],
    List<ProductsRow> marketplaceProducts = const [],
    VoidCallback? onOpenQuickEdit,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (ctx) => LiveRaffleSellerSheet(
        liveId: liveId,
        activeItem: activeItem,
        liveCatalogRows: liveCatalogRows,
        marketplaceProducts: marketplaceProducts,
      ),
    ).then((_) => onChanged?.call());
  }

  @override
  State<LiveRaffleSellerSheet> createState() => _LiveRaffleSellerSheetState();
}

class _LiveRaffleSellerSheetState extends State<LiveRaffleSellerSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  _PrizeSource _source = _PrizeSource.manual;
  LiveItemsRow? _pickedLiveItem;
  ProductsRow? _pickedProduct;
  String? _photoUrl;
  bool _hasTimer = false;
  int _durationMin = 30;
  int _winners = 1;
  bool _showLeaderboard = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _applySource(_initialSource());
  }

  _PrizeSource _initialSource() {
    if (widget.liveCatalogRows.isNotEmpty) return _PrizeSource.liveCatalog;
    if (widget.marketplaceProducts.isNotEmpty) {
      return _PrizeSource.marketplaceCatalog;
    }
    return _PrizeSource.manual;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _applySource(_PrizeSource source) {
    _source = source;
    switch (source) {
      case _PrizeSource.liveCatalog:
        _pickedProduct = null;
        if (_pickedLiveItem == null && widget.liveCatalogRows.isNotEmpty) {
          _pickedLiveItem = widget.liveCatalogRows.first;
        }
        _fillFromLiveItem(_pickedLiveItem);
      case _PrizeSource.marketplaceCatalog:
        _pickedLiveItem = null;
        if (_pickedProduct == null && widget.marketplaceProducts.isNotEmpty) {
          _pickedProduct = widget.marketplaceProducts.first;
        }
        _fillFromProduct(_pickedProduct);
      case _PrizeSource.manual:
        _pickedLiveItem = null;
        _pickedProduct = null;
        _photoUrl = null;
        _titleCtrl.clear();
        _descCtrl.clear();
    }
  }

  void _fillFromLiveItem(LiveItemsRow? row) {
    if (row == null) return;
    _titleCtrl.text = LiveVendorRefDisplay.itemDisplayName(
      title: row.title,
      refCode: row.refCode,
    );
    _photoUrl = row.photoUrl?.trim();
    _descCtrl.text = '';
  }

  void _fillFromProduct(ProductsRow? product) {
    if (product == null) return;
    final t = product.title?.trim();
    _titleCtrl.text = t?.isNotEmpty == true ? t! : 'Artigo marketplace';
    final imgs = product.imageUrls;
    _photoUrl = imgs != null && imgs.isNotEmpty ? imgs.first.trim() : null;
    _descCtrl.text = product.description?.trim() ?? '';
  }

  Future<void> _openPrizeEdit() async {
    final ref = widget.activeItem?.refCode;
    final draft = await LiveRafflePrizeEditSheet.show(
      context,
      initialRefLabel: ref,
    );
    if (draft == null || !mounted) return;
    setState(() {
      _source = _PrizeSource.manual;
      _pickedLiveItem = null;
      _pickedProduct = null;
      _titleCtrl.text = draft.title;
      _descCtrl.text = draft.description?.trim() ?? '';
      _photoUrl = draft.photoUrl;
    });
  }

  Future<void> _pickLiveItem() async {
    final rows = widget.liveCatalogRows;
    if (rows.isEmpty) return;
    final picked = await showModalBottomSheet<LiveItemsRow>(
      context: context,
      backgroundColor: const Color(0xFF1A2228),
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            final label = LiveVendorRefDisplay.itemDisplayName(
              title: r.title,
              refCode: r.refCode,
            );
            return ListTile(
              leading: _thumb(
                r.photoUrl?.trim(),
                icon: Icons.live_tv_rounded,
              ),
              title: Text(label, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                LiveVendorRefDisplay.refLabel(r.refCode),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, r),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedLiveItem = picked;
      _fillFromLiveItem(picked);
    });
  }

  Future<void> _pickMarketplaceProduct() async {
    final rows = widget.marketplaceProducts;
    if (rows.isEmpty) return;
    final picked = await showModalBottomSheet<ProductsRow>(
      context: context,
      backgroundColor: const Color(0xFF1A2228),
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final p = rows[i];
            final img = p.imageUrls != null && p.imageUrls!.isNotEmpty
                ? p.imageUrls!.first.trim()
                : null;
            return ListTile(
              leading: _thumb(img, icon: Icons.storefront_outlined),
              title: Text(
                p.title?.trim().isNotEmpty == true ? p.title!.trim() : 'Artigo',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                LiveVendorRefDisplay.refLabel(p.refCode),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, p),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedProduct = picked;
      _fillFromProduct(picked);
    });
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Nome do prémio obrigatório.');
      return;
    }
    setState(() => _loading = true);
    try {
      DateTime? ends;
      if (_hasTimer) {
        ends = DateTime.now().toUtc().add(Duration(minutes: _durationMin));
      }
      await LiveRaffleService.createRaffle(
        liveId: widget.liveId,
        title: title,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        photoUrl: _photoUrl,
        winnerCount: _winners,
        endsAt: ends,
        showPublicLeaderboard: _showLeaderboard,
      );
      if (mounted) {
        Navigator.pop(context);
        _snack('Rifa da Live criada.');
      }
    } catch (e) {
      if (mounted) _snack(_err(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _err(Object e) {
    final s = e.toString();
    if (s.contains('active_raffle_exists')) {
      return 'Já existe uma Rifa activa neste directo.';
    }
    return 'Não foi possível criar. Tenta outra vez.';
  }

  Widget _thumb(String? url, {required IconData icon}) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: FleaberRadius.circularSm,
        ),
        child: Icon(icon, color: Colors.white38, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: FleaberRadius.circularSm,
      child: SizedBox(
        width: 44,
        height: 44,
        child: BatataCachedNetworkImage(
          imageUrl: u,
          fit: BoxFit.cover,
          placeholderColor: const Color(0xFF222222),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded,
                      color: Color(0xFF00A3AD), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Nova Rifa da Live',
                    style: GoogleFonts.interTight(
                      color: const Color(0xFF00A3AD),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _createReferenceChip(),
              _sourceChip(
                'Escolher artigo da live',
                _PrizeSource.liveCatalog,
                enabled: widget.liveCatalogRows.isNotEmpty,
                thumbUrl: _pickedLiveItem?.photoUrl,
              ),
              _sourceChip(
                'Escolher artigo do catálogo',
                _PrizeSource.marketplaceCatalog,
                enabled: widget.marketplaceProducts.isNotEmpty,
                thumbUrl: _pickedProduct?.imageUrls?.isNotEmpty == true
                    ? _pickedProduct!.imageUrls!.first
                    : null,
              ),
              _sourceChip('Prémio manual', _PrizeSource.manual),
              if (_source == _PrizeSource.liveCatalog) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickLiveItem,
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Seleccionar artigo da live'),
                ),
              ],
              if (_source == _PrizeSource.marketplaceCatalog) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickMarketplaceProduct,
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Seleccionar do catálogo'),
                ),
              ],
              const SizedBox(height: 14),
              if (_photoUrl?.trim().isNotEmpty == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: FleaberRadius.circularSm,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: BatataCachedNetworkImage(
                        imageUrl: _photoUrl!.trim(),
                        fit: BoxFit.cover,
                        placeholderColor: const Color(0xFF222222),
                      ),
                    ),
                  ),
                ),
              if (_photoUrl?.trim().isNotEmpty == true) const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _dec(
                  _source == _PrizeSource.manual
                      ? 'Nome do prémio *'
                      : 'Nome do prémio (editável)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _dec('Descrição (opcional)'),
              ),
              if (_source == _PrizeSource.manual) ...[
                const SizedBox(height: 8),
                Text(
                  'Para oferta surpresa, vale, pack mistério ou brinde.',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                ),
              ],
              SwitchListTile(
                value: _hasTimer,
                onChanged: (v) => setState(() => _hasTimer = v),
                title: Text(
                  'Tempo definido',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  _hasTimer
                      ? '$_durationMin min'
                      : 'Encerras quando quiseres',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_hasTimer)
                Slider(
                  value: _durationMin.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$_durationMin min',
                  onChanged: (v) => setState(() => _durationMin = v.round()),
                ),
              SwitchListTile(
                value: _showLeaderboard,
                onChanged: (v) => setState(() => _showLeaderboard = v),
                title: Text(
                  'Top rifas público',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  _showLeaderboard
                      ? 'Compradores vêem o top 5'
                      : 'Só tu vês o ranking',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Row(
                children: [
                  Text('Vencedores',
                      style: GoogleFonts.inter(color: Colors.white70)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _winners,
                    dropdownColor: const Color(0xFF1A2228),
                    items: List.generate(
                      3,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _winners = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FleaberPrimaryButton(
                label: 'Criar Rifa da Live',
                loading: _loading,
                onPressed: _loading ? null : _create,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createReferenceChip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: FleaberRadius.circularMd,
        child: InkWell(
          onTap: _openPrizeEdit,
          borderRadius: FleaberRadius.circularMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF00A3AD),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Criar Referência',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceChip(
    String label,
    _PrizeSource source, {
    bool enabled = true,
    String? thumbUrl,
  }) {
    final selected = _source == source;
    final showThumb = selected && thumbUrl?.trim().isNotEmpty == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? const Color(0xFF00A3AD).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: FleaberRadius.circularMd,
        child: InkWell(
          onTap: !enabled
              ? null
              : () => setState(() => _applySource(source)),
          borderRadius: FleaberRadius.circularMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: enabled
                      ? (selected ? const Color(0xFF00A3AD) : Colors.white54)
                      : Colors.white24,
                  size: 18,
                ),
                if (showThumb) ...[
                  const SizedBox(width: 8),
                  _thumb(thumbUrl, icon: Icons.image_outlined),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: FleaberRadius.circularMd),
      );
}
