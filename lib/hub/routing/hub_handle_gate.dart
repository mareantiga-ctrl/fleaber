import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'hub_handle_resolver.dart';
import 'hub_reserved_slugs.dart';
import 'hub_route_paths.dart';
import 'hub_route_redirect.dart';
import '../seo/hub_seo_meta.dart';
import '../widgets/hub_seo_scope.dart';
import '../pages/hub_loading_page.dart';
import '../pages/hub_not_found_page.dart';
import '../pages/hub_live_page.dart';
import '../pages/hub_profile_page.dart';

/// Resolve handle + redirect + 404 antes de renderizar skeleton Hub.
class HubHandleGate extends StatefulWidget {
  const HubHandleGate({
    super.key,
    required this.rawHandle,
    required this.uri,
    required this.section,
  });

  final String rawHandle;
  final Uri uri;
  final HubSection section;

  @override
  State<HubHandleGate> createState() => _HubHandleGateState();
}

class _HubHandleGateState extends State<HubHandleGate> {
  late Future<HubHandleResolveResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant HubHandleGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawHandle != widget.rawHandle ||
        oldWidget.uri != widget.uri) {
      _future = _resolve();
    }
  }

  Future<HubHandleResolveResult> _resolve() async {
    final handle = widget.rawHandle.trim();
    if (HubReservedSlugs.blocksHubHandle(handle)) {
      return const HubHandleResolveResult(
        found: false,
        httpStatus: 404,
        error: 'reserved_slug',
      );
    }
    return HubHandleResolver.resolve(handle);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HubHandleResolveResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return HubSeoScope(
            meta: HubSeoMeta.loading(handle: widget.rawHandle),
            child: const HubLoadingPage(),
          );
        }
        if (snap.hasError) {
          return HubSeoScope(
            meta: HubSeoMeta.notFound(),
            child: const HubNotFoundPage(),
          );
        }
        final result = snap.data;
        if (result == null) {
          return HubSeoScope(
            meta: HubSeoMeta.notFound(),
            child: const HubNotFoundPage(),
          );
        }

        if (result.needsRedirect) {
          final target = HubRouteRedirect.rebuildPath(
            uri: widget.uri,
            newHandle: result.redirectTo!,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.go(target);
          });
          return HubSeoScope(
            meta: HubSeoMeta.loading(handle: result.redirectTo),
            child: const HubLoadingPage(),
          );
        }

        if (result.profileId == null) {
          return HubSeoScope(
            meta: HubSeoMeta.notFound(),
            child: const HubNotFoundPage(),
          );
        }

        final liveDiscoveryOk =
            widget.section == HubSection.live && result.found;
        if (!result.isPublished && !liveDiscoveryOk) {
          return HubSeoScope(
            meta: HubSeoMeta.notFound(),
            child: const HubNotFoundPage(),
          );
        }

        final handle = result.handle ?? widget.rawHandle;

        // H04/H05 integradas na H02 — rotas antigas redireccionam com tab.
        if (widget.section == HubSection.shop ||
            widget.section == HubSection.reviews) {
          final tab = widget.section == HubSection.shop
              ? 'marketplace'
              : 'opinioes';
          final target = HubRoutePaths.profileTabFor(handle, tab);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.go(target);
          });
          return HubSeoScope(
            meta: HubSeoMeta.loading(handle: handle),
            child: const HubLoadingPage(),
          );
        }

        return switch (widget.section) {
          HubSection.profile => HubProfilePage(
              handle: handle,
              profileId: result.profileId!,
              initialTab: widget.uri.queryParameters['tab'],
            ),
          HubSection.live => HubLivePage(
              handle: handle,
              profileId: result.profileId!,
              liveId: widget.uri.queryParameters['liveId'],
              psDemo: widget.uri.queryParameters['ps_demo'],
            ),
          HubSection.shop || HubSection.reviews => const HubLoadingPage(),
        };
      },
    );
  }
}
