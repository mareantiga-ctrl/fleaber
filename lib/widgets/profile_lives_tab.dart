import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/index.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/utils/fleaber_colors.dart';
import '/utils/seller_staff_service.dart';
import '/utils/seller_vacation_mode.dart';
import '/utils/fleaber_grid_spacing.dart';
import '/utils/mux_urls.dart';
import '/widgets/batata_cached_image.dart';

/// Aba «Diretos» do perfil — dados reais da tabela `lives`.
class ProfileLivesTab extends StatefulWidget {
  const ProfileLivesTab({super.key, required this.sellerId});

  final String sellerId;

  @override
  State<ProfileLivesTab> createState() => _ProfileLivesTabState();
}

class _ProfileLivesTabState extends State<ProfileLivesTab> {
  static const Color _kTeal = Color(0xFF007782);

  bool _loading = true;
  String? _error;
  LivesRow? _activeLive;
  List<LivesRow> _pastLives = const [];
  bool _hiddenForVacation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sellerId = widget.sellerId.trim();
    if (sellerId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Vendedor inválido.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final onVacation = await SellerVacationMode.isOnVacation(sellerId);
      if (SellerVacationMode.hideSellerFromPublicDiscovery(
        sellerOnVacation: onVacation,
        sellerId: sellerId,
      )) {
        if (!mounted) return;
        setState(() {
          _hiddenForVacation = true;
          _activeLive = null;
          _pastLives = const [];
        });
        return;
      }
      _hiddenForVacation = false;

      final liveNow = await LivesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sellerId)
            .eqOrNull('status', 'live')
            .order('created_at', ascending: false)
            .limit(1),
      );

      final ended = await LivesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('seller_id', sellerId)
            .eqOrNull('status', 'ended')
            .order('created_at', ascending: false)
            .limit(24),
      );

      if (!mounted) return;
      setState(() {
        _activeLive = liveNow.isEmpty ? null : liveNow.first;
        _pastLives = ended;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLive(LivesRow live) {
    final isLiveNow = live.status == 'live' && live.isActive == true;
    final vodId = live.muxVodPlaybackId?.trim();
    final playbackId = isLiveNow
        ? live.muxPlaybackId?.trim()
        : (vodId != null && vodId.isNotEmpty
            ? vodId
            : live.muxPlaybackId?.trim());
    if (playbackId == null || playbackId.isEmpty) return;
    context.pushNamed(
      FleaberLivePlayerWidget.routeName,
      queryParameters: {
        'liveId': serializeParam(live.id, ParamType.String),
        'playbackId': serializeParam(playbackId, ParamType.String),
        'isLive': serializeParam(isLiveNow, ParamType.bool),
        if (live.sellerId != null && live.sellerId!.trim().isNotEmpty)
          'sellerId': serializeParam(live.sellerId, ParamType.String),
      }.withoutNulls,
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    return DateFormat('dd MMM yyyy', 'pt_PT').format(value.toLocal());
  }

  Widget _thumbCard(LivesRow live, {bool showLiveBadge = false}) {
    final playbackId = live.muxPlaybackId;
    final title = live.title?.trim().isNotEmpty == true
        ? live.title!.trim()
        : 'Direto Fleaber';
    final aspectRatio =
        (!kReleaseMode && showLiveBadge) ? 16 / 9 : 9 / 16;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: playbackId == null ? null : () => _openLive(live),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6EEF0)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (playbackId != null)
                    BatataCachedNetworkImage(
                      imageUrl: MuxUrls.portraitThumbnail(playbackId, width: 240),
                      fit: BoxFit.cover,
                    )
                  else
                    const ColoredBox(color: Color(0xFF111111)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.75),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  if (showLiveBadge)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: FleaberColors.danger,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LIVE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        if (_formatDate(live.createdAt).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(live.createdAt),
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: _kTeal),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    final active = _activeLive;
    final past = _pastLives;

    if (_hiddenForVacation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Este vendedor está de férias. Os diretos estão temporariamente ocultos.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Color(0xFF57636C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (active == null && past.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Ainda não há diretos neste perfil.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Color(0xFF57636C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _kTeal,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (active != null) ...[
            Text(
              'Em direto agora',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 10),
            _thumbCard(active, showLiveBadge: true),
            if (!kReleaseMode && _canOpenMaestroPanel(active)) ...[
              const SizedBox(height: 10),
              Semantics(
                label: 'Painel operacional',
                button: true,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kTeal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openMaestroPanel(active),
                    child: Text(
                      'Painel operacional',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
          if (past.isNotEmpty) ...[
            Text(
              'Diretos anteriores',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: past.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: kFleaberTwoColumnGridGap,
                mainAxisSpacing: kFleaberTwoColumnGridGap,
                childAspectRatio: 9 / 16,
              ),
              itemBuilder: (context, index) => _thumbCard(past[index]),
            ),
          ],
        ],
      ),
    );
  }

  bool _canOpenMaestroPanel(LivesRow live) {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return false;
    final liveSeller =
        (live.sellerId ?? live.vendedorId ?? '').trim();
    if (liveSeller.isNotEmpty && liveSeller != uid) return false;
    if (!SellerStaffContext.instance.isOwnerContext) return false;
    return true;
  }

  void _openMaestroPanel(LivesRow live) {
    final liveId = live.id?.trim() ?? '';
    if (liveId.isEmpty) return;
    context.pushNamed(
      MaestroSellerStudioPageWidget.routeName,
      queryParameters: {
        'liveId': serializeParam(liveId, ParamType.String),
      }.withoutNulls,
    );
  }
}
