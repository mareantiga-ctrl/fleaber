import 'dart:convert';

import 'package:flutter/services.dart';

/// Catálogo de capas de directo (ID estável → categorias + asset).
///
/// `cdn_base_url` no JSON permite trocar ficheiros HD sem mudar `cover_id`
/// nas lives (futuro). MVP usa assets locais 540×960.
class LiveCoverCatalog {
  LiveCoverCatalog._();

  static const assetJson = 'assets/jsons/live_cover_catalog.json';
  static const assetDir = 'assets/live_covers';

  static Map<String, List<String>>? _covers;
  static String? _cdnBase;

  static Future<void> ensureLoaded() async {
    if (_covers != null) return;
    final raw = await rootBundle.loadString(assetJson);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final coversRaw = map['covers'] as Map<String, dynamic>? ?? {};
    _covers = {
      for (final e in coversRaw.entries)
        e.key: (e.value as List<dynamic>).map((x) => x.toString()).toList(),
    };
    final cdn = map['cdn_base_url']?.toString().trim();
    _cdnBase = (cdn == null || cdn.isEmpty || cdn == 'null') ? null : cdn;
  }

  static List<String> get allCoverIds {
    final c = _covers;
    if (c == null) return const [];
    final ids = c.keys.toList()..sort();
    return ids;
  }

  static List<String> categoriesFor(String coverId) =>
      List<String>.from(_covers?[coverId] ?? const []);

  /// Path de asset Flutter (sempre válido no MVP).
  static String assetPath(String coverId) => '$assetDir/$coverId.webp';

  /// URL de rede se [cdn_base_url] estiver definido; senão null (usar asset).
  static String? networkUrl(String coverId) {
    final base = _cdnBase;
    if (base == null) return null;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b/$coverId.webp';
  }

  static const int coverCount = 60;

  static String coverIdAt(int index1Based) {
    final n = ((index1Based - 1) % coverCount) + 1;
    return 'fleaber_capa_${n.toString().padLeft(2, '0')}';
  }

  /// Fallback determinístico (mesmo live → mesma capa em App e Hub)
  /// enquanto `lives.cover_id` ainda não existe na BD.
  static String provisionalCoverId(String liveId) {
    final ids = allCoverIds;
    if (ids.isNotEmpty) {
      final h = liveId.hashCode & 0x7fffffff;
      return ids[h % ids.length];
    }
    final h = liveId.hashCode & 0x7fffffff;
    return coverIdAt((h % coverCount) + 1);
  }

  /// Evita capas iguais consecutivas na Home (só modo provisional).
  static List<String> decorrelateProvisional(
    List<String> liveIds,
  ) {
    if (liveIds.isEmpty) return const [];
    final out = <String>[];
    for (var i = 0; i < liveIds.length; i++) {
      var cid = provisionalCoverId(liveIds[i]);
      if (i > 0 && cid == out[i - 1]) {
        final m = RegExp(r'(\d+)$').firstMatch(cid);
        final n = int.tryParse(m?.group(1) ?? '1') ?? 1;
        cid = coverIdAt(n + 1);
      }
      out.add(cid);
    }
    return out;
  }
}
