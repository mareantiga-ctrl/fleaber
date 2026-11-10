import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/utils/live_cover_assign.dart';
import '/utils/seller_vacation_mode.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_cover_image.dart';

import '../data/hub_models.dart';
import '../theme/hub_theme.dart';
import 'hub_shared_widgets.dart';

class HubProfileHero extends StatelessWidget {
  const HubProfileHero({
    super.key,
    required this.profile,
    this.averageRating,
    this.reviewCount = 0,
    this.showLiveBadge = false,
    this.liveBadge,
    this.isFollowing = false,
    this.onFollow,
    this.onShare,
    this.compact = false,
    this.showVerifiedBadge = true,
  });

  final HubProfile profile;
  final double? averageRating;
  final int reviewCount;
  final bool showLiveBadge;
  final HubLive? liveBadge;
  final bool isFollowing;
  final VoidCallback? onFollow;
  final VoidCallback? onShare;
  /// Layout mais baixo (TCL / ecrãs pequenos).
  final bool compact;
  /// Quando false, omite [HubVerifiedBadge] (ex.: `phone_verified` ≠ identidade).
  final bool showVerifiedBadge;

  @override
  Widget build(BuildContext context) {
    final photo = profile.photoUrl?.trim() ?? '';
    final titleSize = compact ? 17.0 : 26.0;
    final metaSize = compact ? 10.0 : 13.0;
    final blockGap = compact ? 3.0 : 10.0;
    final actionGap = compact ? 4.0 : 12.0;
    final topInset = compact ? 4.0 : 12.0;
    final bottomInset = compact ? 4.0 : 12.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo.isNotEmpty)
          BatataCachedNetworkImage(
            imageUrl: photo,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D3D42), HubTheme.bg],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HubTheme.bg.withValues(alpha: 0.72),
                HubTheme.bg.withValues(alpha: 0.2),
                HubTheme.bg.withValues(alpha: 0.88),
                HubTheme.bg,
              ],
              stops: compact
                  ? const [0.0, 0.08, 0.42, 1.0]
                  : const [0.0, 0.28, 0.72, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: topInset,
          bottom: bottomInset,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth,
                    ),
                    child: _heroContent(
                      context,
                      titleSize: titleSize,
                      metaSize: metaSize,
                      blockGap: blockGap,
                      actionGap: actionGap,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _heroContent(
    BuildContext context, {
    required double titleSize,
    required double metaSize,
    required double blockGap,
    required double actionGap,
  }) {
    final nameBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLiveBadge && liveBadge != null) ...[
          HubLiveStatusBadge.forLive(liveBadge!, compact: compact),
          SizedBox(height: blockGap),
        ],
        Text(
          profile.fullName.trim().isEmpty
              ? profile.handle
              : profile.fullName,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: blockGap),
        Wrap(
          spacing: compact ? 6 : 8,
          runSpacing: compact ? 4 : 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showVerifiedBadge && profile.phoneVerified)
              const HubVerifiedBadge(),
            if (!compact &&
                profile.location != null &&
                profile.location!.trim().isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: compact ? 13 : 14, color: HubTheme.textMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      profile.location!.trim(),
                      style: HubTheme.body.copyWith(fontSize: metaSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (averageRating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RatingBarIndicator(
                    rating: averageRating!,
                    itemSize: compact ? 12 : 14,
                    unratedColor: Colors.white24,
                    itemBuilder: (_, __) => const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF9CF58),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    averageRating!.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: metaSize,
                    ),
                  ),
                  if (reviewCount > 0 && !compact)
                    Text(
                      ' ($reviewCount)',
                      style: HubTheme.label.copyWith(
                        fontSize: compact ? 11 : null,
                      ),
                    ),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline,
                    size: compact ? 13 : 14, color: HubTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  profile.followerCount == 0
                      ? 'Sem seguidores'
                      : '${_formatCount(profile.followerCount)} seguidores',
                  style: HubTheme.body.copyWith(fontSize: metaSize),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
        if (profile.vacationMode) ...[
          SizedBox(height: blockGap),
          Text(
            SellerVacationMode.vacationBannerMessage,
            style: GoogleFonts.inter(
              color: const Color(0xFFF9CF58),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    final actions = (onFollow != null || onShare != null)
        ? Row(
            mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (onFollow != null)
                compact
                    ? Expanded(
                        child: FleaberPrimaryButton(
                          label: isFollowing ? 'A seguir' : 'Seguir',
                          height: 32,
                          borderRadius: 14,
                          fontSize: 11,
                          onPressed: onFollow,
                        ),
                      )
                    : FleaberPrimaryButton(
                        label: isFollowing ? 'A seguir' : 'Seguir',
                        height: 40,
                        borderRadius: 14,
                        fontSize: 13,
                        onPressed: onFollow,
                      ),
              if (onFollow != null && onShare != null)
                SizedBox(width: compact ? 8 : 10),
              if (onShare != null)
                compact
                    ? Expanded(
                        child: OutlinedButton(
                          onPressed: onShare,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.22),
                            side: const BorderSide(color: HubTheme.teal),
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Partilhar',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onShare,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HubTheme.accent,
                          backgroundColor: Colors.black.withValues(alpha: 0.22),
                          side: const BorderSide(color: HubTheme.teal),
                          minimumSize: const Size(112, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Partilhar',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
            ],
          )
        : null;

    if (!compact && actions != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: nameBlock),
          const SizedBox(width: 16),
          actions,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nameBlock,
        if (actions != null) ...[
          SizedBox(height: compact ? 10 : actionGap),
          SizedBox(width: compact ? 252 : 300, child: actions),
        ],
      ],
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) {
      final v = n / 1000000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} M';
    }
    if (n >= 10000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(0)} mil';
    }
    if (n >= 1000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(1)} mil';
    }
    return n.toString();
  }
}

