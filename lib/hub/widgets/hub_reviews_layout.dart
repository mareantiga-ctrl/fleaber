import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/hub_models.dart';
import '../theme/hub_theme.dart';
import 'hub_shared_widgets.dart';

/// Alias estável para o painel (stats vêm do servidor).
typedef HubReviewsStats = HubReviewsStatsResult;

/// Resumo editorial (média + distribuição). Sem cartão pesado.
class HubReviewsSummaryPanel extends StatelessWidget {
  const HubReviewsSummaryPanel({
    super.key,
    required this.stats,
    this.compact = false,
  });

  final HubReviewsStatsResult stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (stats.count == 0) {
      return const SizedBox.shrink();
    }
    final avgLabel = stats.average.toStringAsFixed(1);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 8,
        compact ? 8 : 4,
        compact ? 20 : 24,
        compact ? 20 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opiniões',
            style: GoogleFonts.inter(
              color: HubTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avgLabel,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: compact ? 40 : 48,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RatingBarIndicator(
                      rating: stats.average,
                      itemSize: 16,
                      unratedColor: Colors.white24,
                      itemBuilder: (_, __) => const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF9CF58),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stats.count == 1
                          ? '1 avaliação'
                          : '${stats.count} avaliações',
                      style: HubTheme.body.copyWith(
                        fontSize: 13,
                        color: HubTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(5, (i) {
            final stars = 5 - i;
            final n = stats.distribution[i];
            final pct = stats.count == 0 ? 0.0 : n / stats.count;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$stars',
                      style: HubTheme.label.copyWith(
                        color: HubTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.star_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00A3AD),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$n',
                      textAlign: TextAlign.end,
                      style: HubTheme.label.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Text(
            'Classificações de compradoras na Fleaber.',
            style: HubTheme.body.copyWith(
              fontSize: 12,
              color: HubTheme.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtro por estrelas + ordenação (discretos, sem cartões).
class HubReviewsToolbar extends StatelessWidget {
  const HubReviewsToolbar({
    super.key,
    required this.starsFilter,
    required this.sort,
    required this.onStarsFilter,
    required this.onSort,
  });

  final int? starsFilter;
  final String sort;
  final ValueChanged<int?> onStarsFilter;
  final ValueChanged<String> onSort;

  static const _sorts = <String, String>{
    'newest': 'Mais recentes',
    'oldest': 'Mais antigas',
    'highest': 'Melhor nota',
    'lowest': 'Pior nota',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: 'Todas',
                  selected: starsFilter == null,
                  onTap: () => onStarsFilter(null),
                ),
                for (var s = 5; s >= 1; s--)
                  _chip(
                    label: '$s ★',
                    selected: starsFilter == s,
                    onTap: () => onStarsFilter(s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Chips de ordenação (mesmo idioma visual dos filtros ★).
          // DropdownButton/PopupMenu no Flutter Web falham cliques fiáveis.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in _sorts.entries)
                  _chip(
                    label: e.value,
                    selected: sort == e.key,
                    onTap: () => onSort(e.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? HubTheme.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? HubTheme.accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: selected ? HubTheme.accent : HubTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class HubReviewEditorialTile extends StatefulWidget {
  const HubReviewEditorialTile({
    super.key,
    required this.review,
    this.showDivider = true,
  });

  final HubReview review;
  final bool showDivider;

  @override
  State<HubReviewEditorialTile> createState() => _HubReviewEditorialTileState();
}

class _HubReviewEditorialTileState extends State<HubReviewEditorialTile> {
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
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: HubTheme.surfaceElevated,
                child: Text(
                  initial,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (date != null)
                          Text(
                            date,
                            style: HubTheme.label.copyWith(fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RatingBarIndicator(
                      rating: review.stars.toDouble().clamp(0, 5),
                      itemSize: 14,
                      unratedColor: Colors.white24,
                      itemBuilder: (_, __) => const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF9CF58),
                      ),
                    ),
                    if (hasComment) ...[
                      const SizedBox(height: 10),
                      Text(
                        (!_expanded && long)
                            ? '${comment.substring(0, 220).trimRight()}…'
                            : comment,
                        style: HubTheme.body.copyWith(
                          fontSize: 14.5,
                          height: 1.5,
                          color: const Color(0xE6FFFFFF),
                        ),
                      ),
                      if (long)
                        TextButton(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            foregroundColor: HubTheme.accent,
                            padding: const EdgeInsets.only(top: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_expanded ? 'Mostrar menos' : 'Ler mais'),
                        ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sem comentário escrito.',
                        style: HubTheme.body.copyWith(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: HubTheme.textMuted,
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
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
      ],
    );
  }
}

class HubReviewsLoadMoreButton extends StatelessWidget {
  const HubReviewsLoadMoreButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Center(
        child: TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: HubTheme.accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00A3AD),
                  ),
                )
              : Text(
                  'Ver mais avaliações',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Corpo Página 05 com stats servidor + lista paginada.
class HubReviewsPageBody extends StatelessWidget {
  const HubReviewsPageBody({
    super.key,
    required this.stats,
    required this.reviews,
    required this.hasMore,
    required this.loadingMore,
    required this.starsFilter,
    required this.sort,
    required this.onStarsFilter,
    required this.onSort,
    required this.onLoadMore,
  });

  final HubReviewsStatsResult stats;
  final List<HubReview> reviews;
  final bool hasMore;
  final bool loadingMore;
  final int? starsFilter;
  final String sort;
  final ValueChanged<int?> onStarsFilter;
  final ValueChanged<String> onSort;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final split = HubTheme.useReviewsDesktopSplit(context);
    final emptyList = reviews.isEmpty && stats.count == 0;

    if (emptyList) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 48),
        children: const [
          HubEmptyState(
            message: 'Ainda sem avaliações públicas.',
            icon: Icons.star_outline,
          ),
        ],
      );
    }

    Widget listColumn({required EdgeInsets padding}) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: reviews.length +
            2 +
            (hasMore ? 1 : 0) +
            (reviews.isEmpty ? 1 : 0),
        itemBuilder: (context, i) {
          var idx = i;
          if (idx == 0) {
            return HubReviewsToolbar(
              starsFilter: starsFilter,
              sort: sort,
              onStarsFilter: onStarsFilter,
              onSort: onSort,
            );
          }
          idx -= 1;
          if (!split && idx == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HubReviewsSummaryPanel(stats: stats, compact: true),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ],
            );
          }
          if (!split) idx -= 1;

          if (reviews.isEmpty && idx == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Nenhuma avaliação com este filtro.',
                textAlign: TextAlign.center,
                style: HubTheme.body,
              ),
            );
          }
          if (reviews.isEmpty) idx -= 1;

          if (idx < reviews.length) {
            return HubReviewEditorialTile(
              review: reviews[idx],
              showDivider: idx < reviews.length - 1,
            );
          }
          if (hasMore) {
            return HubReviewsLoadMoreButton(
              loading: loadingMore,
              onPressed: onLoadMore,
            );
          }
          return const SizedBox(height: 24);
        },
      );
    }

    if (!split) {
      return listColumn(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: HubTheme.reviewsSummaryDesktopWidth,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 20, 8, 32),
            child: HubReviewsSummaryPanel(stats: stats),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 24),
          color: Colors.white.withValues(alpha: 0.07),
        ),
        Expanded(
          child: listColumn(padding: const EdgeInsets.fromLTRB(28, 12, 16, 40)),
        ),
      ],
    );
  }
}
