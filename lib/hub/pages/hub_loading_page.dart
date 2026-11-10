import 'package:flutter/material.dart';

import '../hub_navigation.dart';
import '../widgets/fleahub_site_chrome.dart';

/// Fallback loading Hub.
///
/// Por defeito usa a superfície **clara** FleaHub (topbar + skeletons),
/// evitando o ecrã preto legado. Live e shells escuros podem pedir [dark].
class HubLoadingPage extends StatelessWidget {
  const HubLoadingPage({
    super.key,
    this.dark = false,
    this.message = 'A carregar…',
  });

  /// `true` = shell escuro histórico ([HubLoadingShell] / Live).
  final bool dark;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (dark) {
      return HubLoadingShell(message: message);
    }
    return FleaHubLoadingShell(message: message);
  }
}
