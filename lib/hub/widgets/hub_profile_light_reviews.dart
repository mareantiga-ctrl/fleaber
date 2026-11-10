import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/utils/fleaber_colors.dart';

import '../data/hub_models.dart';
import 'fleahub_site_chrome.dart';

/// Resumo de opiniões — superfície clara H02 (espelha lógica de [HubReviewsSummaryPanel]).
class HubProfileLightReviewsSummary extends StatelessWidget {
  const HubProfileLightReviewsSummary({
    super.key,
    required this.stats,
    this.compact = false,
  });

  final HubReviewsStatsResult stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (stats.count == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
        child: Text(
          'Ainda sem avaliações públicas.',
          style: GoogleFonts.inter(
            color: FleaberColors.muted,
            fontSize: FleaHubSiteLayout.typeBody,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final avgLabel = stats.average.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              avgLabel,
              style: GoogleFonts.inter(
                color: FleaberColors.text,
                fontSize: compact ? 32 : 40,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RatingBarIndicator(
                    rating: stats.average,
                    itemSize: 15,
                    unratedColor: FleaberColors.alternate,
                    itemBuilder: (_, __) => const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF9CF58),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats.count == 1
                        ? '1 avaliação'
                        : '${stats.count} avaliações',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: FleaberColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...List.generate(5, (i) {
          final stars = 5 - i;
          final n = stats.distribution[i];
          final pct = stats.count == 0 ? 0.0 : n / stats.count;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    '$stars',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FleaberColors.muted,
                    ),
                  ),
                ),
                const Icon(Icons.star_rounded,
                    size: 12, color: Color(0xFFF9CF58)),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: FleaberColors.alternate,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        FleaberColors.teal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text(
                    '$n',
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: FleaberColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class HubProfileLightReviewsToolbar extends StatelessWidget {
  const HubProfileLightReviewsToolbar({
    super.key,
    required this.starsFilter,
    required this.onStarsFilter,
  });

  final int? starsFilter;
  final ValueChanged<int?> onStarsFilter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip(
          label: 'Todas',
          selected: starsFilter == null,
          onTap: () => onStarsFilter(null),
        ),
        for (var s = 5; s >= 1; s--)
          _chip(
            label: '$s★',
            selected: starsFilter == s,
            onTap: () => onStarsFilter(s),
          ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? FleaberColors.teal.withValues(alpha: 0.12)
          : FleaberColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? FleaberColors.teal.withValues(alpha: 0.45)
                  : FleaberColors.alternate,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? FleaberColors.teal : FleaberColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class HubProfileLightReviewTile extends StatefulWidget {
  const HubProfileLightReviewTile({
    super.key,
    required this.review,
    this.showDivider = true,
  });

  final HubReview review;
  final bool showDivider;

  @override
  State<HubProfileLightReviewTile> createState() =>
      _HubProfileLightReviewTileState();
}

class _HubProfileLightReviewTileState extends State<HubProfileLightReviewTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final name = (review.authorDisplay ?? 'Compradora').trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final comment = review.comment?.trim() ?? '';
    final hasComment = comment.isNotEmpty;
    final long = comment.length > 220;
    final date = review.createdAt != null
        ? DateFormat('d MMM yyyy', 'pt_PT').format(review.createdAt!.toLocal())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: FleaberColors.alternate,
                child: Text(
                  initial,
                  style: GoogleFonts.inter(
                    color: FleaberColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              color: FleaberColors.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (date != null)
                          Text(
                            date,
                            style: GoogleFonts.inter(
                              color: FleaberColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    RatingBarIndicator(
                      rating: review.stars.toDouble().clamp(0, 5),
                      itemSize: 13,
                      unratedColor: FleaberColors.alternate,
                      itemBuilder: (_, __) => const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF9CF58),
                      ),
                    ),
                    if (hasComment) ...[
                      const SizedBox(height: 8),
                      Text(
                        (!_expanded && long)
                            ? '${comment.substring(0, 220).trimRight()}…'
                            : comment,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.45,
                          color: FleaberColors.text,
                        ),
                      ),
                      if (long)
                        TextButton(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            foregroundColor: FleaberColors.teal,
                            padding: const EdgeInsets.only(top: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_expanded ? 'Mostrar menos' : 'Ler mais'),
                        ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Text(
                        'Sem comentário escrito.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: FleaberColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.showDivider)
          const Divider(height: 1, color: FleaberColors.alternate),
      ],
    );
  }
}
