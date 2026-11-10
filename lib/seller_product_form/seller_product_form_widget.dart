import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/marketplace_feed_refresh.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '/home_page/home_page_widget.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/utils/fleaber_image_bytes.dart';
import '/hub/widgets/fleahub_site_chrome.dart';
import '/widgets/fleaber_primary_button.dart';

import 'seller_product_form_model.dart';
export 'seller_product_form_model.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/dpd_shipping_rates.dart';
import '/utils/seller_professional.dart';

const _kTeal = Color(0xFF007782);
const _kBatataText = Color(0xFF101518);
const _kBatataSubText = Color(0xFF57636C);
const _kMaxPhotos = 10;
const _kDesktopFormMaxWidth = 1040.0;

const _kCategories = <String>[
  'Roupa e Acessórios',
  'Calçado',
  'Beleza e Cuidados',
  'Casa e Decoração',
  'Eletrónica',
  'Electrodomésticos',
  'Livros e Media',
  'Brinquedos',
  'Desporto e Ar Livre',
  'Colecionáveis',
  'Outra',
];

const _kConditions = <String>[
  'Novo',
  'Muito bom',
  'Bom',
  'Satisfatório',
  'Com Defeito',
];

const _kRoupaCategory = 'Roupa e Acessórios';

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

const _kGenders = <String>[
  'Masculino',
  'Feminino',
  'Unissexo',
  'Criança',
];

class _PhotoSlot {
  _PhotoSlot(this.bytes, this.fileName);
  final Uint8List bytes;
  final String fileName;
}

class SellerProductFormWidget extends StatefulWidget {
  const SellerProductFormWidget({super.key, this.editProductId});

  static String routeName = 'SellerProductForm';
  static String routePath = '/sellerProductForm';

  /// Editar artigo marketplace existente (não criar duplicado).
  final String? editProductId;

  @override
  State<SellerProductFormWidget> createState() => _SellerProductFormWidgetState();
}

class _SellerProductFormWidgetState extends State<SellerProductFormWidget> {
  late SellerProductFormModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final List<_PhotoSlot> _photos = [];
  String? _category;
  String? _condition;
  String? _clothingSize;
  String? _gender;
  bool _listOnMarketplace = true;
  bool _availableForLive = false;
  bool _saving = false;
  bool _loadingExisting = false;
  int _formStep = 0;
  late final TextEditingController _quantityController;
  late final TextEditingController _weightKgController;
  int _quantity = 1;
  /// Escalão DPD opcional se não houver peso exacto: 0_3 | 3_6 | 6_10
  String? _shippingWeightBand;
  List<String> _existingImageUrls = const [];
  String? _editingProductId;
  bool _editingIsDraft = false;
  bool _dirty = false;
  bool _draftSaving = false;

  bool get _isRoupaCategory => _category == _kRoupaCategory;

  void _markDirty() {
    if (_dirty || _loadingExisting) return;
    safeSetState(() => _dirty = true);
  }

  /// Um único ecrã com scroll (Cancelar / Rascunho / Publicar) em todos os dispositivos.
  bool _isWideDesktop(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 768;

  bool _showTwoStepUi(BuildContext context) => false;

  bool get _hasAnyPhotos =>
      _photos.isNotEmpty || _existingImageUrls.isNotEmpty;

  int get _photoCount => _photos.length + _existingImageUrls.length;

  /// Valida apenas o passo 1 (sem descrição).
  List<String> _missingForStep0() {
    final missing = <String>[];
    final title = _model.titleTextController?.text.trim() ?? '';
    final priceRaw = _model.priceTextController?.text.trim() ?? '';
    final priceVal = _parsePricePt(priceRaw);

    if (priceVal == null || priceVal < 1) {
      missing.add('Preço mínimo 1,00 €');
    }
    if (_listOnMarketplace) {
      if (title.isEmpty) missing.add('Título');
      if (_category == null) {
        missing.add('Categoria');
      }
      if (_condition == null) {
        missing.add('Estado do artigo');
      }
      if (_quantity < 1) {
        missing.add('Quantidade');
      }
      final wRaw =
          _weightKgController.text.trim().replaceAll(',', '.');
      final wKg = double.tryParse(wRaw);
      final hasKg = wKg != null && wKg > 0;
      final hasBand = (_shippingWeightBand ?? '').isNotEmpty;
      if (!hasKg && !hasBand) {
        missing.add('Peso aproximado ou escalão de envio');
      }
      if (hasKg && wKg > 10) {
        missing.add('Peso máx. 10 kg para envio DPD');
      }
      if (_isRoupaCategory) {
        if (_clothingSize == null) missing.add('Tamanho');
        if (_gender == null) missing.add('Género');
      }
    }
    if (_listOnMarketplace && !_hasAnyPhotos) {
      missing.add('Pelo menos uma foto');
    } else if (_availableForLive && !_hasAnyPhotos) {
      missing.add('Pelo menos uma foto (Live)');
    }
    return missing;
  }

  List<String> _missingForStep1() {
    final missing = <String>[];
    if (_listOnMarketplace) {
      final description = _model.descriptionTextController?.text.trim() ?? '';
      if (description.isEmpty) missing.add('Descrição');
    }
    return missing;
  }

  void _showMissingFieldsSnack(List<String> missing) {
    if (missing.isEmpty) return;
    final label = missing.length == 1
        ? 'Falta: ${missing.first}.'
        : 'Falta preencher: ${missing.join(', ')}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label)),
    );
  }

