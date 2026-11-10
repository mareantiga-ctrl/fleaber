// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'hub_seo_meta.dart';

void _setMetaName(String name, String content) {
  html.document.querySelector('meta[name="$name"]')?.remove();
  final el = html.MetaElement()
    ..name = name
    ..content = content;
  html.document.head?.append(el);
}

void _setMetaProperty(String property, String content) {
  html.document.querySelector('meta[property="$property"]')?.remove();
  final el = html.MetaElement()
    ..setAttribute('property', property)
    ..content = content;
  html.document.head?.append(el);
}

void _setLinkCanonical(String href) {
  html.document.querySelector('link[rel="canonical"]')?.remove();
  final el = html.LinkElement()
    ..rel = 'canonical'
    ..href = href;
  html.document.head?.append(el);
}

void hubSeoApplyToDocument(HubSeoMeta meta) {
  html.document.title = meta.title;
  _setMetaName('description', meta.description);
  _setMetaName('robots', meta.robots);
  _setLinkCanonical(meta.canonicalUrl);
  _setMetaProperty('og:title', meta.ogTitle);
  _setMetaProperty('og:description', meta.ogDescription);
  _setMetaProperty('og:image', meta.ogImage);
  _setMetaProperty('og:url', meta.effectiveOgUrl);
  _setMetaProperty('og:type', meta.ogType);
  _setMetaProperty('og:site_name', 'Fleaber');
  _setMetaName('twitter:card', 'summary_large_image');
  _setMetaName('twitter:title', meta.ogTitle);
  _setMetaName('twitter:description', meta.ogDescription);
  _setMetaName('twitter:image', meta.ogImage);
}

void hubSeoResetDocument() {
  final d = HubSeoMeta.appDefault();
  hubSeoApplyToDocument(d);
}
