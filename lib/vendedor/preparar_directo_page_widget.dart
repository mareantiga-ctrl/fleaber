import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/live_prep_catalog_loader.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';
import '/utils/live_catalog_prep_service.dart';
import '/utils/live_ref_lineage_prep_gate.dart';
import '/utils/live_ref_scheme.dart';
import '/widgets/live_ref_chip_editor_sheet.dart';
import '/widgets/batata_cached_image.dart';

import '/utils/fleaber_colors.dart';
import '/hub/seller/hub_seller_sheet.dart';

const _kTeal = Color(0xFF007782);

/// Letras e números no prefixo (ex.: C, XRO, B12).
final _kLiveRefPrefixFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]*'));

/// Escolher artigos e referências antes de entrar em [CriarDirectoPageWidget].
class PrepararDirectoPageWidget extends StatefulWidget {
  const PrepararDirectoPageWidget({super.key});

  static String routeName = 'PrepararDirecto';
  static String routePath = '/prepararDirecto';

  @override
  State<PrepararDirectoPageWidget> createState() =>
      _PrepararDirectoPageWidgetState();
}

class _PrepararDirectoPageWidgetState extends State<PrepararDirectoPageWidget>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<ProductsRow> _products = const [];
  List<LiveRefScheme> _refSchemes = const [];
  final _scrollController = ScrollController();
  final _catalogScrollController = ScrollController();
  final _searchController = TextEditingController();

  late TabController _tabController;

  final _prefixController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _excludeController = TextEditingController();
  final Set<int> _draftExclude = <int>{};
  bool _excludePickerOpen = false;
  /// Linha de edição em baixo; fica oculta após gravar (disquete) até carregar em «+».
  bool _refDraftRowVisible = true;
  Map<String, LiveRefChipDetail> _refChipDetails = const {};

  /// Selecção live persistida (IDs), independente da página / pesquisa.
  final Set<String> _selectedLiveIds = <String>{};

  /// REFs normalizadas dos seleccionados (BD completa) — gate de lineage.
  Set<String> _selectedRefKeys = <String>{};

  LivePrepCatalogCursor? _catalogCursor;
  bool _catalogHasMore = true;
  String _activeSearch = '';
  int _loadGeneration = 0;
  Timer? _searchDebounce;

  /// Última medição da 1.ª página (ms) — evidência de desempenho.
  int? lastInitialLoadMs;

  static const double _colPrefix = 46;
  static const double _colNum = 52;
  static const double _colExcludeBtn = 36;
  static const double _colActions = 88;
  static const double _colGap = 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _catalogScrollController.addListener(_onCatalogScroll);
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    _scrollController.dispose();
    _catalogScrollController.removeListener(_onCatalogScroll);
    _catalogScrollController.dispose();
    _searchController.dispose();
    _prefixController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  Map<String, int> _displayQtyByProductId = const {};

  void _onCatalogScroll() {
    if (!_catalogHasMore || _loadingMore || _loading) return;
    final pos = _catalogScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) {
      unawaited(_loadMoreCatalog());
    }
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      final next = raw.trim();
      if (next == _activeSearch) return;
      unawaited(_reloadCatalog(search: next));
    });
  }

  void _mergeSelectedFromRows(Iterable<ProductsRow> rows) {
    for (final row in rows) {
      final id = row.id?.trim() ?? '';
      if (id.isEmpty) continue;
      if (row.availableForLive == true) {
        _selectedLiveIds.add(id);
      }
    }
  }

  Future<void> _load() async {
    final uid = currentUserUid;
    if (uid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Inicia sessão para transmitir.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await LiveCatalogPrepService.purgePrepRefsFromLastSession(sellerId: uid);
      final schemes = await LivePrepRefs.readSchemes();
      final details = await LivePrepRefDetails.readAll();
      unawaited(LiveCatalogPrepService.ensureDraftLive(sellerId: uid));

      final selected = await LivePrepCatalogLoader.fetchSelectedProductIds(
        sellerId: uid,
      );
      if (!selected.complete && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aviso: há demasiados artigos seleccionados para carregar de uma vez. '
              'Confirma a selecção antes de continuar.',
            ),
          ),
        );
      }
      _selectedLiveIds
        ..clear()
        ..addAll(selected.ids);
      final refs = await LivePrepCatalogLoader.fetchSelectedNormalizedRefKeys(
        sellerId: uid,
      );
      if (!refs.complete && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aviso: não foi possível carregar todas as referências seleccionadas.',
            ),
          ),
        );
      }
      _selectedRefKeys = refs.keys;

      await _reloadCatalog(
        search: _activeSearch,
        preserveSchemes: true,
        schemes: schemes,
        details: details,
        initial: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reloadCatalog({
    required String search,
    bool preserveSchemes = false,
    List<LiveRefScheme>? schemes,
    Map<String, LiveRefChipDetail>? details,
    bool initial = false,
  }) async {
    final uid = currentUserUid;
    if (uid.isEmpty) return;
    final gen = ++_loadGeneration;
    _activeSearch = search;

    setState(() {
      _loading = true;
      _error = null;
      if (!preserveSchemes) {
        _products = const [];
      }
      _catalogCursor = null;
      _catalogHasMore = true;
      _loadingMore = false;
    });

    try {
      final page = await LivePrepCatalogLoader.fetchPage(
        sellerId: uid,
        after: null,
        searchQuery: search,
      );
      if (!mounted || gen != _loadGeneration) return;

      _mergeSelectedFromRows(page.rows);
      // Reflect selection flags from the authoritative set.
      final synced = page.rows.map((row) {
        final id = row.id?.trim() ?? '';
        final copy = ProductsRow(Map<String, dynamic>.from(row.data));
        copy.availableForLive = id.isNotEmpty && _selectedLiveIds.contains(id);
        return copy;
      }).toList();

      setState(() {
        _products = synced;
        _displayQtyByProductId = Map<String, int>.from(page.qtyByProductId);
        _catalogCursor = page.nextCursor;
        _catalogHasMore = page.hasMore;
        _loading = false;
        lastInitialLoadMs = page.elapsedMs;
        if (schemes != null) _refSchemes = schemes;
        if (details != null) _refChipDetails = details;
      });

      if (initial && kDebugMode) {
        debugPrint(
          '[PrepararDirecto] initial catalog page ms=${page.elapsedMs} '
          'kept=${synced.length} hasMore=${page.hasMore}',
        );
      }

      // Se a 1.ª página ficou curta por filtro de stock, puxar mais automaticamente.
      if (synced.length < 12 && page.hasMore) {
        unawaited(_loadMoreCatalog());
      }
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreCatalog() async {
    if (_loadingMore || !_catalogHasMore || _loading) return;
    final uid = currentUserUid;
    if (uid.isEmpty) return;
    final gen = _loadGeneration;
    final after = _catalogCursor;
    if (after == null && _products.isNotEmpty) {
      // Sem cursor não avançamos (evita repetir a 1.ª página).
      setState(() => _catalogHasMore = false);
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await LivePrepCatalogLoader.fetchPage(
        sellerId: uid,
        after: after,
        searchQuery: _activeSearch,
      );
      if (!mounted || gen != _loadGeneration) return;

      _mergeSelectedFromRows(page.rows);
      final existing = _products.map((p) => p.id?.trim() ?? '').toSet();
      final appended = <ProductsRow>[];
      final qty = Map<String, int>.from(_displayQtyByProductId);
      for (final row in page.rows) {
        final id = row.id?.trim() ?? '';
        if (id.isEmpty || existing.contains(id)) continue;
        final copy = ProductsRow(Map<String, dynamic>.from(row.data));
        copy.availableForLive = _selectedLiveIds.contains(id);
        appended.add(copy);
        final q = page.qtyByProductId[id];
        if (q != null) qty[id] = q;
        existing.add(id);
      }

      setState(() {
        _products = [..._products, ...appended];
        _displayQtyByProductId = qty;
        _catalogCursor = page.nextCursor;
        _catalogHasMore = page.hasMore;
        _loadingMore = false;
      });

      if (_products.length < 12 && page.hasMore) {
        unawaited(_loadMoreCatalog());
      }
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar mais artigos: $e')),
      );
    }
  }

  void _syncExcludeToController() {
    final sorted = _draftExclude.toList()..sort();
    _excludeController.text = sorted.join(', ');
  }

  void _clearRefDraftForm() {
    _prefixController.clear();
    _fromController.clear();
    _toController.clear();
    _excludeController.clear();
    setState(() {
      _draftExclude.clear();
      _excludePickerOpen = false;
    });
  }

  String _refLabelForNumber(int n) {
    final scheme = _currentDraftRefScheme();
    if (scheme == null) return '#$n';
    return scheme.formatRef(n);
  }

  Future<void> _openRefChipEditor(int n) async {
    final label = _refLabelForNumber(n);
    await _openRefChipEditorForLabel(label);
  }

  Future<void> _openRefChipEditorForScheme(LiveRefScheme scheme, int n) async {
    await _openRefChipEditorForLabel(scheme.formatRef(n));
  }

  Future<void> _openRefChipEditorForLabel(String label) async {
    final key = LivePrepRefDetails.normalizeRefKey(label);
    final creating = !_refChipDetails.containsKey(key);
    final saved = await showLiveRefChipEditorSheet(
      context: context,
      refLabel: label,
      initial: _refChipDetails[key] ?? const LiveRefChipDetail(),
      creatingNew: creating,
    );
    if (saved == null || !mounted) return;
    await LivePrepRefDetails.save(key, saved.detail);
    final ok = await LiveRefLineagePrepGate.resolveRef(
      context: context,
      sellerId: currentUserUid,
      refCode: label,
      detail: saved.detail,
    );
    if (!ok || !mounted) return;
    final details = await LivePrepRefDetails.readAll();
    if (!mounted) return;
    setState(() => _refChipDetails = details);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Referência $label actualizada.')),
    );
  }

  void _loadSchemeIntoDraft(LiveRefScheme scheme) {
    _prefixController.text = scheme.normalizedPrefix;
    _fromController.text = '${scheme.from}';
    _toController.text = '${scheme.to}';
    _draftExclude
      ..clear()
      ..addAll(scheme.exclude);
    _syncExcludeToController();
  }

  Future<void> _startEditScheme(int index) async {
    if (index < 0 || index >= _refSchemes.length) return;
    final scheme = _refSchemes[index];
    await LivePrepRefs.removeAt(index);
    final schemes = await LivePrepRefs.readSchemes();
    if (!mounted) return;
    _loadSchemeIntoDraft(scheme);
    setState(() {
      _refSchemes = schemes;
      _refDraftRowVisible = true;
      _excludePickerOpen = true;
    });
  }

  String _stripLeadingZeros(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final n = int.tryParse(t);
    if (n == null) return t;
    return n.toString();
  }

  void _normalizeNumericField(TextEditingController c) {
    final normalized = _stripLeadingZeros(c.text);
    if (c.text != normalized) {
      c.text = normalized;
      c.selection = TextSelection.collapsed(offset: normalized.length);
    }
  }

  Future<void> _toggleLive(ProductsRow row, bool value) async {
    final id = row.id;
    if (id == null || id.isEmpty) return;
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final previous = row.availableForLive == true;

    final optimistic = ProductsRow(Map<String, dynamic>.from(row.data));
    optimistic.availableForLive = value;
    final refKey = LivePrepRefDetails.normalizeRefKey(row.refCode ?? '');
    setState(() {
      if (value) {
        _selectedLiveIds.add(id);
        if (refKey.isNotEmpty) _selectedRefKeys.add(refKey);
      } else {
        _selectedLiveIds.remove(id);
        // REF pode existir noutro seleccionado — refrescar no continue/load.
        if (refKey.isNotEmpty) {
          final still = _products.any(
            (p) {
              final pid = p.id?.trim() ?? '';
              if (pid.isEmpty || pid == id || !_selectedLiveIds.contains(pid)) {
                return false;
              }
              return LivePrepRefDetails.normalizeRefKey(p.refCode ?? '') ==
                  refKey;
            },
          );
          if (!still) _selectedRefKeys.remove(refKey);
        }
      }
      _products = List<ProductsRow>.from(_products);
      _products[index] = optimistic;
      // Ordem da lista = ordem estável do servidor (created_at/id). Não
      // reordenar por available_for_live (evita saltos / omissões).
    });

    try {
      await ProductsTable().update(
        data: {'available_for_live': value},
        matchingRows: (q) => q.eqOrNull('id', id),
      );
      await LiveCatalogPrepService.setProductInCatalog(
        productId: id,
        inCatalog: value,
      );
    } catch (e) {
      if (!mounted) return;
      final reverted = ProductsRow(Map<String, dynamic>.from(row.data));
      reverted.availableForLive = previous;
      setState(() {
        if (previous) {
          _selectedLiveIds.add(id);
          if (refKey.isNotEmpty) _selectedRefKeys.add(refKey);
        } else {
          _selectedLiveIds.remove(id);
          if (refKey.isNotEmpty) _selectedRefKeys.remove(refKey);
        }
        _products = List<ProductsRow>.from(_products);
        final i = _products.indexWhere((p) => p.id == id);
        if (i >= 0) _products[i] = reverted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível actualizar: $e')),
      );
    }
  }

  LiveRefScheme? _parseCurrentRefScheme() {
    _normalizeNumericField(_fromController);
    _normalizeNumericField(_toController);
    _syncExcludeToController();
    return LiveRefScheme.tryParse(
      prefixRaw: _prefixController.text,
      fromRaw: _fromController.text,
      toRaw: _toController.text,
      excludeRaw: _excludeController.text,
    );
  }

  /// Grava a linha actual na lista. Só [addAnother] mantém/abre linha de rascunho em baixo.
  Future<void> _commitCurrentRefLine({required bool addAnother}) async {
    final scheme = _parseCurrentRefScheme();
    if (scheme == null || scheme.spanCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Indica números válidos: «De» e «Até» (ex.: De 1, Até 100).',
          ),
        ),
      );
      return;
    }
    if (scheme.spanCount > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Intervalo demasiado grande (máx. 5000 referências).'),
        ),
      );
      return;
    }

    final duplicate = _refSchemes.any(
      (s) =>
          s.normalizedPrefix == scheme.normalizedPrefix &&
          s.from == scheme.from &&
          s.to == scheme.to,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este intervalo já está na lista.'),
        ),
      );
      return;
    }

    await LivePrepRefs.appendScheme(scheme);
    final schemes = await LivePrepRefs.readSchemes();
    if (!mounted) return;

    if (addAnother) {
      setState(() {
        _refSchemes = schemes;
        _refDraftRowVisible = true;
        _excludePickerOpen = false;
      });
      _clearRefDraftForm();
    } else {
      setState(() {
        _refSchemes = schemes;
        _refDraftRowVisible = false;
        _excludePickerOpen = false;
      });
      _clearRefDraftForm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: kDebugMode
              ? const Duration(seconds: 10)
              : const Duration(seconds: 4),
          content: Semantics(
            identifier: 'prep_snack_ref_saved',
            label: 'Gravado: ${scheme.displayLabel()}',
            child: Text(
              'Gravado: ${scheme.displayLabel()} (${scheme.spanCount} refs).',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openNewRefDraftLine() async {
    if (!_refDraftRowVisible) {
      setState(() => _refDraftRowVisible = true);
      _clearRefDraftForm();
      return;
    }
    await _commitCurrentRefLine(addAnother: true);
  }

  Future<void> _removeScheme(int index) async {
    await LivePrepRefs.removeAt(index);
    final schemes = await LivePrepRefs.readSchemes();
    if (!mounted) return;
    setState(() => _refSchemes = schemes);
  }

  void _openCreateProduct() {
    context.pushNamed(SellerProductFormWidget.routeName).then((_) => _load());
  }

  Future<bool> _flushPendingRefSchemeFromForm() async {
    if (!_refDraftRowVisible) return false;

    _normalizeNumericField(_fromController);
    _normalizeNumericField(_toController);
    _syncExcludeToController();

    final scheme = LiveRefScheme.tryParse(
      prefixRaw: _prefixController.text,
      fromRaw: _fromController.text,
      toRaw: _toController.text,
      excludeRaw: _excludeController.text,
    );
    if (scheme == null || scheme.spanCount <= 0) return false;
    if (scheme.spanCount > 5000) return false;

    final duplicate = _refSchemes.any(
      (s) =>
          s.normalizedPrefix == scheme.normalizedPrefix &&
          s.from == scheme.from &&
          s.to == scheme.to,
    );
    if (duplicate) return false;

    await LivePrepRefs.appendScheme(scheme);
    _clearRefDraftForm();
    final schemes = await LivePrepRefs.readSchemes();
    if (mounted) setState(() => _refSchemes = schemes);
    return true;
  }

  Future<void> _continueToLive() async {
    await _flushPendingRefSchemeFromForm();

    // Selecção completa na BD (não só a página visível / pesquisa actual).
    final selected = await LivePrepCatalogLoader.fetchSelectedProductIds(
      sellerId: currentUserUid,
    );
    if (!selected.complete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível carregar toda a selecção (limite de segurança). '
            'Reduz o número de artigos marcados e tenta de novo.',
          ),
        ),
      );
      return;
    }
    final selectedIds = selected.ids;
    final selectedRefs =
        await LivePrepCatalogLoader.fetchSelectedNormalizedRefKeys(
      sellerId: currentUserUid,
    );
    if (!selectedRefs.complete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível validar todas as referências seleccionadas. '
            'Reduz a selecção e tenta de novo.',
          ),
        ),
      );
      return;
    }
    _selectedLiveIds
      ..clear()
      ..addAll(selectedIds);
    _selectedRefKeys = selectedRefs.keys;

    final schemes = await LivePrepRefs.readSchemes();
    if (mounted) setState(() => _refSchemes = schemes);

    if (selectedIds.isEmpty && schemes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Semantics(
            identifier: 'prep_snack_need_item',
            label:
                'Tens de ter pelo menos um artigo no catálogo ou uma referência criada.',
            child: const Text(
              'Tens de ter pelo menos um artigo no catálogo ou uma referência criada.',
            ),
          ),
        ),
      );
      return;
    }

    await LiveCatalogPrepService.reconcileDraftToSelectedProducts(
      selectedProductIds: selectedIds,
      sellerId: currentUserUid,
    );

    final refsToResolve = LiveRefLineagePrepGate.refsFromSchemes(
      schemes,
      skipRef: (ref) => _productHasRefForPrep(ref),
    );
    if (refsToResolve.isNotEmpty) {
      final details = await LivePrepRefDetails.readAll();
      if (!mounted) return;
      final resolved = await LiveRefLineagePrepGate.resolveRefsForPrep(
        context: context,
        sellerId: currentUserUid,
        refCodes: refsToResolve,
        refDetails: details,
      );
      if (!resolved || !mounted) return;
    }

    if (!mounted) return;
    context.pushNamed(CriarDirectoPageWidget.routeName);
  }

  /// Considera seleccionados **fora** da página actual (conjunto BD).
  bool _productHasRefForPrep(String ref) {
    final want = LivePrepRefDetails.normalizeRefKey(ref);
    if (want.isEmpty) return false;
    if (_selectedRefKeys.contains(want)) return true;
    return _products.any(
      (p) {
        final id = p.id?.trim() ?? '';
        if (id.isEmpty || !_selectedLiveIds.contains(id)) return false;
        return LivePrepRefDetails.normalizeRefKey(p.refCode ?? '') == want;
      },
    );
  }

  Widget _compactRefField(String text, double? width) {
    final field = Container(
      width: width == null || width == double.infinity ? double.infinity : width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F7),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(color: const Color(0xFF57636C), fontSize: 12),
      ),
    );
    if (width == null || width == double.infinity) return field;
    return SizedBox(width: width, child: field);
  }

  Widget _refHeaderCell({
    required String label,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: const Color(0xFF57636C),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  InputDecoration _compactRefInputDecoration({String? hint}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF98A1AA)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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

  LiveRefScheme? _currentDraftRefScheme() => _parseCurrentRefScheme();

  List<int> _numbersInDraftRange({int max = 200}) {
    final from = int.tryParse(_stripLeadingZeros(_fromController.text));
    final to = int.tryParse(_stripLeadingZeros(_toController.text));
    if (from == null || to == null || from <= 0 || to < from) return const [];
    final total = to - from + 1;
    final limit = total > max ? max : total;
    return List<int>.generate(limit, (i) => from + i);
  }

  void _pruneDraftExclude() {
    final allowed = _numbersInDraftRange(max: 10000).toSet();
    _draftExclude.removeWhere((n) => !allowed.contains(n));
  }

  Widget _refTableHeaderRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _colPrefix,
          child: _refHeaderCell(
            label: 'Pref.',
            tooltip: 'Letras ou números no início da referência (até 3).',
          ),
        ),
        const SizedBox(width: _colGap),
        Expanded(
          child: _refHeaderCell(
            label: 'De',
            tooltip: 'Primeiro número do intervalo.',
          ),
        ),
        const SizedBox(width: _colGap),
        Expanded(
          child: _refHeaderCell(
            label: 'Até',
            tooltip: 'Último número do intervalo.',
          ),
        ),
        const SizedBox(width: _colGap),
        SizedBox(
          width: _colExcludeBtn,
          child: _refHeaderCell(
            label: 'Exc.',
            tooltip: 'Abre a lista para excluir referências do intervalo.',
          ),
        ),
        SizedBox(width: _colActions),
      ],
    );
  }

  Widget _refExampleRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.65,
          child: Row(
            children: [
              _compactRefField('A', _colPrefix),
              const SizedBox(width: _colGap),
              Expanded(child: _compactRefField('1', double.infinity)),
              const SizedBox(width: _colGap),
              Expanded(child: _compactRefField('99999', double.infinity)),
              const SizedBox(width: _colGap),
              SizedBox(
                width: _colExcludeBtn,
                child: _compactRefField('…', _colExcludeBtn),
              ),
              SizedBox(width: _colActions),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refCommittedRow(LiveRefScheme scheme, int index) {
    final prefix = scheme.normalizedPrefix;
    final exCount = scheme.exclude.length;
    final exLabel = exCount == 0
        ? '0 exclusões'
        : '$exCount exclusão${exCount == 1 ? '' : 'ões'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        identifier: 'prep_ref_row_$index',
        label: '${scheme.from}-${scheme.to}',
        onLongPress: scheme.from == scheme.to
            ? () => unawaited(_openRefChipEditorForScheme(scheme, scheme.from))
            : null,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _compactRefField(prefix.isEmpty ? '—' : prefix, _colPrefix),
          const SizedBox(width: _colGap),
          Expanded(child: _compactRefField('${scheme.from}', double.infinity)),
          const SizedBox(width: _colGap),
          Expanded(child: _compactRefField('${scheme.to}', double.infinity)),
          const SizedBox(width: _colGap),
          Expanded(child: _compactRefField(exLabel, double.infinity)),
          SizedBox(
            width: _colActions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  identifier: 'prep_ref_edit_$index',
                  button: true,
                  label: 'Editar linha ${scheme.from}-${scheme.to}',
                  onTap: () {
                    if (scheme.from == scheme.to) {
                      unawaited(
                        _openRefChipEditorForScheme(scheme, scheme.from),
                      );
                    } else {
                      _startEditScheme(index);
                    }
                  },
                  child: ExcludeSemantics(
                    child: IconButton(
                  tooltip: 'Editar linha',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    if (scheme.from == scheme.to) {
                      unawaited(
                        _openRefChipEditorForScheme(scheme, scheme.from),
                      );
                    } else {
                      _startEditScheme(index);
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: _kTeal,
                ),
                  ),
                ),
                Semantics(
                  identifier: 'prep_ref_delete_$index',
                  button: true,
                  label: 'Remover linha',
                  onTap: () => unawaited(_removeScheme(index)),
                  child: ExcludeSemantics(
                    child: IconButton(
                  tooltip: 'Remover linha',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _removeScheme(index),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: const Color(0xFF98A1AA),
                ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _refNumberChip(int n, bool excluded) {
    final draft = _currentDraftRefScheme();
    final label = draft?.formatRef(n).replaceFirst('#', '') ?? '$n';
    final refKey = LivePrepRefDetails.normalizeRefKey(label);
    final hasDetail = _refChipDetails.containsKey(refKey);

    return GestureDetector(
      onLongPress: () => _openRefChipEditor(n),
      child: FilterChip(
        label: Text(hasDetail ? '$label •' : label),
        selected: excluded,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        selectedColor: const Color(0xFFFFE7EA),
        backgroundColor: hasDetail
            ? const Color(0xFFE8F7F8)
            : const Color(0xFFEAF5F6),
        labelStyle: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: excluded ? FontWeight.w700 : FontWeight.w500,
          color: excluded ? const Color(0xFFB71C1C) : const Color(0xFF101518),
        ),
        side: BorderSide(
          color: excluded
              ? const Color(0xFFEF9A9A)
              : hasDetail
                  ? const Color(0xFF80CBC4)
                  : const Color(0xFFB8D5D8),
        ),
        onSelected: (_) {
          setState(() {
            if (_draftExclude.contains(n)) {
              _draftExclude.remove(n);
            } else {
              _draftExclude.add(n);
            }
            _syncExcludeToController();
          });
        },
      ),
    );
  }

  Widget _refExcludePickerCell() {
    final rangeNumbers = _numbersInDraftRange();
    final enabled = rangeNumbers.isNotEmpty;

    return SizedBox(
      width: _colExcludeBtn,
      height: 40,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE0E3E7)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled
              ? () => setState(() => _excludePickerOpen = !_excludePickerOpen)
              : null,
          child: Center(
            child: Icon(
              _excludePickerOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: enabled
                  ? const Color(0xFF57636C)
                  : const Color(0xFF98A1AA),
            ),
          ),
        ),
      ),
    );
  }

  Widget _refDraftActionsRow({required LiveRefScheme? draft}) {
    return SizedBox(
      width: _colActions,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Semantics(
            identifier: 'prep_ref_save',
            button: true,
            label: 'Gravar intervalo',
            enabled: draft != null,
            onTap: draft == null
                ? null
                : () => unawaited(_commitCurrentRefLine(addAnother: false)),
            child: ExcludeSemantics(
              child: IconButton(
            tooltip: 'Gravar intervalo',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: draft == null
                ? null
                : () => _commitCurrentRefLine(addAnother: false),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF5F6),
              foregroundColor: _kTeal,
            ),
            icon: const Icon(Icons.save_outlined, size: 18),
          ),
            ),
          ),
          Semantics(
            identifier: 'prep_ref_add_line',
            button: true,
            label: 'Adicionar outra linha',
            onTap: () => unawaited(_openNewRefDraftLine()),
            child: ExcludeSemantics(
              child: IconButton(
            tooltip: 'Adicionar outra linha',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () => _openNewRefDraftLine(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF3F6F7),
              foregroundColor: const Color(0xFF57636C),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _semCatalogoTab() {
    final draft = _currentDraftRefScheme();
    final rangeNumbers = _numbersInDraftRange();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: [
        Semantics(
          identifier: 'prep_sem_catalogo_hint',
          label:
              'Cria referências numéricas para vender no directo sem artigos no catálogo.',
          child: Text(
            'Cria referências numéricas para vender no directo sem artigos no catálogo.',
            style: GoogleFonts.inter(
              color: const Color(0xFF57636C),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _refTableHeaderRow(),
                const SizedBox(height: 8),
                _refExampleRow(),
                ...List.generate(
                  _refSchemes.length,
                  (i) => _refCommittedRow(_refSchemes[i], i),
                ),
                if (_refSchemes.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Divider(height: 1, color: Color(0xFFE0E7EA)),
                  ),
                if (_refDraftRowVisible) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _colPrefix,
                        child: TextField(
                          controller: _prefixController,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            _kLiveRefPrefixFormatter,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration: _compactRefInputDecoration(),
                        ),
                      ),
                      const SizedBox(width: _colGap),
                      Expanded(
                        child: Semantics(
                          identifier: 'prep_ref_from',
                          label: 'prep_ref_from',
                          textField: true,
                          value: _fromController.text,
                          onSetText: (text) {
                            _fromController.text = text;
                            _normalizeNumericField(_fromController);
                            _pruneDraftExclude();
                            setState(() {});
                          },
                          child: ExcludeSemantics(
                            child: TextField(
                          controller: _fromController,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          onChanged: (_) {
                            _normalizeNumericField(_fromController);
                            _pruneDraftExclude();
                            setState(() {});
                          },
                          decoration: _compactRefInputDecoration(),
                        ),
                          ),
                        ),
                      ),
                      const SizedBox(width: _colGap),
                      Expanded(
                        child: Semantics(
                          identifier: 'prep_ref_to',
                          label: 'prep_ref_to',
                          textField: true,
                          value: _toController.text,
                          onSetText: (text) {
                            _toController.text = text;
                            _normalizeNumericField(_toController);
                            _pruneDraftExclude();
                            setState(() {});
                          },
                          child: ExcludeSemantics(
                            child: TextField(
                          controller: _toController,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          onChanged: (_) {
                            _normalizeNumericField(_toController);
                            _pruneDraftExclude();
                            setState(() {});
                          },
                          decoration: _compactRefInputDecoration(),
                        ),
                          ),
                        ),
                      ),
                      const SizedBox(width: _colGap),
                      _refExcludePickerCell(),
                      _refDraftActionsRow(draft: draft),
                    ],
                  ),
                  if (_excludePickerOpen) ...[
                    const SizedBox(height: 10),
                    if (rangeNumbers.isEmpty)
                      Text(
                        'Preenche Prefixo, De e Até para escolher exclusões.',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF57636C),
                          fontSize: 12,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: rangeNumbers
                            .map(
                              (n) => _refNumberChip(
                                n,
                                _draftExclude.contains(n),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      identifier: 'prep_ref_add_line',
                      button: true,
                      label: 'Adicionar outra linha',
                      onTap: () => unawaited(_openNewRefDraftLine()),
                      child: ExcludeSemantics(
                        child: IconButton(
                      tooltip: 'Adicionar outra linha',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openNewRefDraftLine,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F6F7),
                        foregroundColor: const Color(0xFF57636C),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 22),
                    ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meuCatalogoTab() {
    final emptySearch =
        _products.isEmpty && _activeSearch.isNotEmpty && !_loading;
    final emptyCatalog =
        _products.isEmpty && _activeSearch.isEmpty && !_loading;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 480) {
          unawaited(_loadMoreCatalog());
        }
        return false;
      },
      child: ListView.builder(
        controller: _catalogScrollController,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
        itemCount: _products.length + 3,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kTeal.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Recomendado — artigos com foto, título e preço vendem mais em directo.',
                    style: GoogleFonts.inter(
                      color: _kTeal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Pesquisar por nome ou referência',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF98A1AA),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar pesquisa',
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EEF0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EEF0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kTeal, width: 1.4),
                    ),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
                if (_selectedLiveIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_selectedLiveIds.length} seleccionado(s) para o directo'
                    '${_activeSearch.isNotEmpty ? ' (mantidos na pesquisa)' : ''}',
                    style: GoogleFonts.inter(
                      color: _kTeal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Artigos com anúncio',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Os marcados para Live aparecem primeiro. Scroll para carregar mais.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF57636C),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          }
          if (index == 1) {
            if (emptyCatalog) {
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFE082)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF8A6D00),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ainda não tens artigos no catálogo. Cria um anúncio para '
                            'apresentares produtos no directo — é a forma mais clara para '
                            'os compradores.',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF5C4A00),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _catalogCreateCard(),
                ],
              );
            }
            if (emptySearch) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Nenhum artigo corresponde à pesquisa.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF57636C),
                    fontSize: 13,
                  ),
                ),
              );
            }
            return _catalogCreateCard();
          }

          final productIndex = index - 2;
          if (productIndex >= 0 && productIndex < _products.length) {
            return _productTile(_products[productIndex]);
          }

          // Footer: create card + loading more / end.
          return Column(
            children: [
              if (_products.isNotEmpty) ...[
                const SizedBox(height: 4),
                _catalogCreateCard(),
                const SizedBox(height: 12),
              ],
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: _kTeal,
                      ),
                    ),
                  ),
                )
              else if (!_catalogHasMore && _products.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Fim da lista',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF98A1AA),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: FleaberColors.bgTint,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101518),
        title: Text(
          'Artigos do directo',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        bottom: _loading || _error != null
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: _kTeal,
                unselectedLabelColor: const Color(0xFF57636C),
                indicatorColor: _kTeal,
                indicatorWeight: 2.5,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(
                    child: Semantics(
                      identifier: 'prep_tab_meu_catalogo',
                      button: true,
                      label: 'Meu Catálogo',
                      child: ListenableBuilder(
                        listenable: _tabController,
                        builder: (context, _) {
                          final selected = _tabController.index == 0;
                          final labelColor = selected
                              ? _kTeal
                              : const Color(0xFF57636C);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Meu Catálogo',
                                style: GoogleFonts.inter(
                                  color: labelColor,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Recomendado',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFB8860B),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Tab(
                    child: Semantics(
                      identifier: 'prep_tab_sem_catalogo',
                      button: true,
                      label: 'Sem catálogo',
                      child: ListenableBuilder(
                        listenable: _tabController,
                        builder: (context, _) {
                          final selected = _tabController.index == 1;
                          return Text(
                            'Sem catálogo',
                            style: GoogleFonts.inter(
                              color: selected
                                  ? _kTeal
                                  : const Color(0xFF57636C),
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + keyboardInset),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: Semantics(
              identifier: 'prep_continuar',
              button: true,
              label: 'Continuar para o directo',
              onTap: () => unawaited(_continueToLive()),
              child: ExcludeSemantics(
                child: FilledButton(
                  onPressed: _continueToLive,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Continuar para o directo',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: HubSellerHubCard(
                        compact: true,
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: _kTeal,
                        onRefresh: _load,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _meuCatalogoTab(),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _semCatalogoTab(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _productTile(ProductsRow row) {
    final forLive = row.availableForLive == true;
    final photos = row.imageUrls;
    final thumb = photos.isNotEmpty ? photos.first : null;
    final ref = (row.refCode ?? '').trim();
    final title = (row.title ?? '').trim();
    final pid = row.id?.trim() ?? '';
    final displayQty = pid.isNotEmpty
        ? (_displayQtyByProductId[pid] ?? row.quantity)
        : row.quantity;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggleLive(row, !forLive),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: forLive ? _kTeal : const Color(0xFFE6EEF0),
                width: forLive ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: thumb != null
                        ? BatataCachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                          )
                        : ColoredBox(
                            color: const Color(0xFFE6EEF0),
                            child: Icon(
                              forLive
                                  ? Icons.live_tv_rounded
                                  : Icons.inventory_2_outlined,
                              color: forLive ? _kTeal : const Color(0xFF57636C),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (forLive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kTeal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'No directo',
                            style: GoogleFonts.inter(
                              color: _kTeal,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      Text(
                        title.isNotEmpty ? title : 'Sem título',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (ref.isNotEmpty)
                        Text(
                          ref.startsWith('#') ? ref : '#$ref',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF57636C),
                            fontSize: 12,
                          ),
                        ),
                      if (displayQty > 1)
                        Text(
                          'Quantidade: $displayQty',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF57636C),
                            fontSize: 12,
                          ),
                        )
                      else if (displayQty < 1)
                        Text(
                          'Sem stock (rifa / reserva)',
                          style: GoogleFonts.inter(
                            color: FleaberColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: forLive,
                  activeThumbColor: _kTeal,
                  onChanged: (v) => _toggleLive(row, v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalogCreateCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openCreateProduct,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE6EEF0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFFEAF5F6),
                ),
                child: const Icon(Icons.add_circle_rounded, color: _kTeal, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Criar novo artigo',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Artigos com foto, título e preço fazem até 30% mais vendas em directo.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF57636C),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A1AA),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
