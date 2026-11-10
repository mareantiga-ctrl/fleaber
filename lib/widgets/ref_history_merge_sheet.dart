import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/ref_history_service.dart';
import '/widgets/fleaber_primary_button.dart';

class RefHistoryMergeSheet extends StatefulWidget {
  const RefHistoryMergeSheet({
    super.key,
    required this.sellerId,
    required this.target,
    required this.candidates,
    this.onMerged,
  });

  final String sellerId;
  final RefHistoryListEntry target;
  final List<RefHistoryListEntry> candidates;
  final VoidCallback? onMerged;

  static Future<void> show(
    BuildContext context, {
    required String sellerId,
    required RefHistoryListEntry target,
    required List<RefHistoryListEntry> candidates,
    VoidCallback? onMerged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.75;
        return SizedBox(
          height: sheetH,
          child: RefHistoryMergeSheet(
            sellerId: sellerId,
            target: target,
            candidates: candidates,
            onMerged: onMerged,
          ),
        );
      },
    );
  }

  @override
  State<RefHistoryMergeSheet> createState() => _RefHistoryMergeSheetState();
}

class _RefHistoryMergeSheetState extends State<RefHistoryMergeSheet> {
  RefHistoryListEntry? _source;
  RefHistoryMergePreview? _preview;
  bool _loadingPreview = false;
  bool _merging = false;
  bool _confirmed = false;

  Future<void> _selectSource(RefHistoryListEntry entry) async {
    setState(() {
      _source = entry;
      _preview = null;
      _loadingPreview = true;
      _confirmed = false;
    });
    final preview = await RefHistoryService.mergePreview(
      sellerId: widget.sellerId,
      targetHistoryId: widget.target.historyId,
      sourceHistoryId: entry.historyId,
    );
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loadingPreview = false;
    });
  }

  Future<void> _merge() async {
    final source = _source;
    if (source == null || _preview?.ok != true) return;
    setState(() => _merging = true);
    final ok = await RefHistoryService.merge(
      sellerId: widget.sellerId,
      targetHistoryId: widget.target.historyId,
      sourceHistoryId: source.historyId,
      reason: 'seller_merge',
    );
    if (!mounted) return;
    setState(() => _merging = false);
    if (ok) {
      widget.onMerged?.call();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Históricos juntados com sucesso.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mergeError(_preview?.error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 12.0 + MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Juntar históricos',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Principal: ${widget.target.refCode} · ${widget.target.displayTitle}',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              'Escolhe o histórico a juntar (mesma referência, sem reservas abertas):',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.candidates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final c = widget.candidates[i];
                  final selected = _source?.historyId == c.historyId;
                  return ListTile(
                    tileColor: selected
                        ? const Color(0xFF007782).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      c.displayTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${c.openReservationCount} reservas · ${c.completedPurchaseCount} vendas',
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () => _selectSource(c),
                  );
                },
              ),
            ),
            if (_loadingPreview)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_preview != null) ...[
              if (_preview!.ok) ...[
                Text(
                  '${_preview!.itemsToRepoint} gravações passam para o histórico principal. '
                  'Reservas e encomendas antigas não mudam.',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _confirmed,
                  onChanged: _merging
                      ? null
                      : (v) => setState(() => _confirmed = v == true),
                  title: Text(
                    'Confirmo que quero juntar estes históricos',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFF007782),
                ),
                FleaberPrimaryButton(
                  label: 'Juntar históricos',
                  loading: _merging,
                  onPressed: _confirmed && !_merging ? _merge : null,
                ),
              ] else
                Text(
                  _mergeError(_preview!.error),
                  style: GoogleFonts.inter(color: const Color(0xFFFF8A80), fontSize: 12),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _mergeError(String? code) {
    switch (code) {
      case 'ref_mismatch':
        return 'Só podes juntar históricos da mesma referência.';
      case 'source_has_open_reservations':
        return 'O histórico secundário tem reservas abertas.';
      case 'source_has_unpaid_orders':
        return 'O histórico secundário tem pedidos não pagos.';
      case 'history_not_active':
        return 'Um dos históricos já está encerrado ou juntado.';
      default:
        return 'Não é possível juntar estes históricos.';
    }
  }
}
