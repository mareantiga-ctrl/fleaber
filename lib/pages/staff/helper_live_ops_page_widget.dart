import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_screen_wake.dart';
import '/utils/mux_urls.dart';
import '/utils/seller_staff_permissions.dart';
import '/utils/seller_staff_service.dart';
import '/widgets/live_hls_viewer.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/live_vendor_studio_panel.dart';
import '/widgets/seller_staff_gate.dart';

/// Colaborador: painel operacional sobre o vídeo HLS (sem câmara / sem emitir).
class HelperLiveOpsPageWidget extends StatefulWidget {
  const HelperLiveOpsPageWidget({super.key, this.liveId});

  static String routeName = 'HelperLiveOps';
  static String routePath = '/helperLiveOps';

  final String? liveId;

  @override
  State<HelperLiveOpsPageWidget> createState() =>
      _HelperLiveOpsPageWidgetState();
}

class _HelperLiveOpsPageWidgetState extends State<HelperLiveOpsPageWidget>
    with FleaberScreenWakeMixin {
  final _studioPanelKey = GlobalKey<LiveVendorStudioPanelState>();

  bool _loading = true;
  String? _error;
  LivesRow? _live;
  String? _hlsUrl;
  int _catalogItemCount = 0;
  bool _privateChatMode = false;
  int _privateUnread = 0;
  SellerLiveActivePanel _activePanel = SellerLiveActivePanel.none;
  Timer? _livePoll;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await SellerStaffContext.instance.refresh();
    final staff = SellerStaffContext.instance;

    if (!staff.can(SellerStaffPermissions.canViewLiveDashboard)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Não tens permissão para ver o painel do directo. Pede ao dono da loja.';
      });
      return;
    }

    LivesRow? live;
    final wantedId = widget.liveId?.trim() ?? '';
    if (wantedId.isNotEmpty) {
      live = await SellerStaffContext.findLiveById(wantedId);
    } else {
      live = await SellerStaffContext.findActiveLiveForSeller(
        staff.effectiveSellerId,
      );
    }

    if (live == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = staff.actingAsHelper
            ? 'Não há nenhum directo em curso nesta loja.'
            : 'Escolhe a loja em «Acesso de colaborador» e tenta outra vez.';
      });
      return;
    }

    final sellerId = live.sellerId?.trim() ?? '';
    if (sellerId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Directo inválido (loja em falta).';
      });
      return;
    }

    if (!staff.actingAsHelper || staff.effectiveSellerId != sellerId) {
      SellerHelpersRow? link;
      for (final h in staff.myHelperLinks) {
        if (h.sellerId == sellerId && h.active == true) {
          link = h;
          break;
        }
      }
      if (link == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Não és colaborador desta loja.';
        });
        return;
      }
      await staff.switchToHelperSeller(link);
    }

    final playbackId = live.muxPlaybackId?.trim() ?? '';
    if (playbackId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'O directo ainda não tem vídeo disponível. Aguarda alguns segundos e actualiza.';
      });
      return;
    }

    var catalogCount = 0;
    try {
      final items = await LiveItemsTable().queryRows(
        queryFn: (q) => q.eqOrNull('live_id', live!.id),
      );
      catalogCount = items.length;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _live = live;
      _hlsUrl = MuxUrls.playbackHls(playbackId, live: true);
      _catalogItemCount = catalogCount;
      _loading = false;
    });

    _livePoll?.cancel();
    _livePoll = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_verifyLiveStillActive());
    });
  }

  Future<void> _verifyLiveStillActive() async {
    final live = _live;
    final id = live?.id?.trim() ?? '';
    if (id.isEmpty || !mounted) return;
    final row = await SellerStaffContext.findLiveById(id);
    if (!mounted) return;
    if (row == null ||
        (row.status ?? '').toLowerCase() != 'live' ||
        row.isActive != true) {
      _livePoll?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O directo terminou.')),
      );
      Navigator.maybePop(context);
    }
  }

  DateTime? get _startedAt {
    final t = _live?.createdAt;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return SellerStaffGate(
      permission: SellerStaffPermissions.canViewLiveDashboard,
      fallback: const SellerStaffDeniedPage(
        message:
            'Precisas da permissão «Ver painel do directo» para entrar como colaborador.',
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: FleaberColors.teal),
              )
            : _error != null
                ? _errorBody()
                : _liveBody(),
      ),
    );
  }

  Widget _errorBody() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.live_tv_outlined, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Erro',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.maybePop(context),
              style: FilledButton.styleFrom(
                backgroundColor: FleaberColors.teal,
              ),
              child: const Text('Voltar'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => unawaited(_bootstrap()),
              child: const Text('Tentar outra vez'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveBody() {
    final live = _live!;
    final liveId = live.id!.trim();
    final sellerId = live.sellerId!.trim();
    final title = (live.title ?? '').trim().isNotEmpty
        ? live.title!.trim()
        : 'Directo da loja';
    final hls = _hlsUrl ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hls.isNotEmpty)
          LiveHlsViewer(
            path: hls,
            liveId: liveId,
            isLive: true,
            muxLandscapePlayback:
                MuxUrls.publishBackendUsesLandscapeThumb(live.publishBackend),
          )
        else
          const ColoredBox(color: Colors.black),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.65, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: LiveVendorBroadcastHeader(
                    liveId: liveId,
                    sellerId: sellerId,
                    startedAt: _startedAt,
                    leading: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    title: title,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: FleaberColors.teal.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Modo colaborador · ${SellerStaffContext.instance.contextLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: LiveVendorStudioPanel(
                      key: _studioPanelKey,
                      liveId: liveId,
                      sellerId: sellerId,
                      startedAt: _startedAt,
                      catalogItemCount: _catalogItemCount,
                      hideTopChrome: true,
                      viewerStyleLayout: true,
                      sellerOverlayLayout: true,
                      showTopNav: true,
                      privateChatMode: _privateChatMode,
                      onPrivateChatModeChanged: (v) {
                        if (_privateChatMode == v) return;
                        setState(() => _privateChatMode = v);
                      },
                      onPrivateUnreadChanged: (n) {
                        if (_privateUnread == n) return;
                        setState(() => _privateUnread = n);
                      },
                      activePanel: _activePanel,
                      onActivePanelChanged: (panel) {
                        if (_activePanel == panel) return;
                        setState(() => _activePanel = panel);
                      },
                      onMoreTap: () =>
                          _studioPanelKey.currentState?.showMoreMenu(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
