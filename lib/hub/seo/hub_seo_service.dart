import 'package:flutter/foundation.dart';

import 'hub_seo_head.dart';
import 'hub_seo_meta.dart';

/// Aplica meta tags ao `<head>` (web) — noop noutras plataformas.
abstract final class HubSeoService {
  static HubSeoMeta _lastApplied = HubSeoMeta.appDefault();

  static HubSeoMeta get lastApplied => _lastApplied;

  static void apply(HubSeoMeta meta) {
    _lastApplied = meta;
    if (!kIsWeb) return;
    hubSeoApplyToDocument(meta);
  }

  static void resetToAppDefault() {
    apply(HubSeoMeta.appDefault());
  }
}
