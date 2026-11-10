import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '/utils/dpd_pudo_service.dart';
import '/widgets/fleaber_primary_button.dart';

/// Consulta de lojas DPD Shop próximas onde o **vendedor** pode depositar volumes.
/// Não confunde com o Pickup de receção do comprador — só consulta, sem gravar
/// ponto obrigatório na expedição.
Future<void> showDpdSellerDropoffSheet(
  BuildContext context, {
  String initialZip = '1000-001',
  String initialCity = 'Lisboa',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DpdSellerDropoffBody(
      initialZip: initialZip,
      initialCity: initialCity,
    ),
  );
}

class _DpdSellerDropoffBody extends StatefulWidget {
  const _DpdSellerDropoffBody({
    required this.initialZip,
    required this.initialCity,
  });

  final String initialZip;
  final String initialCity;

  @override
  State<_DpdSellerDropoffBody> createState() => _DpdSellerDropoffBodyState();
}

class _DpdSellerDropoffBodyState extends State<_DpdSellerDropoffBody> {
  late final TextEditingController _zip;
  late final TextEditingController _city;
  bool _loading = false;
  String? _error;
  List<DpdPudoPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _zip = TextEditingController(text: widget.initialZip);
    _city = TextEditingController(text: widget.initialCity);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _zip.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _points = const [];
    });
    try {
      final result = await DpdPudoService.searchDetailed(
        zipCode: _zip.text,
        city: _city.text,
      );
      if (!mounted) return;
      final resolved = (result.resolvedCity ?? '').trim();
      if (resolved.isNotEmpty && _city.text.trim().isEmpty) {
        _city.text = resolved;
      }
      setState(() {
        _points = result.points;
        if (result.points.isEmpty) {
          _error = 'Não encontrámos lojas DPD Shop neste código postal.';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openMaps(DpdPudoPoint p) async {
    final q = Uri.encodeComponent('${p.name} ${p.address1} ${p.zipCode} ${p.city}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DA),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Onde posso entregar as minhas encomendas?',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101518),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Consulta lojas DPD Shop próximas para depositar o volume. '
                'Isto não altera o ponto Pickup do comprador.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.35,
                  color: const Color(0xFF57636C),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _zip,
                      decoration: const InputDecoration(
                        labelText: 'Código postal',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _city,
                      decoration: const InputDecoration(
                        labelText: 'Cidade',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FleaberPrimaryButton(
                label: _loading ? 'A procurar…' : 'Procurar lojas',
                onPressed: _loading ? null : _search,
                height: 44,
                borderRadius: 12,
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
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF007782),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _points.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final p = _points[i];
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
                              '${p.address1}\n${p.zipCode} ${p.city}'
                              '${p.pudoId.isNotEmpty ? '\nRef. ${p.pudoId}' : ''}',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: const Color(0xFF57636C),
                              ),
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'Abrir no mapa',
                              onPressed: () => _openMaps(p),
                              icon: const Icon(
                                Icons.map_outlined,
                                color: Color(0xFF007782),
                              ),
                            ),
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
