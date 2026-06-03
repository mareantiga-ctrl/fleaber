import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/marketplace_feed_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '/product_details/product_details_page_widget.dart';
import '/utils/fleaber_gallery_picker.dart';
import '/widgets/fleaber_primary_button.dart';

import 'seller_product_form_model.dart';
export 'seller_product_form_model.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';

const _kTeal = Color(0xFF007782);
const _kBatataText = Color(0xFF101518);
const _kBatataSubText = Color(0xFF57636C);
const _kMaxPhotos = 10;

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
  int _quantity = 1;
  List<String> _existingImageUrls = const [];
  String? _editingProductId;

  bool get _isRoupaCategory => _category == _kRoupaCategory;

  bool get _usesTwoSteps => _listOnMarketplace;

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
      if (_isRoupaCategory) {
        if (_clothingSize == null) missing.add('Tamanho');
        if (_gender == null) missing.add('Género');
      }
    }
    if (_availableForLive && _photos.isEmpty) {
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

  void _goToNextStep() {
    FocusScope.of(context).unfocus();
    final missing = _missingForStep0();
    if (missing.isNotEmpty) {
      _showMissingFieldsSnack(missing);
      return;
    }
    safeSetState(() => _formStep = 1);
  }

  static double? _parsePricePt(String raw) {
    final t = raw.trim().replaceAll(' ', '');
    if (t.isEmpty) return null;
    final normalized = t.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _pickPhotos() async {
    final source = await _askPhotoSource();
    if (!mounted || source == null) return;
    if (source == _PhotoSource.gallery) {
      await _pickPhotosFromGallery();
      return;
    }
    await _pickPhotoFromCamera();
  }

  Future<void> _pickPhotosFromGallery() async {
    final remaining = _kMaxPhotos - _photos.length;
    if (remaining <= 0) return;

    try {
      final files = await FleaberGalleryPicker.pickImages(
        limit: remaining,
        imageQuality: 82,
      );
      if (files.isEmpty) return;

      final added = <_PhotoSlot>[];
      for (final x in files) {
        if (added.length + _photos.length >= _kMaxPhotos) break;
        final bytes = await x.readAsBytes();
        final name = x.name.isNotEmpty ? x.name : 'foto.jpg';
        added.add(_PhotoSlot(bytes, name));
      }
      if (added.isEmpty) return;
      safeSetState(() => _photos.addAll(added));
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
    if (_photos.length >= _kMaxPhotos) return;
    try {
      final photo = await FleaberGalleryPicker.pickCameraImage(
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      safeSetState(() {
        _photos.add(_PhotoSlot(bytes, photo.name.isNotEmpty ? photo.name : 'camera.jpg'));
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
      final safeName = slot.fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path =
          'product_photos/$uid/${DateTime.now().millisecondsSinceEpoch}_${i}_$safeName';

      await SupaFlow.client.storage.from('chat_media').uploadBinary(
            path,
            slot.bytes,
            fileOptions: const FileOptions(upsert: false),
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
      if (_photos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Para Live, adiciona pelo menos uma foto.'),
          ),
        );
        return;
      }
    }

    if (_availableForLive && _listOnMarketplace && _photos.isEmpty) {
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
      final imageUrls = newUrls.isNotEmpty
          ? newUrls
          : (_existingImageUrls.isNotEmpty ? _existingImageUrls : newUrls);

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
        context.pushReplacement(
          ProductDetailsPageWidget.routePath,
          extra: ProductDetailsPageWidget.routeExtraForProduct(rows.first),
        );
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
      });

      if (!mounted) return;
      if (_listOnMarketplace) {
        requestMarketplaceFeedRefresh();
      }

      context.pushReplacement(
        ProductDetailsPageWidget.routePath,
        extra: ProductDetailsPageWidget.routeExtraForProduct(created),
      );

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
    _editingProductId = widget.editProductId?.trim();
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
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FleaberColors.bgTint,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: FleaberColors.bgTint,
          foregroundColor: const Color(0xFF101518),
          title: Text(
            _editingProductId != null && _editingProductId!.isNotEmpty
                ? 'Editar artigo'
                : 'Novo artigo',
            style: theme.titleMedium.override(
              font: GoogleFonts.inter(fontWeight: FontWeight.w700),
              color: const Color(0xFF101518),
              letterSpacing: 0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              bytes: _photos[i].bytes,
                              onRemove: () => safeSetState(() => _photos.removeAt(i)),
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
                    if (_photos.length < _kMaxPhotos)
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
                decoration: _fieldDecoration('Título', hint: 'Ex.: Casaco de lã cinzento'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _model.priceTextController,
                focusNode: _model.priceFocusNode,
                style: GoogleFonts.inter(color: _kBatataText),
                cursorColor: _kTeal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              if (_usesTwoSteps) ...[
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
              if (!_usesTwoSteps || _formStep == 0) ...[
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
                      onChanged: (v) => safeSetState(() => _clothingSize = v),
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
              if (_usesTwoSteps && _formStep == 1) ...[
                Text(
                  'Descrição e publicação',
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
              const SizedBox(height: 24),
              if (_usesTwoSteps && _formStep == 0) ...[
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'PROSSEGUIR',
                  onPressed: _saving ? null : _goToNextStep,
                ),
              ] else ...[
                if (_usesTwoSteps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => safeSetState(() => _formStep = 0),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Voltar'),
                      ),
                    ),
                  ),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: _editingProductId != null && _editingProductId!.isNotEmpty
                      ? 'GUARDAR ALTERAÇÕES'
                      : 'CONCLUIR ANÚNCIO',
                  loading: _saving,
                  letterSpacing: 0.4,
                  onPressed: _saving ? null : _submit,
                ),
              ],
            ],
            ),
          ),
              if (_loadingExisting)
                const ColoredBox(
                  color: Color(0xAAFFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    String? helperText,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      suffix: suffix,
      labelStyle: GoogleFonts.inter(color: _kBatataSubText),
      floatingLabelStyle: GoogleFonts.inter(color: _kTeal),
      hintStyle: GoogleFonts.inter(color: FleaberColors.muted),
      helperStyle: GoogleFonts.inter(color: _kBatataSubText),
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
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
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.bytes,
    required this.onRemove,
    required this.canMoveLeft,
    required this.canMoveRight,
    this.highlightDropSlot = false,
    this.onMoveLeft,
    this.onMoveRight,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;
  final bool canMoveLeft;
  final bool canMoveRight;
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
            child: Image.memory(
              bytes,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
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
  const _AddPhotoTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: FleaberRadius.circularMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: FleaberRadius.circularMd,
        child: Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: FleaberRadius.circularMd,
            border: Border.all(color: const Color(0xFFD5DCE3)),
          ),
          child: Icon(
            Icons.add_rounded,
            size: 32,
            color: onTap == null ? const Color(0xFFB0B8C1) : const Color(0xFF57636C),
          ),
        ),
      ),
    );
  }
}

enum _PhotoSource { gallery, camera }
