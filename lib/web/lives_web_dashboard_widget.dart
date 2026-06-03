import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_video_player.dart';
import '/utils/mux_urls.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/batata_cached_image.dart';

/// Painel web responsivo para a tabela `lives` (Mux).
/// Abrir no browser: `/diretos-web` (após login).
class LivesWebDashboardWidget extends StatefulWidget {
  const LivesWebDashboardWidget({super.key});

  static const String routeName = 'LivesWebDashboard';
  static const String routePath = '/diretos-web';

  @override
  State<LivesWebDashboardWidget> createState() => _LivesWebDashboardWidgetState();
}

enum _LiveFilter { all, live, ended }

class _LivesWebDashboardWidgetState extends State<LivesWebDashboardWidget> {
  static const Color _kTeal = Color(0xFF007782);
  static const Color _kBg = FleaberColors.bgTint;
  static const Color _kMuted = Color(0xFF57636C);

  _LiveFilter _filter = _LiveFilter.live;
  bool _loading = true;
  String? _error;
  List<LivesRow> _lives = const [];
  Map<String, ProfilesRow> _profilesById = const {};
  LivesRow? _selected;

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
      final lives = await LivesTable().queryRows(
        queryFn: (q) {
          var query = q;
          switch (_filter) {
            case _LiveFilter.live:
              query = query.eqOrNull('status', 'live');
            case _LiveFilter.ended:
              query = query.eqOrNull('status', 'ended');
            case _LiveFilter.all:
              break;
          }
          return query.order('created_at', ascending: false).limit(80);
        },
      );

      final sellerIds = lives
          .map((l) => l.sellerId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      var profiles = <ProfilesRow>[];
      if (sellerIds.isNotEmpty) {
        profiles = await ProfilesTable().queryRows(
          queryFn: (q) => q.inFilter('id', sellerIds),
        );
      }

      if (!mounted) return;
      setState(() {
        _lives = lives;
        _profilesById = {for (final p in profiles) if (p.id != null) p.id!: p};
        if (_selected != null &&
            !lives.any((l) => l.id == _selected!.id)) {
          _selected = lives.isEmpty ? null : lives.first;
        } else if (_selected == null && lives.isNotEmpty) {
          _selected = lives.firstWhere(
            (l) => l.status == 'live',
            orElse: () => lives.first,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sellerName(LivesRow live) {
    final id = live.sellerId;
    if (id == null) return 'Vendedor';
    return _profilesById[id]?.fullName ?? id;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd/MM/yyyy HH:mm', 'pt_PT').format(value.toLocal());
  }

  int _crossAxisCount(double width) {
    if (width >= 1200) return 3;
    if (width >= 800) return 2;
    return 1;
  }

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _LiveFilter.values)
          FilterChip(
            label: Text(_filterLabel(f)),
            selected: _filter == f,
            onSelected: _loading
                ? null
                : (selected) {
                    if (!selected) return;
                    setState(() => _filter = f);
                    _load();
                  },
            selectedColor: _kTeal.withOpacity(0.18),
            checkmarkColor: _kTeal,
            labelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: _filter == f ? _kTeal : _kMuted,
            ),
          ),
      ],
    );
  }

  String _filterLabel(_LiveFilter f) {
    switch (f) {
      case _LiveFilter.all:
        return 'Todos';
      case _LiveFilter.live:
        return 'Ao vivo';
      case _LiveFilter.ended:
        return 'Terminados';
    }
  }

