import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/clothing_option_lists.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/widgets/fleaber_primary_button.dart';

/// Prémio só para rifa — não entra no catálogo do directo nem no marketplace.
class LiveRafflePrizeDraft {
  const LiveRafflePrizeDraft({
    required this.title,
    this.description,
    this.photoUrl,
    this.photos = const [],
  });

  final String title;
  final String? description;
  final String? photoUrl;
  final List<String> photos;
}

class LiveRafflePrizeEditSheet extends StatefulWidget {
  const LiveRafflePrizeEditSheet({super.key, this.initialRefLabel});

  final String? initialRefLabel;

  static Future<LiveRafflePrizeDraft?> show(
    BuildContext context, {
    String? initialRefLabel,
  }) {
    return showModalBottomSheet<LiveRafflePrizeDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: RoundedRectangleBorder(borderRadius: FleaberRadius.circularLg),
      builder: (_) => LiveRafflePrizeEditSheet(initialRefLabel: initialRefLabel),
    );
  }

  @override
  State<LiveRafflePrizeEditSheet> createState() =>
      _LiveRafflePrizeEditSheetState();
}

class _LiveRafflePrizeEditSheetState extends State<LiveRafflePrizeEditSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final List<String> _photos = [];
  String? _selectedSize;
  String? _selectedColor;
  bool _loading = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    final ref = widget.initialRefLabel?.trim();
    if (ref != null && ref.isNotEmpty) {
      _refCtrl.text = ref;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final remaining = 6 - _photos.length;
    if (remaining < 1) return;
    try {
      final picked = await FleaberGalleryPicker.pickImages(limit: remaining);
      if (picked.isEmpty) return;
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      setState(() => _loading = true);
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final path =
            'live_raffle_prize/$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await SupaFlow.client.storage.from('chat_media').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: false),
            );
        _photos.add(
          SupaFlow.client.storage.from('chat_media').getPublicUrl(path),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _inlineError = 'Não foi possível carregar a foto.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _inlineError = 'Nome do prémio obrigatório.');
      return;
    }
    final ref = _refCtrl.text.trim();
    var desc = _descCtrl.text.trim();
    if (ref.isNotEmpty) {
      desc = desc.isEmpty ? 'Ref. $ref' : '$desc · Ref. $ref';
    }
    if (_selectedSize?.isNotEmpty == true) {
      desc = desc.isEmpty
          ? 'Tam. $_selectedSize'
          : '$desc · Tam. $_selectedSize';
    }
    if (_selectedColor?.isNotEmpty == true) {
      desc = desc.isEmpty ? 'Cor $_selectedColor' : '$desc · $_selectedColor';
    }
    Navigator.pop(
      context,
      LiveRafflePrizeDraft(
        title: title,
        description: desc.isEmpty ? null : desc,
        photoUrl: _photos.isNotEmpty ? _photos.first : null,
        photos: List<String>.from(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Artigo para a Rifa',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este artigo é só para o prémio da rifa. Não aparece no catálogo '
              'do directo nem pode ser publicado no marketplace.',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 10),
              Text(
                _inlineError!,
                style: GoogleFonts.inter(
                  color: const Color(0xFFFF8A80),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Fotos',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _photos[i],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => setState(() => _photos.removeAt(i)),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_photos.length < 6)
                    InkWell(
                      onTap: _loading ? null : _addPhotos,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_a_photo_outlined,
                                color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _field('Nome do prémio *', _titleCtrl),
            _field('Referência (opcional)', _refCtrl),
            _dropdown('Tamanho', _selectedSize, ClothingOptionLists.sizes,
                (v) => setState(() => _selectedSize = v)),
            _dropdown('Cor', _selectedColor, ClothingOptionLists.colors,
                (v) => setState(() => _selectedColor = v)),
            _field('Descrição', _descCtrl, maxLines: 3),
            const SizedBox(height: 14),
            FleaberPrimaryButton(
              label: 'Criar artigo para rifa',
              loading: _loading,
              onPressed: _loading ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: const BorderSide(color: FleaberColors.teal),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: value != null && items.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: FleaberRadius.circularSm,
            borderSide: const BorderSide(color: FleaberColors.teal),
          ),
        ),
        dropdownColor: const Color(0xFF1A2228),
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
