import 'dart:html' as html;

/// Navegação same-tab fiável no Chrome (Flutter `launchUrl` + `_self` falha
/// com frequência no Hub — spinner «Pagar» sem ir ao Stripe).
void fleaberWebAssignUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  html.window.location.assign(trimmed);
}