  Widget _statusBadge(LivesRow live) {
    final isLive = live.status == 'live';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLive ? FleaberColors.danger : const Color(0xFFE0E7EA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? 'LIVE' : (live.status ?? '—').toUpperCase(),
        style: GoogleFonts.inter(
          color: isLive ? Colors.white : _kMuted,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _liveListTile(LivesRow live, {required bool compact}) {
    final selected = _selected?.id == live.id;
    final playbackId = live.muxPlaybackId;
    return Material(
      color: selected ? _kTeal.withOpacity(0.08) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _selected = live),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kTeal : const Color(0xFFE6EEF0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (playbackId != null && playbackId.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BatataCachedNetworkImage(
                    imageUrl: MuxUrls.portraitThumbnail(playbackId, width: 72),
                    width: compact ? 56 : 72,
                    height: compact ? 100 : 128,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: compact ? 56 : 72,
                  height: compact ? 100 : 128,
                  color: const Color(0xFFE6EEF0),
                  child: const Icon(Icons.videocam_off_outlined, color: _kMuted),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusBadge(live),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            live.title ?? 'Sem título',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 13 : 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _sellerName(live),
                      style: GoogleFonts.inter(
                        color: _kMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(live.createdAt),
                      style: GoogleFonts.inter(color: _kMuted, fontSize: 11),
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

  Widget _playerPanel(LivesRow live) {
    final playbackId = live.muxPlaybackId;
    final hls = playbackId == null || playbackId.isEmpty
        ? ''
        : MuxUrls.playbackHls(playbackId);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EEF0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ColoredBox(
              color: Colors.black,
              child: hls.isEmpty
                  ? Center(
                      child: Text(
                        'Sem playback Mux',
                        style: GoogleFonts.inter(color: Colors.white70),
                      ),
                    )
                  : FlutterFlowVideoPlayer(
                      path: hls,
                      videoType: VideoType.network,
                      aspectRatio: 9 / 16,
                      autoPlay: true,
                      looping: true,
                      showControls: true,
                      allowFullScreen: true,
                      allowPlaybackSpeedMenu: false,
                      pauseOnNavigate: false,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statusBadge(live),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        live.title ?? 'Sem título',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _detailRow('Vendedor', _sellerName(live)),
                _detailRow('Estado', live.status ?? '—'),
                _detailRow('Criado', _formatDate(live.createdAt)),
                if (playbackId != null && playbackId.isNotEmpty)
                  _detailRow('Playback ID', playbackId),
                if (live.id != null) _detailRow('Live ID', live.id!),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: live.id == null
                          ? null
                          : () {
                              context.pushNamed(
                                FleaberLivePlayerWidget.routeName,
                                queryParameters: {
                                  'liveId': serializeParam(
                                    live.id,
                                    ParamType.String,
                                  ),
                                  if (playbackId != null &&
                                      playbackId.isNotEmpty)
                                    'playbackId': serializeParam(
                                      playbackId,
                                      ParamType.String,
                                    ),
                                }.withoutNulls,
                              );
                            },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Abrir player completo'),
                      style: FilledButton.styleFrom(backgroundColor: _kTeal),
                    ),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Atualizar lista'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: _kMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(double width) {
    final selected = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width >= 1400 ? 420 : 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filterChips(),
              const SizedBox(height: 12),
              Expanded(
                child: _lives.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        itemCount: _lives.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _liveListTile(_lives[index], compact: true),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: selected == null
              ? _emptyState(message: 'Seleciona um direto na lista.')
              : _playerPanel(selected),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(double width) {
    final crossCount = _crossAxisCount(width);
    if (crossCount == 1 && _selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filterChips(),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Voltar à lista'),
          ),
          const SizedBox(height: 8),
          Expanded(child: _playerPanel(_selected!)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterChips(),
        const SizedBox(height: 12),
        Expanded(
          child: _lives.isEmpty
              ? _emptyState()
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: crossCount == 1 ? 2.4 : 1.35,
                  ),
                  itemCount: _lives.length,
                  itemBuilder: (context, index) =>
                      _liveListTile(_lives[index], compact: crossCount > 1),
                ),
        ),
      ],
    );
  }

  Widget _emptyState({String message = 'Nenhum direto encontrado.'}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.live_tv_outlined, size: 64, color: _kTeal),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: _kMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 960;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: FlutterFlowIconButton(
          borderRadius: 20,
          buttonSize: 40,
          icon: const Icon(Icons.arrow_back_rounded, color: _kTeal, size: 24),
          onPressed: () => context.safePop(),
        ),
        title: Text(
          'Diretos Fleaber (Web)',
          style: GoogleFonts.inter(
            color: const Color(0xFF101518),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          if (currentUserUid.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Sessão ativa',
                  style: GoogleFonts.inter(
                    color: _kTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: _kTeal),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kTeal),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: width >= 1200 ? 32 : 16,
                    vertical: 16,
                  ),
                  child: isWide ? _buildWideLayout(width) : _buildNarrowLayout(width),
                ),
    );
  }
}
