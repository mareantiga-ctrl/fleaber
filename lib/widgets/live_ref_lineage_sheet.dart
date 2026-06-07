import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/live_ref_lineage_preview_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

/// Resultado da decisão da seller ao reutilizar ref.
sealed class LiveRefLineageSheetResult {}

class LiveRefLineageInherit extends LiveRefLineageSheetResult {
  LiveRefLineageInherit({required this.logicalItemId});

  final String logicalItemId;
}

class LiveRefLineageNewArticle extends LiveRefLineageSheetResult {}

/// Sheet V1.5 — ref reutilizada com histórico por linhagem.
class LiveRefLineageSheet extends StatelessWidget {
  const LiveRefLineageSheet({
    super.key,
    required this.report,
  });

  final LiveRefLineagePreviewReport report;

  static Future<LiveRefLineageSheetResult?> show(
    BuildContext context, {
    required LiveRefLineagePreviewReport report,
  }) {
    return showModalBottomSheet<LiveRefLineageSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LiveRefLineageSheet(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = report.refCode.trim().isNotEmpty ? report.refCode : '#?';
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
                'Escolhe se continuas o mesmo artigo ou usas $ref como '
                'artigo novo. As reservas e compras antigas não mudam.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: report.lineages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final lineage = report.lineages[index];
                    return _LineageCard(lineage: lineage);
                  },
                ),
              ),
              const SizedBox(height: 14),
              ...report.lineages.map(
                (lineage) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FleaberPrimaryButton(
                        label: 'Continuar — ${lineage.displayTitle}',
                        onPressed: () {
                          Navigator.pop(
                            context,
                            LiveRefLineageInherit(
                              logicalItemId: lineage.logicalItemId,
                            ),
                          );
                        },
                      ),
                      if (lineage.badgeLabel().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          lineage.badgeLabel(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: lineage.hasOpen
                                ? const Color(0xFFFFB74D)
                                : const Color(0xFF81C784),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      'Usar $ref como novo artigo',
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
                ],
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
      ),
    );
  }
}

class _LineageCard extends StatelessWidget {
  const _LineageCard({required this.lineage});

  final LiveRefLineageEntry lineage;

  @override
  Widget build(BuildContext context) {
    final photo = lineage.displayPhotoUrl?.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
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
              child: const Icon(Icons.inventory_2_outlined,
                  color: Colors.white38, size: 22),
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
                if (lineage.displayPrice != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${lineage.displayPrice!.toStringAsFixed(2)} €',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  lineage.badgeLabel(),
                  style: GoogleFonts.inter(
                    color: lineage.hasOpen
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFF81C784),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lineage.lastOrigin.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Última: ${lineage.lastOrigin}',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
