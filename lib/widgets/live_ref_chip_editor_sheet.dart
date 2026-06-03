import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/live_prep_ref_details.dart';

const _kTeal = Color(0xFF007782);

const _kClothingSizes = <String>[
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  '3XL',
];

const _kClothingColors = <String>[
  'Preto',
  'Branco',
  'Cinzento',
  'Bege',
  'Castanho',
  'Azul',
  'Azul claro',
  'Verde',
  'Verde oliva',
  'Vermelho',
  'Rosa',
  'Roxo',
  'Amarelo',
  'Laranja',
  'Bordô',
  'Dourado',
  'Prateado',
  'Multicolor',
  'Outra',
];

class LiveRefChipEditorResult {
  const LiveRefChipEditorResult({
    required this.refLabel,
    required this.detail,
  });

  final String refLabel;
  final LiveRefChipDetail detail;
}

/// Popup compacto para editar uma referência do directo (sem catálogo).
Future<LiveRefChipEditorResult?> showLiveRefChipEditorSheet({
  required BuildContext context,
  required String refLabel,
  LiveRefChipDetail? initial,
  bool creatingNew = false,
  Set<String> existingRefKeys = const {},
}) {
  return showModalBottomSheet<LiveRefChipEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _LiveRefChipEditorSheet(
      refLabel: refLabel,
      initial: initial ?? const LiveRefChipDetail(),
      creatingNew: creatingNew,
      existingRefKeys: existingRefKeys,
    ),
  );
}

class _LiveRefChipEditorSheet extends StatefulWidget {
  const _LiveRefChipEditorSheet({
    required this.refLabel,
    required this.initial,
    this.creatingNew = false,
    this.existingRefKeys = const {},
  });

  final String refLabel;
  final LiveRefChipDetail initial;
  final bool creatingNew;
  final Set<String> existingRefKeys;

  @override
  State<_LiveRefChipEditorSheet> createState() =>
      _LiveRefChipEditorSheetState();
}

class _LiveRefChipEditorSheetState extends State<_LiveRefChipEditorSheet> {
  late final TextEditingController _refController;
  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _quantityController;
  late bool _isClothing;
  String? _clothingSize;
  String? _clothingColor;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final label = widget.refLabel.startsWith('#')
        ? widget.refLabel
        : '#${widget.refLabel}';
    _refController = TextEditingController(text: label);
    _titleController = TextEditingController(text: i.title ?? '');
    _priceController = TextEditingController(
      text: i.price != null ? i.price!.toStringAsFixed(2).replaceAll('.', ',') : '',
    );
    _quantityController = TextEditingController(
      text: '${i.quantity < 1 ? 1 : i.quantity}',
    );
    _isClothing = i.isClothing;
    _clothingSize = i.clothingSize;
    _clothingColor = i.clothingColor;
  }

  @override
  void dispose() {
    _refController.dispose();
    _titleController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF57636C)),
      hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF98A1AA)),
      filled: true,
      fillColor: const Color(0xFFF8FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kTeal, width: 1.2),
      ),
    );
  }

  String _normalizeRefLabel(String raw) {
    var r = raw.trim();
    if (r.isEmpty) return r;
    if (!r.startsWith('#')) r = '#$r';
    return r;
  }

  void _save() {
    final refRaw = _refController.text.trim();
    final refLabel = _normalizeRefLabel(refRaw);
    if (refLabel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica o número da referência.')),
      );
      return;
    }
    final refKey = LivePrepRefDetails.normalizeRefKey(refLabel);
    if (widget.creatingNew && widget.existingRefKeys.contains(refKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A referência $refLabel já existe neste directo.',
          ),
        ),
      );
      return;
    }

    final titleRaw = _titleController.text.trim();
    final qtyRaw = _quantityController.text.trim();
    final qty = qtyRaw.isEmpty ? 1 : (int.tryParse(qtyRaw) ?? 1);
    final priceRaw = _priceController.text.trim().replaceAll(',', '.');
    final price = priceRaw.isEmpty ? null : double.tryParse(priceRaw);
    Navigator.pop(
      context,
      LiveRefChipEditorResult(
        refLabel: refLabel,
        detail: LiveRefChipDetail(
          title: titleRaw.isEmpty ? null : titleRaw,
          price: price,
          quantity: qty < 1 ? 1 : qty,
          clothingSize:
              _isClothing && (_clothingSize?.isNotEmpty ?? false)
                  ? _clothingSize
                  : null,
          clothingColor:
              _isClothing && (_clothingColor?.isNotEmpty ?? false)
                  ? _clothingColor
                  : null,
          isClothing: _isClothing &&
              ((_clothingSize?.isNotEmpty ?? false) ||
                  (_clothingColor?.isNotEmpty ?? false)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E3E7),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.creatingNew ? 'Nova referência' : 'Editar referência',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Todos os campos são opcionais, excepto a referência.',
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _refController,
            enabled: widget.creatingNew,
            style: GoogleFonts.interTight(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _kTeal,
            ),
            decoration: _dec('Referência', hint: '#012'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: _dec('Título (opcional)', hint: 'Ex.: Camisola vintage'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                  ],
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _dec('Preço €', hint: '12,50'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _dec('Qtd.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'É roupa (tamanho / cor)',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            value: _isClothing,
            activeThumbColor: _kTeal,
            onChanged: (v) => setState(() {
              _isClothing = v;
              if (!v) {
                _clothingSize = null;
                _clothingColor = null;
              }
            }),
          ),
          if (_isClothing) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              initialValue: _clothingSize,
              isDense: true,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF101518)),
              decoration: _dec('Tamanho (opcional)'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('—'),
                ),
                ..._kClothingSizes.map(
                  (s) => DropdownMenuItem(value: s, child: Text(s)),
                ),
              ],
              onChanged: (v) => setState(() => _clothingSize = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _clothingColor,
              isDense: true,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF101518)),
              decoration: _dec('Cor (opcional)'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('—'),
                ),
                ..._kClothingColors.map(
                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                ),
              ],
              onChanged: (v) => setState(() => _clothingColor = v),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: _kTeal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                widget.creatingNew ? 'Criar referência' : 'Guardar referência',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
