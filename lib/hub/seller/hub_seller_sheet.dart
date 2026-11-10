import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/pages/staff/live_sales_session_detail_page_widget.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_primary_button.dart';

import '../data/hub_models.dart';
import '../data/hub_public_repository.dart';
import '../hub_account_routes.dart';
import '../hub_urls.dart';
import '../routing/hub_route_paths.dart';
import 'hub_seller_copy.dart';
import 'hub_seller_service.dart';
import 'hub_seller_share.dart';
import 'hub_seller_state.dart';

/// Linha discreta FleaHub — Perfil Seller **próprio** (gestão → sheet).
class HubSellerProfilePublicLine extends StatefulWidget {
  const HubSellerProfilePublicLine({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<HubSellerProfilePublicLine> createState() =>
      _HubSellerProfilePublicLineState();
}

class _HubSellerProfilePublicLineState extends State<HubSellerProfilePublicLine> {
  final _service = HubSellerService();
  late Future<HubSellerStatus?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.fetchStatus();
  }

  Future<void> _openSheet() async {
    await HubSellerHubSheet.show(
      context,
      onChanged: () {
        setState(_reload);
        widget.onChanged?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubSellerStatus?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FleaberColors.teal,
            ),
          );
        }
        final status = snap.data;
        if (status == null) return const SizedBox.shrink();

        final label = status.profilePublicLineLabel;
        final hasFleaHub = status.hasClaimedFleaHub;
        final published =
            status.phase == HubSellerPhase.handleClaimedPublished;

        return Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: _openSheet,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_outlined,
                    size: 14,
                    color: hasFleaHub && published
                        ? FleaberColors.teal
                        : FleaberColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: ExcludeSemantics(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasFleaHub && published
                              ? FleaberColors.teal
                              : const Color(0xFF57636C),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: FleaberColors.muted.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Linha «Ver FleaHub» — perfil vendedor de **outra** seller (visitante).
///
/// Só visível se existir hub publicado (`hub_profiles_public`). Toque → `/{handle}`.
class HubVisitorFleaHubLine extends StatefulWidget {
  const HubVisitorFleaHubLine({
    super.key,
    required this.sellerId,
    this.profileLoader,
  });

  final String sellerId;

  /// Injectável em testes; produção usa [HubPublicRepository.fetchProfileById].
  final Future<HubProfile?> Function(String sellerId)? profileLoader;

  @override
  State<HubVisitorFleaHubLine> createState() => _HubVisitorFleaHubLineState();
}

class _HubVisitorFleaHubLineState extends State<HubVisitorFleaHubLine> {
  late Future<HubProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProfile();
  }

  @override
  void didUpdateWidget(covariant HubVisitorFleaHubLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId ||
        oldWidget.profileLoader != widget.profileLoader) {
      _future = _loadProfile();
    }
  }

  Future<HubProfile?> _loadProfile() {
    final loader = widget.profileLoader;
    if (loader != null) return loader(widget.sellerId);
    return HubPublicRepository().fetchProfileById(widget.sellerId);
  }

  void _openHub(HubProfile profile) {
    final handle = profile.handle.trim();
    if (handle.isEmpty) return;
    context.push(HubRoutePaths.profileFor(handle));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubProfile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final profile = snap.data;
        if (profile == null) return const SizedBox.shrink();

        return Semantics(
          button: true,
          label: HubSellerCopy.visitorLineLabel,
          child: InkWell(
            onTap: () => _openHub(profile),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.language_outlined,
                    size: 14,
                    color: FleaberColors.teal,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: ExcludeSemantics(
                      child: Text(
                        HubSellerCopy.visitorLineLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FleaberColors.teal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: FleaberColors.muted.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cartão compacto Hub seller — embed em definições, preparar directo, etc.
class HubSellerHubCard extends StatefulWidget {
  const HubSellerHubCard({
    super.key,
    this.compact = false,
    this.showLiveActions = false,
    this.onChanged,
    this.onManage,
  });

  final bool compact;
  final bool showLiveActions;
  final VoidCallback? onChanged;
  /// Se definido, substitui o bottom sheet (ex.: gestão in-pane no H11).
  final VoidCallback? onManage;

  @override
  State<HubSellerHubCard> createState() => _HubSellerHubCardState();
}

class _HubSellerHubCardState extends State<HubSellerHubCard> {
  final _service = HubSellerService();
  late Future<HubSellerStatus?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.fetchStatus();
  }

  Future<void> _refresh() async {
    setState(_reload);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubSellerStatus?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 48,
            child: Center(
              child: CircularProgressIndicator(color: FleaberColors.teal),
            ),
          );
        }
        final status = snap.data;
        if (status == null) return const SizedBox.shrink();
        return _HubSellerCardBody(
          status: status,
          compact: widget.compact,
          showLiveActions: widget.showLiveActions,
          onManage: widget.onManage ??
              () => HubSellerHubSheet.show(
                    context,
                    onChanged: _refresh,
                  ),
          onRefresh: _refresh,
        );
      },
    );
  }
}

class _HubSellerCardBody extends StatelessWidget {
  const _HubSellerCardBody({
    required this.status,
    required this.compact,
    required this.showLiveActions,
    required this.onManage,
    required this.onRefresh,
  });

  final HubSellerStatus status;
  final bool compact;
  final bool showLiveActions;
  final VoidCallback onManage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final handle = status.handle?.trim();
    final preview = status.effectiveHandlePreview;
    final phaseLabel = switch (status.phase) {
      HubSellerPhase.noHandle => HubSellerCopy.embedPhaseNoFleaHub,
      HubSellerPhase.suggestedOnly => HubSellerCopy.embedPhaseSuggested,
      HubSellerPhase.handleClaimedHidden => HubSellerCopy.embedPhaseHidden,
      HubSellerPhase.handleClaimedPublished => HubSellerCopy.embedPhaseActive,
    };

    if (compact) {
      return _buildCompact(
        context,
        handle: handle,
        preview: preview,
        phaseLabel: phaseLabel,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FleaberColors.bgTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.public_rounded, color: FleaberColors.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  HubSellerCopy.brand,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: FleaberColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _PhaseChip(label: phaseLabel),
          ),
          const SizedBox(height: 6),
          Text(
            'Nome na app: ${status.fullName?.trim().isNotEmpty == true ? status.fullName!.trim() : '—'}',
            style: GoogleFonts.inter(fontSize: 12, color: FleaberColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            preview != null
                ? HubUrls.displayPath(preview)
                : HubSellerCopy.setupPrompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FleaberColors.tealDark,
            ),
          ),
          if (status.publishBlockReason != null &&
              status.phase != HubSellerPhase.handleClaimedPublished) ...[
            const SizedBox(height: 8),
            Text(
              status.publishBlockReason!,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: FleaberColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (handle != null && status.hasPublicHub) ...[
                FleaberPrimaryButton.compact(
                  label: showLiveActions
                      ? HubSellerCopy.embedViewLive
                      : HubSellerCopy.view,
                  onPressed: () => HubSellerShare.viewPublicHub(
                    context,
                    handle: handle,
                    live: showLiveActions,
                    closeModalFirst: false,
                  ),
                ),
                OutlinedButton(
                  onPressed: () => HubSellerShare.copyUrl(
                    context,
                    showLiveActions
                        ? HubSellerShare.liveUrl(handle)
                        : HubSellerShare.profileUrl(handle),
                  ),
                  child: Text(
                    showLiveActions
                        ? HubSellerCopy.embedCopyLive
                        : HubSellerCopy.copy,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                OutlinedButton(
                  onPressed: () => HubSellerShare.shareUrl(
                    context,
                    showLiveActions
                        ? HubSellerShare.liveUrl(handle)
                        : HubSellerShare.profileUrl(handle),
                  ),
                  child: const Text(HubSellerCopy.share),
                ),
              ] else
                FleaberPrimaryButton.compact(
                  label: status.hasClaimedFleaHub
                      ? HubSellerCopy.embedManage
                      : HubSellerCopy.profileLineCreate,
                  onPressed: onManage,
                ),
              if (handle != null && !status.hasPublicHub)
                TextButton(
                  onPressed: onManage,
                  child: const Text(HubSellerCopy.activateFleaHub),
                ),
              TextButton(
                onPressed: onManage,
                child: const Text(HubSellerCopy.embedManage),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Linha mínima (Preparar directo / Definições): sem Ver/Copiar — Partilhar copia o link.
  Widget _buildCompact(
    BuildContext context, {
    required String? handle,
    required String? preview,
    required String phaseLabel,
  }) {
    final path = preview != null ? HubUrls.displayPath(preview) : null;
    final shareTarget = handle != null && status.hasPublicHub
        ? (showLiveActions
            ? HubSellerShare.liveUrl(handle)
            : HubSellerShare.profileUrl(handle))
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: FleaberColors.bgTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: FleaberColors.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      HubSellerCopy.brand,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: FleaberColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _PhaseChip(label: phaseLabel),
                  ],
                ),
                if (path != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: FleaberColors.tealDark,
                    ),
                  ),
                ] else
                  Text(
                    HubSellerCopy.setupPrompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: FleaberColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (shareTarget != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => HubSellerShare.shareUrl(context, shareTarget),
              child: Text(
                HubSellerCopy.share,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: FleaberColors.tealDark,
                ),
              ),
            ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onManage,
            child: Text(
              status.hasClaimedFleaHub || status.hasPublicHub
                  ? HubSellerCopy.embedManage
                  : HubSellerCopy.profileLineCreate,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: FleaberColors.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: FleaberColors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: FleaberColors.teal,
        ),
      ),
    );
  }
}

/// Bottom sheet completo — claim, publish, alterar handle.
class HubSellerHubSheet {
  HubSellerHubSheet._();

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101518),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: HubSellerHubManageBody(onChanged: onChanged),
      ),
    );
  }
}

