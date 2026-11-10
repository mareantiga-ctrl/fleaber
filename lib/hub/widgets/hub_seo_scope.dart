import 'package:flutter/material.dart';

import '../seo/hub_seo_meta.dart';
import '../seo/hub_seo_service.dart';

/// Aplica [meta] ao `<head>` web no mount; repõe defaults no dispose.
class HubSeoScope extends StatefulWidget {
  const HubSeoScope({
    super.key,
    required this.meta,
    required this.child,
    this.resetOnDispose = true,
  });

  final HubSeoMeta meta;
  final Widget child;
  final bool resetOnDispose;

  @override
  State<HubSeoScope> createState() => _HubSeoScopeState();
}

class _HubSeoScopeState extends State<HubSeoScope> {
  @override
  void initState() {
    super.initState();
    HubSeoService.apply(widget.meta);
  }

  @override
  void didUpdateWidget(covariant HubSeoScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meta.canonicalUrl != widget.meta.canonicalUrl ||
        oldWidget.meta.robots != widget.meta.robots ||
        oldWidget.meta.title != widget.meta.title) {
      HubSeoService.apply(widget.meta);
    }
  }

  @override
  void dispose() {
    // Evitar race: a página seguinte pode já ter aplicado a sua meta em
    // initState antes deste dispose. Só repor default se ainda formos a activa.
    if (widget.resetOnDispose &&
        HubSeoService.lastApplied.title == widget.meta.title &&
        HubSeoService.lastApplied.canonicalUrl == widget.meta.canonicalUrl) {
      HubSeoService.resetToAppDefault();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
