import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/dpd_pudo_service.dart';
import '/utils/fleaber_colors.dart';
import '/utils/pt_postal.dart';
import '/widgets/fleaber_primary_button.dart';

/// Folha para o comprador escolher um ponto Pickup DPD (MyPudo).
Future<DpdPudoPoint?> showDpdPickupPickerSheet(
  BuildContext context, {
  required String initialZip,
  required String initialCity,
}) {
  return showModalBottomSheet<DpdPudoPoint>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DpdPickupPickerBody(
      initialZip: initialZip,
      initialCity: initialCity,
    ),
  );
}

class _DpdPickupPickerBody extends StatefulWidget {
  const _DpdPickupPickerBody({
    required this.initialZip,
    required this.initialCity,
  });

  final String initialZip;
  final String initialCity;

  @override
  State<_DpdPickupPickerBody> createState() => _DpdPickupPickerBodyState();
}

class _DpdPickupPickerBodyState extends State<_DpdPickupPickerBody> {
  late final TextEditingController _zip;
  late final TextEditingController _city;
  final FocusNode _zipFocus = FocusNode();
  final FocusNode _cityFocus = FocusNode();
  bool _loading = false;
  String? _error;
  List<DpdPudoPoint> _points = const [];

  /// Localidade preenchida automaticamente para o CP actual (se houver).
  String? _autoCityLabel;
  String? _autoCityForZip;

  @override
  void initState() {
    super.initState();
    _zip = TextEditingController(
      text: normalizePtPostalCode(widget.initialZip) ?? widget.initialZip,
    );
    _city = TextEditingController(text: widget.initialCity);
    if ((normalizePtPostalCode(_zip.text) ?? '').isNotEmpty ||
        _city.text.trim().length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _zip.dispose();
    _city.dispose();
    _zipFocus.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _onZipChanged(String raw) async {
    final n = normalizePtPostalCode(raw);
    if (n != null && n != _zip.text.trim()) {
      _zip.value = TextEditingValue(
        text: n,
        selection: TextSelection.collapsed(offset: n.length),
      );
    }
    final zipNow = normalizePtPostalCode(_zip.text) ?? _zip.text.trim();

    // Sempre limpar localidade antiga ao mudar o CP — nunca pesquisar com par velho.
    if (_city.text.isNotEmpty) {
      setState(() {
        _city.text = '';
        _autoCityLabel = null;
        _autoCityForZip = null;
      });
    } else {
      _autoCityLabel = null;
      _autoCityForZip = null;
    }

    if (!isValidPtPostalCode(zipNow)) return;

    final look = await lookupPtPostal(zipNow);
    if (!mounted) return;
    // Se o utilizador já mudou o CP outra vez, ignorar resultado antigo.
    final still = normalizePtPostalCode(_zip.text) ?? _zip.text.trim();
    if (still != zipNow) return;

    if (look != null) {
      setState(() {
        _city.text = look.locality;
        _autoCityLabel = look.locality;
        _autoCityForZip = zipNow;
      });
    }
  }

  void _onCityChanged(String raw) {
    final zipNow = normalizePtPostalCode(_zip.text);
    // Cidade editada ≠ auto-resolvida → limpar CP (não misturar zonas).
    if (zipNow != null &&
        _autoCityForZip == zipNow &&
        _autoCityLabel != null &&
        raw.trim().toLowerCase() != _autoCityLabel!.toLowerCase()) {
      setState(() {
        _zip.text = '';
        _autoCityLabel = null;
        _autoCityForZip = null;
      });
    }
  }

  Future<void> _search() async {
    _dismissKeyboard();
    // Snapshot só dos valores actuais — nunca estado stale.
    final zipRaw = _zip.text.trim();
    final cityRaw = _city.text.trim();
    final zip = normalizePtPostalCode(zipRaw) ?? zipRaw;
    final zipOk = isValidPtPostalCode(zip) ||
        zip.replaceAll(RegExp(r'\D'), '').length == 7;
    final cityOk = cityRaw.length >= 2;

    if (!zipOk && !cityOk) {
      setState(() {
        _error =
            'Indica um código postal (ex. 2600-100) e/ou uma localidade.';
        _points = const [];
      });
      return;
    }

    final searchZip = zipOk ? (normalizePtPostalCode(zip) ?? zip) : '';
    final searchCity = cityRaw;

    setState(() {
      _loading = true;
      _error = null;
      _points = const [];
    });
    try {
      final result = await DpdPudoService.searchDetailed(
        zipCode: searchZip,
        city: searchCity,
      );
      if (!mounted) return;
      final resolved = (result.resolvedCity ?? '').trim();
      if (resolved.isNotEmpty && _city.text.trim().isEmpty) {
        _city.text = resolved;
        _autoCityLabel = resolved;
        _autoCityForZip = result.postalCode ?? searchZip;
      }
      final resolvedZip = (result.postalCode ?? '').trim();
      if (resolvedZip.isNotEmpty && _zip.text.trim().isEmpty) {
        _zip.text = resolvedZip;
        if (resolved.isNotEmpty) {
          _autoCityLabel = resolved;
          _autoCityForZip = resolvedZip;
        }
      }
      setState(() {
        _points = result.points;
        if (result.points.isEmpty) {
          _error = 'Não encontrámos pontos Pickup nesta zona.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Escolher loja Pickup DPD',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: FleaberColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pesquisa por código postal, por localidade, ou pelos dois. '
                'Podes escolher qualquer ponto em Portugal.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: FleaberColors.muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _zip,
                focusNode: _zipFocus,
                decoration: const InputDecoration(
                  labelText: 'Código postal',
                  hintText: '2600-100',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: _onZipChanged,
                onSubmitted: (_) => _cityFocus.requestFocus(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _city,
                focusNode: _cityFocus,
                decoration: const InputDecoration(
                  labelText: 'Localidade',
                  hintText: 'Opcional se o CP for válido',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onCityChanged,
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              FleaberPrimaryButton(
                label: 'Procurar lojas',
                loading: _loading,
                onPressed: _loading ? null : _search,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: _points.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _points[i];
                          final dist = p.distanceKm;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              p.name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              [
                                p.subtitle,
                                p.pudoId,
                                if (dist != null)
                                  '~${dist.toStringAsFixed(1)} km',
                              ].join('\n'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.35,
                                color: FleaberColors.muted,
                              ),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              _dismissKeyboard();
                              Navigator.pop(context, p);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
