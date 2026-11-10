import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

import '../data/hub_models.dart';
import '../data/hub_public_repository.dart';
import '../hub_ps_demo.dart';
import '../seo/hub_seo_meta.dart';
import '../seo/hub_seo_policy.dart';
import '../widgets/fleahub_site_chrome.dart';
import '../widgets/hub_live_fleaber_layout.dart';
import '../widgets/hub_seo_scope.dart';
import '../widgets/hub_shared_widgets.dart';

/// Hub Direto — `https://fleaber.pt/{handle}/live` (H03).
class HubLivePage extends StatefulWidget {
  const HubLivePage({
    super.key,
    required this.handle,
    required this.profileId,
    this.liveId,
    this.psDemo,
  });

  final String handle;
  final String profileId;

  /// Sessão Hub pedida (`?liveId=` — gravado ou directo específico).
  final String? liveId;

  /// Modo demo PS/Facebook (`?ps_demo=1`, debug only).
  final String? psDemo;

  @override
  State<HubLivePage> createState() => _HubLivePageState();
}

class _HubLivePageState extends State<HubLivePage> {
  final _repo = HubPublicRepository();
  late Future<HubLiveBundle?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HubLivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.liveId != widget.liveId) {
      _load();
    }
  }

  void _load() {
    _future = _repo.fetchLiveBundle(widget.profileId, liveId: widget.liveId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubLiveBundle?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const FleaHubLoadingShell(message: 'A carregar directo…');
        }
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: FleaberColors.bgTint,
            body: SafeArea(
              child: Column(
                children: [
                  const FleaHubSiteTopBar(),
                  Expanded(
                    child: HubErrorState(onRetry: () => setState(_load)),
                  ),
                ],
              ),
            ),
          );
        }
        final bundle = snap.data;
        if (bundle == null) {
          return Scaffold(
            backgroundColor: FleaberColors.bgTint,
            body: SafeArea(
              child: Column(
                children: [
                  const FleaHubSiteTopBar(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Directo indisponível.',
                        style: GoogleFonts.inter(
                          color: FleaberColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return HubSeoScope(
          meta: HubSeoMeta.forLive(
            profile: bundle.profile,
            bundle: bundle,
            indexable: HubSeoPolicy.allowHubIndexing(),
          ),
          child: HubLiveFleaberLayout(
            bundle: bundle,
            handle: widget.handle,
            onRefresh: _refresh,
            psDemo: HubPsDemo.isQueryActive(widget.psDemo),
          ),
        );
      },
    );
  }
}
