import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_screen_wake.dart';
import '/widgets/live_vendor_ops_ui.dart';
import '/widgets/live_vendor_studio_panel.dart';

/// Painel operacional do vendedor **sem câmara / sem publish** — só Maestro e debug.
///
/// Rota: `/maestroSellerStudio?liveId=…` (deep link `fleaber://fleaber.com/maestroSellerStudio?…`).
/// Em [kReleaseMode] não expõe o painel (zero impacto em produção).
class MaestroSellerStudioPageWidget extends StatefulWidget {
  const MaestroSellerStudioPageWidget({
    super.key,
    this.liveId,
    this.opsSection,
    this.expandCategory,
  });

  static String routeName = 'MaestroSellerStudio';
  static String routePath = '/maestroSellerStudio';

  final String? liveId;
  /// `queue` | `payments` | `history` — abre sub-tab Operação no harness.
  final String? opsSection;
  /// `inBag` | `pending` | `accepted` | `external` | `unpaid` — expande categoria na fila.
  final String? expandCategory;

  @override
  State<MaestroSellerStudioPageWidget> createState() =>
      _MaestroSellerStudioPageWidgetState();
}

class _MaestroSellerStudioPageWidgetState extends State<MaestroSellerStudioPageWidget>
    with FleaberScreenWakeMixin {
  final _studioPanelKey = GlobalKey<LiveVendorStudioPanelState>();

  bool _loading = true;
  String? _error;
  LivesRow? _live;
  int _catalogItemCount = 0;
  bool _privateChatMode = false;
  int _privateUnread = 0;
  SellerLiveActivePanel _activePanel = SellerLiveActivePanel.none;

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
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (kReleaseMode) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Indisponível em release.';
      });
      return;
    }

    final liveId = widget.liveId?.trim() ?? '';
    final uid = currentUserUid.trim();
    if (liveId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'liveId em falta no deep link.';
      });
      return;
    }
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Inicia sessão como vendedora.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', liveId),
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('live_not_found');
      }
      final live = rows.first;
      final sellerId = live.sellerId?.trim() ?? live.vendedorId?.trim() ?? '';
      if (sellerId.isEmpty || sellerId != uid) {
        throw StateError('not_seller');
      }

      var catalogCount = 0;
      try {
        final items = await LiveItemsTable().queryRows(
          queryFn: (q) => q.eqOrNull('live_id', liveId),
        );
        catalogCount = items.length;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _live = live;
        _catalogItemCount = catalogCount;
        _loading = false;
        _activePanel = SellerLiveActivePanel.operation;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _studioPanelKey.currentState?.prepareMaestroHarnessUi(
          section: _opsSectionFromParam(widget.opsSection),
          expandCategory: widget.expandCategory,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is StateError && e.message == 'not_seller'
            ? 'Esta live não pertence à conta actual.'
            : 'Não foi possível abrir o painel Maestro.';
      });
    }
  }

  DateTime? get _startedAt => _live?.createdAt;

  SellerOperationSection _opsSectionFromParam(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'payments' || 'a_receber' => SellerOperationSection.payments,
      'history' || 'historico' => SellerOperationSection.history,
      _ => SellerOperationSection.queue,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Text(
              'Harness Maestro só em builds debug.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A3AD)))
          : _error != null
              ? _errorBody()
              : _studioBody(),
    );
  }

  Widget _errorBody() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error ?? 'Erro',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Voltar'),
            ),
            TextButton(
              onPressed: () => unawaited(_bootstrap()),
              child: const Text('Tentar outra vez'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studioBody() {
    final live = _live!;
    final liveId = live.id!.trim();
    final sellerId = live.sellerId?.trim() ?? currentUserUid;
    final title = (live.title ?? '').trim().isNotEmpty
        ? live.title!.trim()
        : 'Directo Maestro';

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0A0E10)),
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
                      color: const Color(0xFF00A3AD).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00A3AD).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      'MAESTRO · sem vídeo · painel real',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
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