  static double? _parsePricePt(String raw) {
    final t = raw.trim().replaceAll(' ', '');
    if (t.isEmpty) return null;
    final normalized = t.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  /// Abre o detalhe sem importar `ProductDetailsPageWidget` (ciclo via `/index.dart`).
  void _openPublishedProductDetails(String productId) {
    final id = productId.trim();
    if (id.isEmpty || !mounted) return;
    context.pushNamed(
      'ProductDetails',
      queryParameters: <String, String>{
        'product_id': id,
      },
    );
  }

  Future<void> _pickPhotos() async {
    // Web (qualquer largura): input de ficheiros nativo — evita sheet partido no Hub.
    if (kIsWeb) {
      await _pickPhotosFromGallery();
      return;
    }
    final source = await _askPhotoSource();
    if (!mounted || source == null) return;
    if (source == _PhotoSource.gallery) {
      await _pickPhotosFromGallery();
      return;
    }
    await _pickPhotoFromCamera();
  }

  Future<void> _pickPhotosFromGallery() async {
    final remaining = _kMaxPhotos - _photoCount;
    if (remaining <= 0) return;

    try {
      final files = await FleaberGalleryPicker.pickImages(
        limit: remaining,
        imageQuality: 82,
      );
      if (files.isEmpty) return;

      final added = <_PhotoSlot>[];
      for (final x in files) {
        if (added.length + _photoCount >= _kMaxPhotos) break;
        final bytes = await x.readAsBytes();
        final name = x.name.isNotEmpty ? x.name : 'foto.jpg';
        added.add(_PhotoSlot(bytes, name));
      }
      if (added.isEmpty) return;
      safeSetState(() {
        _photos.addAll(added);
        _dirty = true;
      });
      if (added.length > 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${added.length} fotos adicionadas.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on FleaberGalleryPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          action: SnackBarAction(
            label: 'Definições',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir a galeria: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _pickPhotoFromCamera() async {
    if (_photoCount >= _kMaxPhotos) return;
    try {
      final photo = await FleaberGalleryPicker.pickCameraImage(
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      safeSetState(() {
        _photos.add(
          _PhotoSlot(bytes, photo.name.isNotEmpty ? photo.name : 'camera.jpg'),
        );
        _dirty = true;
      });
    } on FleaberGalleryPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          action: SnackBarAction(
            label: 'Definições',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir a câmara: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<_PhotoSource?> _askPhotoSource() async {
    if (_saving) return null;
    return showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(ctx).pop(_PhotoSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto agora'),
              subtitle: const Text('A foto entra diretamente no anúncio.'),
              onTap: () => Navigator.of(ctx).pop(_PhotoSource.camera),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _uploadPhotos() async {
    final uid = currentUserUid;
    if (uid.isEmpty) return [];

    final urls = <String>[];
    for (var i = 0; i < _photos.length; i++) {
      final slot = _photos[i];
      final prepared = await fleaberDownsampleForUpload(slot.bytes);
      final named = fleaberUploadFileName(slot.fileName, prepared);
      final safeName = named.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path =
          'product_photos/$uid/${DateTime.now().millisecondsSinceEpoch}_${i}_$safeName';

      final contentType = fleaberLooksLikePng(prepared)
          ? 'image/png'
          : (safeName.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg');
      await SupaFlow.client.storage.from('chat_media').uploadBinary(
            path,
            prepared,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
            ),
          );
      final url = SupaFlow.client.storage.from('chat_media').getPublicUrl(path);
      urls.add(url);
    }
    return urls;
  }

  String _normalizeRefForStorage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('#')) return t;
    if (RegExp(r'^\d+$').hasMatch(t)) {
      return '#${t.padLeft(3, '0')}';
    }
    return '#$t';
  }

  Future<String> _generateNextLiveRef() async {
    try {
      final rows = await ProductsTable().queryRows(
        queryFn: (q) => q.eqOrNull('seller_id', currentUserUid),
        limit: 500,
      );
      var maxN = 0;
      final digitRef = RegExp(r'^#?(\d+)$');
      for (final row in rows) {
        final raw = (row.refCode ?? '').trim().replaceAll(' ', '');
        if (raw.isEmpty) continue;
        final m = digitRef.firstMatch(raw);
        if (m != null) {
          final n = int.tryParse(m.group(1)!);
          if (n != null) maxN = math.max(maxN, n);
        }
      }
      return '#${(maxN + 1).toString().padLeft(3, '0')}';
    } catch (_) {
      final n = DateTime.now().millisecondsSinceEpoch % 1000;
      return '#${n.toString().padLeft(3, '0')}';
    }
  }

  Map<String, dynamic> _shippingWeightFields() {
    final raw = _weightKgController.text.trim().replaceAll(',', '.');
    final kg = double.tryParse(raw);
    if (kg != null && kg > 0) {
      // Peso em kg → escalão determinado automaticamente.
      final auto = FleaberDpdWeightBand.fromKg(kg);
      return {
        'shipping_weight_kg': kg,
        'shipping_weight_band': auto?.code,
      };
    }
    // Só escalão (sem kg exacto).
    final band = (_shippingWeightBand ?? '').trim();
    return {
      'shipping_weight_kg': null,
      'shipping_weight_band': band.isEmpty ? null : band,
    };
  }

  FleaberDpdWeightBand? _autoBandFromKgField() {
    final raw = _weightKgController.text.trim().replaceAll(',', '.');
    final kg = double.tryParse(raw);
    if (kg == null || kg <= 0) return null;
    return FleaberDpdWeightBand.fromKg(kg);
  }

  Widget _shippingWeightSection() {
    final autoBand = _autoBandFromKgField();
    final hasKg = autoBand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Peso para envio DPD',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _kBatataText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Indica o peso em kg ou escolhe um escalão. Basta uma das duas opções.',
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.35,
            color: _kBatataSubText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _weightKgController,
          style: GoogleFonts.inter(color: _kBatataText),
          cursorColor: _kTeal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            // Peso escrito → limpa escalão manual; o sistema calcula o escalão.
            if (_shippingWeightBand != null) {
              safeSetState(() => _shippingWeightBand = null);
            } else {
              safeSetState(() {});
            }
            _markDirty();
          },
          decoration: _fieldDecoration(
            'Peso aproximado (kg)',
            hint: 'ex. 1,5',
            dense: true,
            helperText: hasKg
                ? 'Escalão automático: ${autoBand.labelPt}'
                : 'Opcional se escolheres um escalão abaixo. Máx. 10 kg.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ou escalão DPD (sem peso exacto)',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kBatataText,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in FleaberDpdWeightBand.values)
              ChoiceChip(
                label: Text(b.labelPt),
                selected: !hasKg && _shippingWeightBand == b.code,
                onSelected: (_saving || _draftSaving || hasKg)
                    ? null
                    : (sel) {
                        safeSetState(() {
                          _shippingWeightBand = sel ? b.code : null;
                          if (sel) _weightKgController.clear();
                          _dirty = true;
                        });
                      },
                selectedColor: _kTeal.withValues(alpha: 0.18),
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kBatataText,
                ),
              ),
          ],
        ),
        if (hasKg) ...[
          const SizedBox(height: 6),
          Text(
            'Com peso em kg, o escalão «${autoBand.labelPt}» fica definido automaticamente.',
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.35,
              color: _kTeal,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          kFleaberDpdWeightSellerResponsibilityNotice,
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.35,
            color: _kBatataSubText,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _draftPayload({
    required String titleOut,
    required double priceVal,
    required List<String> imageUrls,
    required String? refStored,
    required String description,
  }) {
    return {
      'seller_id': currentUserUid,
      'title': titleOut,
      'price': priceVal,
      'image_urls': imageUrls,
      'ref_code': refStored,
      'category': _category,
      'state': _condition,
      'description': description.isEmpty ? null : description,
      'clothing_size': _isRoupaCategory ? _clothingSize : null,
      'gender': _isRoupaCategory ? _gender : null,
      'list_on_marketplace': _listOnMarketplace,
      'available_for_live': _availableForLive,
      'quantity': _quantity < 1 ? 1 : _quantity,
      'is_draft': true,
      ..._shippingWeightFields(),
    };
  }

  /// Guarda sem validações de publicação (permite campos incompletos).
  Future<bool> _saveDraft({bool showSnack = true}) async {
    FocusScope.of(context).unfocus();
    if (currentUserUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicia sessão para guardar o rascunho.')),
        );
      }
      return false;
    }

    final quantityRaw = _quantityController.text.trim();
    final parsedQuantity = int.tryParse(quantityRaw) ?? _quantity;
    _quantity = parsedQuantity < 1 ? 1 : parsedQuantity;

    final priceRaw = _model.priceTextController?.text.trim() ?? '';
    final priceVal = _parsePricePt(priceRaw) ?? 0;
    final title = _model.titleTextController?.text.trim() ?? '';
    final description = _model.descriptionTextController?.text.trim() ?? '';
    final refInput = _model.refTextController?.text.trim() ?? '';
    final refStored =
        refInput.isEmpty ? null : _normalizeRefForStorage(refInput);
    final titleOut = title.isEmpty ? '' : title;

    setState(() => _draftSaving = true);
    try {
      final newUrls = _photos.isNotEmpty ? await _uploadPhotos() : <String>[];
      final imageUrls = <String>[..._existingImageUrls, ...newUrls];
      final data = _draftPayload(
        titleOut: titleOut,
        priceVal: priceVal < 0 ? 0 : priceVal,
        imageUrls: imageUrls,
        refStored: refStored,
        description: description,
      );

      final editId = _editingProductId?.trim() ?? '';
      if (editId.isNotEmpty) {
        await ProductsTable().update(
          data: data,
          matchingRows: (q) => q.eqOrNull('id', editId),
        );
      } else {
        final created = await ProductsTable().insert(data);
        final id = created.id?.trim() ?? '';
        if (id.isNotEmpty) {
          _editingProductId = id;
          _editingIsDraft = true;
        }
      }

      if (!mounted) return true;
      safeSetState(() {
        _photos.clear();
        _existingImageUrls = imageUrls;
        _dirty = false;
        _editingIsDraft = true;
      });
      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Rascunho guardado. Podes continuar depois em Gestão de referências → Rascunhos.',
            ),
          ),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível guardar o rascunho. Tenta outra vez.'),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) safeSetState(() => _draftSaving = false);
    }
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final canDraft = _editingProductId == null ||
        _editingProductId!.trim().isEmpty ||
        _editingIsDraft;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Alterações por guardar',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          canDraft
              ? 'Queres guardar um rascunho antes de sair?'
              : 'Tens alterações por guardar neste anúncio publicado.',
          style: GoogleFonts.inter(fontSize: FleaHubSiteLayout.typeBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Continuar a editar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Descartar'),
          ),
          if (canDraft)
            FleaberPrimaryButton(
              label: 'Guardar rascunho',
              height: 40,
              width: 168,
              onPressed: () => Navigator.of(ctx).pop('save'),
            ),
        ],
      ),
    );
    if (!mounted) return false;
    if (action == null || action == 'stay') return false;
    if (action == 'discard') {
      safeSetState(() => _dirty = false);
      return true;
    }
    final ok = await _saveDraft(showSnack: true);
    return ok;
  }

