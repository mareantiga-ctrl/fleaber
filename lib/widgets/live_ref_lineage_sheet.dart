import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/live_ref_lineage_preview_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/ref_history_detail_sheet.dart';

/// Resultado da decisão da seller ao reutilizar ref.
sealed class LiveRefLineageSheetResult {}

class LiveRefLineageInherit extends LiveRefLineageSheetResult {
  LiveRefLineageInherit({
    required this.logicalItemId,
    this.inheritFrom,
  });

  final String logicalItemId;
  /// Snapshot do card no momento do «Continuar» — evita perder preço/qty no upsert.
  final LiveRefLineageEntry? inheritFrom;
}

class LiveRefLineageNewArticle extends LiveRefLineageSheetResult {}

/// Sheet — ref reutilizada com históricos anteriores.
class LiveRefLineageSheet extends StatefulWidget {
  const LiveRefLineageSheet({
    super.key,
    required this.report,
    this.sellerId,
    this.draftLiveId,
  });

  final LiveRefLineagePreviewReport report;
  final String? sellerId;
  final String? draftLiveId;

  @override
  State<LiveRefLineageSheet> createState() => _LiveRefLineageSheetState();

  static Future<LiveRefLineageSheetResult?> show(
    BuildContext context, {
    required LiveRefLineagePreviewReport report,
    String? sellerId,
    String? draftLiveId,
  }) {
    return showModalBottomSheet<LiveRefLineageSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.88;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SizedBox(
            height: sheetH,
            child: LiveRefLineageSheet(
              report: report,
              sellerId: sellerId,
              draftLiveId: draftLiveId,
            ),
          ),
        );
      },
    );
  }
}

class _LiveRefLineageSheetState extends State<LiveRefLineageSheet> {
  late LiveRefLineagePreviewReport _report;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  void _markHistoryClosed(String historyId) {
    final hid = historyId.trim();
    if (hid.isEmpty || !mounted) return;
    setState(() {
      _report = LiveRefLineagePreviewReport(
        isOk: _report.isOk,
        error: _report.error,
        refCode: _report.refCode,
        refNormalized: _report.refNormalized,
        usageWindowMonths: _report.usageWindowMonths,
        hasRelevantHistory: _report.hasRelevantHistory,
        shouldShowSheet: _report.shouldShowSheet,
        summary: _report.summary,
        draft: _report.draft,
        lineages: _report.lineages
            .map((e) => e.logicalItemId == hid ? e.asClosed() : e)
            .toList(),
      );
    });
  }

  Future<void> _refreshLineages() async {
    final sid = widget.sellerId?.trim() ?? '';
    if (sid.isEmpty) return;
    final fresh = await LiveRefLineagePreviewService.fetch(
      sellerId: sid,
      refCode: _report.refCode,
      liveId: widget.draftLiveId,
    );
    if (fresh != null && mounted) {
      setState(() => _report = fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _report.refCode.trim().isNotEmpty ? _report.refCode : '#?';
    final bottomPad = 12.0 + MediaQuery.paddingOf(context).bottom;
    final histories = _report.lineages;
    final historyCount = histories.length;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 12, 18, bottomPad),
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'A referência $ref já foi usada antes',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escolhe se continuas um histórico existente ou começas '
                    'um novo. As reservas e compras antigas não mudam.',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  if (historyCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      historyCount == 1
                          ? '1 histórico encontrado nesta referência'
                          : '$historyCount históricos encontrados nesta referência',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF80DEEA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (var i = 0; i < histories.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _HistoryChoiceCard(
                      lineage: histories[i],
                      sellerId: widget.sellerId,
                      onHistoryClosed: _markHistoryClosed,
                      onHistoryChanged: _refreshLineages,
                      onContinue: () {
                        if (!histories[i].showContinueButton) return;
                        Navigator.pop(
                          context,
                          LiveRefLineageInherit(
                            logicalItemId: histories[i].logicalItemId,
                            inheritFrom: histories[i],
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context, LiveRefLineageNewArticle());
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF80DEEA),
                      side: const BorderSide(color: Color(0xFF80DEEA)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Começar novo histórico',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'As reservas e compras antigas não serão alteradas.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.inter(color: Colors.white60),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _qtyLine(LiveRefLineageEntry lineage) {
  final parts = <String>[];
  if (lineage.displayPrice != null) {
    parts.add('${lineage.displayPrice!.toStringAsFixed(2)} €');
  }
  if (lineage.displayQuantity != null && lineage.displayQuantity! > 0) {
    parts.add('${lineage.displayQuantity} un. total');
  }
  if (lineage.completedUnits > 0) {
    parts.add('${lineage.completedUnits} vendidas');
  }
  if (lineage.availableQuantity != null) {
    parts.add('${lineage.availableQuantity} disponíveis');
  }
  return parts.join(' · ');
}

class _HistoryChoiceCard extends StatelessWidget {
  const _HistoryChoiceCard({
    required this.lineage,
    required this.onContinue,
    this.onHistoryClosed,
    this.onHistoryChanged,
    this.sellerId,
  });

  final LiveRefLineageEntry lineage;
  final VoidCallback onContinue;
  final void Function(String historyId)? onHistoryClosed;
  final Future<void> Function()? onHistoryChanged;
  final String? sellerId;

  @override
  Widget build(BuildContext context) {
    final photo = lineage.displayPhotoUrl?.trim();
    final badge = lineage.badgeLabel();
    final showOriginFooter = lineage.lastOrigin.isNotEmpty &&
        !badge.contains(lineage.lastOrigin);
    final sid = sellerId?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo != null && photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: BatataCachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      placeholderColor: const Color(0xFF243038),
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white38,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lineage.displayTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (lineage.displayPrice != null ||
                        lineage.displayQuantity != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _qtyLine(lineage),
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (badge.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        badge,
                        style: GoogleFonts.inter(
                          color: lineage.hasOpen
                              ? const Color(0xFFFFB74D)
                              : const Color(0xFF81C784),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (showOriginFooter) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Última: ${lineage.lastOrigin}',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (lineage.showContinueButton)
            FleaberPrimaryButton(
              label: 'Continuar histórico',
              onPressed: onContinue,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Histórico encerrado',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (sid.isNotEmpty) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                final hid = lineage.logicalItemId;
                await RefHistoryDetailSheet.show(
                  context,
                  sellerId: sid,
                  historyId: hid,
                  refCode: null,
                  onChanged: () => onHistoryClosed?.call(hid),
                );
                await onHistoryChanged?.call();
              },
              child: Text(
                'Ver histórico',
                style: GoogleFonts.inter(
                  color: const Color(0xFF80DEEA),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