/// Corpo de gestão FleaHub — sheet escuro (mobile) ou painel claro (H11 desktop).
class HubSellerHubManageBody extends StatefulWidget {
  const HubSellerHubManageBody({
    super.key,
    this.onChanged,
    this.lightChrome = false,
  });

  final VoidCallback? onChanged;
  final bool lightChrome;

  @override
  State<HubSellerHubManageBody> createState() => _HubSellerHubManageBodyState();
}

class _HubSellerHubManageBodyState extends State<HubSellerHubManageBody> {
  bool get _light => widget.lightChrome;
  Color get _fg => _light ? FleaberColors.text : Colors.white;
  Color get _fgMuted => _light ? FleaberColors.muted : Colors.white70;
  Color get _fgFaint => _light ? const Color(0xFF8A9399) : Colors.white54;
  Color get _fieldFill =>
      _light ? const Color(0xFFF4F7F8) : const Color(0xFF1A2228);
  final _service = HubSellerService();
  final _handleCtrl = TextEditingController();
  HubSellerStatus? _status;
  List<String> _suggestions = const [];
  bool _loading = true;
  bool _busy = false;
  bool _editingAddress = false;
  String? _error;
  String? _successFeedback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _handleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _refreshAfterAction(setLoadingDone: false);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshAfterAction({
    bool setLoadingDone = true,
    String? preserveHandle,
    bool? preservePublished,
  }) async {
    HubSellerStatus? status;
    try {
      status = await _service.fetchStatus();
    } catch (_) {
      status = _status;
    }
    final preserved = preserveHandle?.trim();
    if (preserved != null && preserved.isNotEmpty) {
      final fetchedHandle = status?.handle?.trim() ?? '';
      if (fetchedHandle.isEmpty) {
        if (status != null) {
          status = status.copyWith(
            handle: preserved,
            hubPublished: preservePublished ?? status.hubPublished,
          );
        } else if (_status != null) {
          status = _status!.copyWith(
            handle: preserved,
            hubPublished: preservePublished ?? _status!.hubPublished,
          );
        }
      }
    }
    var suggestions = _suggestions;
    try {
      suggestions = await _service.suggestHandles(
        seed: status?.fullName,
        limit: 5,
      );
    } catch (_) {}
    if (!mounted) return;
    final handle = status?.handle?.trim();
    if (handle != null && handle.isNotEmpty) {
      _handleCtrl.text = handle;
    } else if (status?.handleSuggested?.trim().isNotEmpty == true) {
      _handleCtrl.text = status!.handleSuggested!.trim();
    }
    setState(() {
      _status = status;
      _suggestions = suggestions;
      if (setLoadingDone) _loading = false;
    });
  }