/// Destaque «Em direto agora» na home FleaHub.
class HubLiveNowBanner extends StatelessWidget {
  const HubLiveNowBanner({
    super.key,
    required this.live,
    required this.onEnter,
    this.thumbnailUrl,
    this.coverId,
  });

  final HubLive live;
  final VoidCallback onEnter;
  final String? thumbnailUrl;
  final String? coverId;

  static const _desktopBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final title = live.title?.trim().isNotEmpty == true
        ? live.title!.trim()
        : 'Direto Fleaber';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: HubTheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEnter,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: HubTheme.teal.withValues(alpha: 0.55)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: desktop
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 340,
                          child: _thumbStack(aspectRatio: 16 / 10),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'EM DIRETO AGORA',
                                  style: GoogleFonts.inter(
                                    color: HubTheme.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      HubTheme.titleMd.copyWith(fontSize: 20),
                                ),
                                const SizedBox(height: 14),
                                FleaberPrimaryButton(
                                  label: 'Entrar no direto',
                                  height: 44,
                                  icon: const Icon(
                                    Icons.play_circle_fill,
                                    color: Colors.white,
                                  ),
                                  onPressed: onEnter,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _thumbStack(aspectRatio: 16 / 9),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: HubTheme.titleMd.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 12),
                            FleaberPrimaryButton(
                              label: 'Entrar no direto',
                              height: 44,
                              icon: const Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                              ),
                              onPressed: onEnter,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _thumbStack({required double aspectRatio}) {
    final cid = LiveCoverAssign.resolveCoverId(
      liveId: live.id,
      persistedCoverId: coverId ?? live.coverId,
    );
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveCoverImage(
            coverId: cid,
            muxFallbackUrl: thumbnailUrl,
            fallbackAvatarUrl: live.sellerPhotoUrl,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          const Positioned(
            top: 12,
            left: 12,
            child: HubLiveBadge(),
          ),
          if (live.viewerCount > 0)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.visibility_outlined,
                        size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      '${live.viewerCount}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HubReviewsSummaryRow extends StatelessWidget {
  const HubReviewsSummaryRow({
    super.key,
    required this.averageRating,
    required this.reviewCount,
  });

  final double averageRating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          RatingBarIndicator(
            rating: averageRating,
            itemSize: 18,
            unratedColor: Colors.white24,
            itemBuilder: (_, __) => const Icon(
              Icons.star_rounded,
              color: Color(0xFFF9CF58),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            averageRating.toStringAsFixed(1),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $reviewCount ${reviewCount == 1 ? 'opinião' : 'opiniões'}',
            style: HubTheme.body.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class HubAboutSection extends StatelessWidget {
  const HubAboutSection({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text.trim(),
        style: HubTheme.body.copyWith(fontSize: 15, height: 1.45),
      ),
    );
  }
}

class HubSellerCompactRow extends StatelessWidget {
  const HubSellerCompactRow({
    super.key,
    required this.profile,
    this.viewerCount,
    this.onTapProfile,
  });

  final HubProfile profile;
  final int? viewerCount;
  final VoidCallback? onTapProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HubTheme.surface,
      child: InkWell(
        onTap: onTapProfile,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: HubTheme.surfaceElevated,
                backgroundImage: profile.photoUrl != null &&
                        profile.photoUrl!.trim().isNotEmpty
                    ? NetworkImage(profile.photoUrl!.trim())
                    : null,
                child: profile.photoUrl == null ||
                        profile.photoUrl!.trim().isEmpty
                    ? Text(
                        profile.fullName.isNotEmpty
                            ? profile.fullName[0].toUpperCase()
                            : '@',
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName.trim().isEmpty
                          ? '@${profile.handle}'
                          : profile.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '@${profile.handle}',
                      style: HubTheme.label,
                    ),
                  ],
                ),
              ),
              if (viewerCount != null && viewerCount! > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HubTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 14, color: HubTheme.accent),
                      const SizedBox(width: 4),
                      Text(
                        '$viewerCount',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HubLivePreviewCard extends StatelessWidget {
  const HubLivePreviewCard({
    super.key,
    required this.live,
    required this.onTap,
    this.thumbnailUrl,
    this.coverId,
    this.gridStyle = false,
  });

  final HubLive live;
  final VoidCallback onTap;
  final String? thumbnailUrl;
  final String? coverId;
  /// Layout vertical para grelha desktop (perfil). Mobile mantém cartão horizontal.
  final bool gridStyle;

  String get _resolvedCover => LiveCoverAssign.resolveCoverId(
        liveId: live.id,
        persistedCoverId: coverId ?? live.coverId,
      );

  Widget _coverLayer() {
    return LiveCoverImage(
      coverId: _resolvedCover,
      muxFallbackUrl: thumbnailUrl,
      fallbackAvatarUrl: live.sellerPhotoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM · HH:mm', 'pt_PT');
    final title = live.title?.trim().isNotEmpty == true
        ? live.title!.trim()
        : 'Direto Fleaber';
    final subtitle = hubLiveIsCredibleNow(live)
        ? 'Em direto agora'
        : live.isScheduled
            ? 'Agendado · ${live.wentLiveAt != null ? df.format(live.wentLiveAt!.toLocal()) : 'em breve'}'
            : live.isEnded &&
                    (live.effectivePlaybackId == null ||
                        live.effectivePlaybackId!.isEmpty)
                ? 'Gravação a preparar'
                : 'Gravado';

    if (gridStyle) {
      return Material(
        color: HubTheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _coverLayer(),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: HubLiveStatusBadge.forLive(live, compact: true),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HubTheme.titleMd.copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HubTheme.body.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FleaberPrimaryButton.compact(
                      label: hubLiveIsCredibleNow(live) ? 'Entrar' : 'Ver',
                      onPressed: onTap,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: HubTheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 88,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _coverLayer(),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: HubLiveStatusBadge.forLive(live, compact: true),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HubTheme.titleMd.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HubTheme.body.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FleaberPrimaryButton.compact(
                            label:
                                hubLiveIsCredibleNow(live) ? 'Entrar' : 'Ver',
                            onPressed: onTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HubReviewTile extends StatelessWidget {
  const HubReviewTile({super.key, required this.review});

  final HubReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: HubTheme.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RatingBarIndicator(
                  rating: review.stars.toDouble(),
                  itemSize: 14,
                  unratedColor: Colors.white24,
                  itemBuilder: (_, __) => const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFF9CF58),
                  ),
                ),
                const Spacer(),
                Text(
                  review.authorDisplay ?? 'Compradora',
                  style: HubTheme.label,
                ),
              ],
            ),
            if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.comment!.trim(),
                style: HubTheme.body,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HubProductTile extends StatelessWidget {
  const HubProductTile({
    super.key,
    required this.product,
    required this.onTap,
  });

  final HubProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = product.price;
    final priceLabel = price != null
        ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(price)
        : '';
    return Material(
      color: HubTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (product.primaryImage != null)
                      BatataCachedNetworkImage(
                        imageUrl: product.primaryImage!,
                        fit: BoxFit.cover,
                      )
                    else
                      ColoredBox(
                        color: HubTheme.surfaceElevated,
                        child: const Icon(Icons.checkroom_outlined,
                            color: HubTheme.textMuted, size: 32),
                      ),
                    if (product.isSold)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text(
                          'VENDIDO',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: HubTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (priceLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: HubTheme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HubLiveItemHero extends StatelessWidget {
  const HubLiveItemHero({
    super.key,
    required this.item,
    this.fomo,
    required this.onReserve,
    required this.onBuyNow,
    this.vacationMode = false,
  });

  final HubLiveItem item;
  final HubFomoItem? fomo;
  final VoidCallback onReserve;
  final VoidCallback onBuyNow;
  final bool vacationMode;

  @override
  Widget build(BuildContext context) {
    final price = item.price;
    final priceLabel = price != null
        ? NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(price)
        : null;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: HubTheme.cardDecoration.copyWith(
        border: Border.all(color: HubTheme.teal.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Artigo em destaque', style: HubTheme.label),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 88,
                  height: 110,
                  child: item.photoUrl != null &&
                          item.photoUrl!.trim().isNotEmpty
                      ? BatataCachedNetworkImage(
                          imageUrl: item.photoUrl!,
                          fit: BoxFit.cover,
                        )
                      : ColoredBox(
                          color: HubTheme.surfaceElevated,
                          child: const Icon(Icons.shopping_bag_outlined,
                              color: HubTheme.textMuted),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title?.trim().isNotEmpty == true
                          ? item.title!.trim()
                          : 'Artigo do directo',
                      style: HubTheme.titleMd,
                    ),
                    if (item.refCode != null &&
                        item.refCode!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Ref. ${item.refCode}', style: HubTheme.label),
                    ],
                    if (priceLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        priceLabel,
                        style: GoogleFonts.inter(
                          color: HubTheme.accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (fomo != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (fomo!.availableQty > 0)
                            _chip('${fomo!.availableQty} disp.'),
                          if (fomo!.pendingQueueCount > 0)
                            _chip('${fomo!.pendingQueueCount} na fila'),
                          if (fomo!.isLastUnit)
                            _chip('Última unidade', accent: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FleaberPrimaryButton(
                  label: 'Reservar',
                  height: 44,
                  onPressed: vacationMode ? null : onReserve,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: vacationMode ? null : onBuyNow,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: HubTheme.teal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Comprar Já'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? HubTheme.liveRed.withValues(alpha: 0.2)
            : HubTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: accent ? HubTheme.liveRed : HubTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class HubFomoStrip extends StatelessWidget {
  const HubFomoStrip({
    super.key,
    required this.viewerCount,
    required this.fomo,
  });

  final int viewerCount;
  final HubFomoSnapshot? fomo;

  @override
  Widget build(BuildContext context) {
    final pending = fomo?.items
            .fold<int>(0, (a, i) => a + i.pendingQueueCount) ??
        0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: HubTheme.surfaceElevated,
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: HubTheme.liveRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (viewerCount > 0) '$viewerCount a ver',
                if (pending > 0) '$pending na fila',
              ].join(' · ').trim().isEmpty
                  ? 'Directo Fleaber'
                  : [
                      if (viewerCount > 0) '$viewerCount a ver',
                      if (pending > 0) '$pending na fila',
                    ].join(' · '),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HubSocialFeed extends StatelessWidget {
  const HubSocialFeed({super.key, required this.messages});

  final List<HubLiveMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const HubEmptyState(
        message: 'Ainda não há mensagens públicas neste directo.',
        icon: Icons.chat_bubble_outline,
      );
    }
    return Column(
      children: messages.take(20).map((m) {
        final label = m.senderLabel?.trim();
        final body = m.body?.trim() ?? '';
        if (body.isEmpty && m.kind != 'tip') {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: HubTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: RichText(
              text: TextSpan(
                style: HubTheme.body,
                children: [
                  if (m.isFromFacebook)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: _HubFacebookFBadge(),
                      ),
                    ),
                  if (label != null && label.isNotEmpty)
                    TextSpan(
                      text: '$label: ',
                      style: GoogleFonts.inter(
                        color: HubTheme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  TextSpan(
                    text: m.kind == 'tip'
                        ? 'Gorjeta ${m.tipAmount?.toStringAsFixed(0) ?? ''}€'
                        : body,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _HubFacebookFBadge extends StatelessWidget {
  const _HubFacebookFBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF1877F2),
        shape: BoxShape.circle,
      ),
      child: const Text(
        'f',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1,
          fontFamily: 'Arial',
        ),
      ),
    );
  }
}

class HubCatalogStrip extends StatelessWidget {
  const HubCatalogStrip({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  final List<HubLiveItem> items;
  final ValueChanged<HubLiveItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const HubEmptyState(
        message: 'Catálogo do directo vazio.',
        icon: Icons.inventory_2_outlined,
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          final price = item.price;
          return GestureDetector(
            onTap: () => onItemTap(item),
            child: Container(
              width: 100,
              decoration: HubTheme.cardDecoration,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.photoUrl != null)
                          BatataCachedNetworkImage(
                            imageUrl: item.photoUrl!,
                            fit: BoxFit.cover,
                          )
                        else
                          ColoredBox(color: HubTheme.surfaceElevated),
                        if (item.isActive)
                          const Positioned(
                            top: 6,
                            left: 6,
                            child: HubLiveBadge(compact: true),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      price != null
                          ? NumberFormat.currency(locale: 'pt_PT', symbol: '€')
                              .format(price)
                          : item.title ?? 'Artigo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
