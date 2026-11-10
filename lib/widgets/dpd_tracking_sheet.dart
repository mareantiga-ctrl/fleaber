import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/dpd_tracking_service.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

Future<void> showDpdTrackingSheet(
  BuildContext context, {
  required String orderId,
  String? knownGuide,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DpdTrackingBody(
      orderId: orderId,
      knownGuide: knownGuide,
    ),
  );
}

class _DpdTrackingBody extends StatefulWidget {
  const _DpdTrackingBody({
    required this.orderId,
    this.knownGuide,
  });

  final String orderId;
  final String? knownGuide;

  @override
  State<_DpdTrackingBody> createState() => _DpdTrackingBodyState();
}

class _DpdTrackingBodyState extends State<_DpdTrackingBody> {
  bool _loading = true;
  String? _error;
  DpdTrackingResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await DpdTrackingService.fetchForOrder(
        orderId: widget.orderId,
      );
      if (!mounted) return;
      setState(() => _result = r);
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
    final guide = _result?.guide ?? widget.knownGuide;
    return Padding(
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
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Seguimento DPD',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: FleaberColors.text,
              ),
            ),
            if (guide != null && guide.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Guia $guide',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: FleaberColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FleaberPrimaryButton(
                      label: 'Tentar de novo',
                      onPressed: _load,
                    ),
                  ],
                ),
              )
            else
              Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final r = _result;
    if (r == null) {
      return const SizedBox.shrink();
    }
    if (r.status == 'missing_guide' ||
        (r.message != null && r.events.isEmpty && !r.ok)) {
      return Center(
        child: Text(
          r.message ?? 'Sem guia DPD nesta encomenda.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.4,
            color: FleaberColors.muted,
          ),
        ),
      );
    }
    if (r.isEmptyEvents) {
      return Column(
        children: [
          Text(
            r.message ??
                'Ainda não há movimentos registados. Volta a verificar mais tarde.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: FleaberColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          FleaberPrimaryButton(label: 'Atualizar', onPressed: _load),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: r.events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = r.events[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF007782),
                ),
                title: Text(
                  e.description,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  [
                    if (e.at != null) e.at!,
                    if (e.location != null) e.location!,
                    if (e.code != null) e.code!,
                  ].join(' · '),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: FleaberColors.muted,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        FleaberPrimaryButton(label: 'Atualizar', onPressed: _load),
      ],
    );
  }
}