  void _applyClaimedHandle(String handle, {bool? hubPublished}) {
    final h = handle.trim();
    if (h.isEmpty) return;
    _handleCtrl.text = h;
    final base = _status;
    if (base == null) return;
    setState(
      () => _status = base.copyWith(
        handle: h,
        hubPublished: hubPublished ?? base.hubPublished,
      ),
    );
  }

  void _onConfirmCreateTap(HubSellerStatus status) {
    if (_busy) return;
    if (_handleDraft.length < 3) {
      setState(() {
        _error = 'Mínimo 3 caracteres.';
        _successFeedback = null;
      });
      return;
    }
    if (!status.canClaim) {
      setState(() {
        _error = status.publishBlockReason ??
            'Verifica o telemóvel para criares o teu FleaHub.';
        _successFeedback = null;
      });
      return;
    }
    _run(_confirmCreateFleaHub);
  }

  Future<void> _run(Future<HubSellerActionResult> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _successFeedback = null;
    });
    final hadHandle = _status?.hasClaimedFleaHub == true;
    try {
      final result = await action();
      if (!mounted) return;
      if (!result.ok) {
        setState(() {
          _busy = false;
          _error = result.errorMessage ??
              HubSellerErrorMessages.fromCode(result.errorCode);
        });
        return;
      }
      final resultHandle = result.handle?.trim();
      if (resultHandle != null && resultHandle.isNotEmpty) {
        _applyClaimedHandle(
          resultHandle,
          hubPublished: result.hubPublished,
        );
      }
      try {
        await _refreshAfterAction(
          preserveHandle: resultHandle,
          preservePublished: result.hubPublished,
        );
      } catch (_) {
        if (resultHandle != null && resultHandle.isNotEmpty) {
          _applyClaimedHandle(
            resultHandle,
            hubPublished: result.hubPublished,
          );
        }
      }
      if (!mounted) return;

      if (!hadHandle && resultHandle != null && resultHandle.isNotEmpty) {
        final verified = await _service.fetchStatus();
        if (verified?.hasClaimedFleaHub != true) {
          setState(() {
            _busy = false;
            _error =
                'O endereço não ficou guardado. Verifica ligação e tenta outra vez.';
            _successFeedback = null;
          });
          return;
        }
        if (verified != null) {
          setState(() => _status = verified);
        }
      }

      widget.onChanged?.call();
      final wasSetupFlow = !hadHandle;
      final published = _status?.hubPublished == true;
      final hasHandleNow = _status?.hasClaimedFleaHub == true ||
          (resultHandle?.isNotEmpty == true);
      setState(() {
        _busy = false;
        _editingAddress = false;
        _successFeedback = wasSetupFlow && hasHandleNow
            ? (published
                ? HubSellerCopy.fleahubCreatedFeedback
                : HubSellerCopy.fleahubCreatedActivateHint)
            : HubSellerCopy.updatedSnackbar;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível concluir. Tenta outra vez.';
      });
    }
  }

  String get _handleDraft {
    final raw = _handleCtrl.text.trim().toLowerCase();
    return raw.replaceAll(RegExp(r'^@+'), '');
  }

  String _publicPathDisplay(HubSellerStatus status) {
    final slug = status.handle?.trim().isNotEmpty == true
        ? status.handle!.trim().toLowerCase()
        : (_handleDraft.isNotEmpty ? _handleDraft : '…');
    return HubUrls.displayPath(slug);
  }

  String get _draftDisplayPath =>
      HubUrls.displayPath(_handleDraft.isEmpty ? '…' : _handleDraft);

  Future<HubSellerActionResult> _confirmCreateFleaHub() async {
    final draft = _handleDraft;
    final claim = await _service.claimHandle(draft);
    if (!claim.ok) return claim;

    final claimedHandle = claim.handle ?? draft;

    final publish = await _service.publishHub(publish: true);
    if (publish.ok) {
      return HubSellerActionResult(
        ok: true,
        handle: publish.handle ?? claimedHandle,
        hubPublished: publish.hubPublished ?? true,
      );
    }

    try {
      final fresh = await _service.fetchStatus();
      if (fresh?.hasClaimedFleaHub == true) {
        return HubSellerActionResult(
          ok: true,
          handle: fresh!.handle ?? claimedHandle,
          hubPublished: fresh.hubPublished,
        );
      }
    } catch (_) {}

    return HubSellerActionResult(
      ok: true,
      handle: claimedHandle,
      hubPublished: false,
    );
  }

  Future<void> _copyLinkInSheet(String url) async {
    await HubSellerShare.copyUrl(context, url, showSnackBar: false);
    if (!mounted) return;
    setState(() {
      _successFeedback = HubSellerCopy.linkCopiedFeedback;
      _error = null;
    });
  }

  Future<void> _shareLinkInSheet(String url) async {
    await HubSellerShare.shareUrl(context, url, showSnackBar: false);
    if (!mounted) return;
    setState(() {
      _successFeedback = HubSellerCopy.shareCopiedFeedback;
      _error = null;
    });
  }

  Widget _sheetFeedbackBanner() {
    if (_successFeedback == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: FleaberColors.teal.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline,
                color: FleaberColors.teal, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _successFeedback!,
                style: GoogleFonts.inter(
                  color: _fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _discreetSheetLink({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: _fgFaint,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget _addressPreview() {
    return Text(
      _draftDisplayPath,
      style: GoogleFonts.inter(
        color: FleaberColors.teal,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _shareActionsRow(String handle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => HubSellerShare.viewPublicHub(
                  context,
                  handle: handle,
                  closeModalFirst: !_light,
                ),
                child: const Text(HubSellerCopy.view),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _copyLinkInSheet(
                  HubSellerShare.profileUrl(handle),
                ),
                child: const Text(HubSellerCopy.copy),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _shareLinkInSheet(
                  HubSellerShare.profileUrl(handle),
                ),
                child: const Text(HubSellerCopy.share),
              ),
            ),
          ],
        ),
        _sheetFeedbackBanner(),
      ],
    );
  }

  Widget _sheetHandle() {
    if (_light) return const SizedBox.shrink();
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _sheetTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: _fg,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _errorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: FleaberColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FleaberColors.danger.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: FleaberColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  color: _fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetFeedbackOrError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetFeedbackBanner(),
        _errorBanner(),
      ],
    );
  }

  Widget _addressField({required String hint}) {
    return TextField(
      controller: _handleCtrl,
      enabled: !_busy,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.inter(color: _fg),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: GoogleFonts.inter(color: _fgFaint),
        prefixText: '${HubUrls.displayHost}/',
        prefixStyle: GoogleFonts.inter(
          color: FleaberColors.teal,
          fontSize: 13,
        ),
        filled: true,
        fillColor: _fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: _light
              ? const BorderSide(color: Color(0xFFE4EAF0))
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: _light
              ? const BorderSide(color: Color(0xFFE4EAF0))
              : BorderSide.none,
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _suggestions
            .map(
              (s) => ActionChip(
                label: Text(s),
                onPressed: _busy ? null : () => setState(() => _handleCtrl.text = s),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildSetupBody(HubSellerStatus status) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            const SizedBox(height: 16),
            _sheetTitle(HubSellerCopy.brand),
            const SizedBox(height: 8),
            Text(
              HubSellerCopy.setupPrompt,
              style: GoogleFonts.inter(color: _fgMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _addressPreview(),
            const SizedBox(height: 12),
            _addressField(hint: HubSellerCopy.addressFieldHint),
            _suggestionChips(),
            _sheetFeedbackOrError(),
            if (status.publishBlockReason != null && !status.canClaim) ...[
              const SizedBox(height: 10),
              Text(
                status.publishBlockReason!,
                style: GoogleFonts.inter(color: _fgFaint, fontSize: 12),
              ),
              if (!status.phoneVerified) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          if (!_light && Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          HubAccountRoutes.openContaDefinicoes(context);
                        },
                  icon: const Icon(Icons.phone_android_outlined, size: 18),
                  label: const Text('Verificar telemóvel em Definições'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FleaberColors.teal,
                    side: BorderSide(
                      color: FleaberColors.teal.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FleaberPrimaryButton(
              label: HubSellerCopy.confirmCreate,
              loading: _busy,
              onPressed: _busy ? null : () => _onConfirmCreateTap(status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditAddressBody(HubSellerStatus status) {
    final handle = status.handle!.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _editingAddress = false;
                          _error = null;
                          _handleCtrl.text = handle;
                        }),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text(HubSellerCopy.brand),
                style: TextButton.styleFrom(
                  foregroundColor: _fgFaint,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            _sheetTitle(HubSellerCopy.personalizeTitle),
            const SizedBox(height: 8),
            Text(
              HubSellerCopy.setupPrompt,
              style: GoogleFonts.inter(color: _fgMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _addressPreview(),
            const SizedBox(height: 12),
            _addressField(hint: HubSellerCopy.addressFieldHint),
            _suggestionChips(),
            _errorBanner(),
            const SizedBox(height: 16),
            FleaberPrimaryButton(
              label: HubSellerCopy.saveAddress,
              loading: _busy,
              onPressed: _busy
                  ? null
                  : () => _run(() => _service.changeHandle(_handleDraft)),
            ),
            const SizedBox(height: 16),
            Text(
              HubSellerCopy.personalizeFooter,
              style: GoogleFonts.inter(color: _fgFaint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainBody(HubSellerStatus status) {
    final handle = status.handle!.trim();
    final published = status.hubPublished;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            const SizedBox(height: 16),
            _sheetTitle(HubSellerCopy.brand),
            const SizedBox(height: 8),
            Text(
              HubSellerCopy.sheetSubtitle,
              style: GoogleFonts.inter(color: _fgMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SelectableText(
              _publicPathDisplay(status),
              style: GoogleFonts.inter(
                color: FleaberColors.teal,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (published) ...[
              const SizedBox(height: 12),
              _shareActionsRow(handle),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                HubSellerCopy.inactiveHint,
                style: GoogleFonts.inter(color: _fgFaint, fontSize: 13),
              ),
              if (status.publishBlockReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  status.publishBlockReason!,
                  style: GoogleFonts.inter(color: _fgFaint, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              FleaberPrimaryButton(
                label: HubSellerCopy.activateFleaHub,
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() => _service.publishHub(publish: true)),
              ),
            ],
            _errorBanner(),
            const SizedBox(height: 16),
            Divider(
              color: _light ? const Color(0xFFE4EAF0) : Colors.white12,
              height: 1,
            ),
            const SizedBox(height: 8),
            if (published)
              _discreetSheetLink(
                label: HubSellerCopy.hideFleaHub,
                onPressed: _busy
                    ? null
                    : () => _run(() => _service.publishHub(publish: false)),
              ),
            _discreetSheetLink(
              label: HubSellerCopy.personalizeTitle,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _editingAddress = true;
                        _error = null;
                        _handleCtrl.text = handle;
                      }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: FleaberColors.teal),
        ),
      );
    }
    final status = _status;
    if (status == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Perfil indisponível.')),
      );
    }

    final hasHandle = status.handle?.trim().isNotEmpty == true;
    if (!hasHandle) return _buildSetupBody(status);
    if (_editingAddress) return _buildEditAddressBody(status);
    return _buildMainBody(status);
  }
}

/// Prompt pós-live — copiar link gravado + resultados.
class HubSellerPostLivePrompt {
  HubSellerPostLivePrompt._();

  static Future<void> show(
    BuildContext context, {
    String? liveId,
  }) {
    final id = liveId?.trim() ?? '';
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101518),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                'Directo terminado',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                HubSellerCopy.postLiveBody,
                style: GoogleFonts.inter(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const HubSellerHubCard(showLiveActions: true),
              if (id.isNotEmpty) ...[
                const SizedBox(height: 12),
                FleaberPrimaryButton(
                  label: 'Ver resultados desta live',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ctx.pushNamed(
                      LiveSalesSessionDetailPageWidget.routeName,
                      queryParameters: {
                        'liveId': serializeParam(id, ParamType.String),
                      },
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Botão compacto «Copiar link live» para o painel do directo.
class HubSellerLiveLinkButton extends StatelessWidget {
  const HubSellerLiveLinkButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubSellerStatus?>(
      future: HubSellerService().fetchStatus(),
      builder: (context, snap) {
        final handle = snap.data?.handle?.trim();
        final published = snap.data?.hubPublished == true;
        if (handle == null || handle.isEmpty || !published) {
          return IconButton(
            onPressed: () => HubSellerHubSheet.show(context),
            icon: const Icon(Icons.link_off_outlined, color: Colors.white70),
            tooltip: HubSellerCopy.liveLinkSetupTooltip,
          );
        }
        return IconButton(
          onPressed: () => HubSellerShare.copyUrl(
            context,
            HubSellerShare.liveUrl(handle),
          ),
          icon: const Icon(Icons.link_rounded, color: Colors.white),
          tooltip: HubSellerCopy.liveLinkTooltip,
        );
      },
    );
  }
}