  Future<void> _onBack() async {
    final ok = await _confirmLeaveIfDirty();
    if (!ok || !mounted) return;
    if (Navigator.of(context).canPop()) {
      context.safePop();
    } else {
      context.goNamed(HomePageWidget.routeName);
    }
  }

  Future<void> _onCancel() async {
    final ok = await _confirmLeaveIfDirty();
    if (!ok || !mounted) return;
    if (Navigator.of(context).canPop()) {
      context.safePop();
    } else {
      context.goNamed(HomePageWidget.routeName);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final quantityRaw = _quantityController.text.trim();
    final parsedQuantity = int.tryParse(quantityRaw) ?? _quantity;
    _quantity = parsedQuantity < 1 ? 1 : parsedQuantity;
    if (_quantityController.text != _quantity.toString()) {
      _quantityController.text = _quantity.toString();
    }

    if (currentUserUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sessão para publicar.')),
      );
      return;
    }

    final canSell =
        await SellerProfessionalService.canSell(currentUserUid);
    if (!canSell) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Novas vendas suspensas: conclui a verificação profissional '
            'em Definições → Dados profissionais (ou desactiva a declaração).',
          ),
        ),
      );
      return;
    }

    if (!_listOnMarketplace && !_availableForLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ativa "Listar no Marketplace" ou "Disponível para Live".'),
        ),
      );
      return;
    }

    final priceRaw = _model.priceTextController?.text.trim() ?? '';
    final priceVal = _parsePricePt(priceRaw);
    if (priceVal == null || priceVal < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O preço mínimo é 1,00 €.')),
      );
      return;
    }

    var refInput = _model.refTextController?.text.trim() ?? '';
    var refAssignedAuto = false;
    if (_availableForLive) {
      if (refInput.isEmpty) {
        refInput = await _generateNextLiveRef();
        refAssignedAuto = true;
        if (mounted) {
          _model.refTextController?.text = refInput;
        }
      }
    }

    final refStored =
        refInput.isEmpty ? null : _normalizeRefForStorage(refInput);

    final title = _model.titleTextController?.text.trim() ?? '';
    final description = _model.descriptionTextController?.text.trim() ?? '';

    final missing0 = _missingForStep0();
    final missing1 = _missingForStep1();
    if (missing0.isNotEmpty) {
      safeSetState(() => _formStep = 0);
      _showMissingFieldsSnack(missing0);
      return;
    }
    if (missing1.isNotEmpty) {
      safeSetState(() => _formStep = 1);
      _showMissingFieldsSnack(missing1);
      return;
    }

    if (_availableForLive && !_listOnMarketplace) {
      if (!_hasAnyPhotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Para Live, adiciona pelo menos uma foto.'),
          ),
        );
        return;
      }
    }

    if (_availableForLive && _listOnMarketplace && !_hasAnyPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Com Live ativo, adiciona pelo menos uma foto.'),
        ),
      );
      return;
    }

    var titleOut = title;
    if (titleOut.isEmpty && _availableForLive && !_listOnMarketplace) {
      final r = refStored ?? refInput;
      titleOut = r.isNotEmpty ? 'Artigo $r' : 'Artigo Live';
    }

    if (titleOut.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica um título.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final newUrls = _photos.isNotEmpty ? await _uploadPhotos() : <String>[];
      // Manter fotos já no anúncio + novas (não substituir ao editar).
      final imageUrls = <String>[
        ..._existingImageUrls,
        ...newUrls,
      ];

      final editId = _editingProductId?.trim() ?? '';
      if (editId.isNotEmpty) {
        await ProductsTable().update(
          data: {
            'title': titleOut,
            'price': priceVal,
            'image_urls': imageUrls,
            'ref_code': refStored,
            'category': _category,
            'state': _condition,
            'description': description.isEmpty ? null : description,
            'clothing_size': _isRoupaCategory ? _clothingSize : null,
            'gender': _isRoupaCategory ? _gender : null,
            'list_on_marketplace': _listOnMarketplace,
            'available_for_live': _availableForLive,
            'quantity': _quantity < 1 ? 1 : _quantity,
            'is_draft': false,
            ..._shippingWeightFields(),
          },
          matchingRows: (q) => q.eqOrNull('id', editId),
        );
        final rows = await ProductsTable().querySingleRow(
          queryFn: (q) => q.eqOrNull('id', editId),
        );
        if (!mounted || rows.isEmpty) return;
        if (_listOnMarketplace) {
          requestMarketplaceFeedRefresh();
        }
        if (mounted) safeSetState(() => _dirty = false);
        // Sem import de ProductDetails (ciclo via /index.dart).
        _openPublishedProductDetails(editId);
        return;
      }

      final created = await ProductsTable().insert({
        'seller_id': currentUserUid,
        'title': titleOut,
        'price': priceVal,
        'image_urls': newUrls,
        'ref_code': refStored,
        'category': _category,
        'state': _condition,
        'description': description.isEmpty ? null : description,
        'clothing_size': _isRoupaCategory ? _clothingSize : null,
        'gender': _isRoupaCategory ? _gender : null,
        'list_on_marketplace': _listOnMarketplace,
        'available_for_live': _availableForLive,
        'quantity': _quantity < 1 ? 1 : _quantity,
        'is_draft': false,
        ..._shippingWeightFields(),
      });

      if (!mounted) return;
      if (_listOnMarketplace) {
        requestMarketplaceFeedRefresh();
      }
      safeSetState(() => _dirty = false);

      final createdId = created.id?.trim() ?? '';
      _openPublishedProductDetails(createdId);

      if (refAssignedAuto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Referência Live atribuída: ${refStored ?? refInput}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro ao guardar. Verifica nomes das colunas (ex.: state, image_urls) na tabela products.',
          ),
        ),
      );
    } finally {
      if (mounted) safeSetState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SellerProductFormModel());
    _model.refTextController ??= TextEditingController();
    _model.refFocusNode ??= FocusNode();
    _model.titleTextController ??= TextEditingController();
    _model.titleFocusNode ??= FocusNode();
    _model.priceTextController ??= TextEditingController();
    _model.priceFocusNode ??= FocusNode();
    _model.descriptionTextController ??= TextEditingController();
    _model.descriptionFocusNode ??= FocusNode();
    _quantityController = TextEditingController(text: '1');
    _weightKgController = TextEditingController();
    _editingProductId = widget.editProductId?.trim();
    void attachDirty(TextEditingController? c) {
      c?.addListener(_markDirty);
    }
    attachDirty(_model.refTextController);
    attachDirty(_model.titleTextController);
    attachDirty(_model.priceTextController);
    attachDirty(_model.descriptionTextController);
    _quantityController.addListener(_markDirty);
    if (_editingProductId != null && _editingProductId!.isNotEmpty) {
      unawaited(_loadExistingProduct(_editingProductId!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  Future<void> _loadExistingProduct(String productId) async {
    setState(() => _loadingExisting = true);
    try {
      final rows = await ProductsTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', productId),
      );
      if (rows.isEmpty || !mounted) return;
      final p = rows.first;
      if (p.sellerId != currentUserUid) return;

      _model.titleTextController?.text = p.title ?? '';
      _model.descriptionTextController?.text = p.description ?? '';
      _model.refTextController?.text = p.refCode ?? '';
      _model.priceTextController?.text =
          (p.price ?? 0).toStringAsFixed(2).replaceAll('.', ',');
      _quantity = p.quantity < 1 ? 1 : p.quantity;
      _quantityController.text = '$_quantity';
      _category = p.category;
      _condition = p.state;
      _clothingSize = p.clothingSize;
      _gender = p.gender;
      _listOnMarketplace = p.listOnMarketplace ?? true;
      _availableForLive = p.availableForLive ?? false;
      _existingImageUrls = List<String>.from(p.imageUrls);
      _editingIsDraft = p.isDraft;
      // ZIP 140: reidratar peso / escalão na edição.
      final kg = p.shippingWeightKg;
      if (kg != null && kg > 0) {
        _weightKgController.text =
            kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 2)
                .replaceAll('.', ',');
        _shippingWeightBand = null;
      } else {
        _weightKgController.clear();
        final band = (p.shippingWeightBand ?? '').trim();
        _shippingWeightBand =
            band.isEmpty ? null : band;
      }
      if (mounted) {
        setState(() {
          _dirty = false;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _weightKgController.dispose();
    _model.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: FleaHubSiteLayout.typeSection,
          fontWeight: FontWeight.w700,
          color: _kBatataText,
          height: 1.3,
        ),
      ),
    );
  }

  /// Painel suave (não «cartão gigante») — agrupa secções no desktop.
  Widget _sectionPanel({
    required List<Widget> children,
    double marginBottom = 16,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: marginBottom),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _twoCol({
    required Widget left,
    required Widget right,
    double gap = 14,
    int leftFlex = 1,
    int rightFlex = 1,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              SizedBox(height: gap),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: gap),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final wide = _isWideDesktop(context);
    final twoStepUi = _showTwoStepUi(context);
    final photoRowHeight = wide ? 120.0 : 96.0;

    final editing = _editingProductId != null && _editingProductId!.isNotEmpty;
    final titleText = editing
        ? (_editingIsDraft ? 'Editar rascunho' : 'Editar anúncio')
        : 'Novo anúncio';

    final showDraftAction = !editing || _editingIsDraft;

    final formColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (wide) ...[
                _sectionPanel(
                  children: [
                    _sectionTitle('1. Fotografias, referência e título'),
                    Text(
                      'Fotos',
                      style: GoogleFonts.inter(
                        fontSize: FleaHubSiteLayout.typeSecondary,
                        fontWeight: FontWeight.w600,
                        color: _kBatataSubText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: photoRowHeight + 20,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFB),
                        borderRadius: FleaberRadius.circularMd,
                        border: Border.all(color: const Color(0xFFE4EAF0)),
                      ),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _existingImageUrls.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: DragTarget<String>(
                                onWillAcceptWithDetails: (d) {
                                  final data = d.data;
                                  return data.startsWith('e:') &&
                                      data != 'e:$i';
                                },
                                onAcceptWithDetails: (d) {
                                  final from = int.tryParse(
                                    d.data.replaceFirst('e:', ''),
                                  );
                                  if (from == null || from == i) return;
                                  safeSetState(() {
                                    final urls = List<String>.from(
                                      _existingImageUrls,
                                    );
                                    final item = urls.removeAt(from);
                                    final target = from < i ? i - 1 : i;
                                    urls.insert(target, item);
                                    _existingImageUrls = urls;
                                  });
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                  final thumb = _PhotoThumb(
                                    image:
                                        NetworkImage(_existingImageUrls[i]),
                                    size: photoRowHeight,
                                    onRemove: () => safeSetState(() {
                                      final urls = List<String>.from(
                                        _existingImageUrls,
                                      );
                                      urls.removeAt(i);
                                      _existingImageUrls = urls;
                                    }),
                                    canMoveLeft: i > 0,
                                    canMoveRight:
                                        i < _existingImageUrls.length - 1,
                                    highlightDropSlot:
                                        candidateData.isNotEmpty,
                                    onMoveLeft: i > 0
                                        ? () => safeSetState(() {
                                              final urls = List<String>.from(
                                                _existingImageUrls,
                                              );
                                              final item = urls.removeAt(i);
                                              urls.insert(i - 1, item);
                                              _existingImageUrls = urls;
                                            })
                                        : null,
                                    onMoveRight: i <
                                            _existingImageUrls.length - 1
                                        ? () => safeSetState(() {
                                              final urls = List<String>.from(
                                                _existingImageUrls,
                                              );
                                              final item = urls.removeAt(i);
                                              urls.insert(i + 1, item);
                                              _existingImageUrls = urls;
                                            })
                                        : null,
                                  );
                                  return LongPressDraggable<String>(
                                    data: 'e:$i',
                                    axis: Axis.horizontal,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Opacity(
                                        opacity: 0.9,
                                        child: SizedBox(
                                          width: photoRowHeight,
                                          height: photoRowHeight,
                                          child: ClipRRect(
                                            borderRadius:
                                                FleaberRadius.circularMd,
                                            child: Image.network(
                                              _existingImageUrls[i],
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color:
                                                    const Color(0xFFE8EEF0),
                                                child: const Icon(
                                                  Icons
                                                      .broken_image_outlined,
                                                  color: _kBatataSubText,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.35,
                                      child: thumb,
                                    ),
                                    child: thumb,
                                  );
                                },
                              ),
                            ),
                          for (var i = 0; i < _photos.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) => d.data != i,
                                onAcceptWithDetails: (d) {
                                  final from = d.data;
                                  if (from == i) return;
                                  safeSetState(() {
                                    final item = _photos.removeAt(from);
                                    final target = from < i ? i - 1 : i;
                                    _photos.insert(target, item);
                                  });
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                  final thumb = _PhotoThumb(
                                    image: MemoryImage(_photos[i].bytes),
                                    size: photoRowHeight,
                                    onRemove: () => safeSetState(
                                      () => _photos.removeAt(i),
                                    ),
                                    canMoveLeft: i > 0,
                                    canMoveRight: i < _photos.length - 1,
                                    highlightDropSlot:
                                        candidateData.isNotEmpty,
                                    onMoveLeft: i > 0
                                        ? () => safeSetState(() {
                                              final item =
                                                  _photos.removeAt(i);
                                              _photos.insert(i - 1, item);
                                            })
                                        : null,
                                    onMoveRight: i < _photos.length - 1
                                        ? () => safeSetState(() {
                                              final item =
                                                  _photos.removeAt(i);
                                              _photos.insert(i + 1, item);
                                            })
                                        : null,
                                  );
                                  return LongPressDraggable<int>(
                                    data: i,
                                    axis: Axis.horizontal,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Opacity(
                                        opacity: 0.9,
                                        child: SizedBox(
                                          width: photoRowHeight,
                                          height: photoRowHeight,
                                          child: ClipRRect(
                                            borderRadius:
                                                FleaberRadius.circularMd,
                                            child: Image.memory(
                                              _photos[i].bytes,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.35,
                                      child: thumb,
                                    ),
                                    child: thumb,
                                  );
                                },
                              ),
                            ),
                          if (_photoCount < _kMaxPhotos)
                            _AddPhotoTile(
                              size: photoRowHeight,
                              onTap: _saving ? null : _pickPhotos,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _twoCol(
                      leftFlex: 3,
                      rightFlex: 7,
                      left: TextField(
                        controller: _model.refTextController,
                        focusNode: _model.refFocusNode,
                        style: GoogleFonts.inter(color: _kBatataText),
                        cursorColor: _kTeal,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        decoration: _fieldDecoration(
                          'Referência',
                          hint: '#001',
                          helperText: _availableForLive
                              ? 'Obrigatório no Live. Se ficar vazio, geramos #001, #002…'
                              : 'Opcional se não usares Live.',
                          dense: true,
                        ),
                      ),
                      right: TextField(
                        controller: _model.titleTextController,
                        focusNode: _model.titleFocusNode,
                        style: GoogleFonts.inter(color: _kBatataText),
                        cursorColor: _kTeal,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          'Título',
                          hint: 'Ex.: Casaco de lã cinzento',
                          dense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _model.refTextController,
                  focusNode: _model.refFocusNode,
                  style: GoogleFonts.inter(color: _kBatataText),
                  cursorColor: _kTeal,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.none,
                  decoration: _fieldDecoration(
                    'Referência',
                    hint: '#001',
                    helperText: _availableForLive
                        ? 'Obrigatório no Live. Se ficar vazio, geramos #001, #002…'
                        : 'Opcional se não usares Live.',
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Fotos',
                  style: theme.labelLarge.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _existingImageUrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (d) {
                              final data = d.data;
                              return data.startsWith('e:') && data != 'e:$i';
                            },
                            onAcceptWithDetails: (d) {
                              final from = int.tryParse(
                                d.data.replaceFirst('e:', ''),
                              );
                              if (from == null || from == i) return;
                              safeSetState(() {
                                final urls =
                                    List<String>.from(_existingImageUrls);
                                final item = urls.removeAt(from);
                                final target = from < i ? i - 1 : i;
                                urls.insert(target, item);
                                _existingImageUrls = urls;
                              });
                            },
                            builder: (context, candidateData, rejectedData) {
                              final thumb = _PhotoThumb(
                                image: NetworkImage(_existingImageUrls[i]),
                                onRemove: () => safeSetState(() {
                                  final urls =
                                      List<String>.from(_existingImageUrls);
                                  urls.removeAt(i);
                                  _existingImageUrls = urls;
                                }),
                                canMoveLeft: i > 0,
                                canMoveRight:
                                    i < _existingImageUrls.length - 1,
                                highlightDropSlot: candidateData.isNotEmpty,
                                onMoveLeft: i > 0
                                    ? () => safeSetState(() {
                                          final urls = List<String>.from(
                                            _existingImageUrls,
                                          );
                                          final item = urls.removeAt(i);
                                          urls.insert(i - 1, item);
                                          _existingImageUrls = urls;
                                        })
                                    : null,
                                onMoveRight:
                                    i < _existingImageUrls.length - 1
                                        ? () => safeSetState(() {
                                              final urls = List<String>.from(
                                                _existingImageUrls,
                                              );
                                              final item = urls.removeAt(i);
                                              urls.insert(i + 1, item);
                                              _existingImageUrls = urls;
                                            })
                                        : null,
                              );
                              return LongPressDraggable<String>(
                                data: 'e:$i',
                                axis: Axis.horizontal,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Opacity(
                                    opacity: 0.9,
                                    child: SizedBox(
                                      width: 96,
                                      height: 96,
                                      child: ClipRRect(
                                        borderRadius: FleaberRadius.circularMd,
                                        child: Image.network(
                                          _existingImageUrls[i],
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            color: const Color(0xFFE8EEF0),
                                            child: const Icon(
                                              Icons.broken_image_outlined,
                                              color: _kBatataSubText,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: thumb,
                                ),
                                child: thumb,
                              );
                            },
                          ),
                        ),
                      for (var i = 0; i < _photos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: DragTarget<int>(
                            onWillAcceptWithDetails: (d) => d.data != i,
                            onAcceptWithDetails: (d) {
                              final from = d.data;
                              if (from == i) return;
                              safeSetState(() {
                                final item = _photos.removeAt(from);
                                final target = from < i ? i - 1 : i;
                                _photos.insert(target, item);
                              });
                            },
                            builder: (context, candidateData, rejectedData) {
                              final thumb = _PhotoThumb(
                                image: MemoryImage(_photos[i].bytes),
                                onRemove: () =>
                                    safeSetState(() => _photos.removeAt(i)),
                                canMoveLeft: i > 0,
                                canMoveRight: i < _photos.length - 1,
                                highlightDropSlot: candidateData.isNotEmpty,
                                onMoveLeft: i > 0
                                    ? () => safeSetState(() {
                                          final item = _photos.removeAt(i);
                                          _photos.insert(i - 1, item);
                                        })
                                    : null,
                                onMoveRight: i < _photos.length - 1
                                    ? () => safeSetState(() {
                                          final item = _photos.removeAt(i);
                                          _photos.insert(i + 1, item);
                                        })
                                    : null,
                              );
                              return LongPressDraggable<int>(
                                data: i,
                                axis: Axis.horizontal,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Opacity(
                                    opacity: 0.9,
                                    child: SizedBox(
                                      width: 96,
                                      height: 96,
                                      child: ClipRRect(
                                        borderRadius: FleaberRadius.circularMd,
                                        child: Image.memory(
                                          _photos[i].bytes,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: thumb,
                                ),
                                child: thumb,
                              );
                            },
                          ),
                        ),
                      if (_photoCount < _kMaxPhotos)
                        _AddPhotoTile(onTap: _saving ? null : _pickPhotos),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _model.titleTextController,
                  focusNode: _model.titleFocusNode,
                  style: GoogleFonts.inter(color: _kBatataText),
                  cursorColor: _kTeal,
                  textInputAction: TextInputAction.next,
                  decoration: _fieldDecoration(
                    'Título',
                    hint: 'Ex.: Casaco de lã cinzento',
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _sectionPanel(
                            marginBottom: 0,
                            children: [
                              _sectionTitle('2. Preço e quantidade'),
                              TextField(
                                controller: _model.priceTextController,
                                focusNode: _model.priceFocusNode,
                                style: GoogleFonts.inter(color: _kBatataText),
                                cursorColor: _kTeal,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d,\.]'),
                                  ),
                                ],
                                decoration: _fieldDecoration(
                                  'Preço',
                                  hint: '0,00',
                                  dense: true,
                                  suffix: const Padding(
                                    padding: EdgeInsets.only(right: 14, top: 12),
                                    child: Text(
                                      '€',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: Color(0xFF101518),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _quantityController,
                                style: GoogleFonts.inter(color: _kBatataText),
                                cursorColor: _kTeal,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (v) {
                                  final parsed = int.tryParse(v.trim()) ?? 1;
                                  if (parsed == _quantity) return;
                                  safeSetState(
                                    () =>
                                        _quantity = parsed < 1 ? 1 : parsed,
                                  );
                                },
                                decoration: _fieldDecoration(
                                  'Quantidade disponível',
                                  hint: '1',
                                  dense: true,
                                  helperText:
                                      'O comprador pode comprar várias unidades no checkout.',
                                ),
                              ),
                              const SizedBox(height: 12),
                              _shippingWeightSection(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: _sectionPanel(
                            marginBottom: 0,
                            children: [
                              _sectionTitle('3. Canais de venda'),
                              Material(
                                color: const Color(0xFFF7FAFB),
                                borderRadius: FleaberRadius.circularMd,
                                child: SwitchListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  title: Text(
                                    'Disponível para Live',
                                    style: GoogleFonts.inter(
                                      fontSize: FleaHubSiteLayout.typeBody,
                                      fontWeight: FontWeight.w600,
                                      color: _kBatataText,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Aparece no carrossel do próximo directo.',
                                    style: GoogleFonts.inter(
                                      fontSize: FleaHubSiteLayout.typeCaption,
                                      color: _kBatataSubText,
                                    ),
                                  ),
                                  value: _availableForLive,
                                  activeThumbColor: _kTeal,
                                  onChanged: (_saving || _draftSaving)
                                      ? null
                                      : (v) => safeSetState(() {
                                            _availableForLive = v;
                                            _dirty = true;
                                          }),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Material(
                                color: const Color(0xFFF7FAFB),
                                borderRadius: FleaberRadius.circularMd,
                                child: SwitchListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  title: Text(
                                    'Listar no Marketplace',
                                    style: GoogleFonts.inter(
                                      fontSize: FleaHubSiteLayout.typeBody,
                                      fontWeight: FontWeight.w600,
                                      color: _kBatataText,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Venda estilo catálogo.',
                                    style: GoogleFonts.inter(
                                      fontSize: FleaHubSiteLayout.typeCaption,
                                      color: _kBatataSubText,
                                    ),
                                  ),
                                  value: _listOnMarketplace,
                                  activeThumbColor: _kTeal,
                                  onChanged: (_saving || _draftSaving)
                                      ? null
                                      : (v) => safeSetState(() {
                                            _listOnMarketplace = v;
                                            _dirty = true;
                                            if (!v) _formStep = 0;
                                          }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _model.priceTextController,
                  focusNode: _model.priceFocusNode,
                  style: GoogleFonts.inter(color: _kBatataText),
                  cursorColor: _kTeal,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]')),
                  ],
                  decoration: _fieldDecoration(
                    'Preço',
                    hint: '0,00',
                    suffix: const Padding(
                      padding: EdgeInsets.only(right: 14, top: 14),
                      child: Text(
                        '€',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF101518),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _quantityController,
                  style: GoogleFonts.inter(color: _kBatataText),
                  cursorColor: _kTeal,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim()) ?? 1;
                    if (parsed == _quantity) return;
                    safeSetState(() => _quantity = parsed < 1 ? 1 : parsed);
                  },
                  decoration: _fieldDecoration(
                    'Quantidade disponível',
                    hint: '1',
                    helperText:
                        'O comprador pode comprar várias unidades no checkout.',
                  ),
                ),
                const SizedBox(height: 12),
                _shippingWeightSection(),
                const SizedBox(height: 18),
              ],
              if (!wide) ...[
                Text(
                  'Canais de venda',
                  style: theme.labelLarge.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 4),
                Material(
                  color: Colors.white,
                  borderRadius: FleaberRadius.circularMd,
                  child: SwitchListTile(
                    title: Text(
                      'Disponível para Live',
                      style: theme.bodyMedium.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                        color: const Color(0xFF101518),
                      ),
                    ),
                    subtitle: Text(
                      'Aparece no carrossel do próximo directo.',
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: const Color(0xFF57636C),
                      ),
                    ),
                    value: _availableForLive,
                    activeThumbColor: _kTeal,
                    onChanged: _saving
                        ? null
                        : (v) => safeSetState(() => _availableForLive = v),
                  ),
                ),
                const SizedBox(height: 6),
                Material(
                  color: Colors.white,
                  borderRadius: FleaberRadius.circularMd,
                  child: SwitchListTile(
                    title: Text(
                      'Listar no Marketplace',
                      style: theme.bodyMedium.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w500),
                        color: const Color(0xFF101518),
                      ),
                    ),
                    subtitle: Text(
                      'Venda estilo catálogo.',
                      style: theme.bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: const Color(0xFF57636C),
                      ),
                    ),
                    value: _listOnMarketplace,
                    activeThumbColor: _kTeal,
                    onChanged: _saving
                        ? null
                        : (v) => safeSetState(() {
                            _listOnMarketplace = v;
                            if (!v) _formStep = 0;
                          }),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (twoStepUi) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StepChip(
                      label: '1. Artigo',
                      active: _formStep == 0,
                      done: _formStep > 0,
                    ),
                    const SizedBox(width: 8),
                    _StepChip(
                      label: '2. Descrição',
                      active: _formStep == 1,
                      done: false,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (wide && _listOnMarketplace) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _sectionPanel(
                            marginBottom: 0,
                            children: [
                              _sectionTitle('4. Categoria e estado'),
                              DropdownButtonFormField<String?>(
                                value: _category,
                                style: GoogleFonts.inter(color: _kBatataText),
                                dropdownColor: Colors.white,
                                decoration: _fieldDecoration(
                                  'Categoria',
                                  dense: true,
                                  helperText:
                                      'Obrigatório para publicar no Marketplace',
                                ),
                                items: _kCategories
                                    .map(
                                      (c) => DropdownMenuItem<String?>(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => safeSetState(() {
                                  _category = v;
                                  if (v != _kRoupaCategory) {
                                    _clothingSize = null;
                                    _gender = null;
                                  }
                                }),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String?>(
                                value: _condition,
                                style: GoogleFonts.inter(color: _kBatataText),
                                dropdownColor: Colors.white,
                                decoration: _fieldDecoration(
                                  'Estado',
                                  dense: true,
                                ),
                                items: _kConditions
                                    .map(
                                      (c) => DropdownMenuItem<String?>(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    safeSetState(() => _condition = v),
                              ),
                              if (_isRoupaCategory) ...[
                                const SizedBox(height: 12),
                                _twoCol(
                                  left: DropdownButtonFormField<String?>(
                                    value: _clothingSize,
                                    style:
                                        GoogleFonts.inter(color: _kBatataText),
                                    dropdownColor: Colors.white,
                                    decoration: _fieldDecoration(
                                      'Tamanho',
                                      dense: true,
                                    ),
                                    items: _kClothingSizes
                                        .map(
                                          (s) => DropdownMenuItem<String?>(
                                            value: s,
                                            child: Text(s),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => safeSetState(
                                      () => _clothingSize = v,
                                    ),
                                  ),
                                  right: DropdownButtonFormField<String?>(
                                    value: _gender,
                                    style:
                                        GoogleFonts.inter(color: _kBatataText),
                                    dropdownColor: Colors.white,
                                    decoration: _fieldDecoration(
                                      'Género',
                                      dense: true,
                                    ),
                                    items: _kGenders
                                        .map(
                                          (g) => DropdownMenuItem<String?>(
                                            value: g,
                                            child: Text(g),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        safeSetState(() => _gender = v),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: _sectionPanel(
                            marginBottom: 0,
                            children: [
                              _sectionTitle('5. Descrição'),
                              TextField(
                                controller: _model.descriptionTextController,
                                focusNode: _model.descriptionFocusNode,
                                style: GoogleFonts.inter(color: _kBatataText),
                                cursorColor: _kTeal,
                                minLines: 6,
                                maxLines: 10,
                                decoration: _fieldDecoration(
                                  'Descrição',
                                  hint:
                                      'Medidas, defeitos, história do artigo…',
                                  helperText:
                                      'Ajuda o comprador a decidir com confiança',
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (!twoStepUi || _formStep == 0) ...[
                if (_listOnMarketplace) ...[
                  Text(
                    'Detalhes do Marketplace',
                    style: theme.labelLarge.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      color: const Color(0xFF57636C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: _category,
                    style: GoogleFonts.inter(color: _kBatataText),
                    dropdownColor: Colors.white,
                    decoration: _fieldDecoration(
                      'Categoria',
                      helperText: 'Obrigatório para publicar no Marketplace',
                    ),
                    items: _kCategories
                        .map(
                          (c) => DropdownMenuItem<String?>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => safeSetState(() {
                      _category = v;
                      if (v != _kRoupaCategory) {
                        _clothingSize = null;
                        _gender = null;
                      }
                    }),
                  ),
                  if (_isRoupaCategory) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      value: _clothingSize,
                      style: GoogleFonts.inter(color: _kBatataText),
                      dropdownColor: Colors.white,
                      decoration: _fieldDecoration('Tamanho'),
                      items: _kClothingSizes
                          .map(
                            (s) => DropdownMenuItem<String?>(
                              value: s,
                              child: Text(s),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          safeSetState(() => _clothingSize = v),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      value: _gender,
                      style: GoogleFonts.inter(color: _kBatataText),
                      dropdownColor: Colors.white,
                      decoration: _fieldDecoration('Género'),
                      items: _kGenders
                          .map(
                            (g) => DropdownMenuItem<String?>(
                              value: g,
                              child: Text(g),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => safeSetState(() => _gender = v),
                    ),
                  ],
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    value: _condition,
                    style: GoogleFonts.inter(color: _kBatataText),
                    dropdownColor: Colors.white,
                    decoration: _fieldDecoration('Estado'),
                    items: _kConditions
                        .map(
                          (c) => DropdownMenuItem<String?>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => safeSetState(() => _condition = v),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
              // Fluxo único: descrição no mesmo ecrã (marketplace).
              if (!wide && _listOnMarketplace) ...[
                Text(
                  'Descrição',
                  style: theme.labelLarge.override(
                    font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _model.descriptionTextController,
                  focusNode: _model.descriptionFocusNode,
                  style: GoogleFonts.inter(color: _kBatataText),
                  cursorColor: _kTeal,
                  minLines: 4,
                  maxLines: 8,
                  decoration: _fieldDecoration(
                    'Descrição',
                    hint: 'Medidas, defeitos, história do artigo…',
                    helperText: 'Ajuda o comprador a decidir com confiança',
                  ),
                ),
                const SizedBox(height: 18),
              ],
              SizedBox(height: wide ? 8 : 24),
              if (wide) ...[
                _desktopFooterActions(
                  editing: editing,
                  showDraft: showDraftAction,
                ),
              ] else ...[
                _mobileFooterActions(
                  editing: editing,
                  showDraft: showDraftAction,
                ),
              ],
            ],
    );

    final formScroll = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 28 : 16,
        wide ? 8 : 8,
        wide ? 28 : 16,
        wide ? 48 : 28,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? _kDesktopFormMaxWidth : double.infinity,
          ),
          child: formColumn,
        ),
      ),
    );

    final loadingOverlay = _loadingExisting
        ? const ColoredBox(
            color: Color(0xAAFFFFFF),
            child: Center(child: CircularProgressIndicator()),
          )
        : null;

    final scaffold = wide
        ? Scaffold(
            key: scaffoldKey,
            backgroundColor: FleaberColors.bgTint,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FleaHubSiteTopBar(),
                  const FleaHubTopBarBleed(),
                  _desktopTitleRow(titleText),
                  Expanded(
                    child: Stack(
                      children: [
                        formScroll,
                        if (loadingOverlay != null) loadingOverlay,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        : Scaffold(
            key: scaffoldKey,
            backgroundColor: FleaberColors.bgTint,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: FleaberColors.bgTint,
              foregroundColor: const Color(0xFF101518),
              leading: IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: (_saving || _draftSaving) ? null : _onBack,
              ),
              title: Text(
                titleText,
                style: theme.titleMedium.override(
                  font: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  color: const Color(0xFF101518),
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                if (showDraftAction)
                  TextButton(
                    onPressed: (_saving || _draftSaving)
                        ? null
                        : () => _saveDraft(),
                    child: Text(
                      'Rascunho',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: _kTeal,
                      ),
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  formScroll,
                  if (loadingOverlay != null) loadingOverlay,
                ],
              ),
            ),
          );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmLeaveIfDirty();
        if (ok && mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: scaffold,
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    String? helperText,
    Widget? suffix,
    bool dense = false,
    int helperMaxLines = 3,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      suffix: suffix,
      labelStyle: GoogleFonts.inter(
        fontSize: dense ? FleaHubSiteLayout.typeSecondary : null,
        color: _kBatataSubText,
      ),
      floatingLabelStyle: GoogleFonts.inter(color: _kTeal),
      hintStyle: GoogleFonts.inter(
        fontSize: FleaHubSiteLayout.typeSecondary,
        color: FleaberColors.muted,
      ),
      helperStyle: GoogleFonts.inter(
        fontSize: FleaHubSiteLayout.typeSecondary,
        height: 1.35,
        color: _kBatataSubText,
      ),
      isDense: dense,
      filled: true,
      fillColor: Colors.white,
      contentPadding: dense
          ? const EdgeInsets.fromLTRB(14, 14, 14, 14)
          : const EdgeInsets.fromLTRB(16, 18, 16, 18),
      border: OutlineInputBorder(
        borderRadius: FleaberRadius.circularMd,
        borderSide: const BorderSide(color: Color(0xFFE8EDF2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: FleaberRadius.circularMd,
        borderSide: const BorderSide(color: Color(0xFFE8EDF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: FleaberRadius.circularMd,
        borderSide: const BorderSide(color: _kTeal, width: 1.4),
      ),
    );
  }

  /// Cabeçalho de página abaixo da topbar Hub (só desktop).
  Widget _desktopTitleRow(String titleText) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 24, 4),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kDesktopFormMaxWidth),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back_rounded),
                color: const Color(0xFF101518),
                onPressed: (_saving || _draftSaving) ? null : _onBack,
              ),
              Expanded(
                child: Text(
                  titleText,
                  style: GoogleFonts.inter(
                    fontSize: FleaHubSiteLayout.typeDisplay,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF101518),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rodapé telemóvel: Cancelar | Rascunho | Publicar (mesmo contrato que desktop).
  Widget _mobileFooterActions({
    required bool editing,
    required bool showDraft,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FleaberPrimaryButton(
          width: double.infinity,
          label: editing
              ? (_editingIsDraft ? 'Publicar anúncio' : 'Guardar alterações')
              : 'Publicar',
          loading: _saving,
          letterSpacing: 0.2,
          onPressed: (_saving || _draftSaving) ? null : _submit,
        ),
        if (showDraft) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: (_saving || _draftSaving) ? null : () => _saveDraft(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTeal,
              side: const BorderSide(color: _kTeal, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _draftSaving ? 'A guardar…' : 'Guardar rascunho',
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeBody,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        TextButton(
          onPressed: (_saving || _draftSaving) ? null : _onCancel,
          child: Text(
            'Cancelar',
            style: GoogleFonts.inter(
              fontSize: FleaHubSiteLayout.typeBody,
              fontWeight: FontWeight.w600,
              color: _kBatataSubText,
            ),
          ),
        ),
      ],
    );
  }

  /// Rodapé desktop: Cancelar | Guardar rascunho | Publicar.
  Widget _desktopFooterActions({
    required bool editing,
    required bool showDraft,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: (_saving || _draftSaving) ? null : _onCancel,
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(
                fontSize: FleaHubSiteLayout.typeBody,
                fontWeight: FontWeight.w600,
                color: _kBatataSubText,
              ),
            ),
          ),
          if (showDraft)
            OutlinedButton(
              onPressed:
                  (_saving || _draftSaving) ? null : () => _saveDraft(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTeal,
                side: const BorderSide(color: _kTeal, width: 1.2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _draftSaving ? 'A guardar…' : 'Guardar rascunho',
                style: GoogleFonts.inter(
                  fontSize: FleaHubSiteLayout.typeBody,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          FleaberPrimaryButton(
            width: 200,
            label: editing
                ? (_editingIsDraft ? 'Publicar anúncio' : 'Guardar alterações')
                : 'Publicar anúncio',
            loading: _saving,
            letterSpacing: 0.4,
            onPressed: (_saving || _draftSaving) ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.image,
    required this.onRemove,
    required this.canMoveLeft,
    required this.canMoveRight,
    this.size = 96,
    this.highlightDropSlot = false,
    this.onMoveLeft,
    this.onMoveRight,
  });

  final ImageProvider image;
  final VoidCallback onRemove;
  final bool canMoveLeft;
  final bool canMoveRight;
  final double size;
  final bool highlightDropSlot;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: FleaberRadius.circularMd,
        border: Border.all(
          color: highlightDropSlot ? _kTeal : Colors.transparent,
          width: 2,
        ),
        boxShadow: highlightDropSlot
            ? [
                BoxShadow(
                  color: _kTeal.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: FleaberRadius.circularMd,
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: const Color(0xFFE8EEF0),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: _kBatataSubText,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Row(
              children: [
                _ReorderArrow(
                  icon: Icons.chevron_left_rounded,
                  enabled: canMoveLeft,
                  onTap: onMoveLeft,
                ),
                const SizedBox(width: 4),
                _ReorderArrow(
                  icon: Icons.chevron_right_rounded,
                  enabled: canMoveRight,
                  onTap: onMoveRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReorderArrow extends StatelessWidget {
  const _ReorderArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Colors.black54 : Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? _kTeal
        : done
            ? const Color(0xFFE0F2F3)
            : Colors.white;
    final fg = active
        ? Colors.white
        : done
            ? _kTeal
            : _kBatataSubText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active || done ? _kTeal : const Color(0xFFE8EDF2),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap, this.size = 96});

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: FleaberRadius.circularMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularMd,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: const Color(0xFFD5DCE3)),
          ),
          child: Icon(
            Icons.add_rounded,
            size: size >= 110 ? 36 : 32,
            color: onTap == null ? const Color(0xFFB0B8C1) : const Color(0xFF57636C),
          ),
        ),
      ),
    );
  }
}

enum _PhotoSource { gallery, camera }
